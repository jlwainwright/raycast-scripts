#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Debug Browser Detection
# @raycast.mode fullOutput
# @raycast.description Test browser URL detection for troubleshooting
# @raycast.icon 🔧
# @raycast.packageName Debug Tools

echo "🔧 Browser Detection Debug"
echo "=========================="

# Check what browsers are running
echo "1. Checking running applications..."
RUNNING_APPS=$(osascript -e 'tell application "System Events" to get name of every process whose background only is false' 2>/dev/null)
echo "   All running apps: $RUNNING_APPS"

BROWSERS=$(echo "$RUNNING_APPS" | tr ',' '\n' | grep -E "(Chrome|Safari|Arc|Brave|Firefox|Edge)" | head -5)
echo "   Browser processes found:"
if [ -n "$BROWSERS" ]; then
    echo "$BROWSERS" | sed 's/^/     • /'
else
    echo "     ❌ No browsers detected"
fi

echo ""
echo "2. Testing browser URL access..."

# Test Chrome
echo "   Testing Google Chrome:"
CHROME_URL=$(osascript -e 'tell application "Google Chrome" to get URL of active tab of first window' 2>&1)
if [[ "$CHROME_URL" =~ ^https?:// ]]; then
    echo "     ✅ Success: $CHROME_URL"
else
    echo "     ❌ Failed: $CHROME_URL"
fi

# Test Brave
echo "   Testing Brave Browser:"
BRAVE_URL=$(osascript -e 'tell application "Brave Browser" to get URL of active tab of first window' 2>&1)
if [[ "$BRAVE_URL" =~ ^https?:// ]]; then
    echo "     ✅ Success: $BRAVE_URL"
else
    echo "     ❌ Failed: $BRAVE_URL"
fi

# Test Safari
echo "   Testing Safari:"
SAFARI_URL=$(osascript -e 'tell application "Safari" to get URL of current tab of first window' 2>&1)
if [[ "$SAFARI_URL" =~ ^https?:// ]]; then
    echo "     ✅ Success: $SAFARI_URL"
else
    echo "     ❌ Failed: $SAFARI_URL"
fi

# Test Arc
echo "   Testing Arc:"
ARC_URL=$(osascript -e 'tell application "Arc" to get URL of active tab of first window' 2>&1)
if [[ "$ARC_URL" =~ ^https?:// ]]; then
    echo "     ✅ Success: $ARC_URL"
else
    echo "     ❌ Failed: $ARC_URL"
fi

echo ""
echo "3. Checking clipboard..."
CLIPBOARD=$(pbpaste 2>/dev/null)
if [[ "$CLIPBOARD" =~ ^https?:// ]]; then
    echo "   ✅ Clipboard contains URL: $CLIPBOARD"
elif [ -n "$CLIPBOARD" ]; then
    echo "   ⚠️  Clipboard has content but not a URL: $(echo "$CLIPBOARD" | head -c 50)..."
else
    echo "   ❌ Clipboard is empty"
fi

echo ""
echo "4. YouTube URL validation test..."
TEST_URLS=(
    "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
    "https://youtu.be/dQw4w9WgXcQ"
    "https://www.youtube.com/shorts/abc123"
    "https://www.google.com"
    "not a url"
)

for test_url in "${TEST_URLS[@]}"; do
    if [[ "$test_url" =~ youtube\.com/watch\?v=|youtu\.be/|youtube\.com/shorts/ ]]; then
        echo "   ✅ Valid YouTube URL: $test_url"
    else
        echo "   ❌ Not a YouTube URL: $test_url"
    fi
done

echo ""
echo "5. Permissions check..."
echo "   Checking if Terminal/Raycast has accessibility permissions..."

# Test if we can get system events
if osascript -e 'tell application "System Events" to get name of first process' >/dev/null 2>&1; then
    echo "   ✅ System Events access working"
else
    echo "   ❌ System Events access denied - check Privacy settings"
fi

echo ""
echo "📋 Next Steps:"
echo "   1. Make sure you're on a YouTube video page"
echo "   2. If using Safari/Chrome, check that it's the active window"
echo "   3. Try copying a YouTube URL to clipboard as fallback"
echo "   4. Check System Preferences > Privacy & Security > Accessibility"
echo "      Make sure Terminal or Raycast has permission"