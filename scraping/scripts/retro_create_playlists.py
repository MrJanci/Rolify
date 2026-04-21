"""Retro-Fix: Erstellt User-Playlists fuer alle bereits fertig gescrapete
Spotify-Playlists die noch kein resultPlaylistId haben.

One-shot-Einsatz nach v0.16-Deploy:
    docker exec rolify-scraper python -m scripts.retro_create_playlists

Logik:
1. Findet alle ScrapeJob wo playlistUrl wie "spotify:playlist:XXX", status DONE,
   createdBy gesetzt und resultPlaylistId leer.
2. Fuer jeden: fetch_playlist_meta + alle Tracks mit derselben Spotify-Playlist
   (via direkte Abfrage an Spotify-API).
3. create_rolify_playlist + link_tracks_to_playlist.
4. set_result_playlist_id.
"""
from __future__ import annotations

import asyncio
import sys

import psycopg
import structlog

from music_acquirer.config import settings as acq_settings
from music_acquirer.spotify_meta import fetch_playlist_meta, fetch_playlist_tracks
from scraper_worker.worker import (
    create_rolify_playlist,
    link_tracks_to_playlist,
    set_result_playlist_id,
)

log = structlog.get_logger()


async def retro_for_job(conn: psycopg.AsyncConnection, job_id: str, playlist_url: str, user_id: str) -> None:
    job_log = log.bind(job_id=job_id, url=playlist_url)
    try:
        meta = fetch_playlist_meta(playlist_url)
        if not meta:
            job_log.warn("playlist_meta_unavailable")
            return

        tracks = fetch_playlist_tracks(playlist_url)
        if not tracks:
            job_log.warn("no_tracks")
            return

        plist_id = await create_rolify_playlist(conn, user_id, meta)
        linked = await link_tracks_to_playlist(conn, plist_id, tracks)
        await set_result_playlist_id(conn, job_id, plist_id)
        job_log.info("retro_playlist_created", playlist_id=plist_id, linked=linked, name=meta.name)
    except Exception as e:
        job_log.exception("retro_failed")


async def main() -> None:
    log.info("retro_starting")
    async with await psycopg.AsyncConnection.connect(acq_settings.database_url) as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                '''
                SELECT id, "playlistUrl", "createdBy"
                FROM "ScrapeJob"
                WHERE "playlistUrl" LIKE 'spotify:playlist:%'
                  AND status = 'DONE'
                  AND "createdBy" IS NOT NULL
                  AND "resultPlaylistId" IS NULL
                ORDER BY "createdAt" ASC
                '''
            )
            rows = await cur.fetchall()
        log.info("retro_jobs_found", count=len(rows))
        for (job_id, playlist_url, user_id) in rows:
            await retro_for_job(conn, job_id, playlist_url, user_id)
    log.info("retro_done")


if __name__ == "__main__":
    asyncio.run(main())
