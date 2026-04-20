from pathlib import Path
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class ScraperSettings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    output_dir: Path = Field(default=Path("../design-tokens"))
    spotify_cookies_file: Path | None = None
    spotify_email: str | None = None
    spotify_password: str | None = None

    target_url: str = "https://open.spotify.com"

    viewports: list[tuple[int, int]] = [
        (375, 812),   # iPhone X / 11 Pro
        (390, 844),   # iPhone 12-15
        (430, 932),   # iPhone 15 Pro Max / 16 Pro Max
    ]

    target_routes: list[str] = [
        "/",
        "/search",
        "/collection",
        "/collection/playlists",
        "/collection/tracks",
        "/collection/albums",
        "/collection/artists",
    ]

    concurrency: int = 5


settings = ScraperSettings()
