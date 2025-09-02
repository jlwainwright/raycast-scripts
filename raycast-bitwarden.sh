#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Bitwarden Quick Actions
# @raycast.mode compact
# @raycast.packageName Bitwarden

# Optional parameters:
# @raycast.icon 🔐
# @raycast.argument1 { "type": "text", "placeholder": "Action (unlock/lock/search/get)", "optional": false }
# @raycast.argument2 { "type": "text", "placeholder": "Item name (for search/get)", "optional": true }
# @raycast.description Quick Bitwarden operations with Touch ID

# Documentation:
# @raycast.author Jacques Wainwright
# @raycast.authorURL https://github.com/yourusername

# =============================================================================
# Configuration Variables
# =============================================================================
BW_SERVER_URL="https://vault.jacqueswainwright.com"
BW_EMAIL="jlwainwright@gmail.com"
BW_KEYCHAIN_SERVICE="bitwarden-cli"
BW_KEYCHAIN_ACCOUNT="$(whoami)-vault"

# =============================================================================
# Helper Functions
# =============================================================================

# Get password from Keychain (Touch ID)
get_stored_password() {
    security find-generic-password -a "$BW_KEYCHAIN_ACCOUNT" -s "$BW_KEYCHAIN_SERVICE" -w 2>/dev/null
}

# Check Bitwarden status
check_bw_status() {
    if ! command -v bw >/dev/null 2>&1; then
        echo "❌ Bitwarden CLI not installed"
        exit 1
    fi
    
    local status_json=$(bw status 2>/dev/null)
    echo "$status_json" | jq -r '.status // "error"'
}

# Unlock with Touch ID
unlock_with_touchid() {
    local current_status=$(check_bw_status)
    
    case "$current_status" in
        "unauthenticated")
            echo "❌ Not logged in. Run: bw login $BW_EMAIL"
            exit 1
            ;;
        "unlocked")
            echo "✅ Already unlocked"
            return 0
            ;;
        "locked")
            local password=$(get_stored_password)
            if [[ -z "$password" ]]; then
                echo "❌ No password in Keychain. Setup Touch ID first."
                exit 1
            fi
            
            export BW_SESSION=$(echo "$password" | bw unlock --raw)
            if [[ -n "$BW_SESSION" ]]; then
                echo "✅ Unlocked with Touch ID"
            else
                echo "❌ Failed to unlock"
                exit 1
            fi
            ;;
        *)
            echo "❌ Unknown status: $current_status"
            exit 1
            ;;
    esac
}

# =============================================================================
# Main Actions
# =============================================================================

ACTION="$1"
ITEM_NAME="$2"

