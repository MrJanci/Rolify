"""App-Store-Listing Screenshot-Scraper.

Zieht offizielle iOS-Screenshots von apps.apple.com/app/spotify-music-and-podcasts/id324684580.
Das sind die von Spotify selbst genehmigten UI-Renders — authoritative Referenz.
"""
from __future__ import annotations

import json
from pathlib import Path

import httpx

from .base import BaseAgent


SPOTIFY_APP_STORE_URL = "https://apps.apple.com/ch/app/spotify-music-and-podcasts/id324684580"


class AppStoreGalleryAgent(BaseAgent):
    name = "app_store_gallery"

    async def _run(self) -> list[Path]:
        browser_ctx = await self._make_context(viewport=(1440, 900))
        page = await browser_ctx.new_page()

        out_dir = self.ctx.output_dir / "screenshots" / "app_store"
        out_dir.mkdir(parents=True, exist_ok=True)

        artifacts: list[Path] = []

        try:
            await page.goto(SPOTIFY_APP_STORE_URL, wait_until="networkidle", timeout=30_000)
            await page.wait_for_timeout(2000)
        except Exception as e:
            self.log.warn("goto_failed", url=SPOTIFY_APP_STORE_URL, error=str(e))
            await browser_ctx.close()
            return artifacts

        # Screenshot-Gallery-URLs sammeln. Apple-Seite laedt Screenshots als <img src="..._...@2x.webp">
        image_urls = await page.evaluate("""() => {
            const imgs = [...document.querySelectorAll('.we-screenshot-viewer img, .we-artwork--ios-app-screenshot img')];
            return imgs.map(i => i.src || i.dataset.src).filter(Boolean);
        }""")

        # Fallback: broader selector
        if not image_urls:
            image_urls = await page.evaluate("""() => {
                return [...document.images]
                    .map(i => i.src)
                    .filter(src => src && src.includes('mzstatic') && src.includes('screenshot'));
            }""")

        self.log.info("screenshots_found", count=len(image_urls))

        # Downloaden
        async with httpx.AsyncClient(timeout=30) as client:
            for i, url in enumerate(image_urls[:20]):
                try:
                    resp = await client.get(url)
                    resp.raise_for_status()
                    ext = ".webp" if "webp" in resp.headers.get("content-type", "") else ".jpg"
                    fpath = out_dir / f"screenshot_{i:02d}{ext}"
                    fpath.write_bytes(resp.content)
                    artifacts.append(fpath)
                except Exception as e:
                    self.log.warn("download_failed", url=url, error=str(e))

        manifest = {
            "source": SPOTIFY_APP_STORE_URL,
            "image_urls": image_urls[:20],
            "downloaded": len(artifacts),
        }
        mf = out_dir / "manifest.json"
        mf.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
        artifacts.append(mf)

        await browser_ctx.close()
        return artifacts
