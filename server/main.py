"""
Aurora Music resolver — FastAPI + yt-dlp.

Why a server: client-side scraping (youtube_explode) gets rate-limited / 403'd
per device IP and breaks when YouTube changes. yt-dlp is the most robust
extractor; running it server-side gives one stable IP, caching, and a clean
range-proxy so the app never talks to googlevideo directly (no 403).

Endpoints:
  GET /health
  GET /search?q=...&limit=20&filter=tracks|playlists|albums|podcasts
                             -> [{id,title,artist,duration,thumbnail,views,kind,url}]
  GET /stream?v=VIDEO_ID          -> audio bytes (HTTP Range supported)

Run:  uvicorn main:app --host 0.0.0.0 --port 8000
Android emulator reaches the host at http://10.0.2.2:8000
"""
from __future__ import annotations

import os
import re
import json
import difflib
import glob
import logging
import socket
import sqlite3
import threading
import time
import unicodedata
from concurrent.futures import Future, ThreadPoolExecutor
from contextlib import contextmanager
from typing import Any
from urllib.parse import quote_plus, urlsplit

import httpx
import yt_dlp
from google.auth.transport.requests import Request as GoogleAuthRequest
from google.oauth2.id_token import verify_firebase_token
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse

app = FastAPI(title="Aurora Resolver")
# uvicorn configures its own loggers at INFO; a fresh one would stay silent.
logger = logging.getLogger("uvicorn.error")


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
    proxies bypasses it entirely (no cookies/PO-token needed). Supported file
    formats are URL, user:pass@ip:port, ip:port:user:pass, and ip:port."""
    global _proxy_cache
    if _proxy_cache:
        return _proxy_cache
    path = os.path.join(os.path.dirname(__file__), "proxies.txt")
    if not os.path.exists(path):
        return []
    out: list[str] = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith(("#", "//")):
                continue
            if "://" in line:
                candidate = line
            elif "@" in line:
                candidate = f"http://{line}"
            else:
                parts = line.split(":")
                if len(parts) == 4:
                    ip, port, user, pw = parts
                    candidate = f"http://{user}:{pw}@{ip}:{port}"
                elif len(parts) == 2:
                    candidate = f"http://{line}"
                else:
                    continue
            try:
                parsed = urlsplit(candidate)
                if parsed.scheme and parsed.hostname and parsed.port:
                    out.append(candidate)
            except ValueError:
                continue
    _proxy_cache = out
    return out


# Only SOME residential exit nodes are clean for YouTube's player API; the rest
# get "Sign in to confirm you're not a bot" regardless of cookies. We discover
# the clean ones (a background warmer probes them in parallel) and reuse them,
# so the common request hits a known-good IP and resolves in ~3s instead of
# burning attempts on flagged nodes.
_good_proxies: list[str] = []
_good_lock = threading.Lock()
_bad_proxies: dict[str, float] = {}
_BAD_PROXY_TTL = 30 * 60
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


def _mark_bad(p: str | None) -> None:
    if not p:
        return
    _drop_good(p)
    with _good_lock:
        _bad_proxies[p] = time.time()


def _pick_proxy(exclude: set[str] | None = None) -> str | None:
    import random
    exclude = exclude or set()
    now = time.time()
    with _good_lock:
        expired = [p for p, ts in _bad_proxies.items()
                   if now - ts >= _BAD_PROXY_TTL]
        for p in expired:
            _bad_proxies.pop(p, None)
        bad = set(_bad_proxies)
        good = [p for p in _good_proxies if p not in exclude and p not in bad]
    if good and random.random() < 0.9:
        return random.choice(good)
    pool = [p for p in _proxies() if p not in exclude and p not in bad]
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
            "youtube": {"player_client": ["default", "mweb", "web_embedded"]}
        },
        "socket_timeout": 12, "retries": 0, "extractor_retries": 0,
        "proxy": proxy,
    }
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(_PROBE_URL, download=False)
        return bool(info and (info.get("formats") or info.get("url")))
    except Exception:  # noqa: BLE001
        _mark_bad(proxy)
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


_LYRICS_MATCH_VERSION = 3


def _match_text(value: str) -> str:
    """Normalize display text for conservative lyrics identity matching."""
    value = _clean(value).casefold().replace("&", " and ")
    value = unicodedata.normalize("NFKD", value)
    value = "".join(ch for ch in value if not unicodedata.combining(ch))
    return re.sub(r"[^\w]+", " ", value, flags=re.UNICODE).strip()


def _match_artist(value: str) -> str:
    value = re.sub(
        r"(?i)\s*[-–—]?\s*(topic|vevo|official|official artist channel)\s*$",
        "",
        value,
    )
    return _match_text(value)


def _text_similarity(left: str, right: str) -> float:
    if not left or not right:
        return 0.0
    if left == right:
        return 1.0
    left_tokens, right_tokens = set(left.split()), set(right.split())
    overlap = (
        2 * len(left_tokens & right_tokens)
        / (len(left_tokens) + len(right_tokens))
    )
    sequence = difflib.SequenceMatcher(None, left, right).ratio()
    return 0.65 * sequence + 0.35 * overlap


def _lyric_identities(title: str, artist: str) -> list[tuple[str, str]]:
    """Likely (track, artist) pairs from YouTube-style metadata."""
    identities = [(_clean(title), artist)]
    split = re.match(r"^\s*(.+?)\s+[-–—]\s+(.+?)\s*$", title)
    if split:
        inferred_artist, inferred_title = split.groups()
        identities.insert(0, (_clean(inferred_title), inferred_artist))

    unique: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for track_name, artist_name in identities:
        key = (_match_text(track_name), _match_artist(artist_name))
        if key[0] and key not in seen:
            seen.add(key)
            unique.append((track_name, artist_name))
    return unique


def _lyric_hit_score(
    hit: dict[str, Any],
    identities: list[tuple[str, str]],
    duration: int,
) -> float | None:
    candidate_title = _match_text(str(hit.get("trackName") or ""))
    candidate_artist = _match_artist(str(hit.get("artistName") or ""))
    candidate_duration = int(float(hit.get("duration") or 0))

    duration_score = 0.0
    if duration > 0 and candidate_duration > 0:
        delta = abs(duration - candidate_duration)
        tolerance = max(8, min(18, round(duration * 0.08)))
        if delta > tolerance:
            return None
        duration_score = 1 - delta / tolerance

    best: float | None = None
    for title, artist in identities:
        title_score = _text_similarity(_match_text(title), candidate_title)
        if title_score < 0.78:
            continue

        expected_artist = _match_artist(artist)
        artist_score = _text_similarity(expected_artist, candidate_artist)
        if expected_artist and candidate_artist and artist_score < 0.45:
            # Only allow unreliable YouTube channel metadata to disagree when
            # both title and duration are virtually exact.
            if title_score < 0.94 or duration_score < 0.85:
                continue
        elif expected_artist and not candidate_artist and title_score < 0.94:
            continue

        # Synced lyrics are a tie-breaker, never a substitute for identity.
        score = (
            0.70 * title_score
            + 0.22 * artist_score
            + 0.08 * duration_score
            + (0.02 if hit.get("syncedLyrics") else 0.0)
        )
        best = score if best is None else max(best, score)
    return best


def _select_lyric_hit(
    hits: list[dict[str, Any]],
    identities: list[tuple[str, str]],
    duration: int,
) -> dict[str, Any] | None:
    scored = [
        (score, hit)
        for hit in hits
        if (score := _lyric_hit_score(hit, identities, duration)) is not None
    ]
    return max(scored, key=lambda item: item[0])[1] if scored else None


def _lyrics_timing(
    synced: list[dict[str, Any]], duration: int
) -> tuple[bool, str | None, float | None]:
    """Assess whether LRC timestamps plausibly fit this particular version.

    LRCLIB can have separate long/short video metadata pointing to the exact
    same album-version LRC. Metadata matching alone therefore isn't enough.
    """
    if not synced or duration <= 0:
        return True, None, None
    first = float(synced[0]["time"])
    last = float(synced[-1]["time"])
    if last > duration + 3:
        return False, "timestamps_outside_track", None

    trailing_gap = duration - last
    suspicious_gap = max(25.0, duration * 0.08)
    if first < 5 and trailing_gap > suspicious_gap:
        # Most normal LRC files leave roughly 5–10 seconds after the last line.
        # A large remaining gap plus an immediate first line strongly suggests
        # that a video intro was prepended to album-version timestamps.
        suggested = round(max(0.0, trailing_gap - 8.0), 1)
        return False, "possible_video_intro", suggested
    return True, None, None


def _lyrics_response(
    hit: dict[str, Any] | None, duration: int = 0
) -> dict[str, Any]:
    if not hit:
        return {
            "synced": [], "plain": "", "source": "lrclib", "found": False,
            "matchVersion": _LYRICS_MATCH_VERSION,
            "timingReliable": True,
        }
    synced = _parse_lrc(hit.get("syncedLyrics") or "")
    timing_reliable, timing_issue, suggested_offset = _lyrics_timing(
        synced, duration
    )
    return {
        "synced": synced,
        "plain": hit.get("plainLyrics") or "",
        "found": bool(synced or hit.get("plainLyrics")),
        "source": "lrclib",
        "matchVersion": _LYRICS_MATCH_VERSION,
        "matchedTitle": hit.get("trackName") or "",
        "matchedArtist": hit.get("artistName") or "",
        "matchedDuration": int(float(hit.get("duration") or 0)),
        "timingReliable": timing_reliable,
        "timingIssue": timing_issue,
        "suggestedOffset": suggested_offset,
    }


@app.get("/health")
def health() -> dict[str, bool]:
    return {"ok": True}


_DATA_DIR = os.path.abspath(os.environ.get(
    "AURORA_DATA_DIR",
    os.path.join(os.path.dirname(__file__), "data"),
))
_USER_DB = os.path.join(_DATA_DIR, "users.sqlite3")
_user_db_lock = threading.Lock()
_user_db_ready = False


def _init_user_db() -> None:
    global _user_db_ready
    if _user_db_ready:
        return
    with _user_db_lock:
        if _user_db_ready:
            return
        os.makedirs(_DATA_DIR, exist_ok=True)
        with sqlite3.connect(_USER_DB, timeout=30) as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.execute("""
                CREATE TABLE IF NOT EXISTS user_records (
                    uid TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    item_id TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    deleted INTEGER NOT NULL DEFAULT 0,
                    updated_at REAL NOT NULL,
                    PRIMARY KEY (uid, kind, item_id)
                )
            """)
        _user_db_ready = True


def _firebase_uid(request: Request) -> str:
    project_id = os.environ.get("FIREBASE_PROJECT_ID", "").strip()
    authorization = request.headers.get("authorization", "")
    if not project_id:
        raise HTTPException(503, "user sync is not configured")
    if not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "missing Firebase ID token")
    token = authorization.split(" ", 1)[1].strip()
    try:
        claims = verify_firebase_token(
            token,
            GoogleAuthRequest(),
            audience=project_id,
        )
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(401, "invalid Firebase ID token") from exc
    uid = claims.get("sub") or claims.get("user_id")
    if not isinstance(uid, str) or not uid:
        raise HTTPException(401, "invalid Firebase user")
    return uid


def _valid_sync_item(kind: str, item: dict[str, Any]) -> tuple[str, str]:
    if kind not in {"playlists", "favorites", "state"}:
        raise HTTPException(400, "invalid sync record kind")
    item_id = item.get("id")
    if not isinstance(item_id, str) or not re.fullmatch(
        r"[A-Za-z0-9_-]{1,128}", item_id
    ):
        raise HTTPException(400, "invalid sync record ID")
    encoded = json.dumps(item, ensure_ascii=False, separators=(",", ":"))
    max_size = 20 * 1024 * 1024 if kind == "state" else 2 * 1024 * 1024
    if len(encoded.encode("utf-8")) > max_size:
        raise HTTPException(413, "sync record is too large")
    return item_id, encoded


def _upsert_sync_items(
    db: sqlite3.Connection,
    uid: str,
    kind: str,
    items: list[dict[str, Any]],
) -> int:
    now = time.time()
    count = 0
    for item in items:
        item_id, encoded = _valid_sync_item(kind, item)
        db.execute("""
            INSERT INTO user_records
                (uid, kind, item_id, payload, deleted, updated_at)
            VALUES (?, ?, ?, ?, 0, ?)
            ON CONFLICT(uid, kind, item_id) DO UPDATE SET
                payload = excluded.payload,
                deleted = 0,
                updated_at = excluded.updated_at
        """, (uid, kind, item_id, encoded, now))
        count += 1
    return count


@app.get("/sync")
def sync_down(request: Request) -> dict[str, Any]:
    uid = _firebase_uid(request)
    _init_user_db()
    result: dict[str, Any] = {
        "playlists": [],
        "favorites": [],
        "deletedPlaylists": [],
        "deletedFavorites": [],
        "state": None,
    }
    with sqlite3.connect(_USER_DB, timeout=30) as db:
        rows = db.execute(
            "SELECT kind, item_id, payload, deleted FROM user_records "
            "WHERE uid = ? ORDER BY updated_at ASC",
            (uid,),
        ).fetchall()
    for kind, item_id, payload, deleted in rows:
        if kind == "state":
            if not deleted:
                result["state"] = json.loads(payload).get("data")
            continue
        if deleted:
            result["deletedPlaylists" if kind == "playlists"
                   else "deletedFavorites"].append(item_id)
        else:
            result[kind].append(json.loads(payload))
    return result


@app.put("/sync")
def sync_up(payload: dict[str, Any], request: Request) -> dict[str, int]:
    uid = _firebase_uid(request)
    playlists = payload.get("playlists", [])
    favorites = payload.get("favorites", [])
    state = payload.get("state")
    if not isinstance(playlists, list) or not all(
        isinstance(item, dict) for item in playlists
    ):
        raise HTTPException(400, "playlists must be a list")
    if not isinstance(favorites, list) or not all(
        isinstance(item, dict) for item in favorites
    ):
        raise HTTPException(400, "favorites must be a list")
    if state is not None and not isinstance(state, dict):
        raise HTTPException(400, "state must be an object")
    _init_user_db()
    with _user_db_lock, sqlite3.connect(_USER_DB, timeout=30) as db:
        playlist_count = _upsert_sync_items(db, uid, "playlists", playlists)
        favorite_count = _upsert_sync_items(db, uid, "favorites", favorites)
        if state is not None:
            _upsert_sync_items(
                db, uid, "state", [{"id": "snapshot", "data": state}]
            )
    return {
        "playlists": playlist_count,
        "favorites": favorite_count,
        "state": 1 if state is not None else 0,
    }


@app.put("/sync/{kind}/{item_id}")
def sync_one(
    kind: str,
    item_id: str,
    payload: dict[str, Any],
    request: Request,
) -> dict[str, bool]:
    uid = _firebase_uid(request)
    payload = {**payload, "id": item_id}
    _init_user_db()
    with _user_db_lock, sqlite3.connect(_USER_DB, timeout=30) as db:
        _upsert_sync_items(db, uid, kind, [payload])
    return {"ok": True}


@app.delete("/sync/{kind}/{item_id}")
def delete_sync_item(
    kind: str,
    item_id: str,
    request: Request,
) -> dict[str, bool]:
    uid = _firebase_uid(request)
    _valid_sync_item(kind, {"id": item_id})
    _init_user_db()
    with _user_db_lock, sqlite3.connect(_USER_DB, timeout=30) as db:
        db.execute("""
            INSERT INTO user_records
                (uid, kind, item_id, payload, deleted, updated_at)
            VALUES (?, ?, ?, '{}', 1, ?)
            ON CONFLICT(uid, kind, item_id) DO UPDATE SET
                payload = '{}',
                deleted = 1,
                updated_at = excluded.updated_at
        """, (uid, kind, item_id, time.time()))
    return {"ok": True}


def _entry(e: dict[str, Any], *, kind: str = "track") -> dict[str, Any]:
    """One flat yt-dlp entry -> the track shape the app expects."""
    # extract_flat omits duration/views for some entries — keep them anyway.
    eid = e.get("id") or ""
    thumbs = e.get("thumbnails") or []
    thumb = thumbs[-1]["url"] if thumbs else (
        f"https://i.ytimg.com/vi/{eid}/hqdefault.jpg"
        if kind == "track"
        else ""
    )
    url = e.get("url") or e.get("webpage_url") or ""
    if kind != "track" and not url and eid:
        url = f"https://www.youtube.com/playlist?list={eid}"
    if kind == "track" and not url and eid:
        url = f"https://www.youtube.com/watch?v={eid}"
    return {
        "id": eid,
        "title": e.get("title") or "Unknown",
        "artist": e.get("uploader") or e.get("channel")
        or e.get("uploader_id") or "Unknown",
        "duration": int(e.get("duration") or 0),
        "thumbnail": thumb,
        "views": int(e.get("view_count") or e.get("playlist_count") or 0),
        "channelUrl": e.get("channel_url") or e.get("uploader_url"),
        "kind": kind,
        "url": url,
        "live": bool(
            e.get("is_live")
            or e.get("live_status") in ("is_live", "is_upcoming")
        ),
    }


def _entries(info: dict[str, Any], *, kind: str = "track") -> list[dict[str, Any]]:
    return [
        _entry(e, kind=kind)
        for e in (info.get("entries") or [])
        if e and e.get("id")
    ]


def _flat_opts() -> dict[str, Any]:
    opts: dict[str, Any] = {"extract_flat": True}
    proxy = _pick_proxy()
    if proxy:
        opts["proxy"] = proxy
    return opts


# YouTube /results type=playlist filter (base64 protobuf sp=).
_YT_SP_PLAYLIST = "EgIQAw%3D%3D"


@app.get("/search")
def search(
    q: str,
    limit: int = 20,
    filter: str = "tracks",
) -> list[dict[str, Any]]:
    """Search YouTube. filter: tracks | playlists | albums | podcasts."""
    kind_map = {
        "tracks": "track",
        "playlists": "playlist",
        "albums": "album",
        "podcasts": "podcast",
    }
    f = (filter or "tracks").lower().strip()
    if f not in kind_map:
        raise HTTPException(400, f"unknown filter: {filter}")
    kind = kind_map[f]

    query = (q or "").strip()
    if not query:
        return []

    try:
        if f == "tracks":
            ytdl_q = (
                query if query.startswith("ytsearch")
                else f"ytsearch{limit}:{query}"
            )
            with _ydl(_flat_opts()) as ydl:
                info = ydl.extract_info(ytdl_q, download=False)
        else:
            search_q = query
            if f == "albums" and "album" not in query.lower():
                search_q = f"{query} album"
            elif f == "podcasts" and "podcast" not in query.lower():
                search_q = f"{query} podcast"
            url = (
                "https://www.youtube.com/results?"
                f"search_query={quote_plus(search_q)}&sp={_YT_SP_PLAYLIST}"
            )
            opts = _flat_opts()
            # Without a cap yt-dlp walks every results page (~250 hits, 10-25s).
            opts["playlistend"] = max(1, min(limit, 50))
            with _ydl(opts) as ydl:
                info = ydl.extract_info(url, download=False)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(502, f"search failed: {e}") from e

    rows = _entries(info or {}, kind=kind)
    return rows[: max(1, min(limit, 50))]


@app.get("/playlist")
def playlist(url: str, limit: int = 100) -> dict[str, Any]:
    """Import a YouTube playlist / album / mix URL as a track list."""
    opts = _flat_opts()
    opts["noplaylist"] = False
    opts["playlistend"] = limit
    try:
        with _ydl(opts, use_cookies=True) as ydl:
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


@app.get("/youtube/subscriptions")
def youtube_subscriptions(request: Request, limit: int = 20) -> list[dict[str, Any]]:
    """Recent uploads from the signed-in user's YouTube subscriptions."""
    token = request.headers.get("x-google-access-token", "").strip()
    if not token:
        raise HTTPException(401, "Missing Google access token")
    api_key = os.environ.get("YOUTUBE_API_KEY", "").strip()
    if not api_key:
        raise HTTPException(503, "YouTube API key not configured")

    limit = max(1, min(limit, 30))
    tracks: list[dict[str, Any]] = []
    seen: set[str] = set()
    headers = {"Authorization": f"Bearer {token}"}

    try:
        with httpx.Client(timeout=15) as cx:
            subs_resp = cx.get(
                "https://www.googleapis.com/youtube/v3/subscriptions",
                params={
                    "part": "snippet,contentDetails",
                    "mine": "true",
                    "maxResults": 15,
                    "key": api_key,
                },
                headers=headers,
            )
            subs_resp.raise_for_status()
            for sub in subs_resp.json().get("items") or []:
                uploads = (
                    sub.get("contentDetails", {})
                    .get("relatedPlaylists", {})
                    .get("uploads")
                )
                if not uploads:
                    continue
                items_resp = cx.get(
                    "https://www.googleapis.com/youtube/v3/playlistItems",
                    params={
                        "part": "snippet,contentDetails",
                        "playlistId": uploads,
                        "maxResults": 2,
                        "key": api_key,
                    },
                    headers=headers,
                )
                items_resp.raise_for_status()
                for item in items_resp.json().get("items") or []:
                    vid = item.get("contentDetails", {}).get("videoId")
                    snippet = item.get("snippet") or {}
                    if not vid or vid in seen:
                        continue
                    seen.add(vid)
                    thumbs = snippet.get("thumbnails") or {}
                    thumb_obj = (
                        thumbs.get("high")
                        or thumbs.get("medium")
                        or thumbs.get("default")
                        or {}
                    )
                    tracks.append(
                        {
                            "id": vid,
                            "title": snippet.get("title") or "Unknown",
                            "artist": snippet.get("channelTitle") or "Unknown",
                            "duration": 0,
                            "thumbnail": thumb_obj.get("url")
                            or f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg",
                            "views": 0,
                            "channelUrl": None,
                        }
                    )
                    if len(tracks) >= limit:
                        return tracks
    except httpx.HTTPStatusError as e:
        raise HTTPException(502, f"YouTube API error: {e.response.text}") from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(502, f"subscriptions failed: {e}") from e
    return tracks


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
    """Return lyrics only when title, artist and duration identify the track."""
    identities = _lyric_identities(title, artist)
    with httpx.Client(timeout=12, follow_redirects=True) as cx:
        # Exact lookups are cheapest and safest. YouTube commonly formats a
        # title as "Artist - Track", so also try that inferred identity.
        for track_name, artist_name in identities:
            if not artist_name:
                continue
            try:
                params: dict[str, Any] = {
                    "track_name": track_name,
                    "artist_name": artist_name,
                }
                if duration > 0:
                    params["duration"] = duration
                r = cx.get("https://lrclib.net/api/get", params=params)
                if r.status_code == 200:
                    exact = _select_lyric_hit([r.json()], identities, duration)
                    if exact:
                        return _lyrics_response(exact, duration)
            except Exception:  # noqa: BLE001
                pass

        # Fuzzy search is allowed only as candidate discovery. Every result is
        # scored below; the first LRCLIB result is never trusted implicitly.
        candidates: dict[str, dict[str, Any]] = {}
        for track_name, artist_name in identities:
            try:
                query = f"{track_name} {artist_name}".strip()
                r = cx.get("https://lrclib.net/api/search", params={"q": query})
                arr = r.json() if r.status_code == 200 else []
                for candidate in arr if isinstance(arr, list) else []:
                    if not isinstance(candidate, dict):
                        continue
                    key = str(candidate.get("id") or (
                        candidate.get("trackName"),
                        candidate.get("artistName"),
                        candidate.get("duration"),
                    ))
                    candidates[key] = candidate
            except Exception:  # noqa: BLE001
                pass

    return _lyrics_response(
        _select_lyric_hit(list(candidates.values()), identities, duration),
        duration,
    )


