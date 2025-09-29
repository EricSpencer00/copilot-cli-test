#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <workflow_run_id>" >&2
  exit 1
fi

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "GH_TOKEN environment variable must be set for GitHub CLI authentication." >&2
  exit 1
fi

RUN_ID="$1"
WORKDIR=".ai-repair"
BRANCH="copilot/fix-${RUN_ID}"
LOG_FILE="${WORKDIR}/ci.log"
PROMPT_FILE="${WORKDIR}/prompt.md"
OUTPUT_FILE="${WORKDIR}/copilot-output.txt"
PATCH_FILE="${WORKDIR}/copilot.patch"
PR_BODY_FILE="${WORKDIR}/pr-body.md"

mkdir -p "${WORKDIR}"

if [[ ! -f "${LOG_FILE}" ]]; then
  echo "Expected CI log at ${LOG_FILE} (generate it before invoking this script)." >&2
  exit 2
fi

# Configure git identity for the automation user.
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

if git rev-parse --verify "${BRANCH}" >/dev/null 2>&1; then
  git checkout "${BRANCH}"
else
  git checkout -b "${BRANCH}"
fi

echo "${BRANCH}" > "${WORKDIR}/current-branch"

cat > "${PROMPT_FILE}" <<'EOF'
You are GitHub Copilot acting as a continuous integration repair assistant.
The latest pytest run failed. Review the repository and supply a unified diff patch
(compatible with `git apply`) that will make the tests pass. Only respond with the patch
inside a fenced code block, and target the minimal files necessary. Preserve existing
style and docstrings.
EOF

echo "Requesting patch from Copilot..."

PROMPT_PAYLOAD=$(python - <<'PY'
from pathlib import Path
prompt = Path("${PROMPT_FILE}").read_text(encoding="utf-8")
log = Path("${LOG_FILE}").read_text(encoding="utf-8")
print(f"{prompt}\n\nHere is the failing pytest output to consider:\n{log}")
PY
)

echo "${PROMPT_PAYLOAD}" | gh copilot suggest --format markdown > "${OUTPUT_FILE}"

python scripts/extract_patch.py "${OUTPUT_FILE}" > "${PATCH_FILE}"

if [[ ! -s "${PATCH_FILE}" ]]; then
  echo "Copilot did not return a usable patch." >&2
  exit 3
fi

git apply "${PATCH_FILE}"

git status --short

git add -u

timestamp=$(date -u +"%Y-%m-%d %H:%M:%SZ")
cat > "${PR_BODY_FILE}" <<EOF
## Automated repair attempt

- Triggered by workflow run ${RUN_ID}
- Generated at ${timestamp} by the AI repair workflow
- Copilot response saved to \\`${OUTPUT_FILE}\\`

Please review the proposed changes before merging.
EOF

cat "${PR_BODY_FILE}"
