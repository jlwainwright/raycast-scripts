#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Add Gemini API to Bitwarden
# @raycast.mode fullOutput
# @raycast.packageName Bitwarden

# Optional parameters:
# @raycast.icon 🤖
# @raycast.description Add your Gemini API key to Bitwarden vault

# Configuration
GEMINI_API_KEY="AIzaSyCtpvQTlEu6krvsPzlxV0j5_mrpIAB1qes"  # Your current key
ITEM_NAME="Gemini API Key"

echo "🤖 Adding Gemini API Key to Bitwarden..."

# Check if unlocked
status=$(bw status 2>/dev/null | jq -r '.status // "error"')
if [[ "$status" != "unlocked" ]]; then
    echo "🔒 Vault is locked. Please unlock first."
    exit 1
fi

# Check if item already exists
existing_item=$(bw get item "$ITEM_NAME" 2>/dev/null)

if [[ -n "$existing_item" ]]; then
    echo "⚠️ Item '$ITEM_NAME' already exists"
    echo "Current password length: $(echo "$existing_item" | jq -r '.login.password' | wc -c)"
    
    read -p "Update existing item? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Update existing item
        item_id=$(echo "$existing_item" | jq -r '.id')
        echo "$existing_item" | \
            jq --arg key "$GEMINI_API_KEY" '.login.password=$key' | \
            bw encode | bw edit item "$item_id" >/dev/null
        
        echo "✅ Updated existing Gemini API Key"
    else
        echo "❌ Update cancelled"
        exit 1
    fi
else
    # Create new item
    bw get template item | \
        jq --arg name "$ITEM_NAME" --arg key "$GEMINI_API_KEY" \
        '.type=1 | .name=$name | .login.username="Google AI Studio" | .login.password=$key | .login.uris=[{"uri":"https://ai.google.dev"}]' | \
        bw encode | bw create item >/dev/null
    
    echo "✅ Created new Gemini API Key item"
fi

# Sync to server
echo "🔄 Syncing to server..."
bw sync >/dev/null 2>&1

# Test retrieval
test_key=$(bw get password "$ITEM_NAME" 2>/dev/null)
if [[ "$test_key" == "$GEMINI_API_KEY" ]]; then
    echo "✅ Verification successful"
    echo "🔐 Gemini API Key is now stored securely"
    echo ""
    echo "Usage:"
    echo "  bw get password \"$ITEM_NAME\"  # Get API key"
    echo "  export GEMINI_API_KEY=\$(bw get password \"$ITEM_NAME\")  # Load as env var"
else
    echo "❌ Verification failed"
fi