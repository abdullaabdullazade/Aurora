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
