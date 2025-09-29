# ai-repair-test

This repository demonstrates an automated "AI auto-repair loop" that reacts to failing continuous integration runs and asks GitHub Copilot to propose fixes. The goal is to intentionally keep the default branch in a failing state so that the repair workflow can showcase how to capture logs, request a patch from Copilot, and raise a pull request with the proposed change.

## How it works

- `src/hello.py` contains a deliberately broken implementation.
- `tests/test_hello.py` has a simple pytest-based unit test that fails against the broken implementation.
- The **CI - Failing Example** workflow runs on every push or pull request to `main` and executes `pytest`. It is expected to fail until the bug is fixed.
- The **AI Repair** workflow listens for failed runs of the CI workflow. When triggered, it:
  1. Checks out the repository and installs dependencies.
  2. Installs the GitHub CLI Copilot extension.
  3. Downloads the logs from the failing CI run.
  4. Prompts Copilot for a patch that would make the tests pass and applies the suggested diff.
  5. Re-runs `pytest` to validate the fix locally within the workflow.
  6. Commits the change to a new branch, pushes it, and opens a pull request containing Copilot's repair attempt.

## Repository layout

```
.
├── src/hello.py
├── tests/test_hello.py
├── requirements.txt
├── scripts/
│   ├── ai_repair.sh
│   └── extract_patch.py
└── .github/workflows/
    ├── ci-failing-example.yml
    └── ai-repair.yml
```

## Local experimentation

You can reproduce the failing test locally with:

```bash
python -m pip install --upgrade pip
pip install -r requirements.txt
pytest
```

To run the repair helper script manually (simulating what the workflow does), make sure you have the GitHub CLI, the Copilot extension, and a `GITHUB_TOKEN` with write access:

```bash
export GH_TOKEN=<your_token>
gh extension install github/gh-copilot --force
bash scripts/ai_repair.sh <workflow_run_id>
```

> **Note:** The automation assumes the Copilot CLI can produce a unified diff surrounded by triple backticks. Depending on Copilot's output format and your account's access to the Copilot agent, manual adjustments may be necessary.

## License

This project is provided as-is for demonstration purposes.
