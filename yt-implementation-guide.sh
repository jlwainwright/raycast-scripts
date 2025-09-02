#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title YouTube Implementation Guide
# @raycast.mode fullOutput
# @raycast.packageName Media Tools

# Optional parameters:
# @raycast.icon 🛠️
# @raycast.description Create comprehensive step-by-step implementation guide from YouTube videos
# @raycast.argument1 { "type": "text", "placeholder": "YouTube URL" }

URL="$1"
TEMP_DIR="/tmp/yt-guide-$$"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TRANSCRIPT_FILE="$HOME/Downloads/yt-transcript-$TIMESTAMP.txt"
GUIDE_FILE="$HOME/Downloads/yt-implementation-guide-$TIMESTAMP.md"
TEMP_RESPONSE="$TEMP_DIR/response.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

echo -e "${BLUE}🛠️ YouTube Implementation Guide Generator${NC}"
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
VIDEO_DESCRIPTION=$(echo "$VIDEO_INFO" | jq -r '.description // ""')

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

# Truncate if too long (100k chars is safe for Claude)
MAX_CHARS=100000
if [ $CHAR_COUNT -gt $MAX_CHARS ]; then
    echo -e "${YELLOW}⚠️ Transcript too long, truncating to fit API limits...${NC}"
    TRANSCRIPT_TEXT=$(echo "$TRANSCRIPT_TEXT" | head -c $MAX_CHARS)
fi

# Create the comprehensive implementation guide prompt
IMPLEMENTATION_PROMPT="You are an expert technical instructor and implementation specialist. Analyze this YouTube video transcript and create a comprehensive, step-by-step implementation guide for everything discussed in the video.

Video Information:
- Title: $VIDEO_TITLE
- Channel: $VIDEO_CHANNEL
- Duration: $DURATION_STR
- URL: $URL

Please create a detailed implementation guide with the following structure:

# 📋 Implementation Guide: $VIDEO_TITLE

## 🎯 Overview
- Brief summary of what will be implemented
- Expected outcome and benefits
- Time estimate for completion
- Skill level required

## 📦 Prerequisites
- Required software, tools, and dependencies
- System requirements
- Account setups needed
- Background knowledge required

## 🛠️ Step-by-Step Implementation

Create numbered steps with:
- Clear, actionable instructions
- Code examples where applicable
- Configuration details
- Expected outputs at each step
- Validation/testing instructions

## 💻 Code Examples
- Complete, working code snippets
- File structures and organization
- Configuration files
- Command-line instructions

## ✅ Implementation Checklist
- [ ] Checkbox list of all major tasks
- [ ] Verification steps
- [ ] Testing procedures
- [ ] Quality checks

## 🔧 Troubleshooting
- Common issues and solutions
- Error messages and fixes
- Debugging techniques
- Alternative approaches

## 🚀 Next Steps & Enhancements
- Possible improvements
- Advanced features to add
- Related tutorials or resources
- Best practices for production

## 📚 Additional Resources
- Links mentioned in video
- Documentation references
- Community resources
- Related tools and libraries

## 🏷️ Tags
- Relevant technology tags
- Difficulty level
- Implementation categories

---

**Instructions:**
1. Extract ALL technical concepts, tools, frameworks, and implementation details from the transcript
2. Create step-by-step instructions that someone could follow to implement exactly what's shown
3. Include specific code examples, commands, and configurations
4. Add troubleshooting for common issues
5. Make it comprehensive enough that someone could complete the implementation without watching the video
6. Focus on practical, actionable steps rather than theory
7. Include validation steps to verify each part works
8. Add time estimates for each major section

Transcript:
$TRANSCRIPT_TEXT"

echo -e "${PURPLE}🤖 Generating comprehensive implementation guide with Claude Code CLI...${NC}"

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
    if GUIDE_CONTENT=$(claude -p "$IMPLEMENTATION_PROMPT" 2>"$TEMP_DIR/claude_error.log"); then
        if [ -n "$GUIDE_CONTENT" ]; then
            SUCCESS=true
            echo -e "${GREEN}✅ Implementation guide generated successfully${NC}"
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
    echo -e "${RED}❌ Failed to generate implementation guide after $MAX_RETRIES attempts${NC}"
    echo -e "${YELLOW}Creating basic guide template with transcript...${NC}"
    
    # Create a basic template with transcript for manual completion
    cat > "$GUIDE_FILE" << EOF
# 📋 Implementation Guide: $VIDEO_TITLE

