import yt_dlp
import httpx
import time

opts = {
    "format": "140/bestaudio[ext=m4a]/18",
    "remote_components": ["ejs:github"],
    "extractor_args": {
        "youtube": {
            "player_client": ["android_vr"],
            "fetch_pot": ["never"],
        }
    },
    "skip_download": True,
    "quiet": True,
}

start = time.time()
with yt_dlp.YoutubeDL(opts) as ydl:
    info = ydl.extract_info("https://www.youtube.com/watch?v=9bZkp7q19f0", download=False)
    url = info.get("url")

print(f"Extract took: {time.time() - start:.2f}s")
print(f"URL: {url[:60]}...")
