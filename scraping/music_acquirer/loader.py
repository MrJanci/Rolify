"""Loader: schreibt Tracks/Albums/Artists in Postgres und uploadet .enc + cover zu MinIO."""
from __future__ import annotations

import io
from pathlib import Path

import boto3
import httpx
import psycopg
from PIL import Image

from .config import settings
from .encryptor import EncryptedTrack
from .spotify_meta import TrackMeta


def _s3_client():
    return boto3.client(
        "s3",
        endpoint_url=settings.minio_endpoint,
        aws_access_key_id=settings.minio_user,
        aws_secret_access_key=settings.minio_password,
        region_name="us-east-1",
    )


def upload_encrypted_track(enc: EncryptedTrack, track_id: str) -> str:
    s3 = _s3_client()
    key = f"{track_id}.enc"
    with open(enc.enc_path, "rb") as f:
        s3.upload_fileobj(f, settings.minio_bucket_tracks, key)
    enc.enc_path.unlink(missing_ok=True)
    return key


def upload_cover(meta: TrackMeta) -> str | None:
    if not meta.cover_url:
        return None
    resp = httpx.get(meta.cover_url, timeout=20)
    resp.raise_for_status()

    img = Image.open(io.BytesIO(resp.content)).convert("RGB")
    img.thumbnail((640, 640), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=85, optimize=True)
    buf.seek(0)

    s3 = _s3_client()
    key = f"{meta.album_id}.jpg"
    s3.upload_fileobj(buf, settings.minio_bucket_covers, key, ExtraArgs={"ContentType": "image/jpeg"})
    return key


def upsert_track(meta: TrackMeta, enc: EncryptedTrack, blob_key: str, cover_key: str | None) -> None:
    """Upserts Artist -> Album -> Track mit ON CONFLICT.

    Edge-Case: ISRC ist ein UNIQUE-Index, aber Spotify liefert dieselbe ISRC
    fuer Re-Releases/Deluxe-Editions unter verschiedenen spotifyIds. Wenn wir
    einen neuen spotifyId INSERTen und die ISRC schon existiert, gibt's nen
    Unique-Conflict. Fix: Pre-Check - wenn ISRC schon da ist, nutze die
    existing Track-Row und update nur blob/masterKey.
    """
    with psycopg.connect(settings.database_url) as conn, conn.cursor() as cur:
        # Artist
        cur.execute(
            """
            INSERT INTO "Artist" (id, name)
            VALUES (gen_random_uuid()::text, %s)
            ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
            RETURNING id
            """,
            (meta.artist,),
        )
        artist_id = cur.fetchone()[0]

        release_year = int(meta.release_date[:4]) if meta.release_date else 0
        cover_url = f"/{settings.minio_bucket_covers}/{cover_key}" if cover_key else ""
        cur.execute(
            """
            INSERT INTO "Album" (id, title, "coverUrl", "releaseYear", "artistId")
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (id) DO UPDATE SET title = EXCLUDED.title
            """,
            (meta.album_id, meta.album, cover_url, release_year, artist_id),
        )

        # ISRC-Duplicate-Check: falls ISRC bereits existiert, update die bestehende
        # Track-Row statt neuen Insert der wegen unique-constraint crashen wuerde.
        existing_by_isrc: str | None = None
        if meta.isrc:
            cur.execute(
                'SELECT id FROM "Track" WHERE isrc = %s LIMIT 1',
                (meta.isrc,),
            )
            row = cur.fetchone()
            if row:
                existing_by_isrc = row[0]

        if existing_by_isrc and existing_by_isrc != meta.spotify_id:
            # Existing Track mit gleicher ISRC (anderer spotifyId) - nur blob-refresh
            cur.execute(
                """
                UPDATE "Track" SET
                    "encryptedBlobKey" = %s,
                    "masterKey" = %s
                WHERE id = %s
                """,
                (blob_key, enc.master_key, existing_by_isrc),
            )
        else:
            cur.execute(
                """
                INSERT INTO "Track" (id, title, "durationMs", "trackNumber", isrc, "spotifyId",
                                     "albumId", "artistId", "encryptedBlobKey", "masterKey", "createdAt")
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, now())
                ON CONFLICT ("spotifyId") DO UPDATE SET
                    "encryptedBlobKey" = EXCLUDED."encryptedBlobKey",
                    "masterKey" = EXCLUDED."masterKey"
                """,
                (
                    meta.spotify_id,
                    meta.title,
                    meta.duration_ms,
                    meta.track_number,
                    meta.isrc,
                    meta.spotify_id,
                    meta.album_id,
                    artist_id,
                    blob_key,
                    enc.master_key,
                ),
            )
        conn.commit()
