#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Get Password from Bitwarden
# @raycast.mode compact
# @raycast.packageName Bitwarden

# Optional parameters:
# @raycast.icon 🔑
# @raycast.argument1 { "type": "text", "placeholder": "Item name", "optional": false }
# @raycast.description Copy password to clipboard

ITEM_NAME="$1"

if [[ -z "$ITEM_NAME" ]]; then
    echo "❌ Please provide item name"
    exit 1
fi

# Check if unlocked
status=$(bw status 2>/dev/null | jq -r '.status // "error"')
if [[ "$status" != "unlocked" ]]; then
    echo "🔒 Vault locked. Please unlock first."
    exit 1
fi

# Get password
password=$(bw get password "$ITEM_NAME" 2>/dev/null)

if [[ -n "$password" ]]; then
    echo "$password" | pbcopy
    echo "✅ Password copied to clipboard"
    echo "🔐 Item: $ITEM_NAME"
else
    echo "❌ Item not found: $ITEM_NAME"
    
    # Show similar items
    echo "💡 Similar items:"
    bw list items --search "$ITEM_NAME" 2>/dev/null | jq -r '.[] | "• \(.name)"' | head -5
fi