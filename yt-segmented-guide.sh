#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title YouTube Segmented Implementation Guide
# @raycast.mode fullOutput
# @raycast.packageName Media Tools

# Optional parameters:
# @raycast.icon 🧩
# @raycast.description Create detailed implementation guide by analyzing video in small segments
# @raycast.argument1 { "type": "text", "placeholder": "YouTube URL" }
# @raycast.argument2 { "type": "dropdown", "placeholder": "AI Provider", "data": [
#   {"title": "Claude Code (Default)", "value": "claude"},
#   {"title": "Gemini Pro 2.5", "value": "gemini"}
# ], "optional": true }
# @raycast.argument3 { "type": "dropdown", "placeholder": "Segment Length", "data": [
#   {"title": "2 minutes (Detailed)", "value": "2"},
#   {"title": "3 minutes (Balanced)", "value": "3"},
#   {"title": "5 minutes (Faster)", "value": "5"}
# ], "optional": true }

URL="$1"
PROVIDER="${2:-claude}"
SEGMENT_MINUTES="${3:-3}"  # Default 3-minute segments

# Validate segment minutes is a number
if ! [[ "$SEGMENT_MINUTES" =~ ^[0-9]+$ ]] || [ "$SEGMENT_MINUTES" -eq 0 ]; then
    echo -e "${YELLOW}⚠️ Invalid segment minutes '$SEGMENT_MINUTES', using default 3 minutes${NC}"
    SEGMENT_MINUTES=3
fi
TEMP_DIR="/tmp/yt-segmented-$$"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
# GUIDE_FILE will be set after getting video info
SEGMENTS_DIR="$TEMP_DIR/segments"
FRAMES_DIR="$TEMP_DIR/frames"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Token and cost tracking
TOTAL_INPUT_TOKENS=0
TOTAL_OUTPUT_TOKENS=0
TOTAL_ESTIMATED_COST=0
START_TIME=$(date +%s)

# Token estimation function (rough approximation: 1 token ≈ 4 characters)
estimate_tokens() {
    local text="$1"
    local char_count=$(echo "$text" | wc -c | tr -d ' ')
    echo $((char_count / 4))
}

# Cost estimation function (Claude Opus pricing: $15 input, $75 output per 1M tokens)
estimate_cost() {
    local input_tokens=$1
    local output_tokens=$2
    # Convert to dollars (input: $15/1M, output: $75/1M tokens)
    local input_cost=$(echo "scale=6; $input_tokens * 15 / 1000000" | bc -l 2>/dev/null || echo "0")
    local output_cost=$(echo "scale=6; $output_tokens * 75 / 1000000" | bc -l 2>/dev/null || echo "0")
    local total_cost=$(echo "scale=6; $input_cost + $output_cost" | bc -l 2>/dev/null || echo "0")
    echo "$total_cost"
}

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
    if [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
        export CLAUDE_CODE_OAUTH_TOKEN="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"
    fi
    if [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
        echo -e "${RED}⌛ Error: CLAUDE_CODE_OAUTH_TOKEN environment variable is not set${NC}"
        exit 1
    fi
elif [ "$PROVIDER" = "gemini" ]; then
    if [ -z "$GEMINI_API_KEY" ]; then
        echo -e "${RED}⌛ Error: GEMINI_API_KEY environment variable is not set${NC}"
        echo -e "${YELLOW}Get key at: https://aistudio.google.com/apikey${NC}"
        exit 1
    fi
fi

# Check dependencies
REQUIRED_CMDS="yt-dlp ffmpeg"
if [ "$PROVIDER" = "claude" ]; then
    REQUIRED_CMDS="$REQUIRED_CMDS claude"
else
    REQUIRED_CMDS="$REQUIRED_CMDS curl jq base64"
fi

for cmd in $REQUIRED_CMDS; do
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${RED}⌛ Error: $cmd is not installed${NC}"
        case "$cmd" in
            "yt-dlp") echo -e "${YELLOW}Install: brew install yt-dlp${NC}" ;;
            "ffmpeg") echo -e "${YELLOW}Install: brew install ffmpeg${NC}" ;;
            "claude") echo -e "${YELLOW}Install: curl -fsSL https://claude.ai/install.sh | sh${NC}" ;;
            *) echo -e "${YELLOW}Install: brew install $cmd${NC}" ;;
        esac
        exit 1
    fi
