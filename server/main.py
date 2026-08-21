"""
Aurora Music resolver — FastAPI + yt-dlp.

Why a server: client-side scraping (youtube_explode) gets rate-limited / 403'd
per device IP and breaks when YouTube changes. yt-dlp is the most robust
extractor; running it server-side gives one stable IP, caching, and a clean
range-proxy so the app never talks to googlevideo directly (no 403).

Endpoints:
  GET /health
  GET /search?q=...&limit=20      -> [{id,title,artist,duration,thumbnail,views}]
  GET /stream?v=VIDEO_ID          -> audio bytes (HTTP Range supported)

Run:  uvicorn main:app --host 0.0.0.0 --port 8000
Android emulator reaches the host at http://10.0.2.2:8000
"""
from __future__ import annotations

import os
import re
import socket
import threading
import time
from typing import Any

import httpx
import yt_dlp
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse

app = FastAPI(title="Aurora Resolver")


@app.middleware("http")
async def verify_secret_key(request: Request, call_next):
    expected_secret = os.environ.get("AURORA_SECRET_KEY")
    if expected_secret:
        if request.url.path != "/health":
            client_secret = request.headers.get("x-api-key") or request.query_params.get("key")
            if client_secret != expected_secret:
                from fastapi.responses import JSONResponse
                return JSONResponse(
                    status_code=401,
                    content={"detail": "Unauthorized: Invalid or missing API key"}
                )
    return await call_next(request)


def _lan_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except Exception:  # noqa: BLE001
        return "127.0.0.1"
    finally:
        s.close()


def _register_loop() -> None:
    """Publish this machine's current LAN URL to the Vercel registry so the
    mobile app always finds us even when the IP changes."""
    url = os.environ.get("REGISTRY_URL")
    secret = os.environ.get("REGISTER_SECRET")
    port = os.environ.get("PORT", "8000")
    if not url or not secret:
        return
    while True:
        try:
            httpx.post(
                f"{url}/api/register",
                headers={"x-secret": secret},
                json={"url": f"http://{_lan_ip()}:{port}"},
                timeout=8,
            )
        except Exception:  # noqa: BLE001
            pass
        time.sleep(60)


@app.on_event("startup")
def _start_register() -> None:
    threading.Thread(target=_register_loop, daemon=True).start()
    # Seed the clean-proxy pool so the first plays are fast, then keep it topped.
    threading.Thread(target=_warm_loop, daemon=True).start()

# tiny in-memory cache: video_id -> (expiry_ts, direct_url, headers)
_stream_cache: dict[str, tuple[float, str, dict[str, str]]] = {}
_CACHE_TTL = 60 * 30  # 30 min (well under googlevideo expiry)


def _cookiefile() -> str | None:
    """YouTube cookies for datacenter extraction (bypasses the bot/login wall).
    Prefers a cookies.txt next to this file; else base64 in YT_COOKIES_B64."""
    local = os.path.join(os.path.dirname(__file__), "cookies.txt")
    if os.path.exists(local):
        return local
    b64 = os.environ.get("YT_COOKIES_B64")
    if not b64:
        return None
    path = "/tmp/yt_cookies.txt"
    if not os.path.exists(path):
        import base64
        try:
            with open(path, "wb") as f:
                f.write(base64.b64decode(b64))
        except Exception:  # noqa: BLE001
            return None
    return path


_proxy_cache: list[str] = []


def _proxies() -> list[str]:
    """Webshare residential proxies as 'http://user:pass@ip:port' URLs.

    YouTube bot-walls datacenter IPs; routing extraction through residential
    proxies bypasses it entirely (no cookies/PO-token needed). File format is
    one 'ip:port:user:pass' per line."""
    global _proxy_cache
    if _proxy_cache:
        return _proxy_cache
    path = os.path.join(os.path.dirname(__file__), "proxies.txt")
    if not os.path.exists(path):
        return []
    out: list[str] = []
    with open(path) as f:
        for line in f:
            parts = line.strip().split(":")
            if len(parts) == 4:
                ip, port, user, pw = parts
                out.append(f"http://{user}:{pw}@{ip}:{port}")
    _proxy_cache = out
    return out


