"""yt-dlp-Downloader — laedt bestes verfuegbares Audio-Format (meist Opus/webm)."""
from __future__ import annotations

import os
from pathlib import Path

import yt_dlp
from tenacity import retry, stop_after_attempt, wait_exponential

from .config import settings
from .youtube_match import YouTubeMatch


def _base_opts(out_tpl: str) -> dict:
    opts = {
        "format": "bestaudio/best",
        "outtmpl": out_tpl,
        "quiet": True,
        "no_warnings": True,
        "noprogress": True,
        "noplaylist": True,
        "retries": 2,
    }
    # Cookies fuer age-gated Videos — wenn File existiert, benutzen.
    # Ohne Cookies failt `Sign in to confirm your age` hart.
    cookies_path = settings.youtube_cookies_path
    if cookies_path and os.path.exists(cookies_path):
        opts["cookiefile"] = cookies_path
    return opts


@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
def download_audio(match: YouTubeMatch, track_id: str) -> Path:
    """Laedt Bestaudio als .webm / .m4a in den Temp-Ordner. Liefert Pfad zurueck."""
    settings.temp_dir.mkdir(parents=True, exist_ok=True)
    out_tpl = str(settings.temp_dir / f"{track_id}.%(ext)s")
    opts = _base_opts(out_tpl)
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(match.url, download=True)
        ext = info.get("ext", "webm")
        return settings.temp_dir / f"{track_id}.{ext}"