done

mkdir -p "$TEMP_DIR" "$SEGMENTS_DIR" "$FRAMES_DIR"
cd "$TEMP_DIR"

echo -e "${BLUE}🧩 YouTube Segmented Implementation Guide Generator${NC}"
echo -e "${YELLOW}URL: $URL${NC}"
echo -e "${YELLOW}AI Provider: $([ "$PROVIDER" = "claude" ] && echo "Claude Code CLI" || echo "Google Gemini Pro 2.5")${NC}"
echo -e "${YELLOW}Segment Length: $SEGMENT_MINUTES minutes${NC}"
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
VIDEO_UPLOAD_DATE=$(echo "$VIDEO_INFO" | jq -r '.upload_date // "unknown"')

# Create filename with video title, upload date, and channel
SAFE_TITLE=$(echo "$VIDEO_TITLE" | sed 's/[^a-zA-Z0-9 ]//g' | sed 's/ /_/g' | cut -c1-50)
SAFE_CHANNEL=$(echo "$VIDEO_CHANNEL" | sed 's/[^a-zA-Z0-9]//g' | cut -c1-20)
FORMATTED_DATE=$(echo "$VIDEO_UPLOAD_DATE" | sed 's/\(.\{4\}\)\(.\{2\}\)\(.\{2\}\)/\1-\2-\3/' 2>/dev/null || echo "unknown")
GUIDE_FILE="$HOME/Downloads/${SAFE_TITLE}_${FORMATTED_DATE}_${SAFE_CHANNEL}_segmented-guide.md"

# Convert duration
HOURS=$((VIDEO_DURATION / 3600))
MINUTES=$(((VIDEO_DURATION % 3600) / 60))
SECONDS=$((VIDEO_DURATION % 60))
if [ $HOURS -gt 0 ]; then
    DURATION_STR="${HOURS}h ${MINUTES}m ${SECONDS}s"
else
    DURATION_STR="${MINUTES}m ${SECONDS}s"
fi

# Calculate number of segments
SEGMENT_SECONDS=$((SEGMENT_MINUTES * 60))
TOTAL_SEGMENTS=$(((VIDEO_DURATION + SEGMENT_SECONDS - 1) / SEGMENT_SECONDS))

echo -e "${GREEN}✅ Title: $VIDEO_TITLE${NC}"
echo -e "${GREEN}✅ Channel: $VIDEO_CHANNEL${NC}"
echo -e "${GREEN}✅ Duration: $DURATION_STR${NC}"
echo -e "${GREEN}✅ Segments: $TOTAL_SEGMENTS × ${SEGMENT_MINUTES}min${NC}"
echo

# Download video
echo -e "${CYAN}🎬 Downloading video...${NC}"
if ! yt-dlp -f "best[height<=720]/best" -o "video.%(ext)s" "$URL" 2>/dev/null; then
    echo -e "${RED}⌛ Error: Could not download video${NC}"
    exit 1
fi

VIDEO_FILE=$(find . -name "video.*" -type f | head -1)
echo -e "${GREEN}✅ Video downloaded: $(basename "$VIDEO_FILE")${NC}"

# Get full transcript
echo -e "${BLUE}📥 Getting full transcript...${NC}"
TRANSCRIPT_TEXT=""

if yt-dlp --write-auto-sub --write-sub --sub-format "vtt/srt/txt/best" --skip-download -o "%(id)s.%(ext)s" "$URL" 2>/dev/null; then
    SUB_FILE=$(find . -name "${VIDEO_ID}*" -type f | grep -E '\.(vtt|srt|txt)$' | head -1)
    
    if [ -n "$SUB_FILE" ] && [ -f "$SUB_FILE" ]; then
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
    fi
