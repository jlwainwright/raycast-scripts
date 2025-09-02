#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title YouTube Multimodal Implementation Guide
# @raycast.mode fullOutput
# @raycast.packageName Media Tools

# Optional parameters:
# @raycast.icon 🎥
# @raycast.description Create comprehensive implementation guide analyzing both audio and visual content from YouTube videos
# @raycast.argument1 { "type": "text", "placeholder": "YouTube URL" }
# @raycast.argument2 { "type": "dropdown", "placeholder": "AI Provider", "data": [
#   {"title": "Claude Code (Default)", "value": "claude"},
#   {"title": "Gemini Pro 2.5", "value": "gemini"}
# ], "optional": true }
# @raycast.argument3 { "type": "dropdown", "placeholder": "Frame Sampling", "data": [
#   {"title": "Smart Sampling (Default)", "value": "smart"},
#   {"title": "Every 30 seconds", "value": "30s"},
#   {"title": "Every 60 seconds", "value": "60s"},
#   {"title": "Key moments only", "value": "key"}
# ], "optional": true }

URL="$1"
PROVIDER="${2:-claude}"  # Default to Claude if not specified
SAMPLING="${3:-smart}"   # Default to smart sampling
TEMP_DIR="/tmp/yt-multimodal-$$"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TRANSCRIPT_FILE="$HOME/Downloads/yt-transcript-$TIMESTAMP.txt"
GUIDE_FILE="$HOME/Downloads/yt-multimodal-guide-$TIMESTAMP.md"
FRAMES_DIR="$TEMP_DIR/frames"
TEMP_RESPONSE="$TEMP_DIR/response.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
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

# Provider-specific API key checks
if [ "$PROVIDER" = "claude" ]; then
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
elif [ "$PROVIDER" = "gemini" ]; then
    # Check for Gemini API key
    if [ -z "$GEMINI_API_KEY" ]; then
        echo -e "${RED}⌛ Error: GEMINI_API_KEY environment variable is not set${NC}"
        echo -e "${YELLOW}To get a key:${NC}"
        echo -e "1. Go to https://aistudio.google.com/apikey"
        echo -e "2. Create a new API key"
        echo -e "3. Add to ~/.zshrc: export GEMINI_API_KEY='your-key-here'"
        exit 1
    fi
else
    echo -e "${RED}⌛ Error: Invalid provider '$PROVIDER'. Use 'claude' or 'gemini'${NC}"
    exit 1
fi

# Provider-specific dependency checks
if [ "$PROVIDER" = "claude" ]; then
    REQUIRED_CMDS="yt-dlp claude ffmpeg"
else
    REQUIRED_CMDS="yt-dlp curl jq ffmpeg base64"
fi

for cmd in $REQUIRED_CMDS; do
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${RED}⌛ Error: $cmd is not installed${NC}"
        case "$cmd" in
            "yt-dlp") echo -e "${YELLOW}Install with: brew install yt-dlp${NC}" ;;
            "claude") echo -e "${YELLOW}Install with: curl -fsSL https://claude.ai/install.sh | sh${NC}" ;;
            "ffmpeg") echo -e "${YELLOW}Install with: brew install ffmpeg${NC}" ;;
            "curl"|"jq"|"base64") echo -e "${YELLOW}Install with: brew install $cmd${NC}" ;;
        esac
        exit 1
    fi
done

mkdir -p "$TEMP_DIR" "$FRAMES_DIR"
cd "$TEMP_DIR"

echo -e "${BLUE}🎥 YouTube Multimodal Implementation Guide Generator${NC}"
echo -e "${YELLOW}URL: $URL${NC}"
echo -e "${YELLOW}AI Provider: $([ "$PROVIDER" = "claude" ] && echo "Claude Code CLI" || echo "Google Gemini Pro 2.5")${NC}"
echo -e "${YELLOW}Frame Sampling: $SAMPLING${NC}"
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

# Download video for frame extraction
echo -e "${CYAN}🎬 Downloading video for frame analysis...${NC}"
if ! yt-dlp -f "best[height<=720]/best" -o "video.%(ext)s" "$URL" 2>/dev/null; then
    echo -e "${RED}⌛ Error: Could not download video${NC}"
    exit 1
fi

VIDEO_FILE=$(find . -name "video.*" -type f | head -1)
if [ -z "$VIDEO_FILE" ]; then
    echo -e "${RED}⌛ Error: Video file not found after download${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Video downloaded: $(basename "$VIDEO_FILE")${NC}"