# Only SOME residential exit nodes are clean for YouTube's player API; the rest
# get "Sign in to confirm you're not a bot" regardless of cookies. We discover
# the clean ones (a background warmer probes them in parallel) and reuse them,
# so the common request hits a known-good IP and resolves in ~3s instead of
# burning attempts on flagged nodes.
_good_proxies: list[str] = []
_good_lock = threading.Lock()
_PROBE_URL = "https://www.youtube.com/watch?v=9bZkp7q19f0"


def _record_good(p: str | None) -> None:
    if not p:
        return
    with _good_lock:
        if p in _good_proxies:
            _good_proxies.remove(p)
        _good_proxies.insert(0, p)
        del _good_proxies[10:]


def _drop_good(p: str | None) -> None:
    if not p:
        return
    with _good_lock:
        if p in _good_proxies:
            _good_proxies.remove(p)


def _pick_proxy() -> str | None:
    import random
    with _good_lock:
        good = list(_good_proxies)
    if good and random.random() < 0.9:
        return random.choice(good)
    pool = _proxies()
    return random.choice(pool) if pool else None


def _proxy_clean(proxy: str) -> bool:
    """True if this exit node can extract (not bot-walled). Fast, no download."""
    opts = {
        "quiet": True, "no_warnings": True, "skip_download": True,
        "noplaylist": True,
        "js_runtimes": {"node": {}},
        "http_headers": {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            ),
        },
        "extractor_args": {
            "youtube": {"player_client": ["android", "web"]}
        },
        "socket_timeout": 12, "retries": 0, "extractor_retries": 0,
        "proxy": proxy,
    }
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(_PROBE_URL, download=False)
        return bool(info and (info.get("formats") or info.get("url")))
    except Exception:  # noqa: BLE001
        return False


def _warm_proxies(target: int = 5, tries: int = 24) -> None:
    """Probe random proxies in parallel; remember the clean ones."""
    import random
    from concurrent.futures import ThreadPoolExecutor
    pool = _proxies()
    if not pool:
        return
    sample = random.sample(pool, min(tries, len(pool)))
    with ThreadPoolExecutor(max_workers=10) as ex:
        for proxy, ok in zip(sample, ex.map(_proxy_clean, sample)):
            if ok:
                _record_good(proxy)
        # stop early if we already have enough
    # (map drains fully; target is advisory)


def _warm_loop() -> None:
    while True:
        try:
            if len(_good_proxies) < 3:
                _warm_proxies()
        except Exception:  # noqa: BLE001
            pass
        time.sleep(120)


def _ydl(opts: dict[str, Any], use_cookies: bool = True) -> yt_dlp.YoutubeDL:
    base = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "noplaylist": True,
    }
    # Use cookies alongside the proxy (belt-and-suspenders): residential IP
    # bypasses the bot wall, the logged-in account unlocks higher-quality and
    # age/region-restricted formats.
    if use_cookies:
        cf = _cookiefile()
        if cf:
            # yt-dlp writes the (possibly rotated) cookiejar BACK to the
            # cookiefile, degrading the master over time. Hand it a throwaway
            # copy per request so the master cookies.txt stays pristine.
            import shutil
            import tempfile
            fd, tmp = tempfile.mkstemp(prefix="ytck_", suffix=".txt")
            os.close(fd)
            try:
                shutil.copyfile(cf, tmp)
                base["cookiefile"] = tmp
            except Exception:  # noqa: BLE001
                base["cookiefile"] = cf
    base.update(opts)
    return yt_dlp.YoutubeDL(base)


# Strip common YouTube title noise so lyric lookups match real songs.
def _clean(title: str) -> str:
    t = re.sub(r"\([^)]*\)|\[[^\]]*\]", " ", title)
    t = re.sub(
        r"(?i)\b(official|video|audio|lyrics?|music|hd|4k|mv|visualizer|"
        r"remaster(ed)?|feat\.?|ft\.?).*$",
        " ",
        t,
    )
    return re.sub(r"\s+", " ", t).strip(" -–—")


