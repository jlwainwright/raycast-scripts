#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title AI Keys: Test (Bitwarden)
# @raycast.mode fullOutput
# @raycast.packageName AI Keys
# @raycast.keywords ai,keys,models,bitwarden,test

# Optional parameters:
# @raycast.icon 🔐
# @raycast.description Unlock Bitwarden, read keys, and test by listing models
# @raycast.argument1 { "type": "dropdown", "placeholder": "Provider", "data": [
#   {"title": "All Providers", "value": "all"},
#   {"title": "Google Gemini", "value": "gemini"},
#   {"title": "Anthropic", "value": "anthropic"},
#   {"title": "OpenAI", "value": "openai"},
#   {"title": "Perplexity", "value": "perplexity"},
#   {"title": "DeepSeek", "value": "deepseek"}
# ] }

set -euo pipefail

PROVIDER=${1:-all}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TESTER_SCRIPT="$SCRIPT_DIR/raycast-test-api-keys.sh"

if [[ ! -x "$TESTER_SCRIPT" ]]; then
  echo "❌ Missing tester script: $TESTER_SCRIPT"
  echo "Please keep both scripts in the same directory."
  exit 1
fi

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing dependency: $1"; exit 1; }; }
need_cmd bw
need_cmd jq
need_cmd security

# Config for Keychain-stored Bitwarden password (used for Touch ID unlock)
BW_KEYCHAIN_SERVICE=${BW_KEYCHAIN_SERVICE:-bitwarden-cli}
BW_KEYCHAIN_ACCOUNT=${BW_KEYCHAIN_ACCOUNT:-"$(whoami)-vault"}

get_touch_id_password() {
  security find-generic-password -a "$BW_KEYCHAIN_ACCOUNT" -s "$BW_KEYCHAIN_SERVICE" -w 2>/dev/null || true
}

ensure_bw_unlocked() {
  local status_json status
  status_json=$(bw status 2>/dev/null || echo '{}')
  status=$(echo "$status_json" | jq -r '.status // "unknown"')

  case "$status" in
    unlocked)
      echo "🔓 Bitwarden: already unlocked";
      ;;
    locked)
      echo "🔓 Unlocking Bitwarden with Touch ID…"
      local pw
      pw=$(get_touch_id_password)
      if [[ -z "$pw" ]]; then
        echo "❌ No Touch ID password found in Keychain"
        echo "👉 Store it: security add-generic-password -a \"$BW_KEYCHAIN_ACCOUNT\" -s \"$BW_KEYCHAIN_SERVICE\" -w \"<your-master-password>\""
        exit 1
      fi
      export BW_SESSION
      BW_SESSION=$(echo "$pw" | bw unlock --raw 2>/dev/null || true)
      if [[ -z "${BW_SESSION:-}" ]]; then
        echo "❌ Failed to unlock Bitwarden"
        exit 1
      fi
      echo "✅ Bitwarden unlocked"
      ;;
    unauthenticated)
      echo "❌ Bitwarden not logged in. Run: bw login <email>"
      exit 1
      ;;
    *)
      echo "⚠️ Unknown Bitwarden status: $status"
      ;;
  esac
}

get_item_password() {
  local item_name=$1
  bw get password "$item_name" 2>/dev/null || true
}

provider_item_name() {
  case "$1" in
    gemini) echo "Gemini API Key" ;;
    anthropic) echo "Anthropic API Key" ;;
    openai) echo "OpenAI API Key" ;;
    perplexity) echo "Perplexity API Key" ;;
    deepseek) echo "DeepSeek API Key" ;;
    *) return 1 ;;
  esac
}

run_test_for_provider() {
  local provider=$1
  local item_name
  item_name=$(provider_item_name "$provider")

  echo
  echo "🔎 Provider: $provider"
  echo "🔎 Bitwarden item: $item_name"

  local key
  key=$(get_item_password "$item_name")
  if [[ -z "$key" ]]; then
    echo "❌ No API key found in Bitwarden for '$item_name' — skipping"
    return 0
  fi

  echo "🧪 Testing key by listing models…"
  # Call the tester script; it will handle all HTTP and output formatting
  "$TESTER_SCRIPT" "$provider" "$key"
}

main() {
  ensure_bw_unlocked

  local providers=()
  if [[ "$PROVIDER" == "all" ]]; then
    providers=(gemini anthropic openai perplexity deepseek)
  else
    providers=($PROVIDER)
  fi

  local start_ts end_ts
  start_ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "🗝️  AI API Key Tester (Bitwarden)"
  echo "Started: $start_ts"
  echo "-----------------------------------------------"

  local failed=0
  for p in "${providers[@]}"; do
    if ! run_test_for_provider "$p"; then
      failed=$((failed+1))
    fi
  done

  end_ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo
  echo "-----------------------------------------------"
  echo "Finished: $end_ts"
  if [[ $failed -gt 0 ]]; then
    echo "⚠️  Completed with $failed failures"
    exit 1
  else
    echo "✅ All checks completed"
  fi
}

main "$@"
