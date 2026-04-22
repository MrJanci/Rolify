"""Direct YouTube-Metadata-Harvester (ohne Spotify-API-Umweg).

Fuer den Fall dass Spotify-API restricted ist (Nov 2024+), oder fuer
YouTube-exclusive Content (covers, remixes, content ohne Spotify-Release).

Gibt TrackMeta-kompatible Objekte zurueck die mit pipeline.process_track
funktionieren — spotify_id und isrc bleiben None (Track-Schema erlaubt das).
"""
from __future__ import annotations

import os
import re
from dataclasses import dataclass

import yt_dlp

from .config import settings
from .spotify_meta import TrackMeta


# "Artist - Title" oder "Artist — Title" pattern
ARTIST_TITLE_RE = re.compile(r"^\s*(.+?)\s*[-—]\s*(.+?)\s*$")

# Typische YT-Title-Bloat entfernen
TITLE_NOISE_RE = re.compile(
    r"\s*[\(\[]\s*(?:official|officiell|hd|4k|audio|video|music|lyric|lyrics|visualizer|"
    r"full\s*version|extended|radio\s*edit|remastered|"
    r"explicit|clean|prod\s*by\s*[^\)\]]+|feat\.?[^\)\]]*|ft\.?[^\)\]]*|with[^\)\]]*)"
    r"[^\)\]]*[\)\]]\s*",
    re.IGNORECASE,
)


def _clean_title(raw: str) -> str:
    cleaned = TITLE_NOISE_RE.sub("", raw).strip()
    # Trim trailing punctuation
    cleaned = re.sub(r"[-—_|]+\s*$", "", cleaned).strip()
    return cleaned or raw


def _parse_title(yt_title: str, uploader: str) -> tuple[str, str]:
    """Returns (artist, title). Versucht 'Artist - Title'-Muster, fallback uploader."""
    cleaned = _clean_title(yt_title)
    m = ARTIST_TITLE_RE.match(cleaned)
    if m:
        artist_guess = m.group(1).strip()
        title_guess = m.group(2).strip()
        # Wenn artist_guess nur Zahlen oder 1 wort und uploader was anderes, vertrauen wir uploader
        if len(artist_guess) > 2:
            return (artist_guess, title_guess)
    # Fallback: uploader (oft channel-name wie "InnaVEVO" oder "ColdplayVEVO") als artist
    uploader_clean = re.sub(r"(VEVO|Official|Music|Records|Label|Channel|TV|- Topic)\s*$", "", uploader or "", flags=re.I).strip()
    return (uploader_clean or uploader or "Unknown", cleaned)


def _yt_dlp_opts() -> dict:
    opts = {
        "quiet": True,
        "no_warnings": True,
        "extract_flat": False,
        "skip_download": True,
        "noplaylist": True,
    }
    cookies = settings.youtube_cookies_path
    if cookies and os.path.exists(cookies):
        opts["cookiefile"] = cookies
    return opts


def _video_to_meta(info: dict) -> TrackMeta | None:
    if not info or not info.get("id"):
        return None
    vid = info["id"]
    yt_title = info.get("title") or ""
    uploader = info.get("uploader") or info.get("channel") or ""
    duration_s = info.get("duration") or 0
    if duration_s < 30 or duration_s > 900:  # <30s oder >15min: wahrscheinlich kein Track
        return None
    artist, title = _parse_title(yt_title, uploader)

    # Best thumbnail (grosser, square if possible)
    thumb = info.get("thumbnail") or ""
    thumbnails = info.get("thumbnails") or []
    if thumbnails:
        # Nimm den groessten (by width)
        biggest = max(thumbnails, key=lambda t: (t.get("width") or 0))
        thumb = biggest.get("url") or thumb

    upload_date = info.get("upload_date") or ""
    release_year = upload_date[:4] if upload_date else ""

    # "Album" bei YT-only gibt's nicht — verwenden album_id = vid, album = title als fallback
    return TrackMeta(
        spotify_id=f"yt:{vid}",         # marker "yt:" damit nicht mit echten spotify_ids kollidiert
        title=title[:200],
        artist=artist[:120],
        album=f"YouTube: {title[:60]}",
        album_id=f"yt:{vid}",
        isrc=None,
        duration_ms=duration_s * 1000,
        track_number=1,
        cover_url=thumb,
        release_date=release_year,
    )


def fetch_yt_video(video_id_or_url: str) -> list[TrackMeta]:
    """Einzelnes YT-Video → TrackMeta (als liste mit 1 Eintrag fuer API-Konsistenz)."""
    url = video_id_or_url if video_id_or_url.startswith("http") else f"https://youtube.com/watch?v={video_id_or_url}"
    with yt_dlp.YoutubeDL(_yt_dlp_opts()) as ydl:
        info = ydl.extract_info(url, download=False)
        meta = _video_to_meta(info)
        return [meta] if meta else []


def fetch_yt_playlist(playlist_id_or_url: str, max_videos: int = 100) -> list[TrackMeta]:
    """YouTube-Playlist → Liste TrackMeta."""
    url = (
        playlist_id_or_url
        if playlist_id_or_url.startswith("http")
        else f"https://youtube.com/playlist?list={playlist_id_or_url}"
    )
    opts = {**_yt_dlp_opts(), "extract_flat": "in_playlist", "noplaylist": False, "playlistend": max_videos}
    metas: list[TrackMeta] = []
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(url, download=False)
        entries = info.get("entries", []) if info else []
        for entry in entries:
            if not entry:
                continue
            # Flat-extract gibt nur id + title — voll info pro Video nochmal holen
            vid = entry.get("id")
            if not vid:
                continue
            try:
                with yt_dlp.YoutubeDL(_yt_dlp_opts()) as ydl2:
                    full = ydl2.extract_info(f"https://youtube.com/watch?v={vid}", download=False)
                    meta = _video_to_meta(full)
                    if meta:
                        metas.append(meta)
            except Exception:
                continue
    return metas


def fetch_yt_search(query: str, limit: int = 20) -> list[TrackMeta]:
    """ytsearch für Query → top N TrackMetas."""
    opts = {**_yt_dlp_opts(), "default_search": f"ytsearch{limit}"}
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(query, download=False)
        entries = info.get("entries", []) if info else []
        metas: list[TrackMeta] = []
        for entry in entries:
            meta = _video_to_meta(entry)
            if meta:
                metas.append(meta)
        return metas