_CACHE_DIR = os.path.abspath(os.environ.get(
    "AURORA_CACHE_DIR",
    os.path.join(os.path.dirname(__file__), "cache"),
))
_CACHE_DB = os.path.join(_CACHE_DIR, "cache.sqlite3")
_cache_db_lock = threading.Lock()
_cache_db_ready = False
_dl_locks: dict[str, threading.Lock] = {}
_dl_locks_guard = threading.Lock()


def _lock_for(video_id: str) -> threading.Lock:
    with _dl_locks_guard:
        lk = _dl_locks.get(video_id)
        if lk is None:
            lk = _dl_locks[video_id] = threading.Lock()
        return lk


@contextmanager
def _cross_process_lock(video_id: str):
    """Serialize yt-dlp across uvicorn workers (in-memory locks are per-process)."""
    os.makedirs(_CACHE_DIR, exist_ok=True)
    lock_path = os.path.join(_CACHE_DIR, f".{video_id}.lock")
    with open(lock_path, "a+", encoding="utf-8") as fh:
        try:
            import fcntl

            fcntl.flock(fh.fileno(), fcntl.LOCK_EX)
        except ImportError:
            # Windows / non-POSIX: rely on the in-process threading lock only.
            pass
        try:
            yield
        finally:
            try:
                import fcntl

                fcntl.flock(fh.fileno(), fcntl.LOCK_UN)
            except ImportError:
                pass


