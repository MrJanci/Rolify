"""Retry-Script: Enqueue single-track Scrape-Jobs fuer Tracks die in einer
gescrapeten Playlist/Liked-Songs waren aber NICHT in der Track-DB gelandet
(= beim ersten Durchlauf failed, meist wegen age-gated YouTube oder anderen Fehlern).

Mit neuen YouTube-Cookies sollten die meisten jetzt durchgehen.

Usage auf Pi:
    docker exec rolify-scraper python -m scripts.retry_failed_tracks
"""
from __future__ import annotations

import asyncio
import secrets

import psycopg
import structlog

from music_acquirer.config import settings as acq_settings
from music_acquirer.spotify_meta import fetch_playlist_tracks, fetch_liked_tracks

log = structlog.get_logger()


def _cuid() -> str:
    """cuid-kompatible ID-Generation (wie im worker.py)."""
    import time
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


async def main() -> None:
    log.info("retry_starting")
    async with await psycopg.AsyncConnection.connect(acq_settings.database_url) as conn:
        # 1. Finde alle abgeschlossenen playlist/liked-Jobs mit failed-Counts > 0
        async with conn.cursor() as cur:
            await cur.execute("""
                SELECT id, "playlistUrl", "createdBy", "failedTracks", "totalTracks"
                FROM "ScrapeJob"
                WHERE status = 'DONE'
                  AND "failedTracks" > 0
                  AND (
                      "playlistUrl" LIKE 'spotify:playlist:%'
                      OR "playlistUrl" = 'spotify:collection:tracks'
                  )
                ORDER BY "createdAt" ASC
            """)
            jobs = await cur.fetchall()

        log.info("jobs_with_failures", count=len(jobs))
        if not jobs:
            log.info("nothing_to_retry")
            return

        # 2. Sammle alle Spotify-Track-IDs die *sollen* in Track-DB sein
        expected_ids: set[str] = set()
        user_id: str | None = None
        for (job_id, url, created_by, failed_count, total) in jobs:
            if created_by and not user_id:
                user_id = created_by
            try:
                if url == "spotify:collection:tracks":
                    tracks = fetch_liked_tracks()
                else:
                    tracks = fetch_playlist_tracks(url)
                for t in tracks:
                    expected_ids.add(t.spotify_id)
                log.info("fetched_playlist", url=url[:40], tracks=len(tracks))
            except Exception as e:
                log.warn("fetch_failed", url=url[:40], error=str(e)[:120])

        # Fallback user (falls kein createdBy gesetzt)
        if not user_id:
            async with conn.cursor() as cur:
                await cur.execute('SELECT id FROM "User" LIMIT 1')
                row = await cur.fetchone()
                user_id = row[0] if row else None
        if not user_id:
            log.error("no_user_found")
            return

        # 3. Welche spotify_ids sind schon in Track-DB?
        async with conn.cursor() as cur:
            await cur.execute(
                'SELECT "spotifyId" FROM "Track" WHERE "spotifyId" = ANY(%s)',
                (list(expected_ids),),
            )
            rows = await cur.fetchall()
            existing = {r[0] for r in rows if r[0]}

        missing = expected_ids - existing
        log.info("analysis",
                 expected=len(expected_ids),
                 already_in_db=len(existing),
                 missing=len(missing))

        if not missing:
            log.info("all_tracks_present")
            return

        # 4. Welche davon haben schon einen QUEUED/RUNNING/PAUSED single-track Job?
        async with conn.cursor() as cur:
            await cur.execute("""
                SELECT "playlistUrl" FROM "ScrapeJob"
                WHERE "playlistUrl" LIKE 'spotify:track:%'
                  AND status IN ('QUEUED', 'RUNNING', 'PAUSED')
            """)
            queued_urls = {r[0] for r in await cur.fetchall()}
            queued_ids = {u.replace("spotify:track:", "") for u in queued_urls}

        to_enqueue = missing - queued_ids
        log.info("to_enqueue", count=len(to_enqueue), already_queued=len(queued_ids & missing))

        if not to_enqueue:
            log.info("all_missing_already_queued")
            return

        # 5. Enqueue single-track jobs
        async with conn.cursor() as cur:
            for sid in to_enqueue:
                await cur.execute("""
                    INSERT INTO "ScrapeJob" (id, "playlistUrl", status, "totalTracks",
                                             "processedTracks", "failedTracks",
                                             "createdBy", "createdAt", "updatedAt")
                    VALUES (%s, %s, 'QUEUED', 0, 0, 0, %s, now(), now())
                """, (_cuid(), f"spotify:track:{sid}", user_id))
            await conn.commit()

        log.info("enqueued_retries", count=len(to_enqueue))
        log.info("retry_done")


if __name__ == "__main__":
    asyncio.run(main())
