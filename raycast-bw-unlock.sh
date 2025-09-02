#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Unlock Bitwarden
# @raycast.mode compact
# @raycast.packageName Bitwarden

# Optional parameters:
# @raycast.icon 🔓
# @raycast.description Unlock Bitwarden vault with Touch ID

# Configuration
BW_KEYCHAIN_SERVICE="bitwarden-cli"
BW_KEYCHAIN_ACCOUNT="$(whoami)-vault"

# Get Touch ID password
password=$(security find-generic-password -a "$BW_KEYCHAIN_ACCOUNT" -s "$BW_KEYCHAIN_SERVICE" -w 2>/dev/null)

if [[ -z "$password" ]]; then
    echo "❌ No Touch ID password stored"
    echo "💡 Store password first: security add-generic-password -a \"$BW_KEYCHAIN_ACCOUNT\" -s \"$BW_KEYCHAIN_SERVICE\" -w \"your-password\""
    exit 1
fi

# Check current status
status=$(bw status 2>/dev/null | jq -r '.status // "error"')

case "$status" in
    "unlocked")
        echo "✅ Already unlocked"
        ;;
    "locked")
        export BW_SESSION=$(echo "$password" | bw unlock --raw 2>/dev/null)
        if [[ -n "$BW_SESSION" ]]; then
            echo "✅ Unlocked with Touch ID!"
        else
            echo "❌ Failed to unlock"
        fi
        ;;
    *)
        echo "❌ Not logged in or error"
        echo "💡 Run: bw login jlwainwright@gmail.com"
        ;;
esac