def _init_cache_db() -> None:
    """Create the persistent YouTube-ID index and adopt existing cache files."""
    global _cache_db_ready
    if _cache_db_ready:
        return
    with _cache_db_lock:
        if _cache_db_ready:
            return
        os.makedirs(_CACHE_DIR, exist_ok=True)
        with sqlite3.connect(_CACHE_DB, timeout=30) as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.execute("""
                CREATE TABLE IF NOT EXISTS tracks (
                    video_id TEXT PRIMARY KEY,
                    filename TEXT NOT NULL,
                    size_bytes INTEGER NOT NULL,
                    created_at REAL NOT NULL,
                    last_accessed REAL NOT NULL
                )
            """)
            # Files copied from the old /tmp cache are indexed automatically.
            import glob
            now = time.time()
            for path in glob.glob(os.path.join(_CACHE_DIR, "*.mp4")):
                video_id = os.path.splitext(os.path.basename(path))[0]
                if re.fullmatch(r"[A-Za-z0-9_-]{6,64}", video_id):
                    db.execute("""
                        INSERT OR IGNORE INTO tracks
                            (video_id, filename, size_bytes, created_at, last_accessed)
                        VALUES (?, ?, ?, ?, ?)
                    """, (video_id, os.path.basename(path),
                          os.path.getsize(path), now, now))
        _cache_db_ready = True


