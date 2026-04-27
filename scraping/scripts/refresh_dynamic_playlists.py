"""Cron-Script: Refresht alle Dynamic Auto-Playlists.

Per source:
  - Hole top-tracks aus externer Quelle (Last.fm / TikTok)
  - YT-Search pro track-name+artist → enqueue als Single-Track-ScrapeJob
  - Nach Jobs DONE: Track wird zur Playlist verknuepft (separate run)

Sources:
  - lastfm:global:daily       — Last.fm worldwide top-tracks
  - lastfm:de:daily           — Top-Tracks Deutschland
  - lastfm:rap:weekly         — Top-Tag rap (gewichtet)
  - lastfm:pop:weekly         — Top-Tag pop
  - tiktok:trending:de        — TikTok-Sounds DE (Playwright, mit Last.fm-fallback)

Usage (Cron):
  docker exec rolify-scraper python -m scripts.refresh_dynamic_playlists

Optional: --source <key> fuer einzelnen Source.
"""
from __future__ import annotations

import asyncio
import os
import secrets
import sys
import time
from dataclasses import dataclass

import httpx
import psycopg
import structlog

from music_acquirer.config import settings as acq_settings

log = structlog.get_logger()

LASTFM_API_KEY = os.getenv("LASTFM_API_KEY", "")
LASTFM_BASE = "https://ws.audioscrobbler.com/2.0/"


@dataclass(slots=True)
class DynamicSource:
    key: str          # "lastfm:global:daily"
    name: str         # "Top Hits Weltweit"
    description: str
    rotation: str     # "rotate" | "accumulate"
    interval_h: int


SOURCES: list[DynamicSource] = [
    DynamicSource("lastfm:global:daily", "Top Hits Weltweit",
                   "Last.fm globaler Top-Chart, taeglich aktualisiert.",
                   "rotate", 24),
    DynamicSource("lastfm:de:daily", "Top Hits Deutschland",
                   "Last.fm Deutschland-Chart, taeglich.",
                   "rotate", 24),
    DynamicSource("lastfm:rap:weekly", "Rap Trending",
                   "Top-Tracks im Rap-Tag bei Last.fm, woechentlich.",
                   "rotate", 168),
    DynamicSource("lastfm:pop:weekly", "Pop Trending",
                   "Top-Tracks im Pop-Tag bei Last.fm, woechentlich.",
                   "rotate", 168),
    DynamicSource("tiktok:trending:de", "TikTok Trending DE",
                   "Aktuell virale TikTok-Sounds (DE), taeglich.",
                   "rotate", 24),
]


def _cuid() -> str:
    ts = int(time.time() * 1000)
    alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
    def b36(n: int, length: int) -> str:
        s = ""
        for _ in range(length):
            s = alphabet[n % 36] + s
            n //= 36
        return s
    rand = secrets.token_bytes(10)
    return "c" + b36(ts, 8) + b36(int.from_bytes(rand, "big"), 16)


# ---------- Last.fm ----------

def fetch_lastfm_chart_global(limit: int = 50) -> list[tuple[str, str]]:
    """Returns list of (artist, track) tuples."""
    if not LASTFM_API_KEY:
        log.warn("lastfm_no_api_key")
        return []
    try:
        r = httpx.get(LASTFM_BASE, params={
            "method": "chart.gettoptracks",
            "api_key": LASTFM_API_KEY,
            "format": "json",
            "limit": limit,
        }, timeout=15)
        r.raise_for_status()
        data = r.json()
        tracks = data.get("tracks", {}).get("track", []) or []
        return [(t.get("artist", {}).get("name", ""), t.get("name", "")) for t in tracks if t.get("name")]
    except Exception as e:
        log.warn("lastfm_global_failed", error=str(e)[:120])
        return []


