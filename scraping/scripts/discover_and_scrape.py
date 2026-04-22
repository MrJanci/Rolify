"""Discover Playlists via Spotify-Search und enqueue sie als Scrape-Jobs.

Anstatt hardcoded Playlist-IDs (die seit Nov 2024 oft 404) nutzen wir
Spotify's Search-API fuer aktuelle, live-aktive Playlists.

Usage:
    docker exec rolify-scraper python -m scripts.discover_and_scrape \
        "pop 2025" "deutschrap 2025" "phonk" "dance hits"

Parameter: 1-10 Queries. Pro Query werden die top-5 Playlists enqueued.
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


def search_playlists(queries: list[str], per_query: int = 5) -> list[dict]:
    """Search Spotify for live playlists matching each query.
    Filters: only public, only track-playlists, has >10 tracks."""
    sp = _client()
    results: list[dict] = []
    seen_ids: set[str] = set()

    for q in queries:
        try:
            res = sp.search(q=q, type="playlist", limit=per_query, market="CH")
        except spotipy.SpotifyException as e:
            log.warn("search_failed", query=q, error=str(e)[:120])
            continue
        items = res.get("playlists", {}).get("items", []) or []
        for p in items:
            if not p or not p.get("id") or p["id"] in seen_ids:
                continue
            tracks_count = p.get("tracks", {}).get("total", 0) or 0
            if tracks_count < 10:
                continue
            seen_ids.add(p["id"])
            results.append({
                "id": p["id"],
                "name": p.get("name", ""),
                "owner": (p.get("owner") or {}).get("display_name", ""),
                "tracks": tracks_count,
                "query": q,
            })
    return results


async def enqueue(playlists: list[dict], user_id: str) -> int:
    if not playlists:
        return 0
    async with await psycopg.AsyncConnection.connect(acq_settings.database_url) as conn:
        # Filter: schon queued/done
        urls = [f"spotify:playlist:{p['id']}" for p in playlists]
        async with conn.cursor() as cur:
            await cur.execute(
                'SELECT "playlistUrl" FROM "ScrapeJob" WHERE "playlistUrl" = ANY(%s)',
                (urls,),
            )
            existing = {r[0] for r in await cur.fetchall()}
        to_enqueue = [p for p in playlists if f"spotify:playlist:{p['id']}" not in existing]
        if not to_enqueue:
            log.info("all_already_queued")
            return 0

        async with conn.cursor() as cur:
            for p in to_enqueue:
                await cur.execute("""
                    INSERT INTO "ScrapeJob" (id, "playlistUrl", status, "totalTracks",
                                             "processedTracks", "failedTracks",
                                             "createdBy", "createdAt", "updatedAt")
                    VALUES (%s, %s, 'QUEUED', 0, 0, 0, %s, now(), now())
                """, (_cuid(), f"spotify:playlist:{p['id']}", user_id))
            await conn.commit()
        return len(to_enqueue)


async def main() -> None:
    queries = sys.argv[1:] if len(sys.argv) > 1 else [
        # Default: breiter Mainstream-Mix
        "pop hits 2025",
        "rap hits 2025",
        "deutschrap 2025",
        "phonk",
        "dance hits 2025",
        "chill pop",
    ]
    log.info("discover_starting", queries=queries)

    playlists = search_playlists(queries, per_query=5)
    log.info("playlists_found", count=len(playlists))
    for p in playlists:
        log.info("found",
                 id=p["id"][:8],
                 name=p["name"][:40],
                 owner=p["owner"][:20],
                 tracks=p["tracks"],
                 query=p["query"])

    # User-ID aus DB holen
    async with await psycopg.AsyncConnection.connect(acq_settings.database_url) as conn:
        async with conn.cursor() as cur:
            await cur.execute('SELECT id FROM "User" LIMIT 1')
            row = await cur.fetchone()
            user_id = row[0] if row else None
    if not user_id:
        log.error("no_user")
        return

    count = await enqueue(playlists, user_id)
    log.info("enqueued", count=count)


if __name__ == "__main__":
    asyncio.run(main())
