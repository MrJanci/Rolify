"""TikTok-Trending-Sounds via Playwright.

TikTok hat keine offene API. Wir oeffnen tiktok.com/discover via headless
chromium und extracten Track/Artist aus dem DOM.

Risiko: Cloudflare/TikTok-Anti-Bot. Beim Cron-Caller (refresh_dynamic_playlists.py)
gibts try/except mit Last.fm-fallback (tag=tiktok).

Returns: list[(artist, track)] tuples.
"""
from __future__ import annotations

import re

import structlog

log = structlog.get_logger()


def fetch_tiktok_sounds(country: str = "DE", limit: int = 30) -> list[tuple[str, str]]:
    """Headless-Chromium zu tiktok.com → DOM-Extraction.
    Falls Playwright nicht installiert oder Bot-Block: throws → caller catched.
    """
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        raise RuntimeError("playwright not installed in scraper image")

    results: list[tuple[str, str]] = []

    with sync_playwright() as pw:
        browser = pw.chromium.launch(
            headless=True,
            args=[
                "--no-sandbox",
                "--disable-blink-features=AutomationControlled",
                "--disable-dev-shm-usage",
            ],
        )
        ctx = browser.new_context(
            user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                        "(KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            viewport={"width": 1280, "height": 800},
            locale="de-DE",
        )
        page = ctx.new_page()
        try:
            url = f"https://www.tiktok.com/discover/popular-songs"
            page.goto(url, wait_until="networkidle", timeout=30000)
            page.wait_for_timeout(3000)  # JS hydration

            # Selectors fuer track-cards (TikTok DOM aendert sich, robust mit fallbacks)
            cards = page.query_selector_all('[data-e2e="music-item"]') or \
                    page.query_selector_all('a[href*="/music/"]') or \
                    page.query_selector_all('[class*="MusicCard"]')

            for card in cards[:limit]:
                try:
                    title_text = card.inner_text() or ""
                    # Pattern "Track Title - Artist Name" oder "Track Title\nArtist Name"
                    parts = re.split(r"\s+[—–-]\s+|\n", title_text.strip())
                    if len(parts) >= 2:
                        title = parts[0].strip()
                        artist = parts[1].strip()
                    else:
                        title = parts[0].strip() if parts else ""
                        artist = ""
                    if title and artist:
                        results.append((artist, title))
                except Exception:
                    continue
        finally:
            browser.close()

    log.info("tiktok_extracted", count=len(results))
    return results