# Extract frames based on sampling strategy
echo -e "${CYAN}🖼️ Extracting frames ($SAMPLING sampling)...${NC}"

case "$SAMPLING" in
    "30s")
        # Extract frame every 30 seconds
        ffmpeg -i "$VIDEO_FILE" -vf "fps=1/30" -q:v 2 "$FRAMES_DIR/frame_%04d.jpg" -y >/dev/null 2>&1
        ;;
    "60s")
        # Extract frame every 60 seconds
        ffmpeg -i "$VIDEO_FILE" -vf "fps=1/60" -q:v 2 "$FRAMES_DIR/frame_%04d.jpg" -y >/dev/null 2>&1
        ;;
    "key")
        # Extract only key frames (scene changes)
        ffmpeg -i "$VIDEO_FILE" -vf "select=gt(scene\\,0.3)" -vsync vfr -q:v 2 "$FRAMES_DIR/keyframe_%04d.jpg" -y >/dev/null 2>&1
        ;;
    "smart"|*)
        # Smart sampling: more frames at beginning, key moments, less at end
        DURATION_SECS=$VIDEO_DURATION
        if [ $DURATION_SECS -le 300 ]; then
            # Short video: every 15 seconds
            ffmpeg -i "$VIDEO_FILE" -vf "fps=1/15" -q:v 2 "$FRAMES_DIR/frame_%04d.jpg" -y >/dev/null 2>&1
        elif [ $DURATION_SECS -le 900 ]; then
            # Medium video: every 30 seconds
            ffmpeg -i "$VIDEO_FILE" -vf "fps=1/30" -q:v 2 "$FRAMES_DIR/frame_%04d.jpg" -y >/dev/null 2>&1
        else
            # Long video: every 60 seconds
            ffmpeg -i "$VIDEO_FILE" -vf "fps=1/60" -q:v 2 "$FRAMES_DIR/frame_%04d.jpg" -y >/dev/null 2>&1
        fi
        ;;
esac

FRAME_COUNT=$(find "$FRAMES_DIR" -name "*.jpg" | wc -l | tr -d ' ')
echo -e "${GREEN}✅ Extracted $FRAME_COUNT frames${NC}"

if [ $FRAME_COUNT -eq 0 ]; then
    echo -e "${YELLOW}⚠️ No frames extracted, falling back to audio-only analysis${NC}"
fi

# Get transcript (same as before)
echo -e "${BLUE}📥 Checking for subtitles...${NC}"
TRANSCRIPTION_METHOD=""
TRANSCRIPT_TEXT=""

# Try to get subtitles in various formats
if yt-dlp --write-auto-sub --write-sub --sub-format "vtt/srt/txt/best" --skip-download -o "%(id)s.%(ext)s" "$URL" 2>/dev/null; then
    SUB_FILE=$(find . -name "${VIDEO_ID}*" -type f | grep -E '\.(vtt|srt|txt)$' | head -1)
    
    if [ -n "$SUB_FILE" ] && [ -f "$SUB_FILE" ]; then
        echo -e "${GREEN}✅ Found subtitles, processing...${NC}"
        
        if [[ "$SUB_FILE" == *.vtt ]]; then
            TRANSCRIPT_TEXT=$(sed -n '/-->/,/^$/p' "$SUB_FILE" | \
                grep -v '\-\->' | \
                grep -v '^[[:space:]]*$' | \
                sed 's/<[^>]*>//g' | \
                awk '!seen[$0]++')
        elif [[ "$SUB_FILE" == *.srt ]]; then
            TRANSCRIPT_TEXT=$(grep -v '^[0-9]*$' "$SUB_FILE" | \
                grep -v '\-\->' | \
                grep -v '^[[:space:]]*$' | \
                sed 's/<[^>]*>//g' | \
                awk '!seen[$0]++')
        else
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

# Truncate transcript if too long
MAX_CHARS=80000  # Leave room for frame analysis
if [ $CHAR_COUNT -gt $MAX_CHARS ]; then
    echo -e "${YELLOW}⚠️ Transcript too long, truncating to fit with frame analysis...${NC}"
    TRANSCRIPT_TEXT=$(echo "$TRANSCRIPT_TEXT" | head -c $MAX_CHARS)
fi