fi

if [ -z "$TRANSCRIPT_TEXT" ]; then
    echo -e "${RED}⌛ Error: Could not extract transcript${NC}"
    exit 1
fi

TOTAL_WORDS=$(echo "$TRANSCRIPT_TEXT" | wc -w | tr -d ' ')
echo -e "${GREEN}✅ Full transcript: $TOTAL_WORDS words${NC}"

# Create segments and analyze each
echo -e "${CYAN}🔪 Creating and analyzing segments...${NC}"

# Initialize guide with header
cat > "$GUIDE_FILE" << EOF
# 📋 Segmented Implementation Guide: $VIDEO_TITLE

**Video Information:**
- **Title:** $VIDEO_TITLE  
- **Channel:** $VIDEO_CHANNEL  
- **Duration:** $DURATION_STR  
- **URL:** [$URL]($URL)  
- **Generated:** $(date '+%Y-%m-%d %H:%M:%S')  
- **AI Provider:** $([ "$PROVIDER" = "claude" ] && echo "Claude Code CLI" || echo "Google Gemini Pro 2.5")
- **Analysis Method:** Segmented Analysis ($SEGMENT_MINUTES min segments)
- **Total Segments:** $TOTAL_SEGMENTS
- **Word Count:** $TOTAL_WORDS words

---

EOF

# Split transcript into segments with overlap
WORDS_PER_SEGMENT=$((TOTAL_WORDS / TOTAL_SEGMENTS))
OVERLAP_WORDS=$((WORDS_PER_SEGMENT / 10))  # 10% overlap

SEGMENT_ANALYSES=""
COMBINED_STEPS=""

for ((seg=1; seg<=TOTAL_SEGMENTS; seg++)); do
    START_TIME=$(((seg - 1) * SEGMENT_SECONDS))
    END_TIME=$((seg * SEGMENT_SECONDS))
    
    # Don't go beyond video duration
    if [ $END_TIME -gt $VIDEO_DURATION ]; then
        END_TIME=$VIDEO_DURATION
    fi
    
    # Format timestamps
    START_MIN=$((START_TIME / 60))
    START_SEC=$((START_TIME % 60))
    END_MIN=$((END_TIME / 60))
    END_SEC=$((END_TIME % 60))
    
    echo -e "${CYAN}   📍 Segment $seg/$TOTAL_SEGMENTS: ${START_MIN}:$(printf '%02d' $START_SEC) - ${END_MIN}:$(printf '%02d' $END_SEC)${NC}"
    
    # Extract video segment
    SEGMENT_FILE="$SEGMENTS_DIR/segment_$seg.mp4"
    ffmpeg -i "$VIDEO_FILE" -ss $START_TIME -t $SEGMENT_SECONDS -c copy "$SEGMENT_FILE" -y >/dev/null 2>&1
    
    # Extract 2-3 frames from this segment
    SEGMENT_FRAMES_DIR="$FRAMES_DIR/segment_$seg"
    mkdir -p "$SEGMENT_FRAMES_DIR"
    ffmpeg -i "$SEGMENT_FILE" -vf "fps=1/$((SEGMENT_SECONDS/3))" -q:v 2 "$SEGMENT_FRAMES_DIR/frame_%02d.jpg" -y >/dev/null 2>&1
    
    # Get transcript segment (fixed approach using word arrays)
    WORDS_TOTAL=$(echo "$TRANSCRIPT_TEXT" | wc -w | tr -d ' ')
    WORDS_PER_SEGMENT=$((WORDS_TOTAL / TOTAL_SEGMENTS))
    OVERLAP_WORDS=$((WORDS_PER_SEGMENT / 10))  # 10% overlap
    
    START_WORD=$(((seg - 1) * WORDS_PER_SEGMENT - OVERLAP_WORDS))
    if [ $START_WORD -lt 1 ]; then START_WORD=1; fi  # sed uses 1-based indexing
    
    END_WORD=$((seg * WORDS_PER_SEGMENT + OVERLAP_WORDS))
    if [ $END_WORD -gt $WORDS_TOTAL ]; then END_WORD=$WORDS_TOTAL; fi
    
    # Extract segment using word-based indexing (more reliable)
    SEGMENT_TRANSCRIPT=$(echo "$TRANSCRIPT_TEXT" | tr ' ' '\n' | sed -n "${START_WORD},${END_WORD}p" | tr '\n' ' ' | sed 's/^ *//; s/ *$//')
    
    SEGMENT_WORD_COUNT=$(echo "$SEGMENT_TRANSCRIPT" | wc -w | tr -d ' ')
    
    # Debug: Show segment info
    echo -e "${CYAN}      📊 Segment words: $START_WORD-$END_WORD, Total: $SEGMENT_WORD_COUNT${NC}"
    
    # Create simplified segment prompt
    SEGMENT_PROMPT="Analyze this video segment and create detailed implementation steps:

