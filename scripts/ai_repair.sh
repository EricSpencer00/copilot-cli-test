#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <workflow_run_id>" >&2
  exit 1
fi

## Accept either GH_TOKEN or GITHUB_TOKEN (workflow provides GITHUB_TOKEN)
if [[ -z "${GH_TOKEN:-}" && -z "${GITHUB_TOKEN:-}" ]]; then
  echo "GH_TOKEN or GITHUB_TOKEN environment variable must be set for Copilot authentication." >&2
  echo "In GitHub Actions set 'GH_TOKEN: \\${{ secrets.GITHUB_TOKEN }}' on the step or pass GITHUB_TOKEN and this script will pick it up." >&2
  exit 1
fi
# Prefer GH_TOKEN but fall back to GITHUB_TOKEN
GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
export GH_TOKEN

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

PROMPT_PAYLOAD=$(python - <<EOF
from pathlib import Path
prompt = Path("${PROMPT_FILE}").read_text(encoding="utf-8")
log = Path("${LOG_FILE}").read_text(encoding="utf-8")
print(f"{prompt}\n\nHere is the failing pytest output to consider:\n{log}")
EOF
)

COPILOT_CMD="copilot"
if ! command -v "${COPILOT_CMD}" >/dev/null 2>&1; then
  echo "Copilot CLI not found: expected 'copilot' in PATH. Ensure @github/copilot is installed." >&2
  exit 4
fi

echo "Using Copilot CLI: ${COPILOT_CMD}"
if ! echo "${PROMPT_PAYLOAD}" | ${COPILOT_CMD} suggest > "${OUTPUT_FILE}" 2>"${WORKDIR}/copilot.err"; then
  echo "'copilot suggest' failed, attempting fallback to 'copilot chat'..." >&2
  if ! echo "${PROMPT_PAYLOAD}" | ${COPILOT_CMD} chat > "${OUTPUT_FILE}" 2>>"${WORKDIR}/copilot.err"; then
    # If copilot fails due to missing auth, provide a clearer message for Actions logs
    if grep -q "No valid GitHub CLI OAuth token detected" "${WORKDIR}/copilot.err" 2>/dev/null; then
      echo "Copilot CLI error: no valid OAuth token detected. Ensure GH_TOKEN/GITHUB_TOKEN is exported for copilot auth." >&2
      echo "In Actions you can pass GH_TOKEN: 'GH_TOKEN: \\${{ secrets.GITHUB_TOKEN }}' in the step env." >&2
    fi
    echo "Copilot CLI did not produce output. See ${WORKDIR}/copilot.err for details." >&2
    tail -n +1 "${WORKDIR}/copilot.err" >&2 || true
    exit 4
  fi
fi

# Extract patch from Copilot output
python scripts/extract_patch.py "${OUTPUT_FILE}" > "${PATCH_FILE}" || true

if [[ ! -s "${PATCH_FILE}" ]]; then
  echo "Copilot did not return a usable patch." >&2
  exit 3
fi

git apply "${PATCH_FILE}"

git status --short

# Only add updated files if any changes were made by the patch
if git diff --quiet --exit-code; then
  echo "No changes detected after applying patch. Exiting."
  exit 0
fi

git add -A

timestamp=$(date -u +"%Y-%m-%d %H:%M:%SZ")
cat > "${PR_BODY_FILE}" <<EOF
## Automated repair attempt

- Triggered by workflow run ${RUN_ID}
- Generated at ${timestamp} by the AI repair workflow
- Copilot response saved to \\`${OUTPUT_FILE}\\`

Please review the proposed changes before merging.
EOF

cat "${PR_BODY_FILE}"