def _cache_put(video_id: str, path: str) -> None:
    _init_cache_db()
    now = time.time()
    with sqlite3.connect(_CACHE_DB, timeout=30) as db:
        db.execute("""
            INSERT INTO tracks
                (video_id, filename, size_bytes, created_at, last_accessed)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(video_id) DO UPDATE SET
                filename = excluded.filename,
                size_bytes = excluded.size_bytes,
                last_accessed = excluded.last_accessed
        """, (video_id, os.path.basename(path), os.path.getsize(path), now, now))


def _cache_get(video_id: str) -> str | None:
    _init_cache_db()
    with sqlite3.connect(_CACHE_DB, timeout=30) as db:
        row = db.execute(
            "SELECT filename FROM tracks WHERE video_id = ?", (video_id,)
        ).fetchone()
        if row:
            path = os.path.join(_CACHE_DIR, row[0])
            if os.path.isfile(path) and os.path.getsize(path) > 0:
                db.execute(
                    "UPDATE tracks SET last_accessed = ? WHERE video_id = ?",
                    (time.time(), video_id),
                )
                return path
            db.execute("DELETE FROM tracks WHERE video_id = ?", (video_id,))
    return None


def _cache_count() -> int:
    _init_cache_db()
    with sqlite3.connect(_CACHE_DB, timeout=30) as db:
        return int(db.execute("SELECT COUNT(*) FROM tracks").fetchone()[0])