def fetch_lastfm_chart_country(country: str, limit: int = 50) -> list[tuple[str, str]]:
    if not LASTFM_API_KEY: return []
    try:
        r = httpx.get(LASTFM_BASE, params={
            "method": "geo.gettoptracks",
            "country": country,
            "api_key": LASTFM_API_KEY,
            "format": "json",
            "limit": limit,
        }, timeout=15)
        r.raise_for_status()
        tracks = r.json().get("tracks", {}).get("track", []) or []
        return [(t.get("artist", {}).get("name", ""), t.get("name", "")) for t in tracks if t.get("name")]
    except Exception as e:
        log.warn("lastfm_country_failed", country=country, error=str(e)[:120])
        return []


def fetch_lastfm_tag(tag: str, limit: int = 50) -> list[tuple[str, str]]:
    if not LASTFM_API_KEY: return []
    try:
        r = httpx.get(LASTFM_BASE, params={
            "method": "tag.gettoptracks",
            "tag": tag,
            "api_key": LASTFM_API_KEY,
            "format": "json",
            "limit": limit,
        }, timeout=15)
        r.raise_for_status()
        tracks = r.json().get("tracks", {}).get("track", []) or []
        return [(t.get("artist", {}).get("name", ""), t.get("name", "")) for t in tracks if t.get("name")]
    except Exception as e:
        log.warn("lastfm_tag_failed", tag=tag, error=str(e)[:120])
        return []


# ---------- TikTok ----------

def fetch_tiktok_trending(country: str = "DE") -> list[tuple[str, str]]:
    """Versuch via Playwright. Fallback: Last.fm-tag 'tiktok' (less accurate)."""
    try:
        from music_acquirer.tiktok_meta import fetch_tiktok_sounds
        return fetch_tiktok_sounds(country=country)
    except Exception as e:
        log.warn("tiktok_playwright_failed_fallback_lastfm", error=str(e)[:120])
        return fetch_lastfm_tag("tiktok", limit=30)


# ---------- Source dispatch ----------

def fetch_source_tracks(source_key: str) -> list[tuple[str, str]]:
    if source_key == "lastfm:global:daily":
        return fetch_lastfm_chart_global(50)
    if source_key == "lastfm:de:daily":
        return fetch_lastfm_chart_country("Germany", 50)
    if source_key == "lastfm:rap:weekly":
        return fetch_lastfm_tag("rap", 50)
    if source_key == "lastfm:pop:weekly":
        return fetch_lastfm_tag("pop", 50)
    if source_key == "tiktok:trending:de":
        return fetch_tiktok_trending("DE")
    return []


# ---------- DB-Operations ----------

async def ensure_dynamic_playlist(conn: psycopg.AsyncConnection, source: DynamicSource, owner_id: str) -> str:
    """Stellt sicher dass die globale dyn-Playlist existiert. Returns playlist_id."""
    async with conn.cursor() as cur:
        await cur.execute(
            'SELECT id FROM "Playlist" WHERE "dynamicSource" = %s LIMIT 1',
            (source.key,),
        )
        row = await cur.fetchone()
        if row:
            return row[0]
        plist_id = _cuid()
        await cur.execute(
            '''
            INSERT INTO "Playlist" (id, "userId", name, description,
                                    "isPublic", "isCollaborative", "isMixed",
                                    "isDynamic", "dynamicSource", "rotationMode",
                                    "refreshIntervalH", "createdAt", "updatedAt")
            VALUES (%s, %s, %s, %s, true, false, false,
                    true, %s, %s, %s, now(), now())
            ''',
            (plist_id, owner_id, source.name, source.description,
             source.key, source.rotation, source.interval_h),
        )
        await conn.commit()
        log.info("dyn_playlist_created", source=source.key, id=plist_id)
        return plist_id


async def needs_refresh(conn: psycopg.AsyncConnection, playlist_id: str, interval_h: int) -> bool:
    async with conn.cursor() as cur:
        await cur.execute(
            'SELECT "lastRefreshedAt" FROM "Playlist" WHERE id = %s',
            (playlist_id,),
        )
        row = await cur.fetchone()
    if not row or row[0] is None:
        return True
    last = row[0]
    age_h = (time.time() - last.timestamp()) / 3600
    return age_h >= interval_h


