"""Mass-enqueue YT-Search-Jobs.

Im Gegensatz zu scrape_artists.py (das Spotify API nutzt das seit Nov 2024
restricted ist) nutzt das hier direkt YouTube-Search via yt-dlp.

Funktioniert IMMER — keine API-Limits, keine Extended Quota noetig.

Usage:
    docker exec rolify-scraper python -m scripts.yt_mass_scrape \
        "INNA hits" "David Guetta best" "Coldplay greatest hits" \
        "deutschrap 2025" "phonk tiktok" "justin bieber hits"

Jede Query wird als ein yt:search:<query> Job enqueued. Der Worker holt dann
top 25 YT-videos fuer die Query, sorted by YT-Relevanz.
"""
from __future__ import annotations

import asyncio
import secrets
import sys
import time

import psycopg
import structlog

from music_acquirer.config import settings as acq_settings

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


async def main() -> None:
    queries = sys.argv[1:] if len(sys.argv) > 1 else [
        # Default: user's taste
        "INNA hits",
        "Titanium David Guetta Sia",
        "Justin Bieber best songs",
        "Coldplay greatest hits",
        "Taylor Swift top songs",
        "Billie Eilish hits",
        "Olivia Rodrigo best",
        "phonk tiktok",
        "Lilacs azrxel",
        "abxddon phonk",
        "deutschrap 2025",
        "rap hits 2025",
        "white girl indie pop",
        "dance hits 2025",
    ]

    async with await psycopg.AsyncConnection.connect(acq_settings.database_url) as conn:
        # User-ID
        async with conn.cursor() as cur:
            await cur.execute('SELECT id FROM "User" LIMIT 1')
            row = await cur.fetchone()
            user_id = row[0] if row else None
        if not user_id:
            log.error("no_user")
            return

        # Dedupe: skon queued jobs fuer diese queries
        urls = [f"yt:search:{q}" for q in queries]
        async with conn.cursor() as cur:
            await cur.execute(
                'SELECT "playlistUrl" FROM "ScrapeJob" WHERE "playlistUrl" = ANY(%s) AND status IN (\'QUEUED\', \'RUNNING\', \'PAUSED\')',
                (urls,),
            )
            existing = {r[0] for r in await cur.fetchall()}

        to_enqueue = [q for q in queries if f"yt:search:{q}" not in existing]
        log.info("plan", total=len(queries), already_queued=len(existing), new=len(to_enqueue))

        async with conn.cursor() as cur:
            for q in to_enqueue:
                await cur.execute("""
                    INSERT INTO "ScrapeJob" (id, "playlistUrl", status, "totalTracks",
                                             "processedTracks", "failedTracks",
                                             "createdBy", "createdAt", "updatedAt")
                    VALUES (%s, %s, 'QUEUED', 0, 0, 0, %s, now(), now())
                """, (_cuid(), f"yt:search:{q}", user_id))
            await conn.commit()
        log.info("enqueued", count=len(to_enqueue))


if __name__ == "__main__":
    asyncio.run(main())