# Analyze frames if available
FRAME_ANALYSIS=""
if [ $FRAME_COUNT -gt 0 ]; then
    echo -e "${CYAN}🔍 Analyzing visual content from frames...${NC}"
    
    # Limit frames to avoid token limits (max 10 frames for detailed analysis)
    MAX_FRAMES=10
    FRAME_FILES=($(find "$FRAMES_DIR" -name "*.jpg" | sort | head -$MAX_FRAMES))
    
    for i in "${!FRAME_FILES[@]}"; do
        FRAME_FILE="${FRAME_FILES[$i]}"
        FRAME_NUM=$((i + 1))
        
        echo -e "${CYAN}   Analyzing frame $FRAME_NUM/$MAX_FRAMES...${NC}"
        
        if [ "$PROVIDER" = "claude" ]; then
            # For Claude, we'll create a prompt that includes the frame
            FRAME_PROMPT="Analyze this video frame and describe:
1. What technical concepts are shown visually
2. Any code, diagrams, or UI elements visible
3. Key visual information for implementation
4. How this relates to the overall tutorial

Frame $FRAME_NUM of $MAX_FRAMES from: $VIDEO_TITLE"
            
            # Claude Code CLI can handle images directly
            if FRAME_RESULT=$(claude -p "$FRAME_PROMPT" --image "$FRAME_FILE" 2>/dev/null); then
                FRAME_ANALYSIS="$FRAME_ANALYSIS

## 🖼️ Frame $FRAME_NUM Analysis
$FRAME_RESULT"
            fi
            
        elif [ "$PROVIDER" = "gemini" ]; then
            # For Gemini, encode image to base64
            FRAME_B64=$(base64 -i "$FRAME_FILE" | tr -d '\n')
            
            FRAME_PROMPT="Analyze this video frame and describe:
1. What technical concepts are shown visually
2. Any code, diagrams, or UI elements visible  
3. Key visual information for implementation
4. How this relates to the overall tutorial

Frame $FRAME_NUM of $MAX_FRAMES from: $VIDEO_TITLE"
            
            # Gemini API call with image
            JSON_PAYLOAD=$(cat <<EOF
{
  "contents": [{
    "parts": [
      {"text": "$FRAME_PROMPT"},
      {
        "inline_data": {
          "mime_type": "image/jpeg",
          "data": "$FRAME_B64"
        }
      }
    ]
  }],
  "generationConfig": {
    "temperature": 0.3,
    "maxOutputTokens": 1024,
    "topP": 0.95,
    "topK": 40
  }
}
EOF
)
            
            GEMINI_ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent"
            
            if HTTP_CODE=$(curl -s -w "%{http_code}" -o "$TEMP_DIR/frame_response.json" \
                -H "Content-Type: application/json" \
                -H "x-goog-api-key: $GEMINI_API_KEY" \
                -X POST \
                -d "$JSON_PAYLOAD" \
                "$GEMINI_ENDPOINT") && [ "$HTTP_CODE" = "200" ]; then
                
                FRAME_RESULT=$(jq -r '.candidates[0].content.parts[0].text // empty' "$TEMP_DIR/frame_response.json" 2>/dev/null)
                if [ -n "$FRAME_RESULT" ]; then
                    FRAME_ANALYSIS="$FRAME_ANALYSIS

## 🖼️ Frame $FRAME_NUM Analysis
$FRAME_RESULT"
                fi
            fi
        fi
        
        # Limit processing to avoid overwhelming the final prompt
        if [ $FRAME_NUM -ge $MAX_FRAMES ]; then
            break
        fi
    done
    
    echo -e "${GREEN}✅ Completed visual analysis of $FRAME_NUM frames${NC}"
fi

# Create the comprehensive multimodal implementation guide prompt
IMPLEMENTATION_PROMPT="You are an expert technical instructor and implementation specialist. Analyze this YouTube video using BOTH the audio transcript AND visual frame analysis to create the most comprehensive step-by-step implementation guide possible.

Video Information:
- Title: $VIDEO_TITLE
- Channel: $VIDEO_CHANNEL
- Duration: $DURATION_STR
- URL: $URL
- Frames Analyzed: $FRAME_COUNT
- Analysis Method: Audio transcript + Visual frame analysis

Please create a detailed implementation guide with the following structure:

# 📋 Multimodal Implementation Guide: $VIDEO_TITLE

## 🎯 Overview
- Brief summary of what will be implemented (from both audio and visual analysis)
- Expected outcome and benefits
- Time estimate for completion
- Skill level required

