"""Mass-scrape alle Tracks von Artist-Namen. Sehr effektiv fuer Genre-Coverage
weil Spotify's search(type=artist) + artist_albums OHNE Extended-Quota laufen.

Usage:
    docker exec rolify-scraper python -m scripts.scrape_artists \
        "INNA" "David Guetta" "Justin Bieber" "Coldplay" "Taylor Swift"

Pro Artist:
- Top 10 Tracks
- Alle Alben + Singles + EPs (bis zu 500)
- Deduplicate via spotifyId

Alle Tracks werden als spotify:track:<id> Single-Scrape-Jobs enqueued.
"""
from __future__ import annotations

import asyncio
import secrets
import sys
import time

import psycopg
import spotipy
import structlog

from music_acquirer.config import settings as acq_settings
from music_acquirer.spotify_meta import _client

log = structlog.get_logger()


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


def collect_artist_tracks(sp: spotipy.Spotify, artist_name: str) -> list[str]:
    """Gibt alle unique Track-IDs dieses Artists zurueck."""
    res = sp.search(q=artist_name, type="artist", limit=1)
    items = res.get("artists", {}).get("items", []) or []
    if not items:
        log.warn("artist_not_found", name=artist_name)
        return []
    artist = items[0]
    artist_id = artist["id"]
    log.info("artist_found", name=artist["name"], id=artist_id[:8], followers=artist.get("followers", {}).get("total", 0))

    track_ids: set[str] = set()

    # Top Tracks
    try:
        top = sp.artist_top_tracks(artist_id, country="DE")
        for t in top.get("tracks", []) or []:
            if t and t.get("id"):
                track_ids.add(t["id"])
    except spotipy.SpotifyException as e:
        log.warn("top_tracks_failed", error=str(e)[:100])

    # Alle Alben + Singles + Compilations
    offset = 0
    while True:
        try:
            page = sp.artist_albums(
                artist_id,
                album_type="album,single,compilation",
                country="DE",
                limit=50,
                offset=offset,
            )
        except spotipy.SpotifyException as e:
            log.warn("albums_page_failed", offset=offset, error=str(e)[:100])
            break
        items = page.get("items", []) or []
        if not items:
            break
        for alb in items:
            alb_id = alb.get("id")
            if not alb_id:
                continue
            try:
                at_page_offset = 0
                while True:
                    ap = sp.album_tracks(alb_id, limit=50, offset=at_page_offset, market="DE")
                    at_items = ap.get("items", []) or []
                    if not at_items:
                        break
                    for t in at_items:
                        if t and t.get("id"):
                            track_ids.add(t["id"])
                    at_page_offset += len(at_items)
                    if at_page_offset >= ap.get("total", 0):
                        break
            except spotipy.SpotifyException as e:
                log.warn("album_tracks_failed", alb=alb_id[:8], error=str(e)[:100])
        offset += len(items)
        if offset >= page.get("total", 0):
            break

    log.info("collected", artist=artist_name, total_tracks=len(track_ids))
    return list(track_ids)


async def enqueue_tracks(spotify_ids: list[str], user_id: str) -> int:
    if not spotify_ids:
        return 0
    async with await psycopg.AsyncConnection.connect(acq_settings.database_url) as conn:
        # Filter: skon in Track-DB
        async with conn.cursor() as cur:
            await cur.execute(
                'SELECT "spotifyId" FROM "Track" WHERE "spotifyId" = ANY(%s)',
                (spotify_ids,),
            )
            existing = {r[0] for r in await cur.fetchall() if r[0]}
        # Filter: schon QUEUED/RUNNING/PAUSED als single-track
        async with conn.cursor() as cur:
            urls = [f"spotify:track:{sid}" for sid in spotify_ids]
            await cur.execute(
                'SELECT "playlistUrl" FROM "ScrapeJob" WHERE "playlistUrl" = ANY(%s) AND status IN (\'QUEUED\', \'RUNNING\', \'PAUSED\')',
                (urls,),
            )
            queued = {r[0].replace("spotify:track:", "") for r in await cur.fetchall()}

        to_enqueue = [sid for sid in spotify_ids if sid not in existing and sid not in queued]
        log.info("enqueue_plan",
                 total=len(spotify_ids),
                 already_in_db=len(existing),
                 already_queued=len(queued),
                 new=len(to_enqueue))
        if not to_enqueue:
            return 0

        async with conn.cursor() as cur:
            for sid in to_enqueue:
                await cur.execute("""
                    INSERT INTO "ScrapeJob" (id, "playlistUrl", status, "totalTracks",
                                             "processedTracks", "failedTracks",
                                             "createdBy", "createdAt", "updatedAt")
                    VALUES (%s, %s, 'QUEUED', 0, 0, 0, %s, now(), now())
                """, (_cuid(), f"spotify:track:{sid}", user_id))
            await conn.commit()
        return len(to_enqueue)


async def main() -> None:
    artist_names = sys.argv[1:] if len(sys.argv) > 1 else [
        "INNA", "David Guetta", "Justin Bieber", "Coldplay",
        "Taylor Swift", "Drake", "Rick Ross",
    ]
    log.info("scrape_artists_starting", count=len(artist_names))

    sp = _client()
    all_track_ids: set[str] = set()
    for name in artist_names:
        ids = collect_artist_tracks(sp, name)
        all_track_ids.update(ids)

    log.info("total_unique_tracks", count=len(all_track_ids))

    # User-ID aus DB
    async with await psycopg.AsyncConnection.connect(acq_settings.database_url) as conn:
        async with conn.cursor() as cur:
            await cur.execute('SELECT id FROM "User" LIMIT 1')
            row = await cur.fetchone()
            user_id = row[0] if row else None
    if not user_id:
        log.error("no_user")
        return

    count = await enqueue_tracks(list(all_track_ids), user_id)
    log.info("done", enqueued=count)


if __name__ == "__main__":
    asyncio.run(main())
