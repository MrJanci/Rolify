"""Spotify-Metadata-Harvester.

Seit der Feb-2026 Migration braucht `/playlists/{id}/items` Authorization-Code-Flow
(OAuth mit User-Consent) — Client-Credentials-Flow gibt nur 401 fuer Playlists.

Erstes Ausfuehren oeffnet den Browser, User akzeptiert Scope einmal,
Refresh-Token wird im `.spotify-token.json` gecacht (nicht committet).
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import spotipy
from spotipy.cache_handler import CacheFileHandler
from spotipy.oauth2 import SpotifyOAuth

from .config import settings


@dataclass(slots=True)
class TrackMeta:
    spotify_id: str
    title: str
    artist: str
    album: str
    album_id: str
    isrc: str | None
    duration_ms: int
    track_number: int
    cover_url: str
    release_date: str


SCOPES = "playlist-read-private playlist-read-collaborative user-library-read"
CACHE_PATH = Path(__file__).resolve().parent.parent / ".spotify-token.json"


def _client() -> spotipy.Spotify:
    auth = SpotifyOAuth(
        client_id=settings.spotify_client_id,
        client_secret=settings.spotify_client_secret,
        redirect_uri="http://127.0.0.1:3000/callback",
        scope=SCOPES,
        cache_handler=CacheFileHandler(cache_path=str(CACHE_PATH)),
        open_browser=True,
        show_dialog=False,
    )
    return spotipy.Spotify(auth_manager=auth)


def fetch_playlist_tracks(playlist_uri: str) -> list[TrackMeta]:
    """Holt alle Tracks einer oeffentlichen Spotify-Playlist."""
    sp = _client()
    playlist_id = playlist_uri.split(":")[-1]
    results: list[TrackMeta] = []

    offset = 0
    while True:
        page = sp.playlist_items(playlist_id, offset=offset, limit=100, market="CH")
        items = page.get("items", [])
        if not items:
            break
        for item in items:
            # Feb-2026 Migration: 'track' -> 'item' (Spotify renamed field)
            track = item.get("item") or item.get("track")
            if not track or item.get("is_local") or track.get("is_local"):
                continue
            # Skip episodes/podcasts, nur Tracks
            if track.get("type") and track["type"] != "track":
                continue
            results.append(_to_meta(track))
        offset += len(items)
        if offset >= page.get("total", 0):
            break
    return results


def _to_meta(track: dict) -> TrackMeta:
    album = track["album"]
    return TrackMeta(
        spotify_id=track["id"],
        title=track["name"],
        artist=", ".join(a["name"] for a in track["artists"]),
        album=album["name"],
        album_id=album["id"],
        isrc=track.get("external_ids", {}).get("isrc"),
        duration_ms=track["duration_ms"],
        track_number=track.get("track_number", 1),
        cover_url=album["images"][0]["url"] if album.get("images") else "",
        release_date=album.get("release_date", ""),
    )
