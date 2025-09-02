#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Clear Cache Directories
# @raycast.mode compact
# @raycast.packageName System Maintenance

# Optional parameters:
# @raycast.icon 🗑️
# @raycast.description Clear common cache directories to free up disk space
# @raycast.argument1 { "type": "dropdown", "placeholder": "Select cache to clear", "data": [{"title": "All Caches", "value": "all"}, {"title": "HuggingFace (8.4GB)", "value": "huggingface"}, {"title": "UV Python (5.7GB)", "value": "uv"}, {"title": "Puppeteer (3.2GB)", "value": "puppeteer"}, {"title": "Whisper (2.1GB)", "value": "whisper"}, {"title": "Pre-commit (110MB)", "value": "precommit"}] }

CACHE_DIR="$HOME/.cache"

# Function to get directory size
get_size() {
    if [ -d "$1" ]; then
        du -sh "$1" 2>/dev/null | cut -f1
    else
        echo "0B"
    fi
}

# Function to clear specific cache
clear_cache() {
    local cache_name=$1
    local cache_path="$CACHE_DIR/$cache_name"
    
    if [ -d "$cache_path" ]; then
        local size_before=$(get_size "$cache_path")
        rm -rf "$cache_path"
        echo "✅ Cleared $cache_name cache ($size_before freed)"
    else
        echo "⚠️  $cache_name cache not found"
    fi
}

case "$1" in
    "all")
        echo "🧹 Clearing all cache directories..."
        total_before=$(get_size "$CACHE_DIR")
        
        clear_cache "huggingface"
        clear_cache "uv" 
        clear_cache "puppeteer"
        clear_cache "whisper"
        clear_cache "pre-commit"
        clear_cache "prisma"
        
        total_after=$(get_size "$CACHE_DIR")
        echo "🎉 Total cache cleared: $total_before → $total_after"
        ;;
    "huggingface")
        clear_cache "huggingface"
        ;;
    "uv")
        clear_cache "uv"
        ;;
    "puppeteer")
        clear_cache "puppeteer"
        ;;
    "whisper")
        clear_cache "whisper"
        ;;
    "precommit")
        clear_cache "pre-commit"
        ;;
    *)
        echo "❌ Invalid option. Use: all, huggingface, uv, puppeteer, whisper, or precommit"
        exit 1
        ;;
esac