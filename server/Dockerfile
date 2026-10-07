FROM python:3.12-slim

LABEL org.opencontainers.image.title="aurora-server"
LABEL org.opencontainers.image.description="Aurora Music resolver — FastAPI + yt-dlp stream proxy"
LABEL org.opencontainers.image.source="https://github.com/abdullaabdullazade/Aurora/tree/main/server"

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg nodejs npm curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir -U yt-dlp yt-dlp-ejs

COPY . .

ENV AURORA_CACHE_DIR=/app/cache \
    AURORA_DATA_DIR=/app/data

RUN mkdir -p /app/cache /app/data

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8000/health || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
