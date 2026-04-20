"""Screenshot-Agent: macht PNGs aller relevanten Spotify-Web-Player-Screens pro Viewport.

Output: design-tokens/screenshots/{route}_{viewport}.png
        design-tokens/screenshots/manifest.json mit Bounding-Boxes fuer relevante DOM-Nodes
"""
from __future__ import annotations

import json
from pathlib import Path

from ..config import settings
from .base import BaseAgent


class ScreenshotsAgent(BaseAgent):
    name = "screenshots"

    async def _run(self) -> list[Path]:
        artifacts: list[Path] = []
        screenshots_dir = self.ctx.output_dir / "screenshots"
        screenshots_dir.mkdir(exist_ok=True)

        manifest: dict[str, dict] = {}

        for viewport in settings.viewports:
            browser_ctx = await self._make_context(viewport)
            await self._maybe_load_cookies(browser_ctx)
            page = await browser_ctx.new_page()

            for route in settings.target_routes:
                url = settings.target_url.rstrip("/") + route
                try:
                    await page.goto(url, wait_until="networkidle", timeout=30_000)
                except Exception as e:
                    self.log.warn("goto_failed", url=url, error=str(e))
                    continue

                await page.wait_for_timeout(1500)  # let lazy-loads settle

                slug = route.strip("/").replace("/", "_") or "home"
                filename = f"{slug}_{viewport[0]}x{viewport[1]}.png"
                path = screenshots_dir / filename
                await page.screenshot(path=str(path), full_page=True)
                artifacts.append(path)

                boxes = await self._collect_bounding_boxes(page)
                manifest[filename] = {
                    "url": url,
                    "viewport": {"width": viewport[0], "height": viewport[1]},
                    "elements": boxes,
                }

            await browser_ctx.close()

        manifest_path = screenshots_dir / "manifest.json"
        manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
        artifacts.append(manifest_path)
        return artifacts

    async def _collect_bounding_boxes(self, page) -> list[dict]:
        """Sammelt alle sichtbaren top-level Elemente mit Position + Groesse fuer Wireframes."""
        return await page.evaluate(
            """() => {
                const selectors = [
                    '[data-testid="top-bar"]',
                    '[data-testid="left-sidebar"]',
                    '[data-testid="now-playing-bar"]',
                    '[data-testid="main-view-container"]',
                    'nav', 'header', 'footer', 'main', 'aside',
                ];
                const results = [];
                for (const sel of selectors) {
                    document.querySelectorAll(sel).forEach((el) => {
                        const r = el.getBoundingClientRect();
                        if (r.width > 0 && r.height > 0) {
                            results.push({
                                selector: sel,
                                x: r.x, y: r.y, w: r.width, h: r.height,
                                tag: el.tagName.toLowerCase(),
                            });
                        }
                    });
                }
                return results;
            }"""
        )

    async def _maybe_load_cookies(self, browser_ctx) -> None:
        if not settings.spotify_cookies_file or not settings.spotify_cookies_file.exists():
            return
        # TODO: parse Netscape cookie file and inject via browser_ctx.add_cookies()
        self.log.info("cookies_loaded", path=str(settings.spotify_cookies_file))
