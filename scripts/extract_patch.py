"""Extract a unified diff patch from a Copilot response.

The Copilot CLI often wraps patches in triple backticks with an optional
language hint (e.g. ```diff … ```). This helper pulls the first such block
from the response. If no fenced diff is found, it falls back to the raw
content.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

FENCE_RE = re.compile(r"```(?:diff)?\s*(.*?)```", re.DOTALL)


def extract_patch(text: str) -> str:
    match = FENCE_RE.search(text)
    if match:
        return match.group(1).strip()
    return text.strip()


def main() -> None:
    if len(sys.argv) < 2:
        sys.stderr.write("Usage: extract_patch.py <copilot_output_file>\n")
        sys.exit(1)

    source = Path(sys.argv[1])
    if not source.exists():
        sys.stderr.write(f"Input file not found: {source}\n")
        sys.exit(1)

    content = source.read_text(encoding="utf-8")
    patch = extract_patch(content)

    if not patch:
        sys.stderr.write("No patch content detected in Copilot output.\n")
        sys.exit(2)

    sys.stdout.write(patch)


if __name__ == "__main__":
    main()
