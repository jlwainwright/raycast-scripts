#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title AI Keys: Test (Paste Key)
# @raycast.mode fullOutput
# @raycast.packageName AI Keys
# @raycast.keywords ai,keys,models,test

# Optional parameters:
# @raycast.icon 🧪
# @raycast.description Paste API key; auto-detect provider and list models (or use provider:key)
# @raycast.argument1 { "type": "text", "placeholder": "API Key (or provider:key)", "optional": false }

set -euo pipefail

INPUT=${1:-}

# Dependencies check
for cmd in curl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Missing dependency: $cmd"
    echo "👉 Install with: brew install $cmd"
    exit 1
  fi
done

if [[ -z "$INPUT" ]]; then
  echo "❌ API key is required."
  echo "Tip: optionally prefix with provider (e.g., openai:sk-..., deepseek:sk-..., anthropic:sk-ant-..., perplexity:pplx-..., gemini:AIza...)."
  exit 1
fi

# Parse optional provider override in the form "provider:key"
PROVIDER="auto"
API_KEY="$INPUT"
if [[ "$INPUT" == *:* ]]; then
  prefix=${INPUT%%:*}
  rest=${INPUT#*:}
  case "$prefix" in
    openai|gemini|anthropic|perplexity|deepseek)
      PROVIDER="$prefix"
      API_KEY="$rest"
      ;;
    *)
      API_KEY="$INPUT"
      ;;
  esac
fi

TMP_RESP=$(mktemp)
cleanup() { rm -f "$TMP_RESP"; }
trap cleanup EXIT

header_line() {
  echo "==============================================="
}

print_models() {
  local provider_name=$1
  local jq_filter=$2

  local count
  count=$(jq -r "$jq_filter" "$TMP_RESP" | sed '/^$/d' | wc -l | tr -d ' ')

  if [[ "$count" -gt 0 ]]; then
    echo "✅ $provider_name: $count models found"
    header_line
    jq -r "$jq_filter" "$TMP_RESP" | sed '/^$/d' | sort
  else
    echo "⚠️ Parsed zero models for $provider_name. Raw response snippet:"
    header_line
    head -c 2000 "$TMP_RESP"
  fi
}

# Perform request and handle errors
request_and_parse() {
  local curl_cmd=()
  local provider_name=$1
  shift
  curl_cmd=("curl" "-sS" "-w" "%{http_code}" "-o" "$TMP_RESP" "$@")

  local http_code
  http_code=$("${curl_cmd[@]}")

  if [[ "$http_code" != "200" ]]; then
    echo "❌ $provider_name request failed (HTTP $http_code)"
    # Try to extract error message if any
    if jq -e . >/dev/null 2>&1 <"$TMP_RESP"; then
      local msg
      msg=$(jq -r '.error.message // .message // .error // "(no error message)"' "$TMP_RESP")
      echo "Error: $msg"
    else
      echo "Response:"
      head -c 2000 "$TMP_RESP"
    fi
    exit 1
  fi
}

detect_provider() {
  local key="$1"
  # Strong identifiers
  if [[ "$key" =~ ^AIza[0-9A-Za-z_-]+$ ]]; then echo gemini; return; fi
  if [[ "$key" =~ ^pplx-[A-Za-z0-9_-]+$ ]]; then echo perplexity; return; fi
  if [[ "$key" =~ ^sk-ant-[A-Za-z0-9_-]+$ ]]; then echo anthropic; return; fi
  # Ambiguous: could be OpenAI or DeepSeek
  if [[ "$key" =~ ^sk-[A-Za-z0-9_-]+$ ]]; then echo ambiguous; return; fi
  echo unknown
}

case "${PROVIDER:-auto}" in
  gemini)
    echo "🔑 Testing Google Gemini API key..."
    request_and_parse "Gemini" \
      -H "x-goog-api-key: $API_KEY" \
      "https://generativelanguage.googleapis.com/v1beta/models"
    # models[].name (e.g., models/gemini-1.5-pro)
    # Strip leading "models/" for readability
    print_models "Gemini" '.models[]?.name | sub("^models/"; "")'
    ;;

  anthropic)
    echo "🔑 Testing Anthropic API key..."
    request_and_parse "Anthropic" \
      -H "x-api-key: $API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      "https://api.anthropic.com/v1/models"
    print_models "Anthropic" '.data[]?.id'
    ;;

  openai)
    echo "🔑 Testing OpenAI API key..."
    request_and_parse "OpenAI" \
      -H "Authorization: Bearer $API_KEY" \
      "https://api.openai.com/v1/models"
    print_models "OpenAI" '.data[]?.id'
    ;;

  perplexity)
    echo "🔑 Testing Perplexity API key..."
    request_and_parse "Perplexity" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Accept: application/json" \
      "https://api.perplexity.ai/models"
    # Some responses are { models: ["model-a", ...] } or objects
    print_models "Perplexity" 'if has("models") then (.models[] | (if type=="object" then (.id // .name // .) else . end)) else empty end'
    ;;

  deepseek)
    echo "🔑 Testing DeepSeek API key..."
    request_and_parse "DeepSeek" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Accept: application/json" \
      "https://api.deepseek.com/v1/models"
    print_models "DeepSeek" '.data[]?.id'
    ;;

  auto)
    echo "🔎 Detecting provider from key format..."
    detected=$(detect_provider "$API_KEY")
    case "$detected" in
      gemini)
        echo "🔍 Detected: Google Gemini"
        request_and_parse "Gemini" \
          -H "x-goog-api-key: $API_KEY" \
          "https://generativelanguage.googleapis.com/v1beta/models"
        print_models "Gemini" '.models[]?.name | sub("^models/"; "")'
        ;;
      anthropic)
        echo "🔍 Detected: Anthropic"
        request_and_parse "Anthropic" \
          -H "x-api-key: $API_KEY" \
          -H "anthropic-version: 2023-06-01" \
          "https://api.anthropic.com/v1/models"
        print_models "Anthropic" '.data[]?.id'
        ;;
      perplexity)
        echo "🔍 Detected: Perplexity"
        request_and_parse "Perplexity" \
          -H "Authorization: Bearer $API_KEY" \
          -H "Accept: application/json" \
          "https://api.perplexity.ai/models"
        print_models "Perplexity" 'if has("models") then (.models[] | (if type=="object" then (.id // .name // .) else . end)) else empty end'
        ;;
      ambiguous)
        echo "⚠️ Cannot safely determine provider: key looks like 'sk-...' which may be OpenAI or DeepSeek."
        echo "👉 Prefix key to force: openai:sk-...   or   deepseek:sk-..."
        exit 1
        ;;
      *)
        echo "⚠️ Unknown key format. Supported providers:"
        echo "   gemini(AIza...), anthropic(sk-ant-...), perplexity(pplx-...), openai(sk-...), deepseek(sk-...)"
        echo "👉 Prefix with provider to force: openai:KEY | deepseek:KEY | anthropic:KEY | perplexity:KEY | gemini:KEY"
        exit 1
        ;;
    esac
    ;;

  *)
    echo "❌ Unknown provider override: $PROVIDER"
    echo "Supported: gemini, anthropic, openai, perplexity, deepseek, or leave blank for auto-detect"
    exit 1
    ;;
esac

echo
echo "🎉 Done. If models are listed above, your key is valid."
