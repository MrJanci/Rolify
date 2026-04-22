from pathlib import Path
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class AcquirerSettings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    spotify_client_id: str = ""
    spotify_client_secret: str = ""

    minio_endpoint: str = "http://localhost:9000"
    minio_user: str = "minioadmin"
    minio_password: str = "minioadmin"
    minio_bucket_tracks: str = "tracks"
    minio_bucket_covers: str = "covers"

    database_url: str = "postgres://postgres:postgres@localhost:5432/rolify"

    temp_dir: Path = Path("/tmp/rolify-dl")
    # Env-override via CONCURRENCY_DOWNLOAD=16 etc. (docker-compose env)
    concurrency_download: int = 12
    concurrency_transcode: int = 4

    target_bitrate_kbps: int = 256
    target_format: str = "m4a"   # AAC container

    # Optional: YouTube cookies.txt Pfad (fuer age-gated Videos).
    # Nicht in Git — kommt via docker volume-mount oder env.
    youtube_cookies_path: str = "/app/.youtube-cookies.txt"


settings = AcquirerSettings()
