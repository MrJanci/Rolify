# syntax=docker/dockerfile:1.7
FROM python:3.13-slim AS runtime
WORKDIR /app

# ffmpeg-binary kommt via imageio-ffmpeg pip package, aber wir brauchen paar system deps
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY music_acquirer ./music_acquirer
COPY scraper_worker ./scraper_worker
COPY ui_scraper ./ui_scraper

# .spotify-token.json kommt als Volume-Mount (nicht in Image baken)
# Output-Temp-Ordner
RUN mkdir -p /tmp/rolify-dl

ENV PYTHONUNBUFFERED=1
CMD ["python", "-m", "scraper_worker.worker"]
