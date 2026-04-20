from __future__ import annotations

import asyncio
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import structlog
from playwright.async_api import Browser, BrowserContext

log = structlog.get_logger()


@dataclass
class AgentContext:
    """Geteilter Kontext zwischen allen parallel laufenden Agents.

    Jeder Agent bekommt seinen eigenen Playwright-BrowserContext, aber teilt
    Output-Verzeichnis und kann Events via Asyncio-Queues an Peers schicken.
    """
    browser: Browser
    output_dir: Path
    shared_state: dict[str, Any] = field(default_factory=dict)
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)


@dataclass
class AgentResult:
    agent_name: str
    ok: bool
    artifacts: list[Path] = field(default_factory=list)
    duration_s: float = 0.0
    error: str | None = None
    payload: dict[str, Any] = field(default_factory=dict)


class BaseAgent(ABC):
    """Baseklasse fuer alle UI-Scraping-Agents.

    Unterklassen ueberschreiben `_run()`, der Rest (Context-Setup, Timing,
    Error-Handling) wird zentral gemacht.
    """

    name: str = "base"

    def __init__(self, ctx: AgentContext):
        self.ctx = ctx
        self.log = log.bind(agent=self.name)

    async def run(self) -> AgentResult:
        start = asyncio.get_event_loop().time()
        self.log.info("starting")
        try:
            artifacts = await self._run()
            duration = asyncio.get_event_loop().time() - start
            self.log.info("done", duration_s=round(duration, 2), artifact_count=len(artifacts))
            return AgentResult(agent_name=self.name, ok=True, artifacts=artifacts, duration_s=duration)
        except Exception as e:
            duration = asyncio.get_event_loop().time() - start
            self.log.exception("failed")
            return AgentResult(agent_name=self.name, ok=False, duration_s=duration, error=str(e))

    @abstractmethod
    async def _run(self) -> list[Path]:
        """Fuehrt die Agent-Logik aus. Liefert Liste der erzeugten Artefakte zurueck."""

    async def _make_context(self, viewport: tuple[int, int] = (390, 844)) -> BrowserContext:
        """Erstellt isolierten Playwright-Context pro Agent."""
        return await self.ctx.browser.new_context(
            viewport={"width": viewport[0], "height": viewport[1]},
            device_scale_factor=3,
            user_agent=(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) "
                "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
            ),
            locale="de-CH",
        )
