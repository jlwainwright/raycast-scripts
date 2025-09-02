#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title YouTube Summarizer (Claude Complete)
# @raycast.mode fullOutput
# @raycast.packageName Media Tools

# Optional parameters:
# @raycast.icon 🎬
# @raycast.description Download, transcribe, and summarize YouTube videos with Claude API
# @raycast.argument1 { "type": "text", "placeholder": "YouTube URL" }

URL="$1"
TEMP_DIR="/tmp/yt-claude-$$"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TRANSCRIPT_FILE="$HOME/Downloads/yt-transcript-$TIMESTAMP.txt"
SUMMARY_FILE="$HOME/Downloads/yt-summary-$TIMESTAMP.md"
TEMP_RESPONSE="$TEMP_DIR/response.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Validate input
if [ -z "$URL" ]; then
    echo -e "${RED}⌛ Error: Please provide a YouTube URL${NC}"
    exit 1
fi

# Set Claude Code OAuth token (fallback if not in environment)
if [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
    export CLAUDE_CODE_OAUTH_TOKEN="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"
fi

# Verify token is available
if [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
    echo -e "${RED}⌛ Error: CLAUDE_CODE_OAUTH_TOKEN environment variable is not set${NC}"
    echo -e "${YELLOW}Add to ~/.zshrc or ~/.bash_profile:${NC}"
    echo -e "export CLAUDE_CODE_OAUTH_TOKEN='your-oauth-token-here'"
    exit 1
fi

# Check dependencies
for cmd in yt-dlp claude; do
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${RED}⌛ Error: $cmd is not installed${NC}"
        if [ "$cmd" = "yt-dlp" ]; then
            echo -e "${YELLOW}Install with: brew install yt-dlp${NC}"
        elif [ "$cmd" = "claude" ]; then
            echo -e "${YELLOW}Install with: curl -fsSL https://claude.ai/install.sh | sh${NC}"
        fi
        exit 1
    fi
done

mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

echo -e "${BLUE}🎬 YouTube Summarizer with Claude API${NC}"
echo -e "${YELLOW}URL: $URL${NC}"
echo

# Get video info
echo -e "${BLUE}📋 Getting video information...${NC}"
VIDEO_INFO=$(yt-dlp --dump-json "$URL" 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${RED}⌛ Error: Could not fetch video information${NC}"
    exit 1
fi

VIDEO_TITLE=$(echo "$VIDEO_INFO" | jq -r '.title // "Unknown Title"')
VIDEO_ID=$(echo "$VIDEO_INFO" | jq -r '.id // "unknown"')
VIDEO_CHANNEL=$(echo "$VIDEO_INFO" | jq -r '.uploader // "Unknown Channel"')
VIDEO_DURATION=$(echo "$VIDEO_INFO" | jq -r '.duration // 0')

# Convert duration to human-readable
if [ "$VIDEO_DURATION" -ne 0 ]; then
    HOURS=$((VIDEO_DURATION / 3600))
    MINUTES=$(((VIDEO_DURATION % 3600) / 60))
    SECONDS=$((VIDEO_DURATION % 60))
    if [ $HOURS -gt 0 ]; then
        DURATION_STR="${HOURS}h ${MINUTES}m ${SECONDS}s"
    else
        DURATION_STR="${MINUTES}m ${SECONDS}s"
    fi
else
    DURATION_STR="Unknown"
fi

echo -e "${GREEN}✅ Title: $VIDEO_TITLE${NC}"
echo -e "${GREEN}✅ Channel: $VIDEO_CHANNEL${NC}"
echo -e "${GREEN}✅ Duration: $DURATION_STR${NC}"
echo

# Try subtitles first
echo -e "${BLUE}📥 Checking for subtitles...${NC}"
TRANSCRIPTION_METHOD=""
TRANSCRIPT_TEXT=""

# Try to get subtitles in various formats
if yt-dlp --write-auto-sub --write-sub --sub-format "vtt/srt/txt/best" --skip-download -o "%(id)s.%(ext)s" "$URL" 2>/dev/null; then
    # Find any subtitle file
    SUB_FILE=$(find . -name "${VIDEO_ID}*" -type f | grep -E '\.(vtt|srt|txt)$' | head -1)
    
    if [ -n "$SUB_FILE" ] && [ -f "$SUB_FILE" ]; then
        echo -e "${GREEN}✅ Found subtitles, processing...${NC}"
        
        # Process based on file type
        if [[ "$SUB_FILE" == *.vtt ]]; then
            # Process VTT format
            TRANSCRIPT_TEXT=$(sed -n '/-->/,/^$/p' "$SUB_FILE" | \
                grep -v '\-\->' | \
                grep -v '^[[:space:]]*$' | \
                sed 's/<[^>]*>//g' | \
                awk '!seen[$0]++')
        elif [[ "$SUB_FILE" == *.srt ]]; then
            # Process SRT format
            TRANSCRIPT_TEXT=$(grep -v '^[0-9]*$' "$SUB_FILE" | \
                grep -v '\-\->' | \
                grep -v '^[[:space:]]*$' | \
                sed 's/<[^>]*>//g' | \
                awk '!seen[$0]++')
        else
            # Plain text
            TRANSCRIPT_TEXT=$(cat "$SUB_FILE")
        fi
        TRANSCRIPTION_METHOD="subtitles"
    fi
fi

# If no subtitles, try Whisper transcription
if [ -z "$TRANSCRIPT_TEXT" ]; then
    if command -v whisper &> /dev/null; then
        echo -e "${BLUE}🎵 No subtitles found, downloading audio for transcription...${NC}"
        if yt-dlp --extract-audio --audio-format mp3 --audio-quality 192K -o "audio.%(ext)s" "$URL" 2>/dev/null; then
            echo -e "${BLUE}🎙️ Transcribing with Whisper (this may take a while)...${NC}"
            whisper audio.mp3 --model base --output_format txt --output_dir . >/dev/null 2>&1
            if [ -f "audio.txt" ]; then
                TRANSCRIPT_TEXT=$(cat audio.txt)
                TRANSCRIPTION_METHOD="whisper"
            fi
        fi
    else
        echo -e "${RED}⌛ Error: No subtitles available and Whisper is not installed${NC}"
        echo -e "${YELLOW}Install Whisper with: pip install openai-whisper${NC}"
        exit 1
    fi
fi

if [ -z "$TRANSCRIPT_TEXT" ]; then
    echo -e "${RED}⌛ Error: Could not extract transcript from video${NC}"
    exit 1
fi

# Save transcript
echo "$TRANSCRIPT_TEXT" > "$TRANSCRIPT_FILE"
WORD_COUNT=$(echo "$TRANSCRIPT_TEXT" | wc -w | tr -d ' ')
CHAR_COUNT=$(echo "$TRANSCRIPT_TEXT" | wc -c | tr -d ' ')

echo -e "${GREEN}✅ Transcript extracted: $WORD_COUNT words${NC}"

# Prepare the transcript for API (escape for JSON)
# Truncate if too long (100k chars is safe for Claude)
MAX_CHARS=100000
if [ $CHAR_COUNT -gt $MAX_CHARS ]; then
    echo -e "${YELLOW}⚠️ Transcript too long, truncating to fit API limits...${NC}"
    TRANSCRIPT_TEXT=$(echo "$TRANSCRIPT_TEXT" | head -c $MAX_CHARS)
fi

# Create the prompt for Claude
PROMPT="You are analyzing a YouTube video transcript. Please provide a comprehensive analysis with the following sections:

Video Information:
- Title: $VIDEO_TITLE
- Channel: $VIDEO_CHANNEL
- Duration: $DURATION_STR
- URL: $URL

Please analyze the transcript and provide:

1. **Summary** (2-3 paragraphs): A comprehensive overview of the video content
2. **Key Points**: The main points discussed (as bullet points)
3. **Topics Covered**: List all major topics discussed
4. **Important Details**: Any specific facts, numbers, statistics, recommendations, or technical information
5. **Takeaways**: The main conclusions or lessons from the video

Format your response in clean markdown. Be thorough but concise.

Transcript:
$TRANSCRIPT_TEXT"

# Prepare the prompt for Claude CLI (no JSON escaping needed)
CLAUDE_PROMPT="$PROMPT"

echo -e "${BLUE}🤖 Sending to Claude Code CLI for analysis...${NC}"

# Call Claude Code CLI with retries
MAX_RETRIES=3
RETRY_COUNT=0
SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$SUCCESS" = false ]; do
    if [ $RETRY_COUNT -gt 0 ]; then
        echo -e "${YELLOW}🔄 Retry attempt $RETRY_COUNT...${NC}"
        sleep 3
    fi
    
    # Call Claude Code CLI
    if ANALYSIS=$(claude -p "$CLAUDE_PROMPT" 2>"$TEMP_DIR/claude_error.log"); then
        if [ -n "$ANALYSIS" ]; then
            SUCCESS=true
            echo -e "${GREEN}✅ Analysis completed successfully${NC}"
        else
            echo -e "${YELLOW}⚠️ Empty response from Claude CLI${NC}"
        fi
    else
        ERROR_MSG=$(cat "$TEMP_DIR/claude_error.log" 2>/dev/null || echo "Unknown error")
        echo -e "${YELLOW}⚠️ Claude CLI Error: $ERROR_MSG${NC}"
        
        if [[ "$ERROR_MSG" == *"rate"* ]] || [[ "$ERROR_MSG" == *"limit"* ]]; then
            echo -e "${YELLOW}⏳ Rate limited, waiting 10 seconds...${NC}"
            sleep 10
        fi
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
done

if [ "$SUCCESS" = false ]; then
    echo -e "${RED}❌ Failed to get analysis after $MAX_RETRIES attempts${NC}"
    echo -e "${YELLOW}Creating partial summary file with transcript only...${NC}"
    
    # Create a basic file with just the transcript
    cat > "$SUMMARY_FILE" << EOF
# YouTube Video Summary

**Title:** $VIDEO_TITLE  
**Channel:** $VIDEO_CHANNEL  
**Duration:** $DURATION_STR  
**URL:** [$URL]($URL)  
**Generated:** $(date '+%Y-%m-%d %H:%M:%S')  
**Transcription Method:** $TRANSCRIPTION_METHOD  
**Word Count:** $WORD_COUNT words

---

## ⚠️ Analysis Failed

The Claude API analysis failed after multiple attempts. The transcript is included below for manual analysis.

---

## Video Transcript

$TRANSCRIPT_TEXT

---

*Note: You can try running the script again or analyze the transcript manually.*
EOF
else
    # Create the complete markdown file with analysis
    cat > "$SUMMARY_FILE" << EOF
# YouTube Video Summary

**Title:** $VIDEO_TITLE  
**Channel:** $VIDEO_CHANNEL  
**Duration:** $DURATION_STR  
**URL:** [$URL]($URL)  
**Generated:** $(date '+%Y-%m-%d %H:%M:%S')  
**Transcription Method:** $TRANSCRIPTION_METHOD  
**Word Count:** $WORD_COUNT words

---

$ANALYSIS

---

## Full Transcript

<details>
<summary>Click to expand full transcript</summary>

$TRANSCRIPT_TEXT

</details>

---

*This summary was generated using Claude AI from the video's transcript.*
EOF
fi

# Verify the output file
if [ -f "$SUMMARY_FILE" ]; then
    FILE_SIZE=$(wc -c < "$SUMMARY_FILE" | tr -d ' ')
    LINE_COUNT=$(wc -l < "$SUMMARY_FILE" | tr -d ' ')
    
    echo
    echo -e "${GREEN}🎉 Summary saved successfully!${NC}"
    echo -e "${BLUE}📍 Location: $SUMMARY_FILE${NC}"
    echo -e "${BLUE}📊 Stats: $LINE_COUNT lines, $FILE_SIZE bytes${NC}"
    
    # Open the file
    if command -v typora &> /dev/null; then
        echo -e "${BLUE}📖 Opening in Typora...${NC}"
        typora "$SUMMARY_FILE" &
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo -e "${BLUE}📖 Opening file...${NC}"
        open "$SUMMARY_FILE"
    fi
    
    echo
    echo -e "${GREEN}✅ Done! The summary has been created and opened.${NC}"
else
    echo -e "${RED}❌ Error: Failed to create output file${NC}"
    exit 1
fi