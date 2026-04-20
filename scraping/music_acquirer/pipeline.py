"""Music-Acquisition-Pipeline — End-to-End-Orchestrator.

Stages pro Track:
    1. Spotify-Meta     (cheap, sequential batch)
    2. YouTube-Match    (async concurrency)
    3. yt-dlp Download  (async concurrency)
    4. ffmpeg Transcode (async concurrency)
    5. AES-Encrypt      (CPU-bound, sync)
    6. MinIO Upload     (async)
    7. Postgres Insert  (sync)

Usage:
    python -m music_acquirer.pipeline --playlist spotify:playlist:37i9dQZF1DXcBWIGoYBM5M
"""
from __future__ import annotations

import argparse
import asyncio
import sys

import structlog
from rich.console import Console
from rich.progress import Progress

from . import downloader, encryptor, loader, transcoder, youtube_match
from .config import settings
from .spotify_meta import TrackMeta, fetch_playlist_tracks

log = structlog.get_logger()
console = Console()


async def process_track(meta: TrackMeta, semaphore: asyncio.Semaphore) -> bool:
    async with semaphore:
        try:
            loop = asyncio.get_running_loop()

            match = await loop.run_in_executor(None, youtube_match.match_track, meta)
            if not match:
                log.warn("no_match", track=meta.title)
                return False

            raw_path = await loop.run_in_executor(None, downloader.download_audio, match, meta.spotify_id)
            audio_path = await loop.run_in_executor(None, transcoder.transcode, raw_path, meta.spotify_id)
            enc = await loop.run_in_executor(None, encryptor.encrypt_file, audio_path, meta.spotify_id)
            blob_key = await loop.run_in_executor(None, loader.upload_encrypted_track, enc, meta.spotify_id)
            cover_key = await loop.run_in_executor(None, loader.upload_cover, meta)
            await loop.run_in_executor(None, loader.upsert_track, meta, enc, blob_key, cover_key)

            log.info("track_ok", title=meta.title, bytes=enc.size_bytes)
            return True
        except Exception as e:
            log.exception("track_failed", title=meta.title, error=str(e))
            return False


async def run(playlist_uri: str) -> int:
    console.print(f"[cyan]Fetching playlist:[/] {playlist_uri}")
    tracks = fetch_playlist_tracks(playlist_uri)
    console.print(f"[green]Got {len(tracks)} tracks[/]")

    semaphore = asyncio.Semaphore(settings.concurrency_download)

    successes = 0
    with Progress() as progress:
        task = progress.add_task("[cyan]Acquiring tracks...", total=len(tracks))
        coros = [process_track(t, semaphore) for t in tracks]
        for fut in asyncio.as_completed(coros):
            ok = await fut
            if ok:
                successes += 1
            progress.update(task, advance=1)

    console.print(f"[green]{successes}/{len(tracks)} tracks ok[/]")
    return 0 if successes == len(tracks) else 1


def main() -> int:
    p = argparse.ArgumentParser(description="Rolify Music-Acquisition Pipeline")
    p.add_argument("--playlist", required=True, help="Spotify Playlist URI (spotify:playlist:xyz)")
    args = p.parse_args()
    return asyncio.run(run(args.playlist))


if __name__ == "__main__":
    sys.exit(main())