## 📦 Prerequisites
- Required software, tools, and dependencies (from transcript and visual elements)
- System requirements
- Account setups needed
- Background knowledge required

## 🛠️ Step-by-Step Implementation

Create numbered steps combining insights from BOTH audio and visual content:
- Clear, actionable instructions
- Code examples from what was shown on screen
- Configuration details mentioned in audio or shown visually
- Expected outputs at each step
- Validation/testing instructions

## 💻 Code Examples & Visual Elements
- Complete, working code snippets (from screen captures and audio)
- File structures and organization shown in video
- UI/UX elements and design patterns
- Configuration files and settings
- Command-line instructions and terminal outputs

## 🖼️ Visual Implementation Notes
- Key screenshots or diagrams to recreate
- UI components and layouts shown
- Visual debugging techniques demonstrated
- Design patterns and architectural diagrams

## ✅ Implementation Checklist
- [ ] Checkbox list of all major tasks (audio + visual)
- [ ] Verification steps for each component
- [ ] Testing procedures shown in video
- [ ] Quality checks and validation

## 🔧 Troubleshooting
- Common issues mentioned in audio
- Error messages shown on screen
- Debugging techniques demonstrated
- Alternative approaches discussed

## 🚀 Next Steps & Enhancements
- Improvements suggested in video
- Advanced features shown or mentioned
- Related tutorials or resources referenced
- Best practices for production deployment

## 📚 Additional Resources
- Links mentioned in video or shown on screen
- Documentation references from visual content
- Tools and libraries used
- Community resources mentioned

## 🎥 Frame Analysis Summary
$FRAME_ANALYSIS

## 🏷️ Tags
- Technology stack identified from video and audio
- Implementation complexity level
- Categories and domains covered

---

**Instructions for Analysis:**
1. Combine insights from both transcript and visual frame analysis
2. Extract ALL technical concepts, tools, frameworks from both audio and visual content
3. Include specific code examples shown on screen, not just mentioned in audio
4. Reference visual elements like UI designs, diagrams, and screen layouts
5. Create implementation steps that account for both what was said and what was shown
6. Include visual debugging and troubleshooting techniques demonstrated
7. Make the guide comprehensive enough to implement without watching the video
8. Focus on practical, actionable steps that combine audio instructions with visual examples
9. Include validation steps that test both functional and visual aspects
10. Add time estimates considering both development and visual design work

Audio Transcript:
$TRANSCRIPT_TEXT"

# Provider-specific processing for multimodal analysis
if [ "$PROVIDER" = "claude" ]; then
    echo -e "${PURPLE}🤖 Generating multimodal implementation guide with Claude Code CLI...${NC}"
    
    # Create frame attachments for Claude (if frames exist)
    CLAUDE_ARGS=()
    if [ $FRAME_COUNT -gt 0 ] && [ $FRAME_COUNT -le 5 ]; then
        # For Claude, attach up to 5 frames directly
        for frame in $(find "$FRAMES_DIR" -name "*.jpg" | head -5); do
            CLAUDE_ARGS+=(--image "$frame")
        done
    fi
    
    # Call Claude Code CLI with retries
    MAX_RETRIES=3
    RETRY_COUNT=0
    SUCCESS=false
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$SUCCESS" = false ]; do
        if [ $RETRY_COUNT -gt 0 ]; then
            echo -e "${YELLOW}🔄 Retry attempt $RETRY_COUNT...${NC}"
            sleep 3
        fi
        
        # Call Claude Code CLI with image attachments
        if GUIDE_CONTENT=$(claude -p "$IMPLEMENTATION_PROMPT" "${CLAUDE_ARGS[@]}" 2>"$TEMP_DIR/claude_error.log"); then
            if [ -n "$GUIDE_CONTENT" ]; then
                SUCCESS=true
                echo -e "${GREEN}✅ Multimodal analysis completed successfully${NC}"
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

