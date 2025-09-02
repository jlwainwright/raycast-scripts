# Repository Guidelines

## Project Structure & Module Organization
- `raycast-*.sh`, `yt-summarize-*.sh`, `raycast-bw-*.sh`: Raycast Script Commands (Bitwarden tools, YouTube summarizers).
- `debug_browser_script.sh`, `clear-cache.sh`, `mcp-health-check.sh`, `Create New Text File.sh`: Utility scripts surfaced in Raycast.
- `*.rayconfig`: Raycast config snapshot (generated). Do not hand‑edit.

## Build, Test, and Development Commands
- Run script locally: `bash raycast-bitwarden.sh help`, `bash yt-summarize-gemini.sh "<youtube-url>"`.
- Required tools: `brew install jq yt-dlp shellcheck shfmt bitwarden-cli` (plus `whisper` optional).
- Lint: `shellcheck *.sh` (fix all warnings for new/changed lines).
- Format: `shfmt -w -i 2 -ci -bn .` (2‑space indent, indent case, binary ops at line end).

## Coding Style & Naming Conventions
- Shebang: `#!/bin/bash`; prefer `set -euo pipefail` in new scripts.
- Indentation: 2 spaces. Filenames: kebab-case (`raycast-foo-bar.sh`).
- Functions: `snake_case`; constants and env: `UPPER_SNAKE_CASE`.
- Raycast headers: include `@raycast.title`, `@raycast.mode`, `@raycast.packageName`, and arguments. Example:
  ```
  # @raycast.schemaVersion 1
  # @raycast.title Example
  # @raycast.mode compact
  # @raycast.argument1 { "type": "text", "placeholder": "Input" }
  ```

## Testing Guidelines
- No formal suite yet; smoke‑test via Bash: run with sample inputs and invalid inputs.
- Optional: add Bats tests under `test/` and run with `bats test`.
- Keep external calls stub‑friendly (read from env, check `command -v`, exit non‑zero on error).

## Commit & Pull Request Guidelines
- Use Conventional Commits: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`.
- PRs should include: purpose, user‑visible behavior (Raycast title/args), screenshots of Raycast output if relevant, dependency notes, and manual test steps.

## Security & Configuration Tips
- Never hard‑code secrets. Store keys in Bitwarden and load via `bw get password "<Item Name>"` or `./raycast-bitwarden.sh env`.
- Document required env vars (e.g., `GEMINI_API_KEY`, `ANTHROPIC_API_KEY`, `BW_SESSION`). Prefer configurable paths over hard‑coded user directories.

## AI Keys Utilities
- `raycast-test-api-keys.sh`: Paste a key; provider auto-detected (or use `provider:key`). Example: `./raycast-test-api-keys.sh "$OPENAI_API_KEY"` or `./raycast-test-api-keys.sh openai:sk-...`.
- `raycast-test-api-keys-bitwarden.sh`: Unlocks Bitwarden and tests keys from items: “Gemini/Anthropic/OpenAI/Perplexity/DeepSeek API Key”. Example: `./raycast-test-api-keys-bitwarden.sh all`.
- `raycast-bw-seed-api-key.sh`: Create or update a provider key item. Example: `./raycast-bw-seed-api-key.sh perplexity "$PPLX_KEY" update`.
- `raycast-bw-delete-api-key.sh`: Delete provider key item(s) from Bitwarden (trash or purge). Example: `./raycast-bw-delete-api-key.sh openai trash yes`.