**Video Information:**
- **Title:** $VIDEO_TITLE  
- **Channel:** $VIDEO_CHANNEL  
- **Duration:** $DURATION_STR  
- **URL:** [$URL]($URL)  
- **Generated:** $(date '+%Y-%m-%d %H:%M:%S')  
- **Transcription Method:** $TRANSCRIPTION_METHOD  
- **Word Count:** $WORD_COUNT words

---

## ⚠️ Guide Generation Failed

The Claude Code CLI analysis failed after multiple attempts. Please use the transcript below to manually create the implementation guide.

## 🎯 Manual Implementation Steps

1. **Watch the video** and identify key technical concepts
2. **Extract tools and frameworks** mentioned
3. **Create step-by-step instructions** for each process
4. **Add code examples** and configurations
5. **Include troubleshooting** for common issues
6. **Test the implementation** to verify it works

---

## 📝 Video Transcript

$TRANSCRIPT_TEXT

---

## 📋 Implementation Template

Copy this template and fill in the details:

### 🎯 Overview
- **What will be implemented:** 
- **Expected outcome:** 
- **Time estimate:** 
- **Skill level:** 

### 📦 Prerequisites
- [ ] Required software:
- [ ] Dependencies:
- [ ] Accounts needed:
- [ ] Background knowledge:

### 🛠️ Step-by-Step Implementation

1. **Step 1:** 
   - Instructions:
   - Code example:
   - Expected output:

2. **Step 2:**
   - Instructions:
   - Code example:
   - Expected output:

(Continue for all steps...)

### ✅ Implementation Checklist
- [ ] Task 1
- [ ] Task 2
- [ ] Testing
- [ ] Verification

### 🔧 Troubleshooting
- **Issue:** Solution
- **Error:** Fix

---

*This guide template was generated from the video transcript. Complete the implementation details manually.*
EOF
else
    # Create the complete guide with Claude's analysis
    cat > "$GUIDE_FILE" << EOF
# 📋 Implementation Guide: $VIDEO_TITLE

**Video Information:**
- **Title:** $VIDEO_TITLE  
- **Channel:** $VIDEO_CHANNEL  
- **Duration:** $DURATION_STR  
- **URL:** [$URL]($URL)  
- **Generated:** $(date '+%Y-%m-%d %H:%M:%S')  
- **Transcription Method:** $TRANSCRIPTION_METHOD  
- **Word Count:** $WORD_COUNT words

---

$GUIDE_CONTENT

---

## 📝 Original Transcript

<details>
<summary>Click to expand full transcript</summary>

$TRANSCRIPT_TEXT

</details>

---

*This implementation guide was generated using Claude Code CLI from the video's transcript.*
EOF
fi

# Verify the output file
if [ -f "$GUIDE_FILE" ]; then
    FILE_SIZE=$(wc -c < "$GUIDE_FILE" | tr -d ' ')
    LINE_COUNT=$(wc -l < "$GUIDE_FILE" | tr -d ' ')
    
    echo
    echo -e "${GREEN}🎉 Implementation guide created successfully!${NC}"
    echo -e "${BLUE}📍 Location: $GUIDE_FILE${NC}"
    echo -e "${BLUE}📊 Stats: $LINE_COUNT lines, $FILE_SIZE bytes${NC}"
    
    # Count sections in the guide
    SECTION_COUNT=$(grep -c '^##' "$GUIDE_FILE" 2>/dev/null || echo "0")
    STEP_COUNT=$(grep -c '^[0-9]\+\.' "$GUIDE_FILE" 2>/dev/null || echo "0")
    CHECKLIST_COUNT=$(grep -c '^\- \[ \]' "$GUIDE_FILE" 2>/dev/null || echo "0")
    
    echo -e "${PURPLE}📈 Guide Structure:${NC}"
    echo -e "${PURPLE}   • Sections: $SECTION_COUNT${NC}"
    echo -e "${PURPLE}   • Implementation Steps: $STEP_COUNT${NC}"
    echo -e "${PURPLE}   • Checklist Items: $CHECKLIST_COUNT${NC}"
    echo
    
    # Open the file
    if command -v typora &> /dev/null; then
        echo -e "${BLUE}📖 Opening in Typora...${NC}"
        typora "$GUIDE_FILE" &
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo -e "${BLUE}📖 Opening file...${NC}"
        open "$GUIDE_FILE"
    fi
    
    echo
    echo -e "${GREEN}✅ Done! The implementation guide has been created and opened.${NC}"
    echo -e "${BLUE}💡 Use this guide to implement everything from the video step-by-step.${NC}"
else
    echo -e "${RED}❌ Error: Failed to create output file${NC}"
    exit 1
fi