Video: $VIDEO_TITLE
Segment: $seg/$TOTAL_SEGMENTS (${START_MIN}:$(printf '%02d' $START_SEC) - ${END_MIN}:$(printf '%02d' $END_SEC))

Create implementation steps with:
1. What's covered in this segment
2. Specific implementation steps with code examples
3. Configuration details
4. Checklist of tasks

Transcript:
$SEGMENT_TRANSCRIPT"

    # Analyze segment with chosen provider
    echo -e "${PURPLE}      🤖 Analyzing with $([ "$PROVIDER" = "claude" ] && echo "Claude" || echo "Gemini")...${NC}"
    
    if [ "$PROVIDER" = "claude" ]; then
        # Claude analysis - text only for now (Claude CLI doesn't support image attachments easily)
        # Add frame information to the prompt instead
        FRAME_INFO=""
        FRAME_LIST=$(find "$SEGMENT_FRAMES_DIR" -name "*.jpg" 2>/dev/null | head -3)
        if [ -n "$FRAME_LIST" ]; then
            FRAME_COUNT_SEG=$(echo "$FRAME_LIST" | wc -l | tr -d ' ')
            FRAME_INFO="

Note: $FRAME_COUNT_SEG frames were extracted from this segment and saved for manual review if needed."
        fi
        
        ENHANCED_PROMPT="$SEGMENT_PROMPT$FRAME_INFO"
        
        # Debug: Show prompt length
        PROMPT_LENGTH=$(echo "$ENHANCED_PROMPT" | wc -c | tr -d ' ')
        echo -e "${CYAN}      📏 Prompt: $PROMPT_LENGTH chars, Transcript: $SEGMENT_WORD_COUNT words${NC}"
        
        if SEGMENT_ANALYSIS=$(claude -p "$ENHANCED_PROMPT" 2>"$TEMP_DIR/claude_error_$seg.log"); then
            if [ -n "$SEGMENT_ANALYSIS" ]; then
                ANALYSIS_LENGTH=$(echo "$SEGMENT_ANALYSIS" | wc -c | tr -d ' ')
                
                # Track tokens and costs
                SEGMENT_INPUT_TOKENS=$(estimate_tokens "$ENHANCED_PROMPT")
                SEGMENT_OUTPUT_TOKENS=$(estimate_tokens "$SEGMENT_ANALYSIS")
                TOTAL_INPUT_TOKENS=$((TOTAL_INPUT_TOKENS + SEGMENT_INPUT_TOKENS))
                TOTAL_OUTPUT_TOKENS=$((TOTAL_OUTPUT_TOKENS + SEGMENT_OUTPUT_TOKENS))
                SEGMENT_COST=$(estimate_cost $SEGMENT_INPUT_TOKENS $SEGMENT_OUTPUT_TOKENS)
                TOTAL_ESTIMATED_COST=$(echo "scale=6; $TOTAL_ESTIMATED_COST + $SEGMENT_COST" | bc -l 2>/dev/null || echo "$TOTAL_ESTIMATED_COST")
                
                echo -e "${GREEN}      ✅ Segment $seg analyzed ($ANALYSIS_LENGTH chars, ~$SEGMENT_INPUT_TOKENS→$SEGMENT_OUTPUT_TOKENS tokens, \$$(echo "$SEGMENT_COST" | cut -c1-7))${NC}"
            else
                echo -e "${YELLOW}      ⚠️ Segment $seg empty response${NC}"
                SEGMENT_ANALYSIS="## 🔧 Segment $seg Implementation (${START_MIN}:$(printf '%02d' $START_SEC) - ${END_MIN}:$(printf '%02d' $END_SEC))

