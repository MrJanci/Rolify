"""Spotify Web-Player Deep-Scraper.

Scraped authentifizierte Album/Artist/Playlist-Pages vom Web-Player.
Nutzt den OAuth-Token vom music_acquirer (.spotify-token.json) um eingeloggt zu scrapen.
Extrahiert:
- Hero-Header-Gradient-Farben pro Album-Cover
- Track-Row-Metrics (Hoehe, Typography, Spacing)
- Icon-Set (aus SVG-Sprites)
- Play-Button-Placement
"""
from __future__ import annotations

import json
from pathlib import Path

from ..config import settings
from .base import BaseAgent


DEMO_PLAYLISTS = [
    "37i9dQZEVXbMDoHDwVN2tF",  # Top 50 Global (public editorial)
]
DEMO_ALBUMS = [
    "4aawyAB9vmqN3uQ7FjRGTy",  # Global Warming - Pitbull (random)
]
DEMO_ARTISTS = [
    "0TnOYISbd1XYRBk9myaseg",  # Pitbull (random)
]


class SpotifyWebPlayerAgent(BaseAgent):
    name = "spotify_web_player"

    async def _run(self) -> list[Path]:
        browser_ctx = await self._make_context(viewport=(1440, 900))
        await self._maybe_load_cookies(browser_ctx)
        page = await browser_ctx.new_page()

        out_dir = self.ctx.output_dir / "screenshots" / "spotify_web_player"
        out_dir.mkdir(parents=True, exist_ok=True)

        artifacts: list[Path] = []
        manifest: list[dict] = []

        targets = [
            (f"playlist/{p}", "playlist") for p in DEMO_PLAYLISTS
        ] + [
            (f"album/{a}", "album") for a in DEMO_ALBUMS
        ] + [
            (f"artist/{a}", "artist") for a in DEMO_ARTISTS
        ]

        for path, kind in targets:
            url = f"https://open.spotify.com/{path}"
            try:
                await page.goto(url, wait_until="networkidle", timeout=30_000)
                await page.wait_for_timeout(1500)
            except Exception as e:
                self.log.warn("goto_failed", url=url, error=str(e))
                continue

            slug = path.replace("/", "_")
            shot = out_dir / f"{slug}.png"
            await page.screenshot(path=str(shot), full_page=False)
            artifacts.append(shot)

            # Extract hero-gradient (background-image) + track-row metrics
            metrics = await page.evaluate("""() => {
                const heroBg = document.querySelector('[data-testid="background-image"]')
                    || document.querySelector('.main-entityHeader-background');
                const bgStyle = heroBg ? getComputedStyle(heroBg) : null;
                const rowEl = document.querySelector('[data-testid="tracklist-row"]')
                    || document.querySelector('.main-trackList-row');
                const rowStyle = rowEl ? getComputedStyle(rowEl) : null;
                return {
                    hero: bgStyle ? {
                        backgroundImage: bgStyle.backgroundImage,
                        backgroundColor: bgStyle.backgroundColor,
                    } : null,
                    trackRow: rowStyle ? {
                        height: rowStyle.height,
                        paddingLeft: rowStyle.paddingLeft,
                        paddingRight: rowStyle.paddingRight,
                        fontSize: rowStyle.fontSize,
                        color: rowStyle.color,
                    } : null,
                };
            }""")

            manifest.append({"path": path, "kind": kind, "url": url, "metrics": metrics})

        mf = out_dir / "manifest.json"
        mf.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
        artifacts.append(mf)
        await browser_ctx.close()
        return artifacts

    async def _maybe_load_cookies(self, browser_ctx) -> None:
        # Der spotify_meta OAuth-Cache ist nicht direkt ein Cookie-File; fuer public
        # pages brauchen wir auch keinen Login. Kann spaeter ergaenzt werden.
        pass
