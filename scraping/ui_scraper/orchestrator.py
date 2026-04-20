"""Orchestrator fuer die 5 parallel laufenden UI-Scraping-Agents.

Startet alle Agents gleichzeitig via asyncio.gather(), nutzt einen geteilten
Playwright-Browser und fasst am Ende die Ergebnisse zu einem Design-System-Dump zusammen.

Usage:
    python -m ui_scraper.orchestrator --output ../design-tokens
"""
from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path

import structlog
from playwright.async_api import async_playwright
from rich.console import Console
from rich.table import Table

from .agents import (
    AgentContext,
    AgentResult,
    AppStoreGalleryAgent,
    ColorsAgent,
    FlowsAgent,
    IconsAgent,
    ScreenshotsAgent,
    SpotifyBrandAgent,
    SpotifyWebPlayerAgent,
    TypographyAgent,
)
from .config import settings

log = structlog.get_logger()
console = Console()


AGENT_CLASSES = [
    # Web-Player Scraping (Layout, Colors, Typography, Icons, Flows)
    ScreenshotsAgent, ColorsAgent, TypographyAgent, IconsAgent, FlowsAgent,
    # Deep-Scrape einzelner Pages (Album/Artist/Playlist Web-Player)
    SpotifyWebPlayerAgent,
    # Offizielle Brand-Referenz
    SpotifyBrandAgent,
    # iOS-App-Screenshots (authoritative UI-Renders)
    AppStoreGalleryAgent,
]


async def orchestrate(output_dir: Path) -> list[AgentResult]:
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "icons").mkdir(exist_ok=True)
    (output_dir / "wireframes").mkdir(exist_ok=True)
    (output_dir / "screenshots").mkdir(exist_ok=True)

    async with async_playwright() as pw:
        browser = await pw.chromium.launch(headless=False, args=["--disable-blink-features=AutomationControlled"])
        ctx = AgentContext(browser=browser, output_dir=output_dir)

        agents = [AgentCls(ctx) for AgentCls in AGENT_CLASSES]
        log.info("dispatching_agents", count=len(agents))

        results = await asyncio.gather(*(agent.run() for agent in agents), return_exceptions=False)
        await browser.close()

    _write_summary(output_dir, results)
    _print_summary(results)
    return results


def _write_summary(output_dir: Path, results: list[AgentResult]) -> None:
    summary = {
        "agents": [
            {
                "name": r.agent_name,
                "ok": r.ok,
                "duration_s": round(r.duration_s, 2),
                "artifacts": [str(p.relative_to(output_dir)) for p in r.artifacts if p.is_relative_to(output_dir)],
                "error": r.error,
                "payload": r.payload,
            }
            for r in results
        ],
    }
    (output_dir / "scrape-summary.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8"
    )


def _print_summary(results: list[AgentResult]) -> None:
    table = Table(title="UI-Scraping Summary")
    table.add_column("Agent", style="cyan")
    table.add_column("OK", style="green")
    table.add_column("Artefakte", justify="right")
    table.add_column("Dauer (s)", justify="right")
    table.add_column("Fehler", style="red")

    for r in results:
        table.add_row(
            r.agent_name,
            "yes" if r.ok else "no",
            str(len(r.artifacts)),
            f"{r.duration_s:.2f}",
            (r.error or "")[:60],
        )
    console.print(table)


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Rolify UI-Scraping Orchestrator")
    p.add_argument("--output", type=Path, default=settings.output_dir, help="Output directory fuer design-tokens")
    return p.parse_args()


def main() -> int:
    args = _parse_args()
    results = asyncio.run(orchestrate(args.output))
    failed = [r for r in results if not r.ok]
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