def _parse_lrc(lrc: str) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for line in lrc.splitlines():
        m = re.match(r"\[(\d+):(\d+)(?:\.(\d+))?\](.*)", line)
        if not m:
            continue
        mm, ss, cs, text = m.groups()
        t = int(mm) * 60 + int(ss) + (int(cs) / 100 if cs else 0)
        text = text.strip()
        if text:
            out.append({"time": round(t, 2), "text": text})
    return out


@app.get("/health")
def health() -> dict[str, bool]:
    return {"ok": True}


def _entry(e: dict[str, Any]) -> dict[str, Any]:
    """One flat yt-dlp entry -> the track shape the app expects."""
    # extract_flat omits duration/views for some entries — keep them anyway.
    thumbs = e.get("thumbnails") or []
    thumb = thumbs[-1]["url"] if thumbs else (
        f"https://i.ytimg.com/vi/{e['id']}/hqdefault.jpg"
    )
    return {
        "id": e["id"],
        "title": e.get("title") or "Unknown",
        "artist": e.get("uploader") or e.get("channel")
        or e.get("uploader_id") or "Unknown",
        "duration": int(e.get("duration") or 0),
        "thumbnail": thumb,
        "views": int(e.get("view_count") or 0),
        "channelUrl": e.get("channel_url") or e.get("uploader_url"),
    }


def _entries(info: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        _entry(e)
        for e in (info.get("entries") or [])
        if e and e.get("id")
    ]


def _flat_opts() -> dict[str, Any]:
    opts: dict[str, Any] = {"extract_flat": True}
    proxy = _pick_proxy()
    if proxy:
        opts["proxy"] = proxy
    return opts


@app.get("/search")
def search(q: str, limit: int = 20) -> list[dict[str, Any]]:
    query = q if q.startswith("ytsearch") else f"ytsearch{limit}:{q}"
    try:
        with _ydl(_flat_opts()) as ydl:
            info = ydl.extract_info(query, download=False)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(502, f"search failed: {e}") from e
    return _entries(info)


@app.get("/playlist")
def playlist(url: str, limit: int = 100) -> dict[str, Any]:
    """Import a YouTube playlist / album / mix URL as a track list."""
    opts = _flat_opts()
    opts["noplaylist"] = False
    opts["playlistend"] = limit
    try:
        with _ydl(opts) as ydl:
            info = ydl.extract_info(url, download=False)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(502, f"playlist failed: {e}") from e

    tracks = _entries(info)
    if not tracks:
        raise HTTPException(404, "no tracks in that link")
    return {
        "title": info.get("title") or "Imported playlist",
        "uploader": info.get("uploader") or info.get("channel") or "",
        "tracks": tracks,
    }


@app.get("/suggest")
def suggest(q: str) -> list[str]:
    """YouTube's own search autocomplete. Returns [] rather than failing —
    a suggestion strip must never break the search box."""
    if not q.strip():
        return []
    try:
        with httpx.Client(timeout=6) as cx:
            r = cx.get(
                "https://suggestqueries-clients6.youtube.com/complete/search",
                params={"client": "youtube", "ds": "yt", "q": q},
            )
        # JSONP: window.google.ac.h([...])
        body = r.text
        start, end = body.find("("), body.rfind(")")
        if start < 0 or end < 0:
            return []
        import json
        data = json.loads(body[start + 1:end])
        return [s[0] for s in data[1] if isinstance(s, list) and s]
    except Exception:  # noqa: BLE001
        return []