elif [ "$PROVIDER" = "gemini" ]; then
    echo -e "${PURPLE}🤖 Generating multimodal implementation guide with Gemini Pro 2.5...${NC}"
    
    # For Gemini, we'll include frames in the main request
    MODEL="gemini-2.0-flash-exp"
    GEMINI_ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent"
    
    # Prepare multimodal content for Gemini
    CONTENT_PARTS='[{"text": "'"$(echo "$IMPLEMENTATION_PROMPT" | sed 's/"/\\"/g' | tr '\n' ' ')"'"}]'
    
    # Add up to 5 frames to the content
    if [ $FRAME_COUNT -gt 0 ]; then
        FRAME_PARTS=""
        FRAME_COUNTER=0
        for frame in $(find "$FRAMES_DIR" -name "*.jpg" | head -5); do
            FRAME_B64=$(base64 -i "$frame" | tr -d '\n')
            if [ $FRAME_COUNTER -eq 0 ]; then
                FRAME_PARTS="{\"inline_data\": {\"mime_type\": \"image/jpeg\", \"data\": \"$FRAME_B64\"}}"
            else
                FRAME_PARTS="$FRAME_PARTS, {\"inline_data\": {\"mime_type\": \"image/jpeg\", \"data\": \"$FRAME_B64\"}}"
            fi
            FRAME_COUNTER=$((FRAME_COUNTER + 1))
        done
        
        # Combine text and image parts
        CONTENT_PARTS="[{\"text\": \"$(echo "$IMPLEMENTATION_PROMPT" | sed 's/"/\\"/g' | tr '\n' ' ')\"}, $FRAME_PARTS]"
    fi
    
    # Call Gemini API with retries
    MAX_RETRIES=3
    RETRY_COUNT=0
    SUCCESS=false
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$SUCCESS" = false ]; do
        if [ $RETRY_COUNT -gt 0 ]; then
            echo -e "${YELLOW}🔄 Retry attempt $RETRY_COUNT...${NC}"
            sleep 3
        fi
        
        # Create JSON payload with multimodal content
        JSON_PAYLOAD=$(cat <<EOF
{
  "contents": [{
    "parts": $CONTENT_PARTS
  }],
  "generationConfig": {
    "temperature": 0.3,
    "maxOutputTokens": 8192,
    "topP": 0.95,
    "topK": 40
  }
}
EOF
)
        
        # Make API call
        HTTP_CODE=$(curl -s -w "%{http_code}" -o "$TEMP_RESPONSE" \
            -H "Content-Type: application/json" \
            -H "x-goog-api-key: $GEMINI_API_KEY" \
            -X POST \
            -d "$JSON_PAYLOAD" \
            "$GEMINI_ENDPOINT")
        
        if [ "$HTTP_CODE" = "200" ]; then
            if [ -s "$TEMP_RESPONSE" ]; then
                ERROR_MSG=$(jq -r '.error.message // empty' "$TEMP_RESPONSE" 2>/dev/null)
                
                if [ -z "$ERROR_MSG" ]; then
                    GUIDE_CONTENT=$(jq -r '.candidates[0].content.parts[0].text // empty' "$TEMP_RESPONSE" 2>/dev/null)
                    
                    if [ -n "$GUIDE_CONTENT" ]; then
                        SUCCESS=true
                        echo -e "${GREEN}✅ Multimodal analysis completed successfully${NC}"
                    else
                        echo -e "${YELLOW}⚠️ Empty response from Gemini API${NC}"
                    fi
                else
                    echo -e "${YELLOW}⚠️ API Error: $ERROR_MSG${NC}"
                    if [[ "$ERROR_MSG" == *"quota"* ]] || [[ "$ERROR_MSG" == *"rate"* ]]; then
                        echo -e "${YELLOW}⏳ Rate limited, waiting 10 seconds...${NC}"
                        sleep 10
                    fi
                fi
            fi
        else
            echo -e "${YELLOW}⚠️ HTTP Error: $HTTP_CODE${NC}"
            if [ "$HTTP_CODE" = "429" ]; then
                echo -e "${YELLOW}⏳ Rate limited, waiting 10 seconds...${NC}"
                sleep 10
            fi
        fi
        
        RETRY_COUNT=$((RETRY_COUNT + 1))
    done
fi

# Create output based on success/failure
if [ "$SUCCESS" = false ]; then
    echo -e "${RED}❌ Failed to generate implementation guide after $MAX_RETRIES attempts${NC}"
    echo -e "${YELLOW}Creating template with transcript and frame references...${NC}"
    
    # Create basic template with available content
    cat > "$GUIDE_FILE" << EOF
# 📋 Multimodal Implementation Guide: $VIDEO_TITLE

**Video Information:**
- **Title:** $VIDEO_TITLE  
- **Channel:** $VIDEO_CHANNEL  
- **Duration:** $DURATION_STR  
- **URL:** [$URL]($URL)  
- **Generated:** $(date '+%Y-%m-%d %H:%M:%S')  
- **AI Provider:** $([ "$PROVIDER" = "claude" ] && echo "Claude Code CLI" || echo "Google Gemini Pro 2.5")
- **Frames Extracted:** $FRAME_COUNT frames
- **Sampling Method:** $SAMPLING
- **Word Count:** $WORD_COUNT words