async def enqueue_tracks_for_source(
    conn: psycopg.AsyncConnection,
    source: DynamicSource,
    playlist_id: str,
    tracks: list[tuple[str, str]],
    owner_id: str,
) -> int:
    """Enqueue YT-Search-Jobs fuer jeden Track. Worker handelt rest.
    Wenn rotation=rotate: alte PlaylistTracks vor enqueue DELETE."""
    if not tracks:
        return 0

    if source.rotation == "rotate":
        async with conn.cursor() as cur:
            await cur.execute('DELETE FROM "PlaylistTrack" WHERE "playlistId" = %s', (playlist_id,))
            await conn.commit()
        log.info("playlist_rotated_clean", source=source.key)

    # Pro Track: enqueue YT-Search-Job mit query "artist title"
    enqueued = 0
    async with conn.cursor() as cur:
        for (artist, title) in tracks:
            if not artist or not title:
                continue
            query = f"{artist} {title}".strip()
            url = f"yt:search:{query}"
            # Skip wenn schon QUEUED/RUNNING fuer diese query
            await cur.execute(
                'SELECT 1 FROM "ScrapeJob" WHERE "playlistUrl" = %s AND status IN (%s, %s, %s) LIMIT 1',
                (url, "QUEUED", "RUNNING", "PAUSED"),
            )
            if await cur.fetchone():
                continue
            await cur.execute(
                '''
                INSERT INTO "ScrapeJob" (id, "playlistUrl", status, "totalTracks",
                                         "processedTracks", "failedTracks",
                                         "createdBy", "resultPlaylistId",
                                         "createdAt", "updatedAt")
                VALUES (%s, %s, 'QUEUED', 0, 0, 0, %s, %s, now(), now())
                ''',
                (_cuid(), url, owner_id, playlist_id),
            )
            enqueued += 1
        await cur.execute(
            'UPDATE "Playlist" SET "lastRefreshedAt" = now(), "updatedAt" = now() WHERE id = %s',
            (playlist_id,),
        )
        await conn.commit()
    return enqueued


async def refresh_one(conn: psycopg.AsyncConnection, source: DynamicSource, owner_id: str, force: bool = False) -> int:
    plist_id = await ensure_dynamic_playlist(conn, source, owner_id)
    if not force and not await needs_refresh(conn, plist_id, source.interval_h):
        log.info("source_skipped_recent", source=source.key)
        return 0
    log.info("refreshing", source=source.key)
    tracks = fetch_source_tracks(source.key)
    log.info("source_fetched", source=source.key, count=len(tracks))
    return await enqueue_tracks_for_source(conn, source, plist_id, tracks, owner_id)


async def main() -> None:
    only_source = None
    force = False
    args = sys.argv[1:]
    if "--source" in args:
        idx = args.index("--source")
        only_source = args[idx + 1] if idx + 1 < len(args) else None
    if "--force" in args:
        force = True

    log.info("dyn_refresh_starting", source_filter=only_source, force=force)

    async with await psycopg.AsyncConnection.connect(acq_settings.database_url) as conn:
        # Owner = erster User in DB (admin/jan)
        async with conn.cursor() as cur:
            await cur.execute('SELECT id FROM "User" ORDER BY "createdAt" ASC LIMIT 1')
            row = await cur.fetchone()
        if not row:
            log.error("no_user")
            return
        owner_id = row[0]

        sources_to_run = SOURCES if not only_source else [s for s in SOURCES if s.key == only_source]
        total = 0
        for src in sources_to_run:
            try:
                count = await refresh_one(conn, src, owner_id, force=force)
                total += count
                log.info("source_done", source=src.key, enqueued=count)
            except Exception as e:
                log.exception("source_failed", source=src.key, error=str(e)[:120])
        log.info("dyn_refresh_done", total_enqueued=total)


if __name__ == "__main__":
    asyncio.run(main())