**Empty response - trying shorter prompt**

Transcript excerpt:
$SEGMENT_TRANSCRIPT"
            fi
        else
            ERROR_MSG=$(cat "$TEMP_DIR/claude_error_$seg.log" 2>/dev/null || echo "Unknown error")
            echo -e "${YELLOW}      ⚠️ Segment $seg failed: $ERROR_MSG${NC}"
            
            # Try a much simpler prompt as fallback
            SIMPLE_PROMPT="Create implementation steps for this video segment:

$SEGMENT_TRANSCRIPT"
            
            echo -e "${CYAN}      🔄 Trying simplified prompt...${NC}"
            if SEGMENT_ANALYSIS=$(claude -p "$SIMPLE_PROMPT" 2>/dev/null); then
                if [ -n "$SEGMENT_ANALYSIS" ]; then
                    echo -e "${GREEN}      ✅ Segment $seg analyzed with simple prompt${NC}"
                    SEGMENT_ANALYSIS="## 🔧 Segment $seg Implementation (${START_MIN}:$(printf '%02d' $START_SEC) - ${END_MIN}:$(printf '%02d' $END_SEC))

$SEGMENT_ANALYSIS"
                else
                    SEGMENT_ANALYSIS="## 🔧 Segment $seg Implementation (${START_MIN}:$(printf '%02d' $START_SEC) - ${END_MIN}:$(printf '%02d' $END_SEC))

**Both detailed and simple prompts failed**

Transcript excerpt:
$SEGMENT_TRANSCRIPT"
                fi
            else
                SEGMENT_ANALYSIS="## 🔧 Segment $seg Implementation (${START_MIN}:$(printf '%02d' $START_SEC) - ${END_MIN}:$(printf '%02d' $END_SEC))

**Analysis failed: $ERROR_MSG**

