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

import re
import time
from typing import Any

import httpx
import yt_dlp
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse

app = FastAPI(title="Aurora Resolver")

# tiny in-memory cache: video_id -> (expiry_ts, direct_url, headers)
_stream_cache: dict[str, tuple[float, str, dict[str, str]]] = {}
_CACHE_TTL = 60 * 30  # 30 min (well under googlevideo expiry)


def _ydl(opts: dict[str, Any]) -> yt_dlp.YoutubeDL:
    base = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "noplaylist": True,
    }
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


def _resolve(video_id: str) -> tuple[str, dict[str, str]]:
    cached = _stream_cache.get(video_id)
    if cached and cached[0] > time.time():
        return cached[1], cached[2]

    opts = {"format": "bestaudio[ext=m4a]/bestaudio/best"}
    with _ydl(opts) as ydl:
        info = ydl.extract_info(
            f"https://www.youtube.com/watch?v={video_id}", download=False
        )
    url = info.get("url")
    if not url:
        raise HTTPException(404, "no audio stream")
    headers = info.get("http_headers") or {}
    _stream_cache[video_id] = (time.time() + _CACHE_TTL, url, headers)
    return url, headers


@app.get("/stream")
async def stream(v: str, request: Request) -> StreamingResponse:
    try:
        url, up_headers = _resolve(v)
    except HTTPException:
        raise
    except Exception as e:  # noqa: BLE001
        raise HTTPException(502, f"resolve failed: {e}") from e

    # Forward the client's Range so just_audio can seek.
    fwd = dict(up_headers)
    rng = request.headers.get("range")
    if rng:
        fwd["Range"] = rng

    client = httpx.AsyncClient(timeout=None, follow_redirects=True)
    upstream = await client.send(
        client.build_request("GET", url, headers=fwd), stream=True
    )

    async def body():
        try:
            async for chunk in upstream.aiter_bytes(64 * 1024):
                yield chunk
        finally:
            await upstream.aclose()
            await client.aclose()

    passthru = {}
    for h in ("content-range", "content-length", "accept-ranges", "content-type"):
        if h in upstream.headers:
            passthru[h] = upstream.headers[h]
    passthru.setdefault("content-type", "audio/mp4")
    passthru.setdefault("accept-ranges", "bytes")

    return StreamingResponse(
        body(), status_code=upstream.status_code, headers=passthru
    )
