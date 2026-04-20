"""Typography-Agent: sammelt alle Font-Styles und clustert sie zu einem Typographie-System.

Output: design-tokens/typography.json
"""
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

import numpy as np
from sklearn.cluster import KMeans

from ..config import settings
from .base import BaseAgent


STYLE_NAMES = [
    "headline-l", "headline-m", "headline-s",
    "title-l", "title-m", "title-s",
    "body-l", "body-m", "body-s",
    "caption", "label", "button",
]


class TypographyAgent(BaseAgent):
    name = "typography"

    async def _run(self) -> list[Path]:
        browser_ctx = await self._make_context()
        page = await browser_ctx.new_page()
        await page.goto(settings.target_url, wait_until="networkidle", timeout=30_000)
        await page.wait_for_timeout(2000)

        samples: list[dict] = await page.evaluate(
            """() => {
                const out = [];
                const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
                let n;
                while ((n = walker.nextNode())) {
                    const text = n.textContent?.trim();
                    if (!text || text.length < 2) continue;
                    const el = n.parentElement;
                    if (!el) continue;
                    const cs = getComputedStyle(el);
                    out.push({
                        family: cs.fontFamily,
                        size: parseFloat(cs.fontSize),
                        weight: parseInt(cs.fontWeight) || 400,
                        line_height: parseFloat(cs.lineHeight) || 0,
                        letter_spacing: parseFloat(cs.letterSpacing) || 0,
                        sample: text.slice(0, 40),
                    });
                }
                return out;
            }"""
        )
        await browser_ctx.close()

        clusters = self._cluster(samples, k=min(len(STYLE_NAMES), 12))
        families = Counter(s["family"] for s in samples).most_common(5)

        output = {
            "source_url": settings.target_url,
            "dominant_families": [{"family": f, "usages": c} for f, c in families],
            "clusters": clusters,
            "sample_count": len(samples),
        }
        path = self.ctx.output_dir / "typography.json"
        path.write_text(json.dumps(output, indent=2, ensure_ascii=False), encoding="utf-8")
        return [path]

    def _cluster(self, samples: list[dict], k: int) -> list[dict]:
        if len(samples) < k:
            return []
        X = np.array([[s["size"], s["weight"], s["line_height"] or s["size"] * 1.4] for s in samples])
        km = KMeans(n_clusters=k, random_state=42, n_init=10).fit(X)
        clusters = []
        for i in range(k):
            mask = km.labels_ == i
            members = [samples[j] for j in np.where(mask)[0]]
            if not members:
                continue
            avg_size = float(np.mean([m["size"] for m in members]))
            avg_weight = int(round(float(np.mean([m["weight"] for m in members]))))
            avg_lh = float(np.mean([m["line_height"] for m in members if m["line_height"]]) or avg_size * 1.4)
            clusters.append(
                {
                    "name": STYLE_NAMES[i] if i < len(STYLE_NAMES) else f"style-{i}",
                    "font_size": round(avg_size, 1),
                    "font_weight": avg_weight,
                    "line_height": round(avg_lh, 1),
                    "usage_count": int(mask.sum()),
                    "examples": [m["sample"] for m in members[:3]],
                }
            )
        clusters.sort(key=lambda c: -c["font_size"])
        return clusters