def _cache_max_bytes() -> int | None:
    """Return the configured byte limit, or None for an unlimited cache.

    AURORA_CACHE_MAX_BYTES accepts a byte count, values such as 10GB/500MB,
    or unlimited/none/0. The safe default is unlimited: cached songs are never
    deleted unless the operator explicitly configures a finite limit.
    """
    raw = os.environ.get("AURORA_CACHE_MAX_BYTES", "unlimited").strip().lower()
    if raw in {"", "0", "none", "unlimited", "infinite", "inf"}:
        return None
    match = re.fullmatch(r"(\d+(?:\.\d+)?)\s*(b|kb|mb|gb|tb)?", raw)
    if not match:
        raise RuntimeError(
            "AURORA_CACHE_MAX_BYTES must be unlimited or a size such as 10GB"
        )
    value = float(match.group(1))
    multiplier = {
        None: 1,
        "b": 1,
        "kb": 1024,
        "mb": 1024 ** 2,
        "gb": 1024 ** 3,
        "tb": 1024 ** 4,
    }[match.group(2)]
    return int(value * multiplier)


def _enforce_cache_limit(protected_video_id: str) -> None:
    """Evict least-recently-used tracks only when a finite limit is set."""
    limit = _cache_max_bytes()
    if limit is None:
        return
    _init_cache_db()
    with _cache_db_lock, sqlite3.connect(_CACHE_DB, timeout=30) as db:
        rows = db.execute(
            "SELECT video_id, filename, size_bytes FROM tracks "
            "ORDER BY last_accessed ASC"
        ).fetchall()
        total = sum(int(row[2]) for row in rows)
        for video_id, filename, size_bytes in rows:
            if total <= limit:
                break
            # Never delete the track that has just been downloaded. A single
            # large track may therefore temporarily exceed a very small limit.
            if video_id == protected_video_id:
                continue
            path = os.path.join(_CACHE_DIR, filename)
            try:
                if os.path.isfile(path):
                    os.remove(path)
                db.execute("DELETE FROM tracks WHERE video_id = ?", (video_id,))
                total -= int(size_bytes)
            except OSError:
                continue


