"""Rolify Scrape-Worker mit Pause/Resume + Dedupe.

Pollt die Postgres-Tabelle `ScrapeJob` nach queued jobs, locked einen,
laeuft die Music-Acquisition-Pipeline durch mit:
- Dedupe: Tracks die bereits mit gleicher spotifyId in Track-Table sind werden uebersprungen
- Pause: vor jedem Track wird der aktuelle Status geprueft. Bei PAUSED haelt der Job an.
- Resume: User kann via API status auf QUEUED setzen, Worker picked ihn neu auf und startet bei processedTracks weiter

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
    """Atomar einen queued job claim'en."""
    async with conn.cursor() as cur:
        await cur.execute("""
            UPDATE "ScrapeJob"
               SET status = 'RUNNING', "startedAt" = COALESCE("startedAt", now()), "updatedAt" = now()
             WHERE id = (
                 SELECT id FROM "ScrapeJob"
                  WHERE status = 'QUEUED'
                  ORDER BY "createdAt" ASC
                  LIMIT 1
                  FOR UPDATE SKIP LOCKED
             )
             RETURNING id, "playlistUrl", "processedTracks", "failedTracks", "totalTracks"
        """)
        row = await cur.fetchone()
        await conn.commit()
        if not row:
            return None
        return {
            "id": row[0],
            "playlistUrl": row[1],
            "processedTracks": row[2] or 0,
            "failedTracks": row[3] or 0,
            "totalTracks": row[4] or 0,
        }


async def check_still_running(conn: psycopg.AsyncConnection, job_id: str) -> bool:
    """True wenn Job noch RUNNING, False wenn PAUSED/cancelled."""
    async with conn.cursor() as cur:
        await cur.execute('SELECT status FROM "ScrapeJob" WHERE id = %s', (job_id,))
        row = await cur.fetchone()
        if not row:
            return False   # deleted/cancelled
        status = row[0]
        return status == "RUNNING"


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


async def existing_spotify_ids(conn: psycopg.AsyncConnection, ids: list[str]) -> set[str]:
    """Gibt zurueck welche Spotify-IDs bereits in Track-Table sind (Dedupe)."""
    if not ids:
        return set()
    async with conn.cursor() as cur:
        await cur.execute('SELECT "spotifyId" FROM "Track" WHERE "spotifyId" = ANY(%s)', (ids,))
        rows = await cur.fetchall()
        return {row[0] for row in rows if row[0]}


async def run_job(conn: psycopg.AsyncConnection, job_id: str, playlist_url: str,
                  prev_processed: int, prev_failed: int) -> None:
    job_log = log.bind(job_id=job_id, url=playlist_url)
    job_log.info("job_started", resume_from=prev_processed + prev_failed)
    try:
        tracks = fetch_playlist_tracks(playlist_url)
        total = len(tracks)
        job_log.info("tracks_fetched", total=total)

        if total == 0:
            await complete_job(conn, job_id, error="playlist_empty_or_unauthorized")
            return

        # DEDUPE: filtere bereits gescrapete Tracks raus
        spotify_ids = [t.spotify_id for t in tracks]
        existing = await existing_spotify_ids(conn, spotify_ids)
        new_tracks = [t for t in tracks if t.spotify_id not in existing]
        skipped = total - len(new_tracks)
        job_log.info("dedupe_done", skipped_existing=skipped, to_process=len(new_tracks))

        # Progress: bereits vorhandene Tracks als "processed" markieren
        processed = prev_processed + skipped
        failed = prev_failed
        await update_progress(conn, job_id, total, processed, failed)

        if not new_tracks:
            job_log.info("all_tracks_exist")
            await complete_job(conn, job_id)
            return

        sem = asyncio.Semaphore(acq_settings.concurrency_download)
        paused = False

        async def run_one(track, new_conn_factory):
            nonlocal processed, failed, paused
            if paused:
                return
            # Check pause-state vor jedem track
            try:
                async with await new_conn_factory() as c:
                    if not await check_still_running(c, job_id):
                        paused = True
                        return
            except Exception:
                pass

            ok = await process_track(track, sem)
            if ok:
                processed += 1
            else:
                failed += 1
            # Progress alle 3 tracks updaten
            if (processed + failed) % 3 == 0:
                try:
                    async with await new_conn_factory() as c:
                        await update_progress(c, job_id, total, processed, failed)
                except Exception as e:
                    job_log.warn("progress_update_failed", error=str(e))

        def new_conn_factory():
            return psycopg.AsyncConnection.connect(acq_settings.database_url)

        await asyncio.gather(
            *(run_one(t, new_conn_factory) for t in new_tracks),
            return_exceptions=False
        )

        await update_progress(conn, job_id, total, processed, failed)
        if paused:
            job_log.info("job_paused", processed=processed, failed=failed)
            # Bleibt in PAUSED-Status (gesetzt vom User via API)
            return
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
                    await run_job(
                        conn, job["id"], job["playlistUrl"],
                        job["processedTracks"], job["failedTracks"]
                    )
                else:
                    await asyncio.sleep(POLL_INTERVAL_S)
        except Exception as e:
            log.exception("worker_loop_error")
            await asyncio.sleep(POLL_INTERVAL_S * 2)

    log.info("scraper_worker_stopped")


if __name__ == "__main__":
    asyncio.run(main())
