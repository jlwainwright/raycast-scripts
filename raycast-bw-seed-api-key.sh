#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title AI Keys: Seed Key (Bitwarden)
# @raycast.mode fullOutput
# @raycast.packageName AI Keys
# @raycast.keywords ai,keys,bitwarden,seed,create

# Optional parameters:
# @raycast.icon 🧩
# @raycast.description Create a Bitwarden item for the selected provider if missing
# @raycast.argument1 { "type": "dropdown", "placeholder": "Provider", "data": [
#   {"title": "Google Gemini", "value": "gemini"},
#   {"title": "Anthropic", "value": "anthropic"},
#   {"title": "OpenAI", "value": "openai"},
#   {"title": "Perplexity", "value": "perplexity"},
#   {"title": "DeepSeek", "value": "deepseek"}
# ] }
# @raycast.argument2 { "type": "text", "placeholder": "API Key (paste here)", "optional": false }
# @raycast.argument3 { "type": "dropdown", "placeholder": "If item exists", "data": [
#   {"title": "Skip", "value": "skip"},
#   {"title": "Update", "value": "update"}
# ], "optional": true }

set -euo pipefail

PROVIDER=${1:-}
API_KEY=${2:-}
ON_EXISTS=${3:-skip}

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing dependency: $1"; exit 1; }; }
need_cmd bw
need_cmd jq

if [[ -z "$PROVIDER" || -z "$API_KEY" ]]; then
  echo "❌ Provider and API key are required"
  exit 1
fi

status=$(bw status 2>/dev/null | jq -r '.status // "error"')
if [[ "$status" != "unlocked" ]]; then
  echo "🔒 Vault locked. Please unlock first (e.g., raycast-bw-unlock.sh)"
  exit 1
fi

ITEM_NAME=""
LOGIN_USER=""
URI=""

case "$PROVIDER" in
  gemini)
    ITEM_NAME="Gemini API Key"
    LOGIN_USER="Google AI Studio"
    URI="https://ai.google.dev"
    ;;
  anthropic)
    ITEM_NAME="Anthropic API Key"
    LOGIN_USER="Anthropic"
    URI="https://api.anthropic.com"
    ;;
  openai)
    ITEM_NAME="OpenAI API Key"
    LOGIN_USER="OpenAI"
    URI="https://api.openai.com"
    ;;
  perplexity)
    ITEM_NAME="Perplexity API Key"
    LOGIN_USER="Perplexity"
    URI="https://api.perplexity.ai"
    ;;
  deepseek)
    ITEM_NAME="DeepSeek API Key"
    LOGIN_USER="DeepSeek"
    URI="https://api.deepseek.com"
    ;;
  *)
    echo "❌ Unsupported provider: $PROVIDER"
    echo "Supported: gemini, anthropic, openai, perplexity, deepseek"
    exit 1
    ;;
esac

echo "🧩 Seeding Bitwarden item if missing: $ITEM_NAME"

existing_item=$(bw get item "$ITEM_NAME" 2>/dev/null || true)
if [[ -n "$existing_item" ]]; then
  if [[ "$ON_EXISTS" == "update" ]]; then
    echo "✏️  Updating existing item: $ITEM_NAME"
    item_id=$(echo "$existing_item" | jq -r '.id')
    if [[ -z "$item_id" || "$item_id" == "null" ]]; then
      echo "❌ Could not determine item id for update"
      exit 1
    fi

    updated=$(echo "$existing_item" | \
      jq --arg user "$LOGIN_USER" --arg key "$API_KEY" --arg uri "$URI" --arg ts "$(date '+%Y-%m-%d %H:%M:%S')" '
        .login = (.login // {})
        | .login.username = $user
        | .login.password = $key
        | .login.uris = [{"uri": $uri}]
        | .notes = ((.notes // "") + "\nUpdated via Raycast seed script on " + $ts)
      ')

    echo "$updated" | bw encode | bw edit item "$item_id" >/dev/null

    echo "🔄 Syncing..."
    bw sync >/dev/null 2>&1 || true

    # Verify
    test_key=$(bw get password "$ITEM_NAME" 2>/dev/null || true)
    if [[ "$test_key" == "$API_KEY" ]]; then
      echo "🎉 Updated '$ITEM_NAME' and verified retrieval"
    else
      echo "⚠️ Updated item but verification failed. Please check Bitwarden."
    fi
    exit 0
  else
    echo "✅ Item already exists. Skipping creation (override by choosing 'Update')."
    exit 0
  fi
fi

# Create new item
bw get template item | \
  jq --arg name "$ITEM_NAME" \
     --arg user "$LOGIN_USER" \
     --arg key "$API_KEY" \
     --arg uri "$URI" \
     '.type=1
      | .name=$name
      | .notes="API key stored via Raycast seed script"
      | .login.username=$user
      | .login.password=$key
      | .login.uris=[{"uri":$uri}]' | \
  bw encode | bw create item >/dev/null

echo "🔄 Syncing..."
bw sync >/dev/null 2>&1 || true

# Verify
test_key=$(bw get password "$ITEM_NAME" 2>/dev/null || true)
if [[ "$test_key" == "$API_KEY" ]]; then
  echo "🎉 Created '$ITEM_NAME' and verified retrieval"
  echo "👉 You can now run: ./raycast-test-api-keys-bitwarden.sh $PROVIDER"
else
  echo "⚠️ Created item but verification failed. Please check Bitwarden."
fi
