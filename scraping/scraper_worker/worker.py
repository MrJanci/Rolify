"""Rolify Scrape-Worker.

Pollt die Postgres-Tabelle `ScrapeJob` nach queued jobs, locked einen,
laeuft die Music-Acquisition-Pipeline durch, updatet Progress.

Start: `python -m scraper_worker.worker`
Docker: laeuft als rolify-scraper Container im docker-compose.
"""
from __future__ import annotations

import asyncio
import os
import signal
import sys
import time
import traceback

import psycopg
import structlog

from music_acquirer.config import settings as acq_settings
from music_acquirer.pipeline import process_track
from music_acquirer.spotify_meta import fetch_playlist_tracks

log = structlog.get_logger()

POLL_INTERVAL_S = 5
shutdown = False


def _handle_signal(signum, frame):
    global shutdown
    log.info("shutdown_requested", signal=signum)
    shutdown = True


async def claim_next_job(conn: psycopg.AsyncConnection) -> dict | None:
    """Atomar einen queued job claim'en (UPDATE ... RETURNING mit FOR UPDATE SKIP LOCKED)."""
    async with conn.cursor() as cur:
        await cur.execute("""
            UPDATE "ScrapeJob"
               SET status = 'RUNNING', "startedAt" = now(), "updatedAt" = now()
             WHERE id = (
                 SELECT id FROM "ScrapeJob"
                  WHERE status = 'QUEUED'
                  ORDER BY "createdAt" ASC
                  LIMIT 1
                  FOR UPDATE SKIP LOCKED
             )
             RETURNING id, "playlistUrl"
        """)
        row = await cur.fetchone()
        await conn.commit()
        if not row:
            return None
        return {"id": row[0], "playlistUrl": row[1]}


async def update_progress(conn: psycopg.AsyncConnection, job_id: str, total: int, processed: int, failed: int):
    async with conn.cursor() as cur:
        await cur.execute("""
            UPDATE "ScrapeJob"
               SET "totalTracks" = %s, "processedTracks" = %s,
                   "failedTracks" = %s, "updatedAt" = now()
             WHERE id = %s
        """, (total, processed, failed, job_id))
        await conn.commit()


async def complete_job(conn: psycopg.AsyncConnection, job_id: str, error: str | None = None):
    status = "FAILED" if error else "DONE"
    async with conn.cursor() as cur:
        await cur.execute("""
            UPDATE "ScrapeJob"
               SET status = %s, "errorMessage" = %s, "completedAt" = now(), "updatedAt" = now()
             WHERE id = %s
        """, (status, error, job_id))
        await conn.commit()


async def run_job(conn: psycopg.AsyncConnection, job_id: str, playlist_url: str) -> None:
    job_log = log.bind(job_id=job_id, url=playlist_url)
    job_log.info("job_started")
    try:
        # 1. Metadaten holen (sync, aber schnell)
        tracks = fetch_playlist_tracks(playlist_url)
        total = len(tracks)
        job_log.info("tracks_fetched", total=total)
        await update_progress(conn, job_id, total, 0, 0)

        if total == 0:
            await complete_job(conn, job_id, error="playlist_empty_or_unauthorized")
            return

        # 2. Parallel processing
        sem = asyncio.Semaphore(acq_settings.concurrency_download)
        processed = 0
        failed = 0

        async def run_one(track):
            nonlocal processed, failed
            ok = await process_track(track, sem)
            if ok:
                processed += 1
            else:
                failed += 1
            # Progress alle 3 tracks updaten
            if (processed + failed) % 3 == 0:
                try:
                    async with await psycopg.AsyncConnection.connect(acq_settings.database_url) as prog_conn:
                        await update_progress(prog_conn, job_id, total, processed, failed)
                except Exception as e:
                    job_log.warn("progress_update_failed", error=str(e))

        await asyncio.gather(*(run_one(t) for t in tracks), return_exceptions=False)

        await update_progress(conn, job_id, total, processed, failed)
        await complete_job(conn, job_id)
        job_log.info("job_done", processed=processed, failed=failed)

    except Exception as e:
        job_log.exception("job_failed")
        await complete_job(conn, job_id, error=f"{type(e).__name__}: {str(e)[:400]}")


async def main():
    signal.signal(signal.SIGTERM, _handle_signal)
    signal.signal(signal.SIGINT, _handle_signal)

    log.info("scraper_worker_started", db=acq_settings.database_url[:30] + "...")

    while not shutdown:
        try:
            async with await psycopg.AsyncConnection.connect(acq_settings.database_url) as conn:
                job = await claim_next_job(conn)
                if job:
                    await run_job(conn, job["id"], job["playlistUrl"])
                else:
                    # Keine Jobs — kurz warten
                    await asyncio.sleep(POLL_INTERVAL_S)
        except Exception as e:
            log.exception("worker_loop_error")
            await asyncio.sleep(POLL_INTERVAL_S * 2)  # backoff on DB errors

    log.info("scraper_worker_stopped")


if __name__ == "__main__":
    asyncio.run(main())