def _promote_download(download_dir: str, path: str) -> str | None:
    """Atomically publish a completed yt-dlp file into the stream cache.

    yt-dlp leaves non-empty .part/.ytdl files behind when YouTube or a proxy
    disconnects. The old glob accepted those files as playable audio, which
    made an intermittent resolver failure poison every later play from cache.
    Downloads now happen in an isolated directory and only final media files
    are moved to the canonical path.
    """
    import glob
    candidates: list[str] = []
    for extension in ("m4a", "mp4"):
        candidates.extend(glob.glob(os.path.join(download_dir, f"*.{extension}")))
    candidates = [
        candidate for candidate in candidates
        if os.path.isfile(candidate) and os.path.getsize(candidate) > 0
    ]
    if not candidates:
        return None
    # There should be one file, but prefer the largest completed media file if
    # an extractor happens to leave more than one final format behind.
    selected = max(candidates, key=os.path.getsize)
    os.replace(selected, path)
    return path


def _ensure_local(video_id: str) -> str:
    """Download the track to a local cache file and return its path.

    Why download instead of proxying the googlevideo URL directly: on a
    datacenter IP the web client only yields progressive format 18, whose URL
    is SABR/PO-token-gated and 403s on a plain GET. yt-dlp itself negotiates
    SABR + the bgutil PO-token + nsig (deno/EJS), so we let it pull the bytes
    once and serve the cached file (Range-seekable) to the app.
    """
    if not re.fullmatch(r"[A-Za-z0-9_-]{6,64}", video_id):
        raise HTTPException(400, "invalid YouTube video ID")
    cached = _cache_get(video_id)
    if cached:
        return cached
    path = os.path.join(_CACHE_DIR, f"{video_id}.mp4")

    lock = _lock_for(video_id)
    with lock, _cross_process_lock(video_id):
        # Another request may have finished it while we waited.
        cached = _cache_get(video_id)
        if cached:
            return cached
        import shutil
        import tempfile
        os.makedirs(_CACHE_DIR, exist_ok=True)
        url = f"https://www.youtube.com/watch?v={video_id}"
        # Retry with a fresh residential IP each attempt (a flagged exit node
        # fails fast thanks to socket_timeout). Do NOT force player_client:
        # pinning web/web_safari/mweb forces the SABR/PO-token path, which hangs
        # for ~minutes when bgutil's get_pot stalls. yt-dlp's default client set
        # picks a non-PO client and pulls the bytes in ~1s (proven manually).
        last_err: Exception | None = None
        started = time.monotonic()
        # Many fast attempts with a short timeout beat few slow ones: a good
        # residential proxy pulls the bytes in ~2-4s, a dead one is abandoned in
        # ~8s and we hop to the next exit node — so first-byte stays under the
        # player's ~8s connect timeout in the common case.
        used_proxies: set[str] = set()
        for attempt in range(6):
            download_dir = tempfile.mkdtemp(
                prefix=f".{video_id}-", dir=_CACHE_DIR
            )
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
                        "player_client": ["default", "mweb", "web_embedded"]
                    }
                },
                "outtmpl": os.path.join(download_dir, f"{video_id}.%(ext)s"),
                # The .part file is streamed to the first listener while it
                # grows, so the finished file must be that same inode: an
                # ffmpeg remux would swap it and break the in-flight stream.
                # ExoPlayer plays YouTube's fragmented m4a as is.
                "fixup": "never",
                "skip_download": False,
                "overwrites": True,
                "retries": 1,
                "extractor_retries": 1,
                # Dead/slow proxy is abandoned fast so we hop to a fresh IP.
                "socket_timeout": 12,
            }
            proxy = _pick_proxy(exclude=used_proxies)
            if proxy:
                opts["proxy"] = proxy
                used_proxies.add(proxy)
            try:
                # Fresh logged-in cookies (auto-refreshed from the VPS Chrome)
                # ride along on a clean residential IP — unlocks restricted
                # formats and matches the account; the clean IP is what actually
                # clears the bot wall.
                with _ydl(opts, use_cookies=True) as ydl:
                    ydl.download([url])
                # The real extension (.m4a/.mp4) varies. Publish only after a
                # complete download so stream readers never see partial bytes.
                got = _promote_download(download_dir, path)
                if got:
                    if proxy:
                        _record_good(proxy)
                    _cache_put(video_id, got)
                    _enforce_cache_limit(video_id)
                    logger.info(
                        "download %s ok attempt=%d %.1fs %d bytes",
                        video_id, attempt + 1, time.monotonic() - started,
                        os.path.getsize(got),
                    )
                    return got
            except Exception as e:  # noqa: BLE001
                last_err = e
                logger.info(
                    "download %s attempt=%d failed after %.1fs: %s",
                    video_id, attempt + 1, time.monotonic() - started, e,
                )
                if proxy:
                    _mark_bad(proxy)
            finally:
                shutil.rmtree(download_dir, ignore_errors=True)
            # brief backoff before the next attempt
            if attempt < 5:
                time.sleep(0.5)

    if not (os.path.exists(path) and os.path.getsize(path) > 0):
        raise HTTPException(404, f"no audio stream: {last_err}")
    _cache_put(video_id, path)
    _enforce_cache_limit(video_id)
    return path