@app.get("/lyrics")
def lyrics(title: str, artist: str = "", duration: int = 0) -> dict[str, Any]:
    """Real lyrics from lrclib.net (synced LRC when available, else plain)."""
    name = _clean(title)
    with httpx.Client(timeout=12, follow_redirects=True) as cx:
        hit: dict[str, Any] | None = None
        # 1) exact get (best for synced + correct match)
        if artist:
            try:
                r = cx.get("https://lrclib.net/api/get", params={
                    "track_name": name,
                    "artist_name": artist,
                    "duration": duration,
                })
                if r.status_code == 200:
                    hit = r.json()
            except Exception:  # noqa: BLE001
                hit = None
        # 2) fuzzy search fallback
        if not hit:
            try:
                q = f"{name} {artist}".strip()
                r = cx.get("https://lrclib.net/api/search",
                           params={"q": q})
                arr = r.json() if r.status_code == 200 else []
                # prefer a result that actually has synced lyrics
                arr.sort(key=lambda x: 0 if x.get("syncedLyrics") else 1)
                hit = arr[0] if arr else None
            except Exception:  # noqa: BLE001
                hit = None

    if not hit:
        return {"synced": [], "plain": "", "source": "lrclib", "found": False}

    synced = _parse_lrc(hit.get("syncedLyrics") or "")
    return {
        "synced": synced,
        "plain": hit.get("plainLyrics") or "",
        "found": bool(synced or hit.get("plainLyrics")),
        "source": "lrclib",
    }


_CACHE_DIR = "/tmp/aurora_cache"
_dl_locks: dict[str, threading.Lock] = {}
_dl_locks_guard = threading.Lock()


def _lock_for(video_id: str) -> threading.Lock:
    with _dl_locks_guard:
        lk = _dl_locks.get(video_id)
        if lk is None:
            lk = _dl_locks[video_id] = threading.Lock()
        return lk


_CACHE_MAX_BYTES = 2 * 1024 * 1024 * 1024  # 2 GB


def _trim_cache() -> None:
    """Keep the cache under a size cap by evicting the oldest files, so an
    unattended box never fills its disk (each track is ~22 MB)."""
    try:
        files = [
            (os.path.getmtime(p), os.path.getsize(p), p)
            for p in __import__("glob").glob(os.path.join(_CACHE_DIR, "*"))
            if os.path.isfile(p)
        ]
    except Exception:  # noqa: BLE001
        return
    total = sum(s for _, s, _ in files)
    if total <= _CACHE_MAX_BYTES:
        return
    for _, size, p in sorted(files):  # oldest first
        try:
            os.remove(p)
            total -= size
        except Exception:  # noqa: BLE001
            pass
        if total <= _CACHE_MAX_BYTES:
            break


def _normalize_cache(video_id: str, path: str) -> str | None:
    """yt-dlp writes <id>.<ext> (m4a/mp4). Rename the produced file to the
    canonical .mp4 cache path and return it (None if nothing was produced)."""
    import glob
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return path
    hits = [
        p for p in glob.glob(os.path.join(_CACHE_DIR, f"{video_id}.*"))
        if os.path.getsize(p) > 0
    ]
    if not hits:
        return None
    try:
        os.replace(hits[0], path)
        return path
    except Exception:  # noqa: BLE001
        return hits[0]