Transcript excerpt:
$SEGMENT_TRANSCRIPT"
            fi
        fi
        
    elif [ "$PROVIDER" = "gemini" ]; then
        # Gemini analysis with image data
        FRAME_PARTS=""
        FRAME_COUNT_SEG=0
        for frame in $(find "$SEGMENT_FRAMES_DIR" -name "*.jpg" 2>/dev/null | head -3); do
            FRAME_B64=$(base64 -i "$frame" | tr -d '\n')
            if [ $FRAME_COUNT_SEG -eq 0 ]; then
                FRAME_PARTS="{\"inline_data\": {\"mime_type\": \"image/jpeg\", \"data\": \"$FRAME_B64\"}}"
            else
                FRAME_PARTS="$FRAME_PARTS, {\"inline_data\": {\"mime_type\": \"image/jpeg\", \"data\": \"$FRAME_B64\"}}"
            fi
            FRAME_COUNT_SEG=$((FRAME_COUNT_SEG + 1))
        done
        
        # Create content with text and images
        if [ -n "$FRAME_PARTS" ]; then
            CONTENT_PARTS="[{\"text\": \"$(echo "$SEGMENT_PROMPT" | sed 's/"/\\"/g' | tr '\n' ' ')\"}, $FRAME_PARTS]"
        else
            CONTENT_PARTS="[{\"text\": \"$(echo "$SEGMENT_PROMPT" | sed 's/"/\\"/g' | tr '\n' ' ')\"}]"
        fi
        
        JSON_PAYLOAD=$(cat <<EOF
{
  "contents": [{
    "parts": $CONTENT_PARTS
  }],
  "generationConfig": {
    "temperature": 0.3,
    "maxOutputTokens": 4096,
    "topP": 0.95,
    "topK": 40
  }
}
EOF
)
        
        if HTTP_CODE=$(curl -s -w "%{http_code}" -o "$TEMP_DIR/segment_response.json" \
            -H "Content-Type: application/json" \
            -H "x-goog-api-key: $GEMINI_API_KEY" \
            -X POST \
            -d "$JSON_PAYLOAD" \
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent") && [ "$HTTP_CODE" = "200" ]; then
            
            SEGMENT_ANALYSIS=$(jq -r '.candidates[0].content.parts[0].text // empty' "$TEMP_DIR/segment_response.json" 2>/dev/null)
            if [ -n "$SEGMENT_ANALYSIS" ]; then
                ANALYSIS_LENGTH=$(echo "$SEGMENT_ANALYSIS" | wc -c | tr -d ' ')
                
                # Track tokens and costs for Gemini (different pricing: $1.25 input, $5 output per 1M tokens)
                SEGMENT_INPUT_TOKENS=$(estimate_tokens "$SEGMENT_PROMPT")
                SEGMENT_OUTPUT_TOKENS=$(estimate_tokens "$SEGMENT_ANALYSIS")
                TOTAL_INPUT_TOKENS=$((TOTAL_INPUT_TOKENS + SEGMENT_INPUT_TOKENS))
                TOTAL_OUTPUT_TOKENS=$((TOTAL_OUTPUT_TOKENS + SEGMENT_OUTPUT_TOKENS))
                SEGMENT_COST=$(echo "scale=6; ($SEGMENT_INPUT_TOKENS * 1.25 + $SEGMENT_OUTPUT_TOKENS * 5) / 1000000" | bc -l 2>/dev/null || echo "0")
                TOTAL_ESTIMATED_COST=$(echo "scale=6; $TOTAL_ESTIMATED_COST + $SEGMENT_COST" | bc -l 2>/dev/null || echo "$TOTAL_ESTIMATED_COST")
                
                echo -e "${GREEN}      ✅ Segment $seg analyzed ($ANALYSIS_LENGTH chars, ~$SEGMENT_INPUT_TOKENS→$SEGMENT_OUTPUT_TOKENS tokens, \$$(echo "$SEGMENT_COST" | cut -c1-7))${NC}"
            else
                echo -e "${YELLOW}      ⚠️ Segment $seg analysis failed${NC}"
                SEGMENT_ANALYSIS="## 🔧 Segment $seg Implementation

**Analysis failed - manual review needed**
Transcript: $SEGMENT_TRANSCRIPT"
            fi
        else
            echo -e "${YELLOW}      ⚠️ Segment $seg API call failed${NC}"
            SEGMENT_ANALYSIS="## 🔧 Segment $seg Implementation

**API call failed - manual review needed**
Transcript: $SEGMENT_TRANSCRIPT"
        fi
    fi
    
    # Add segment analysis to guide
    echo "$SEGMENT_ANALYSIS" >> "$GUIDE_FILE"
    echo "" >> "$GUIDE_FILE"
    echo "---" >> "$GUIDE_FILE"
    echo "" >> "$GUIDE_FILE"
    
    # Extract implementation steps for combined summary
    SEGMENT_STEPS=$(echo "$SEGMENT_ANALYSIS" | grep -E '^[0-9]+\.|^\*\*Step|^- \[|^###.*Step' | head -10)
    COMBINED_STEPS="$COMBINED_STEPS

**Segment $seg (${START_MIN}:$(printf '%02d' $START_SEC)-${END_MIN}:$(printf '%02d' $END_SEC)):**
$SEGMENT_STEPS"
    
    # Small delay to be respectful to APIs
    sleep 1
done

echo -e "${GREEN}✅ All segments analyzed!${NC}"

# Generate final combined analysis
echo -e "${PURPLE}🔗 Creating combined implementation summary...${NC}"

FINAL_PROMPT="Based on the segmented analysis below, create a unified implementation guide that combines all segments into a coherent, step-by-step implementation.

Original Video: $VIDEO_TITLE by $VIDEO_CHANNEL ($DURATION_STR)

Create a final comprehensive guide with:

## 🎯 Complete Implementation Overview
- What the full system does
- End-to-end workflow
- Expected final result

## 📦 Complete Prerequisites  
- All dependencies from all segments
- System requirements
- Setup steps in proper order

## 🛠️ Unified Step-by-Step Implementation
- Combine steps from all segments into logical order
- Remove redundancy between segments
- Add transitions between major sections
- Include all code examples in proper sequence

## 💻 Complete Code Repository Structure
\`\`\`
project/
├── [all files and folders mentioned across segments]
└── [proper organization]
\`\`\`

## ✅ Master Implementation Checklist
- [ ] All tasks from all segments in proper order
- [ ] Integration steps between components
- [ ] End-to-end testing

## 🔧 Complete Troubleshooting Guide
- All issues mentioned across segments
- Integration problems between components
- Testing and validation

Segment Implementation Steps Summary:
$COMBINED_STEPS"

if [ "$PROVIDER" = "claude" ]; then
    if FINAL_ANALYSIS=$(claude -p "$FINAL_PROMPT" 2>/dev/null); then
        echo -e "${GREEN}✅ Final analysis complete${NC}"
    else
        FINAL_ANALYSIS="## ⚠️ Final Analysis Failed
Use the segment-by-segment implementation details above."
    fi
else
    # Gemini final analysis
    ESCAPED_FINAL=$(echo "$FINAL_PROMPT" | jq -Rs .)
    JSON_PAYLOAD=$(cat <<EOF
{
  "contents": [{
    "parts": [{"text": $ESCAPED_FINAL}]
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
    
    if HTTP_CODE=$(curl -s -w "%{http_code}" -o "$TEMP_DIR/final_response.json" \
        -H "Content-Type: application/json" \
        -H "x-goog-api-key: $GEMINI_API_KEY" \
        -X POST \
        -d "$JSON_PAYLOAD" \
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent") && [ "$HTTP_CODE" = "200" ]; then
        
        FINAL_ANALYSIS=$(jq -r '.candidates[0].content.parts[0].text // empty' "$TEMP_DIR/final_response.json" 2>/dev/null)
        if [ -n "$FINAL_ANALYSIS" ]; then
            echo -e "${GREEN}✅ Final analysis complete${NC}"
        else
            FINAL_ANALYSIS="## ⚠️ Final Analysis Failed
Use the segment-by-segment details above."
        fi
    else
        FINAL_ANALYSIS="## ⚠️ Final Analysis Failed  
Use the segment-by-segment details above."
    fi
fi

# Add final analysis to guide
cat >> "$GUIDE_FILE" << EOF

# 🎯 UNIFIED IMPLEMENTATION GUIDE

$FINAL_ANALYSIS

---

## 📝 Complete Transcript

<details>
<summary>Click to expand full transcript ($TOTAL_WORDS words)</summary>

$TRANSCRIPT_TEXT

</details>

---

## 💰 Generation Metrics

- **Total Tokens:** $(printf '%,d' $((TOTAL_INPUT_TOKENS + TOTAL_OUTPUT_TOKENS))) ($(printf '%,d' $TOTAL_INPUT_TOKENS) input + $(printf '%,d' $TOTAL_OUTPUT_TOKENS) output)
- **Estimated Cost:** \$$(echo "$TOTAL_ESTIMATED_COST" | cut -c1-7) ($([ "$PROVIDER" = "claude" ] && echo "Claude Opus" || echo "Gemini 2.0 Flash") pricing)
- **Processing Time:** ${DURATION_MIN}m ${DURATION_SEC}s
- **Efficiency:** \$$(echo "scale=4; $TOTAL_ESTIMATED_COST / ($DURATION / 60)" | bc -l 2>/dev/null || echo "0.0000")/min

---

*This segmented implementation guide was generated using $([ "$PROVIDER" = "claude" ] && echo "Claude Code CLI" || echo "Google Gemini Pro 2.5") with $TOTAL_SEGMENTS segments of $SEGMENT_MINUTES minutes each for detailed analysis.*
EOF

# Display results
if [ -f "$GUIDE_FILE" ]; then
    FILE_SIZE=$(wc -c < "$GUIDE_FILE" | tr -d ' ')
    LINE_COUNT=$(wc -l < "$GUIDE_FILE" | tr -d ' ')
    
    echo
    echo -e "${GREEN}🎉 Segmented implementation guide completed!${NC}"
    echo -e "${BLUE}📍 Location: $GUIDE_FILE${NC}"
    echo -e "${BLUE}📊 Stats: $LINE_COUNT lines, $FILE_SIZE bytes${NC}"
    echo -e "${CYAN}🧩 Analysis: $TOTAL_SEGMENTS segments × $SEGMENT_MINUTES min${NC}"
    
    SECTION_COUNT=$(grep -c '^##' "$GUIDE_FILE" 2>/dev/null || echo "0")
    STEP_COUNT=$(grep -c '^[0-9]\+\.' "$GUIDE_FILE" 2>/dev/null || echo "0")
    
    echo -e "${PURPLE}📈 Guide Structure:${NC}"
    echo -e "${PURPLE}   • Total Sections: $SECTION_COUNT${NC}"
    echo -e "${PURPLE}   • Implementation Steps: $STEP_COUNT${NC}"
    echo -e "${PURPLE}   • Segments Analyzed: $TOTAL_SEGMENTS${NC}"
    
    # Calculate session duration and display cost metrics
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    DURATION_MIN=$((DURATION / 60))
    DURATION_SEC=$((DURATION % 60))
    
    echo
    echo -e "${CYAN}💰 Token & Cost Analysis:${NC}"
    echo -e "${CYAN}   • Input Tokens: $(printf '%,d' $TOTAL_INPUT_TOKENS)${NC}"
    echo -e "${CYAN}   • Output Tokens: $(printf '%,d' $TOTAL_OUTPUT_TOKENS)${NC}"
    echo -e "${CYAN}   • Total Tokens: $(printf '%,d' $((TOTAL_INPUT_TOKENS + TOTAL_OUTPUT_TOKENS)))${NC}"
    echo -e "${CYAN}   • Estimated Cost: \$$(echo "$TOTAL_ESTIMATED_COST" | cut -c1-7) ($([ "$PROVIDER" = "claude" ] && echo "Claude Opus" || echo "Gemini 2.0 Flash") rates)${NC}"
    echo -e "${CYAN}   • Processing Time: ${DURATION_MIN}m ${DURATION_SEC}s${NC}"
    echo -e "${CYAN}   • Cost per Minute: \$$(echo "scale=4; $TOTAL_ESTIMATED_COST / ($DURATION / 60)" | bc -l 2>/dev/null || echo "0.0000")/min${NC}"
    echo
    
    # Open file
    if command -v typora &> /dev/null; then
        echo -e "${BLUE}📖 Opening in Typora...${NC}"
        typora "$GUIDE_FILE" &
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo -e "${BLUE}📖 Opening file...${NC}"
        open "$GUIDE_FILE"
    fi
    
    echo -e "${GREEN}✅ Done! Comprehensive segmented implementation guide created.${NC}"
    echo -e "${CYAN}💡 Each segment provides detailed steps - combine for complete implementation.${NC}"
else
    echo -e "${RED}❌ Error: Failed to create guide file${NC}"
    exit 1
fi