def _parse_range(rng: str, size: int) -> tuple[int, int]:
    m = re.fullmatch(r"bytes=(\d*)-(\d*)", (rng or "").strip())
    if size <= 0 or not m or (not m.group(1) and not m.group(2)):
        raise HTTPException(
            416, "invalid byte range", headers={"Content-Range": f"bytes */{size}"}
        )
    a, b = m.group(1), m.group(2)
    if a == "":  # suffix range: last N bytes
        n = int(b)
        if n <= 0:
            raise HTTPException(
                416, "invalid byte range",
                headers={"Content-Range": f"bytes */{size}"},
            )
        return max(0, size - n), size - 1
    start = int(a)
    end = int(b) if b else size - 1
    if start >= size or end < start:
        raise HTTPException(
            416, "range not satisfiable",
            headers={"Content-Range": f"bytes */{size}"},
        )
    return start, min(end, size - 1)


_bg_downloads: dict[str, Future] = {}
_bg_downloads_lock = threading.Lock()
_bg_executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="aurora-dl")
# How long a cold request waits for yt-dlp to write its first bytes.
_PROGRESSIVE_START_TIMEOUT = 60.0
# A growing file that stops growing this long is treated as a dead download.
_PROGRESSIVE_STALL_TIMEOUT = 60.0
_PROGRESSIVE_POLL = 0.1
_CHUNK = 64 * 1024