case "$ACTION" in
    "unlock"|"u")
        unlock_with_touchid
        ;;
        
    "lock"|"l")
        bw lock 2>/dev/null
        unset BW_SESSION
        echo "🔒 Vault locked"
        ;;
        
    "status"|"s")
        local status_json=$(bw status 2>/dev/null)
        local status=$(echo "$status_json" | jq -r '.status')
        local email=$(echo "$status_json" | jq -r '.userEmail // "N/A"')
        local server=$(echo "$status_json" | jq -r '.serverUrl')
        
        echo "🏠 Server: $server"
        echo "👤 User: $email"
        echo "🔐 Status: $status"
        
        if [[ "$status" == "unlocked" ]]; then
            local item_count=$(bw list items 2>/dev/null | jq length 2>/dev/null || echo "0")
            echo "📊 Items: $item_count"
        fi
        ;;
        
    "search"|"find")
        if [[ -z "$ITEM_NAME" ]]; then
            echo "❌ Please provide search term"
            exit 1
        fi
        
        unlock_with_touchid
        
        echo "🔍 Searching for: $ITEM_NAME"
        bw list items --search "$ITEM_NAME" | jq -r '.[] | "• \(.name) (\(.login.username // "no username"))"'
        ;;
        
    "get"|"password"|"pass")
        if [[ -z "$ITEM_NAME" ]]; then
            echo "❌ Please provide item name"
            exit 1
        fi
        
        unlock_with_touchid
        
        local password=$(bw get password "$ITEM_NAME" 2>/dev/null)
        if [[ -n "$password" ]]; then
            echo "$password" | pbcopy
            echo "✅ Password copied to clipboard"
            echo "🔐 Item: $ITEM_NAME"
        else
            echo "❌ Item not found: $ITEM_NAME"
            exit 1
        fi
        ;;
        
    "totp"|"2fa")
        if [[ -z "$ITEM_NAME" ]]; then
            echo "❌ Please provide item name"
            exit 1
        fi
        
        unlock_with_touchid
        
        local totp_code=$(bw get totp "$ITEM_NAME" 2>/dev/null)
        if [[ -n "$totp_code" ]]; then
            echo "$totp_code" | pbcopy
            echo "✅ TOTP code copied to clipboard"
            echo "🔐 Item: $ITEM_NAME"
            echo "⏰ Code: $totp_code"
        else
            echo "❌ No TOTP found for: $ITEM_NAME"
            exit 1
        fi
        ;;
        
    "sync")
        unlock_with_touchid
        bw sync
        echo "✅ Vault synchronized"
        ;;
        
    "generate"|"gen")
        local length="${ITEM_NAME:-32}"
        local password=$(bw generate --length "$length" --uppercase --lowercase --number --special)
        echo "$password" | pbcopy
        echo "✅ Generated password copied to clipboard"
        echo "🔐 Length: $length characters"
        ;;
        
    "env")
        # Load environment variables
        unlock_with_touchid
        
        echo "🔄 Loading environment variables..."
        
        # Load common API keys
        local gemini_key=$(bw get password "Gemini API Key" 2>/dev/null)
        local openai_key=$(bw get password "OpenAI API Key" 2>/dev/null)
        local anthropic_key=$(bw get password "Anthropic API Key" 2>/dev/null)
        local github_token=$(bw get password "GitHub Token" 2>/dev/null)
        
        # Export variables
        [[ -n "$gemini_key" ]] && export GEMINI_API_KEY="$gemini_key" && echo "✅ GEMINI_API_KEY"
        [[ -n "$openai_key" ]] && export OPENAI_API_KEY="$openai_key" && echo "✅ OPENAI_API_KEY"
        [[ -n "$anthropic_key" ]] && export ANTHROPIC_API_KEY="$anthropic_key" && echo "✅ ANTHROPIC_API_KEY"
        [[ -n "$github_token" ]] && export GITHUB_TOKEN="$github_token" && echo "✅ GITHUB_TOKEN"
        
        echo "🚀 Environment ready for development"
        ;;
        
    "help"|"h"|"")
        echo "🔐 Bitwarden Raycast Quick Actions"
        echo ""
        echo "Usage: raycast-bitwarden.sh <action> [item-name]"
        echo ""
        echo "Actions:"
        echo "  unlock, u           - Unlock vault with Touch ID"
        echo "  lock, l             - Lock vault"
        echo "  status, s           - Show vault status"
        echo "  search <term>       - Search for items"
        echo "  get <item>          - Copy password to clipboard"
        echo "  totp <item>         - Copy TOTP code to clipboard"
        echo "  generate [length]   - Generate secure password"
        echo "  sync                - Sync with server"
        echo "  env                 - Load API keys as environment variables"
        echo ""
        echo "Examples:"
        echo "  raycast-bitwarden.sh unlock"
        echo "  raycast-bitwarden.sh get \"GitHub Token\""
        echo "  raycast-bitwarden.sh search github"
        echo "  raycast-bitwarden.sh generate 16"
        ;;
        
    *)
        echo "❌ Unknown action: $ACTION"
        echo "💡 Use 'help' to see available actions"
        exit 1
        ;;
esac