def _ensure_local(video_id: str) -> str:
    """Download the track to a local cache file and return its path.

    Why download instead of proxying the googlevideo URL directly: on a
    datacenter IP the web client only yields progressive format 18, whose URL
    is SABR/PO-token-gated and 403s on a plain GET. yt-dlp itself negotiates
    SABR + the bgutil PO-token + nsig (deno/EJS), so we let it pull the bytes
    once and serve the cached file (Range-seekable) to the app.
    """
    path = os.path.join(_CACHE_DIR, f"{video_id}.mp4")
    if os.path.exists(path) and os.path.getsize(path) > 0:
        age = time.time() - os.path.getmtime(path)
        if age < _CACHE_TTL:
            return path

    lock = _lock_for(video_id)
    with lock:
        # Another request may have finished it while we waited.
        if os.path.exists(path) and os.path.getsize(path) > 0:
            if time.time() - os.path.getmtime(path) < _CACHE_TTL:
                return path
        os.makedirs(_CACHE_DIR, exist_ok=True)
        url = f"https://www.youtube.com/watch?v={video_id}"
        # Retry with a fresh residential IP each attempt (a flagged exit node
        # fails fast thanks to socket_timeout). Do NOT force player_client:
        # pinning web/web_safari/mweb forces the SABR/PO-token path, which hangs
        # for ~minutes when bgutil's get_pot stalls. yt-dlp's default client set
        # picks a non-PO client and pulls the bytes in ~1s (proven manually).
        last_err: Exception | None = None
        # Many fast attempts with a short timeout beat few slow ones: a good
        # residential proxy pulls the bytes in ~2-4s, a dead one is abandoned in
        # ~8s and we hop to the next exit node — so first-byte stays under the
        # player's ~8s connect timeout in the common case.
        for attempt in range(6):
            opts = {
                # Audio-only, m4a/mp4 only (itag 140 ≈ 4MB, then any m4a audio,
                # last resort itag 18 360p ≈ 3MB). No bare "bestaudio" (could be
                # webm/opus) and no "/best" (multi-hundred-MB video) — keeps the
                # container mp4-family so we can serve it as audio/mp4.
                "format": "140/bestaudio[ext=m4a]/18",
                # nsig/signature solved via local nodejs (yt-dlp-ejs package).
                "js_runtimes": {"node": {}},
                "http_headers": {
                    "User-Agent": (
                        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                    ),
                },
                "extractor_args": {
                    "youtube": {
                        "player_client": ["android", "web"]
                    }
                },
                "outtmpl": os.path.join(_CACHE_DIR, f"{video_id}.%(ext)s"),
                "skip_download": False,
                "overwrites": True,
                "retries": 1,
                "extractor_retries": 1,
                # Dead/slow proxy is abandoned fast so we hop to a fresh IP.
                "socket_timeout": 12,
            }
            proxy = _pick_proxy()
            if proxy:
                opts["proxy"] = proxy
            try:
                # Fresh logged-in cookies (auto-refreshed from the VPS Chrome)
                # ride along on a clean residential IP — unlocks restricted
                # formats and matches the account; the clean IP is what actually
                # clears the bot wall.
                with _ydl(opts) as ydl:
                    ydl.download([url])
                # The real extension (.m4a/.mp4) varies; normalize to .mp4 so
                # the cache key + audio/mp4 content-type are stable.
                got = _normalize_cache(video_id, path)
                if got:
                    _record_good(proxy)
                    _trim_cache()
                    return got
            except Exception as e:  # noqa: BLE001
                last_err = e
                _drop_good(proxy)
            # brief backoff before the next attempt
            if attempt < 5:
                time.sleep(0.5)

    if not (os.path.exists(path) and os.path.getsize(path) > 0):
        raise HTTPException(404, f"no audio stream: {last_err}")
    return path


def _parse_range(rng: str, size: int) -> tuple[int, int]:
    m = re.match(r"bytes=(\d*)-(\d*)", rng or "")
    if not m:
        return 0, size - 1
    a, b = m.group(1), m.group(2)
    if a == "":  # suffix range: last N bytes
        n = int(b or 0)
        return max(0, size - n), size - 1
    start = int(a)
    end = int(b) if b else size - 1
    return start, min(end, size - 1)


@app.get("/stream")
def stream(v: str, request: Request) -> StreamingResponse:
    try:
        path = _ensure_local(v)
    except HTTPException:
        raise
    except Exception as e:  # noqa: BLE001
        raise HTTPException(502, f"resolve failed: {e}") from e

    size = os.path.getsize(path)
    rng = request.headers.get("range")
    start, end = _parse_range(rng, size) if rng else (0, size - 1)
    length = end - start + 1

    def body():
        with open(path, "rb") as f:
            f.seek(start)
            remaining = length
            while remaining > 0:
                chunk = f.read(min(64 * 1024, remaining))
                if not chunk:
                    break
                remaining -= len(chunk)
                yield chunk

    headers = {
        "accept-ranges": "bytes",
        "content-length": str(length),
        "content-type": "audio/mp4",
    }
    status = 200
    if rng:
        headers["content-range"] = f"bytes {start}-{end}/{size}"
        status = 206
    return StreamingResponse(body(), status_code=status, headers=headers)