---

## ⚠️ Guide Generation Failed

The AI analysis failed after multiple attempts. Use the transcript and frame references below for manual analysis.

## 🎯 Manual Implementation Steps

1. **Review transcript** for spoken instructions and concepts
2. **Examine frames** in the frames directory for visual elements
3. **Identify technical components** from both audio and visual content
4. **Extract code examples** shown on screen
5. **Note UI/UX patterns** and design elements
6. **Create step-by-step instructions** combining both sources
7. **Add troubleshooting** for issues mentioned or shown
8. **Test implementation** to verify completeness

## 📁 Frame Directory
Frames saved to: $FRAMES_DIR (temporary - copy if needed)
Frame count: $FRAME_COUNT
Sampling: $SAMPLING

## 📝 Video Transcript
$TRANSCRIPT_TEXT

$FRAME_ANALYSIS

---

*Manual analysis required. Combine transcript and visual frames for complete implementation guide.*
EOF
else
    # Create complete guide with AI analysis
    cat > "$GUIDE_FILE" << EOF
# 📋 Multimodal Implementation Guide: $VIDEO_TITLE

**Video Information:**
- **Title:** $VIDEO_TITLE  
- **Channel:** $VIDEO_CHANNEL  
- **Duration:** $DURATION_STR  
- **URL:** [$URL]($URL)  
- **Generated:** $(date '+%Y-%m-%d %H:%M:%S')  
- **AI Provider:** $([ "$PROVIDER" = "claude" ] && echo "Claude Code CLI" || echo "Google Gemini Pro 2.5")
- **Analysis Method:** Multimodal (Audio + Visual)
- **Frames Analyzed:** $FRAME_COUNT frames ($SAMPLING sampling)
- **Word Count:** $WORD_COUNT words

---

$GUIDE_CONTENT

---

## 📝 Original Content

<details>
<summary>Click to expand full transcript</summary>

$TRANSCRIPT_TEXT

</details>

$FRAME_ANALYSIS

---

*This comprehensive implementation guide was generated using $([ "$PROVIDER" = "claude" ] && echo "Claude Code CLI" || echo "Google Gemini Pro 2.5") with multimodal analysis of both audio and visual content.*
EOF
fi

# Verify and open the output file
if [ -f "$GUIDE_FILE" ]; then
    FILE_SIZE=$(wc -c < "$GUIDE_FILE" | tr -d ' ')
    LINE_COUNT=$(wc -l < "$GUIDE_FILE" | tr -d ' ')
    
    echo
    echo -e "${GREEN}🎉 Multimodal implementation guide created successfully!${NC}"
    echo -e "${BLUE}📍 Location: $GUIDE_FILE${NC}"
    echo -e "${BLUE}📊 Stats: $LINE_COUNT lines, $FILE_SIZE bytes${NC}"
    echo -e "${CYAN}🎥 Analysis: Audio transcript + $FRAME_COUNT visual frames${NC}"
    
    # Count sections in the guide
    SECTION_COUNT=$(grep -c '^##' "$GUIDE_FILE" 2>/dev/null || echo "0")
    STEP_COUNT=$(grep -c '^[0-9]\+\.' "$GUIDE_FILE" 2>/dev/null || echo "0")
    CHECKLIST_COUNT=$(grep -c '^\- \[ \]' "$GUIDE_FILE" 2>/dev/null || echo "0")
    
    echo -e "${PURPLE}📈 Guide Structure:${NC}"
    echo -e "${PURPLE}   • Sections: $SECTION_COUNT${NC}"
    echo -e "${PURPLE}   • Implementation Steps: $STEP_COUNT${NC}"
    echo -e "${PURPLE}   • Checklist Items: $CHECKLIST_COUNT${NC}"
    echo -e "${PURPLE}   • Provider: $([ "$PROVIDER" = "claude" ] && echo "Claude Code CLI" || echo "Gemini Pro 2.5")${NC}"
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
    echo -e "${GREEN}✅ Done! Comprehensive multimodal implementation guide created.${NC}"
    echo -e "${CYAN}💡 This guide combines audio instructions with visual analysis for complete implementation.${NC}"
else
    echo -e "${RED}❌ Error: Failed to create output file${NC}"
    exit 1
fi