#!/usr/bin/env python3
"""Live smoke test for the Google Antigravity SDK shipped in agy-box.

Runs one tiny, budget-capped agent turn and checks the reply.

  smoke.py gemini   Hosted Gemini via LocalAgentConfig (reads GEMINI_API_KEY)
  smoke.py openai   OpenAI-compatible server via LocalOpenAIAgentConfig
                    (SDK_SMOKE_BASE_URL, SDK_SMOKE_MODEL), e.g. the DGX Spark
                    cluster's vLLM endpoint. No cloud credentials needed.
"""

import asyncio
import os
import sys
import tempfile

from google.antigravity import Agent, LocalAgentConfig, LocalOpenAIAgentConfig
from google.antigravity import types

PROMPT = "Reply with exactly the single word PONG and nothing else."
TIMEOUT_S = int(os.environ.get("SDK_SMOKE_TIMEOUT", "180"))


def build_config(mode: str, workdir: str):
    budget = types.BudgetConfig(max_model_calls=3, max_tool_calls=2)
    common = {
        "budget_config": budget,
        "workspaces": [workdir],
        "app_data_dir": os.path.join(workdir, "app-data"),
    }
    if mode == "gemini":
        if not os.environ.get("GEMINI_API_KEY"):
            sys.exit("GEMINI_API_KEY is not set")
        return LocalAgentConfig(**common)
    if mode == "openai":
        base_url = os.environ.get("SDK_SMOKE_BASE_URL")
        model = os.environ.get("SDK_SMOKE_MODEL")
        if not base_url or not model:
            sys.exit("SDK_SMOKE_BASE_URL and SDK_SMOKE_MODEL must be set")
        return LocalOpenAIAgentConfig(model=model, base_url=base_url, **common).lightweight()
    sys.exit(f"unknown mode {mode!r} (expected 'gemini' or 'openai')")


async def run(mode: str) -> int:
    with tempfile.TemporaryDirectory(prefix="agy-sdk-smoke-") as workdir:
        config = build_config(mode, workdir)
        async with Agent(config) as agent:
            response = await agent.chat(PROMPT)
            text = (await response.text()).strip()
            stop = getattr(response, "stop_reason", None)
    print(f"[{mode}] stop_reason={stop} reply={text[:200]!r}")
    if "PONG" not in text.upper():
        print(f"::error::Antigravity SDK smoke test ({mode}) did not get PONG back")
        return 1
    print(f"Antigravity SDK smoke test ({mode}) passed")
    return 0


def main() -> int:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    return asyncio.run(asyncio.wait_for(run(sys.argv[1]), TIMEOUT_S))


if __name__ == "__main__":
    sys.exit(main())
