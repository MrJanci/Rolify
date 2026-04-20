"""Color-Token-Agent: extrahiert alle CSS Custom Properties + computed Farben des Spotify-Web-Players.

Output: design-tokens/colors.json
"""
from __future__ import annotations

import json
from pathlib import Path

from ..config import settings
from .base import BaseAgent


class ColorsAgent(BaseAgent):
    name = "colors"

    async def _run(self) -> list[Path]:
        browser_ctx = await self._make_context()
        page = await browser_ctx.new_page()
        await page.goto(settings.target_url, wait_until="networkidle", timeout=30_000)
        await page.wait_for_timeout(2000)

        # 1. Alle CSS Custom Properties sammeln
        custom_props = await page.evaluate(
            """() => {
                const out = {};
                const styles = getComputedStyle(document.documentElement);
                for (let i = 0; i < styles.length; i++) {
                    const name = styles[i];
                    if (name.startsWith('--')) {
                        out[name] = styles.getPropertyValue(name).trim();
                    }
                }
                return out;
            }"""
        )

        # 2. Computed Farbwerte aller sichtbaren Elemente sammeln + clustern
        color_usage = await page.evaluate(
            """() => {
                const colors = { bg: {}, text: {}, border: {} };
                const count = (bucket, value) => {
                    if (!value || value === 'rgba(0, 0, 0, 0)' || value === 'transparent') return;
                    bucket[value] = (bucket[value] || 0) + 1;
                };
                document.querySelectorAll('*').forEach((el) => {
                    const cs = getComputedStyle(el);
                    count(colors.bg, cs.backgroundColor);
                    count(colors.text, cs.color);
                    count(colors.border, cs.borderTopColor);
                });
                // Sort by frequency, top 30 je Kategorie
                const topN = (obj, n = 30) =>
                    Object.entries(obj).sort((a, b) => b[1] - a[1]).slice(0, n);
                return { bg: topN(colors.bg), text: topN(colors.text), border: topN(colors.border) };
            }"""
        )

        semantic = self._build_semantic_palette(custom_props, color_usage)

        output = {
            "source_url": settings.target_url,
            "custom_properties": custom_props,
            "usage_ranking": color_usage,
            "semantic_tokens": semantic,
        }

        path = self.ctx.output_dir / "colors.json"
        path.write_text(json.dumps(output, indent=2, ensure_ascii=False), encoding="utf-8")
        await browser_ctx.close()
        return [path]

    def _build_semantic_palette(self, custom_props: dict, usage: dict) -> dict:
        """Mappt Spotify's CSS-Vars auf Rolify-Semantic-Tokens."""
        mapping = {
            "background.base": custom_props.get("--background-base", "#121212"),
            "background.elevated-base": custom_props.get("--background-elevated-base", "#1A1A1A"),
            "background.elevated-highlight": custom_props.get("--background-elevated-highlight", "#2A2A2A"),
            "text.base": custom_props.get("--text-base", "#FFFFFF"),
            "text.subdued": custom_props.get("--text-subdued", "#A7A7A7"),
            "text.bright-accent": custom_props.get("--text-bright-accent", "#1ED760"),
            "essential.bright-accent": custom_props.get("--essential-bright-accent", "#1ED760"),
            "essential.negative": custom_props.get("--essential-negative", "#F15E6C"),
            "decorative.subdued": custom_props.get("--decorative-subdued", "#292929"),
        }
        return mapping
