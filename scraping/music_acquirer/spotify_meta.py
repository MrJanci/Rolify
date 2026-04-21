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


@dataclass(slots=True)
class PlaylistMeta:
    spotify_id: str
    name: str
    description: str
    cover_url: str
    owner_name: str


def fetch_playlist_meta(playlist_uri: str) -> PlaylistMeta | None:
    """Holt Name / Cover / Owner einer Playlist (fuer Auto-Create in Rolify).
    Fehlt die Playlist / privat → None (worker macht nur Tracks-Scrape dann).
    """
    sp = _client()
    playlist_id = playlist_uri.split(":")[-1]
    try:
        p = sp.playlist(playlist_id, fields="id,name,description,images,owner(display_name,id)")
    except Exception:
        return None
    if not p:
        return None
    images = p.get("images") or []
    return PlaylistMeta(
        spotify_id=p["id"],
        name=p.get("name") or "Unbenannte Playlist",
        description=p.get("description") or "",
        cover_url=images[0]["url"] if images else "",
        owner_name=(p.get("owner") or {}).get("display_name", ""),
    )


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


def fetch_liked_tracks() -> list[TrackMeta]:
    """Holt alle Liked-Songs des authentifizierten Users.

    Der OAuth-Scope 'user-library-read' ist bereits in SCOPES enthalten,
    der Token wird beim erstmaligen Aufruf entsprechend erweitert.
    """
    sp = _client()
    results: list[TrackMeta] = []
    offset = 0
    while True:
        page = sp.current_user_saved_tracks(offset=offset, limit=50, market="CH")
        items = page.get("items", [])
        if not items:
            break
        for item in items:
            track = item.get("track")
            if not track or item.get("is_local") or track.get("is_local"):
                continue
            if track.get("type") and track["type"] != "track":
                continue
            results.append(_to_meta(track))
        offset += len(items)
        if offset >= page.get("total", 0):
            break
    return results


def fetch_single_track(track_uri: str) -> list[TrackMeta]:
    """Holt Metadata fuer einen einzelnen Track (fuer 'download from search')."""
    sp = _client()
    track_id = track_uri.split(":")[-1].split("/")[-1].split("?")[0]
    track = sp.track(track_id, market="CH")
    if not track or track.get("is_local") or (track.get("type") and track["type"] != "track"):
        return []
    return [_to_meta(track)]


def search_tracks(query: str, limit: int = 20) -> list[dict]:
    """Spotify-Catalog-Search fuer External-Search-Feature.

    Returns Raw-Response mit id/title/artist/album/duration/cover,
    KEIN TrackMeta weil wir auch die spotify_id fuer UI-Status-Check brauchen.
    """
    sp = _client()
    res = sp.search(q=query, type="track", limit=min(50, limit), market="CH")
    hits = res.get("tracks", {}).get("items", []) or []
    out = []
    for t in hits:
        if not t or t.get("is_local"):
            continue
        album = t.get("album", {})
        out.append({
            "spotifyId": t["id"],
            "title": t.get("name", ""),
            "artist": ", ".join(a["name"] for a in t.get("artists", [])),
            "album": album.get("name", ""),
            "albumId": album.get("id", ""),
            "coverUrl": album["images"][0]["url"] if album.get("images") else "",
            "durationMs": t.get("duration_ms", 0),
            "isrc": t.get("external_ids", {}).get("isrc"),
        })
    return out


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
