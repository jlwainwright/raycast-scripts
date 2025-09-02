#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title AI Keys: Delete Key (Bitwarden)
# @raycast.mode fullOutput
# @raycast.packageName AI Keys
# @raycast.needsConfirmation true
# @raycast.keywords ai,keys,bitwarden,delete,purge

# Optional parameters:
# @raycast.icon 🗑️
# @raycast.description Delete provider API key item(s) from Bitwarden (trash or purge)
# @raycast.argument1 { "type": "dropdown", "placeholder": "Provider", "data": [
#   {"title": "All Providers", "value": "all"},
#   {"title": "Google Gemini", "value": "gemini"},
#   {"title": "Anthropic", "value": "anthropic"},
#   {"title": "OpenAI", "value": "openai"},
#   {"title": "Perplexity", "value": "perplexity"},
#   {"title": "DeepSeek", "value": "deepseek"}
# ] }
# @raycast.argument2 { "type": "dropdown", "placeholder": "Action", "data": [
#   {"title": "Move to Trash", "value": "trash"},
#   {"title": "Permanently Delete", "value": "purge"}
# ], "optional": true }
# @raycast.argument3 { "type": "dropdown", "placeholder": "Confirm", "data": [
#   {"title": "No", "value": "no"},
#   {"title": "Yes — Delete", "value": "yes"}
# ], "optional": true }

set -euo pipefail

PROVIDER=${1:-all}
ACTION=${2:-trash}
CONFIRM=${3:-no}

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing dependency: $1"; exit 1; }; }
need_cmd bw
need_cmd jq

status=$(bw status 2>/dev/null | jq -r '.status // "error"')
if [[ "$status" != "unlocked" ]]; then
  echo "🔒 Bitwarden vault is locked or not logged in."
  echo "👉 Unlock first: run raycast-bw-unlock.sh or bw unlock"
  exit 1
fi

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

delete_item() {
  local id=$1
  local name=$2

  if [[ "$ACTION" == "purge" ]]; then
    # Try permanent delete via flag; fallback to purge command if necessary
    if bw delete item "$id" --permanent >/dev/null 2>&1; then
      echo "🧨 Purged: $name ($id)"
    elif bw purge item "$id" >/dev/null 2>&1; then
      echo "🧨 Purged via bw purge: $name ($id)"
    else
      echo "❌ Failed to permanently delete $name ($id)"
      return 1
    fi
  else
    if bw delete item "$id" >/dev/null 2>&1; then
      echo "🗑️  Moved to trash: $name ($id)"
    else
      echo "❌ Failed to move $name ($id) to trash"
      return 1
    fi
  fi
}

run_for_provider() {
  local provider=$1
  local item_name
  item_name=$(provider_item_name "$provider") || { echo "⚠️ Unknown provider: $provider"; return 0; }

  local item_json id
  item_json=$(bw get item "$item_name" 2>/dev/null || true)
  if [[ -z "$item_json" ]]; then
    echo "ℹ️  No item found for: $item_name (skipping)"
    return 0
  fi
  id=$(echo "$item_json" | jq -r '.id // empty')
  if [[ -z "$id" ]]; then
    echo "❌ Could not parse item id for: $item_name"
    return 1
  fi
  delete_item "$id" "$item_name"
}

if [[ "$CONFIRM" != "yes" ]]; then
  echo "❌ Deletion not confirmed. Set Confirm to 'Yes — Delete'."
  exit 1
fi

echo "🧹 Bitwarden API Key Cleaner"
echo "Provider: $PROVIDER | Action: $ACTION"
echo "----------------------------------------"

failed=0
if [[ "$PROVIDER" == "all" ]]; then
  for p in gemini anthropic openai perplexity deepseek; do
    if ! run_for_provider "$p"; then
      failed=$((failed+1))
    fi
  done
else
  if ! run_for_provider "$PROVIDER"; then
    failed=$((failed+1))
  fi
fi

echo ""
echo "🔄 Syncing vault..."
bw sync >/dev/null 2>&1 || true

if [[ $failed -gt 0 ]]; then
  echo "⚠️ Completed with $failed error(s)."
  exit 1
else
  echo "✅ Done."
fi
