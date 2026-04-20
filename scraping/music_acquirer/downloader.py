"""yt-dlp-Downloader — laedt bestes verfuegbares Audio-Format (meist Opus/webm)."""
from __future__ import annotations

from pathlib import Path

import yt_dlp
from tenacity import retry, stop_after_attempt, wait_exponential

from .config import settings
from .youtube_match import YouTubeMatch


@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
def download_audio(match: YouTubeMatch, track_id: str) -> Path:
    """Laedt Bestaudio als .webm / .m4a in den Temp-Ordner. Liefert Pfad zurueck."""
    settings.temp_dir.mkdir(parents=True, exist_ok=True)
    out_tpl = str(settings.temp_dir / f"{track_id}.%(ext)s")

    opts = {
        "format": "bestaudio/best",
        "outtmpl": out_tpl,
        "quiet": True,
        "no_warnings": True,
        "noprogress": True,
        "noplaylist": True,
        "retries": 2,
    }
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(match.url, download=True)
        ext = info.get("ext", "webm")
        return settings.temp_dir / f"{track_id}.{ext}"
