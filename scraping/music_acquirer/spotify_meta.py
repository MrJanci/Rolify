"""Spotify-Metadata-Harvester.

Nutzt Spotify Web API mit Client-Credentials-Flow (kein User-Login).
Keine Audio-Downloads hier — nur strukturierte Metadaten als Input fuer
die YouTube-Matching-Stage.
"""
from __future__ import annotations

from dataclasses import dataclass

import spotipy
from spotipy.oauth2 import SpotifyClientCredentials

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


def _client() -> spotipy.Spotify:
    auth = SpotifyClientCredentials(
        client_id=settings.spotify_client_id,
        client_secret=settings.spotify_client_secret,
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
            track = item.get("track")
            if not track or track.get("is_local"):
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
