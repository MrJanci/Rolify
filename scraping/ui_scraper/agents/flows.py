"""UX-Flow-Agent: nimmt Playwright-Traces (Video + DOM-Events) fuer kritische User-Flows auf.

Output: design-tokens/wireframes/<flow>.md  (Markdown-Beschreibung + Step-Screenshots)
        design-tokens/wireframes/traces/<flow>.zip  (Playwright-Trace fuer trace-viewer)
"""
from __future__ import annotations

from pathlib import Path

from ..config import settings
from .base import BaseAgent


FLOWS = [
    {
        "name": "login",
        "steps": [
            ("Goto Homepage", lambda p: p.goto(settings.target_url, wait_until="networkidle")),
            ("Wait", lambda p: p.wait_for_timeout(1500)),
        ],
    },
    {
        "name": "browse_home",
        "steps": [
            ("Goto Homepage", lambda p: p.goto(settings.target_url, wait_until="networkidle")),
            ("Wait", lambda p: p.wait_for_timeout(1500)),
            ("Scroll Feed", lambda p: p.mouse.wheel(0, 600)),
            ("Wait Lazyload", lambda p: p.wait_for_timeout(1000)),
        ],
    },
    {
        "name": "search_flow",
        "steps": [
            ("Goto Search", lambda p: p.goto(settings.target_url.rstrip("/") + "/search", wait_until="networkidle")),
            ("Wait", lambda p: p.wait_for_timeout(1500)),
        ],
    },
]


class FlowsAgent(BaseAgent):
    name = "flows"

    async def _run(self) -> list[Path]:
        flows_dir = self.ctx.output_dir / "wireframes"
        flows_dir.mkdir(exist_ok=True)
        traces_dir = flows_dir / "traces"
        traces_dir.mkdir(exist_ok=True)
        screens_dir = flows_dir / "screens"
        screens_dir.mkdir(exist_ok=True)

        artifacts: list[Path] = []

        for flow in FLOWS:
            flow_name = flow["name"]
            browser_ctx = await self._make_context()
            await browser_ctx.tracing.start(screenshots=True, snapshots=True, sources=False)
            page = await browser_ctx.new_page()

            md_lines = [f"# Flow: {flow_name}", "", "Generiert vom FlowsAgent — automatische Trace."]
            step_artifacts: list[Path] = []

            for i, (label, action) in enumerate(flow["steps"]):
                try:
                    await action(page)
                except Exception as e:
                    self.log.warn("step_failed", flow=flow_name, step=label, error=str(e))
                    continue
                await page.wait_for_timeout(500)
                shot = screens_dir / f"{flow_name}_{i:02d}.png"
                await page.screenshot(path=str(shot), full_page=False)
                step_artifacts.append(shot)
                md_lines.append(f"## Step {i + 1}: {label}")
                md_lines.append(f"![{label}](screens/{shot.name})")
                md_lines.append("")

            trace_path = traces_dir / f"{flow_name}.zip"
            await browser_ctx.tracing.stop(path=str(trace_path))
            await browser_ctx.close()

            md_path = flows_dir / f"{flow_name}.md"
            md_path.write_text("\n".join(md_lines), encoding="utf-8")

            artifacts.extend([md_path, trace_path, *step_artifacts])

        return artifacts
