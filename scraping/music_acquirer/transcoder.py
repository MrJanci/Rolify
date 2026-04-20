"""Transcoding via ffmpeg: Opus/webm -> AAC/m4a, loudness-normalized auf -14 LUFS.

Nutzt das mit `imageio-ffmpeg` gebundelte ffmpeg-Binary — kein System-Install noetig.
Fallback auf "ffmpeg" im PATH, falls imageio-ffmpeg aus irgendeinem Grund fehlt.
"""
from __future__ import annotations

import subprocess
from functools import cache
from pathlib import Path

from .config import settings


@cache
def _ffmpeg_bin() -> str:
    try:
        from imageio_ffmpeg import get_ffmpeg_exe
        return get_ffmpeg_exe()
    except ImportError:
        return "ffmpeg"


def transcode(input_path: Path, track_id: str) -> Path:
    """Transcoded zu AAC bei target_bitrate_kbps, embedded nichts (Cover kommt via mutagen spaeter)."""
    output = input_path.parent / f"{track_id}.{settings.target_format}"

    cmd = [
        _ffmpeg_bin(),
        "-y",
        "-i", str(input_path),
        "-vn",
        "-c:a", "aac",
        "-b:a", f"{settings.target_bitrate_kbps}k",
        "-af", "loudnorm=I=-14:TP=-1.5:LRA=11",
        "-movflags", "+faststart",
        str(output),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(f"ffmpeg failed: {proc.stderr[-500:]}")

    input_path.unlink(missing_ok=True)
    return output
