"""Spotify Brand-Guidelines Scraper.

Zieht offizielle Spotify Brand-Guidelines und Design-System-Referenz.
Quellen:
- https://developer.spotify.com/documentation/design (Developer-Doc-Design-Principles)
- https://spotify.design (Design-Blog)

Extrahiert: offizielle Farbcodes, Typography-Referenzen, Principles.
"""
from __future__ import annotations

import json
from pathlib import Path

from .base import BaseAgent


SOURCES = [
    {"name": "developer-design", "url": "https://developer.spotify.com/documentation/design"},
    {"name": "spotify-design",  "url": "https://spotify.design"},
]


class SpotifyBrandAgent(BaseAgent):
    name = "spotify_brand"

    async def _run(self) -> list[Path]:
        browser_ctx = await self._make_context(viewport=(1440, 900))
        page = await browser_ctx.new_page()

        out_dir = self.ctx.output_dir / "brand"
        out_dir.mkdir(parents=True, exist_ok=True)

        artifacts: list[Path] = []
        manifest: list[dict] = []

        for source in SOURCES:
            url = source["url"]
            try:
                await page.goto(url, wait_until="networkidle", timeout=30_000)
                await page.wait_for_timeout(2000)
            except Exception as e:
                self.log.warn("goto_failed", url=url, error=str(e))
                continue

            shot = out_dir / f"{source['name']}.png"
            await page.screenshot(path=str(shot), full_page=True)
            artifacts.append(shot)

            # Alle <code> tags auf der Seite (oft Brand-Hex-Codes)
            code_snippets = await page.evaluate("""() => {
                return [...document.querySelectorAll('code,pre')]
                    .map(el => el.textContent?.trim())
                    .filter(t => t && t.length < 200);
            }""")

            manifest.append({
                "name": source["name"],
                "url": url,
                "code_snippets": code_snippets[:50],
            })

        # Offizielle bekannte Spotify-Brand-Farben (hardcoded aus Brand Guidelines)
        brand_colors = {
            "green": "#1DB954",        # Spotify Green
            "green_light": "#1ED760",  # Rolify-Accent uebernahme-Kandidat
            "black": "#191414",        # Spotify Black (Brand)
            "white": "#FFFFFF",
            "gray_dark": "#121212",    # UI-Background (Player)
            "gray_elevated": "#181818",
        }

        brand_json = out_dir / "colors.json"
        brand_json.write_text(json.dumps(brand_colors, indent=2), encoding="utf-8")
        artifacts.append(brand_json)

        mf = out_dir / "manifest.json"
        mf.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
        artifacts.append(mf)

        await browser_ctx.close()
        return artifacts
