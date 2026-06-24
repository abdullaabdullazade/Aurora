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


def _ydl(opts: dict[str, Any]) -> yt_dlp.YoutubeDL:
    base = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "noplaylist": True,
    }
    cf = _cookiefile()
    if cf:
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


@app.get("/search")
def search(q: str, limit: int = 20) -> list[dict[str, Any]]:
    opts = {"extract_flat": True}
    query = q if q.startswith("ytsearch") else f"ytsearch{limit}:{q}"
    try:
        with _ydl(opts) as ydl:
            info = ydl.extract_info(query, download=False)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(502, f"search failed: {e}") from e

    out: list[dict[str, Any]] = []
    for e in info.get("entries") or []:
        if not e or e.get("id") is None:
            continue
        # extract_flat omits duration/views for some entries — keep them anyway.
        thumbs = e.get("thumbnails") or []
        thumb = thumbs[-1]["url"] if thumbs else (
            f"https://i.ytimg.com/vi/{e['id']}/hqdefault.jpg"
        )
        out.append({
            "id": e["id"],
            "title": e.get("title") or "Unknown",
            "artist": e.get("uploader") or e.get("channel")
            or e.get("uploader_id") or "Unknown",
            "duration": int(e.get("duration") or 0),
            "thumbnail": thumb,
            "views": int(e.get("view_count") or 0),
            "channelUrl": e.get("channel_url") or e.get("uploader_url"),
        })
    return out


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
        opts = {
            "format": "bestaudio/best",
            # web client + bgutil PO-token passes the datacenter bot/login wall.
            "extractor_args": {"youtube": {"player_client": ["web"]}},
            # nsig/signature need a JS runtime (deno) + EJS solver scripts;
            # yt-dlp fetches+caches them on first use.
            "remote_components": ["ejs:github"],
            "outtmpl": os.path.join(_CACHE_DIR, "%(id)s.%(ext)s"),
            "skip_download": False,
            # avoid the extractor's mandatory ~5s throttle sleep.
            "sleep_interval": 0,
            "max_sleep_interval": 0,
            "sleep_interval_requests": 0,
            "overwrites": True,
        }
        with _ydl(opts) as ydl:
            ydl.download([f"https://www.youtube.com/watch?v={video_id}"])

    if not (os.path.exists(path) and os.path.getsize(path) > 0):
        raise HTTPException(404, "no audio stream")
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
