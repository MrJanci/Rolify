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
from music_acquirer.spotify_meta import (
    fetch_playlist_tracks,
    fetch_liked_tracks,
    fetch_single_track,
    fetch_playlist_meta,
    PlaylistMeta,
    TrackMeta,
)
from music_acquirer.yt_meta import (
    fetch_yt_search,
    fetch_yt_playlist,
    fetch_yt_video,
)

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
             RETURNING id, "playlistUrl", "processedTracks", "failedTracks", "totalTracks", "createdBy"
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
            "createdBy": row[5],
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


def _cuid() -> str:
    """Simple cuid-kompatible ID-Generation (Prisma erwartet cuid-format).
    Nutzt Python secrets + base36 — reicht fuer Uniqueness."""
    import secrets
    import time
    ts = int(time.time() * 1000)
    # c + 8-char-timestamp-base36 + 16-char-random-base36
    alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
    def b36(n: int, length: int) -> str:
        s = ""
        for _ in range(length):
            s = alphabet[n % 36] + s
            n //= 36
        return s
    rand = secrets.token_bytes(10)
    rand_int = int.from_bytes(rand, "big")
    return "c" + b36(ts, 8) + b36(rand_int, 16)


async def create_rolify_playlist(
    conn: psycopg.AsyncConnection,
    user_id: str,
    meta: PlaylistMeta,
) -> str:
    """Erstellt eine Rolify-Playlist als Spiegel der Spotify-Playlist.
    Returns playlist_id. Idempotent: wenn bereits eine Playlist fuer denselben
    User+Name existiert (von einem frueheren Scrape derselben URL), re-use die."""
    async with conn.cursor() as cur:
        # Suche existing playlist von diesem User mit gleichem Namen
        await cur.execute(
            'SELECT id FROM "Playlist" WHERE "userId" = %s AND name = %s LIMIT 1',
            (user_id, meta.name),
        )
        row = await cur.fetchone()
        if row:
            return row[0]
        playlist_id = _cuid()
        description = f"Aus Spotify: {meta.owner_name}".strip() if meta.owner_name else "Aus Spotify gescraped"
        await cur.execute(
            '''
            INSERT INTO "Playlist" (id, "userId", name, "coverUrl", description,
                                    "isPublic", "isCollaborative", "isMixed",
                                    "createdAt", "updatedAt")
            VALUES (%s, %s, %s, %s, %s, false, false, false, now(), now())
            ''',
            (playlist_id, user_id, meta.name, meta.cover_url or None, description),
        )
        await conn.commit()
        return playlist_id


async def link_tracks_to_playlist(
    conn: psycopg.AsyncConnection,
    playlist_id: str,
    track_metas: list[TrackMeta],
) -> int:
    """Fuegt gescrape Tracks als PlaylistTrack-Rows hinzu (upsert + position-order).
    Returns anzahl added/existing."""
    async with conn.cursor() as cur:
        # Hole track_ids aus DB per spotifyId
        spotify_ids = [t.spotify_id for t in track_metas]
        await cur.execute(
            'SELECT "spotifyId", id FROM "Track" WHERE "spotifyId" = ANY(%s)',
            (spotify_ids,),
        )
        rows = await cur.fetchall()
        sid_to_tid = {r[0]: r[1] for r in rows}

        # Position: append to end
        await cur.execute(
            'SELECT COALESCE(MAX(position), -1) FROM "PlaylistTrack" WHERE "playlistId" = %s',
            (playlist_id,),
        )
        max_pos_row = await cur.fetchone()
        start_pos = (max_pos_row[0] if max_pos_row else -1) + 1

        count = 0
        for i, tm in enumerate(track_metas):
            tid = sid_to_tid.get(tm.spotify_id)
            if not tid:
                continue
            try:
                await cur.execute(
                    '''
                    INSERT INTO "PlaylistTrack" ("playlistId", "trackId", position, "addedAt")
                    VALUES (%s, %s, %s, now())
                    ON CONFLICT ("playlistId", "trackId") DO NOTHING
                    ''',
                    (playlist_id, tid, start_pos + i),
                )
                count += 1
            except Exception:
                pass
        await conn.commit()
        # Touch playlist updatedAt
        async with conn.cursor() as cur2:
            await cur2.execute('UPDATE "Playlist" SET "updatedAt" = now() WHERE id = %s', (playlist_id,))
            await conn.commit()
        return count