def _start_background_download(video_id: str) -> Future:
    """One _ensure_local per video per process, shared by every listener."""
    with _bg_downloads_lock:
        future = _bg_downloads.get(video_id)
        if future is None or future.done():
            future = _bg_executor.submit(_ensure_local, video_id)
            _bg_downloads[video_id] = future

            def forget(done: Future, video_id: str = video_id) -> None:
                with _bg_downloads_lock:
                    if _bg_downloads.get(video_id) is done:
                        del _bg_downloads[video_id]

            future.add_done_callback(forget)
        return future


def _partial_download(video_id: str) -> str | None:
    """The .part file yt-dlp is writing for this video, in any worker."""
    pattern = os.path.join(
        glob.escape(_CACHE_DIR), f".{video_id}-*", f"{video_id}.*.part"
    )
    best: tuple[int, str] | None = None
    for candidate in glob.glob(pattern):
        try:
            size = os.path.getsize(candidate)
        except OSError:
            continue
        if size > 0 and (best is None or size > best[0]):
            best = (size, candidate)
    return best[1] if best else None


def _is_progressive_range(rng: str | None) -> bool:
    return not rng or bool(re.fullmatch(r"bytes=0-\d*", rng.strip()))


def _wait_for_source(video_id: str, future: Future) -> tuple[str, str]:
    """Block until the track is cached ("file") or has started ("part")."""
    final_path = os.path.join(_CACHE_DIR, f"{video_id}.mp4")
    deadline = time.monotonic() + _PROGRESSIVE_START_TIMEOUT
    while True:
        if future.done():
            return "file", future.result()
        if os.path.isfile(final_path):
            cached = _cache_get(video_id)
            if cached:
                return "file", cached
        part = _partial_download(video_id)
        if part:
            return "part", part
        if time.monotonic() > deadline:
            raise HTTPException(504, "download did not start in time")
        time.sleep(_PROGRESSIVE_POLL)


def _tail_growing_file(fh, part_path: str, limit: int | None):
    """Yield bytes of a file yt-dlp is still writing until it is complete.

    yt-dlp renames the finished .part into place (same inode, still linked);
    a failed attempt deletes its temp dir (inode unlinked). Ending the body
    early on failure would look like a short song, so that raises instead and
    the client sees a broken connection it can retry.
    """
    remaining = limit
    idle_since = time.monotonic()
    try:
        while remaining is None or remaining > 0:
            want = _CHUNK if remaining is None else min(_CHUNK, remaining)
            chunk = fh.read(want)
            if chunk:
                if remaining is not None:
                    remaining -= len(chunk)
                idle_since = time.monotonic()
                yield chunk
                continue
            if not os.path.exists(part_path):
                if os.fstat(fh.fileno()).st_nlink == 0:
                    raise RuntimeError("download attempt failed mid-stream")
                tail = fh.read(want)
                if not tail:
                    return
                if remaining is not None:
                    remaining -= len(tail)
                yield tail
                continue
            if time.monotonic() - idle_since > _PROGRESSIVE_STALL_TIMEOUT:
                raise RuntimeError("download stalled mid-stream")
            time.sleep(_PROGRESSIVE_POLL)
    finally:
        fh.close()


def _progressive_response(
    part_path: str, rng: str | None
) -> StreamingResponse | None:
    """Stream a download in progress; None if it finished meanwhile."""
    try:
        fh = open(part_path, "rb")
    except FileNotFoundError:
        return None
    headers = {"accept-ranges": "bytes", "content-type": "audio/mp4"}
    end = None
    if rng:
        m = re.fullmatch(r"bytes=0-(\d*)", rng.strip())
        if m and m.group(1):
            end = int(m.group(1))
    if end is None:
        # Total length is unknown until yt-dlp finishes: plain chunked 200.
        return StreamingResponse(
            _tail_growing_file(fh, part_path, None), headers=headers
        )
    length = end + 1
    deadline = time.monotonic() + _PROGRESSIVE_STALL_TIMEOUT
    while os.fstat(fh.fileno()).st_size < length and os.path.exists(part_path):
        if time.monotonic() > deadline:
            fh.close()
            raise HTTPException(504, "download stalled")
        time.sleep(_PROGRESSIVE_POLL)
    if os.fstat(fh.fileno()).st_size < length:
        fh.close()
        return None
    headers["content-range"] = f"bytes 0-{end}/*"
    headers["content-length"] = str(length)
    return StreamingResponse(
        _tail_growing_file(fh, part_path, length),
        status_code=206,
        headers=headers,
    )


@app.get("/stream")
def stream(v: str, request: Request) -> StreamingResponse:
    if not re.fullmatch(r"[A-Za-z0-9_-]{6,64}", v):
        raise HTTPException(400, "invalid YouTube video ID")
    rng = request.headers.get("range")
    try:
        path = _cache_get(v)
        if path is None and _is_progressive_range(rng):
            # Cold track: start playback from the bytes yt-dlp has so far
            # instead of making the player wait for the whole file.
            kind, source = _wait_for_source(v, _start_background_download(v))
            if kind == "part":
                response = _progressive_response(source, rng)
                if response is not None:
                    return response
                path = _ensure_local(v)
            else:
                path = source
        elif path is None:
            path = _ensure_local(v)
    except HTTPException:
        raise
    except Exception as e:  # noqa: BLE001
        raise HTTPException(502, f"resolve failed: {e}") from e

    size = os.path.getsize(path)
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
