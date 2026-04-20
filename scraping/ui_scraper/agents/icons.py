"""Icons-Agent: sammelt inline-SVGs + Icon-Sprite-URLs als Referenz.

Wichtig: Spotify-Logo / Branded-Assets werden NICHT gespeichert — nur generische
Icons wie Play, Pause, Skip, Shuffle etc. werden als Design-Referenz extrahiert.
Die tatsaechlichen Assets fuer Rolify werden spaeter aus SF Symbols / eigenem Set gezogen.

Output: design-tokens/icons/*.svg (nur generische Controls)
        design-tokens/icons/manifest.json mit Usage-Info
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from ..config import settings
from .base import BaseAgent


# Whitelist nur funktionale Icons, keine Logos/Branding
GENERIC_ICON_KEYWORDS = [
    "play", "pause", "stop", "skip", "previous", "next",
    "shuffle", "repeat", "heart", "plus", "minus", "close",
    "search", "home", "library", "queue", "more", "menu",
    "download", "volume", "mute", "settings", "gear",
]


class IconsAgent(BaseAgent):
    name = "icons"

    async def _run(self) -> list[Path]:
        browser_ctx = await self._make_context()
        page = await browser_ctx.new_page()
        await page.goto(settings.target_url, wait_until="networkidle", timeout=30_000)
        await page.wait_for_timeout(2000)

        svgs: list[dict] = await page.evaluate(
            """() => {
                return Array.from(document.querySelectorAll('svg')).map((svg, i) => ({
                    idx: i,
                    aria_label: svg.getAttribute('aria-label') || '',
                    data_testid: svg.getAttribute('data-testid') || '',
                    title: svg.querySelector('title')?.textContent || '',
                    viewbox: svg.getAttribute('viewBox') || '',
                    outer: svg.outerHTML.length > 5000 ? '' : svg.outerHTML,
                }));
            }"""
        )
        await browser_ctx.close()

        icons_dir = self.ctx.output_dir / "icons"
        icons_dir.mkdir(exist_ok=True)
        manifest: list[dict] = []
        saved: set[str] = set()

        for svg in svgs:
            name = self._classify(svg)
            if not name or name in saved or not svg["outer"]:
                continue
            saved.add(name)
            clean = self._strip_classes(svg["outer"])
            (icons_dir / f"{name}.svg").write_text(clean, encoding="utf-8")
            manifest.append({
                "name": name,
                "viewbox": svg["viewbox"],
                "aria_label": svg["aria_label"],
            })

        manifest_path = icons_dir / "manifest.json"
        manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")

        artifacts = [icons_dir / f"{m['name']}.svg" for m in manifest]
        artifacts.append(manifest_path)
        return artifacts

    def _classify(self, svg: dict) -> str | None:
        haystack = f"{svg['aria_label']} {svg['data_testid']} {svg['title']}".lower()
        for kw in GENERIC_ICON_KEYWORDS:
            if kw in haystack:
                return kw
        return None

    def _strip_classes(self, svg_html: str) -> str:
        """Entfernt class-Attribute und Spotify-spezifische Encore-Styles."""
        return re.sub(r'\s+class="[^"]*"', "", svg_html)