async def set_result_playlist_id(conn: psycopg.AsyncConnection, job_id: str, playlist_id: str) -> None:
    async with conn.cursor() as cur:
        await cur.execute(
            'UPDATE "ScrapeJob" SET "resultPlaylistId" = %s, "updatedAt" = now() WHERE id = %s',
            (playlist_id, job_id),
        )
        await conn.commit()


async def run_job(conn: psycopg.AsyncConnection, job_id: str, playlist_url: str,
                  prev_processed: int, prev_failed: int,
                  created_by: str | None = None) -> None:
    job_log = log.bind(job_id=job_id, url=playlist_url)
    job_log.info("job_started", resume_from=prev_processed + prev_failed)
    try:
        # Dispatch nach URL-Typ
        lower = playlist_url.lower()
        should_create_playlist = False
        playlist_meta: PlaylistMeta | None = None

        if "collection/tracks" in lower or lower == "spotify:collection:tracks":
            tracks = fetch_liked_tracks()
            job_log.info("dispatched_liked_tracks")
        elif "spotify:track:" in lower or "/track/" in lower:
            tracks = fetch_single_track(playlist_url)
            job_log.info("dispatched_single_track")
        # NEW: YT direct-scraping (umgeht Spotify-API-Restrictions)
        elif lower.startswith("yt:search:"):
            query = playlist_url.split(":", 2)[2]  # "yt:search:pop hits 2025"
            tracks = fetch_yt_search(query, limit=25)
            job_log.info("dispatched_yt_search", query=query, count=len(tracks))
        elif lower.startswith("yt:playlist:") or "youtube.com/playlist" in lower or "music.youtube.com/playlist" in lower:
            pid = playlist_url.split(":", 2)[2] if lower.startswith("yt:playlist:") else playlist_url
            tracks = fetch_yt_playlist(pid, max_videos=100)
            job_log.info("dispatched_yt_playlist", count=len(tracks))
        elif lower.startswith("yt:video:") or "youtube.com/watch" in lower or "youtu.be/" in lower:
            vid = playlist_url.split(":", 2)[2] if lower.startswith("yt:video:") else playlist_url
            tracks = fetch_yt_video(vid)
            job_log.info("dispatched_yt_video")
        else:
            tracks = fetch_playlist_tracks(playlist_url)
            job_log.info("dispatched_playlist")
            should_create_playlist = bool(created_by)
            if should_create_playlist:
                try:
                    playlist_meta = fetch_playlist_meta(playlist_url)
                    if playlist_meta:
                        job_log.info("playlist_meta_fetched", name=playlist_meta.name)
                except Exception as e:
                    job_log.warn("playlist_meta_fetch_failed", error=str(e))
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

        # Auto-Playlist-Creation nach erfolgreichem Playlist-Scrape
        if should_create_playlist and playlist_meta and created_by:
            try:
                async with await psycopg.AsyncConnection.connect(acq_settings.database_url) as c:
                    plist_id = await create_rolify_playlist(c, created_by, playlist_meta)
                    linked = await link_tracks_to_playlist(c, plist_id, tracks)
                    await set_result_playlist_id(c, job_id, plist_id)
                    job_log.info("playlist_created", playlist_id=plist_id, linked_tracks=linked)
            except Exception as e:
                job_log.warn("playlist_creation_failed", error=str(e))

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
                        job["processedTracks"], job["failedTracks"],
                        created_by=job.get("createdBy"),
                    )
                else:
                    await asyncio.sleep(POLL_INTERVAL_S)
        except Exception as e:
            log.exception("worker_loop_error")
            await asyncio.sleep(POLL_INTERVAL_S * 2)

    log.info("scraper_worker_stopped")


if __name__ == "__main__":
    asyncio.run(main())
