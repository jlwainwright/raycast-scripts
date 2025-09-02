#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title MCP Health Check
# @raycast.mode compact
# @raycast.packageName MCP Tools

# Optional parameters:
# @raycast.icon 🔧
# @raycast.description Run MCP server health check and open report
# @raycast.author Jacques Wainwright
# @raycast.authorURL https://github.com/yourusername

# Documentation:
# @raycast.argument1 { "type": "dropdown", "placeholder": "Report Format", "data": [{"title": "Markdown", "value": "markdown"}, {"title": "HTML", "value": "html"}, {"title": "JSON", "value": "json"}], "optional": true }

# Script configuration
HEALTH_CHECKER="/Users/jacques/DevFolder/HouseKeeping/mcp_health_checker.sh"
REPORTS_DIR="/Users/jacques/DevFolder/HouseKeeping/reports"
DESKTOP_DIR="/Users/jacques/Desktop"

# Get format from argument or default to markdown
FORMAT="${1:-markdown}"

# Function to display notification
notify() {
    osascript -e "display notification \"$1\" with title \"MCP Health Check\""
}

# Function to copy file to desktop
copy_to_desktop() {
    local source_file="$1"
    local filename=$(basename "$source_file")
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local desktop_file="${DESKTOP_DIR}/mcp_health_report_${timestamp}.${filename##*.}"
    
    cp "$source_file" "$desktop_file"
    echo "$desktop_file"
}

# Check if health checker exists
if [[ ! -f "$HEALTH_CHECKER" ]]; then
    echo "❌ Health checker not found at: $HEALTH_CHECKER"
    notify "Health checker script not found"
    exit 1
fi

# Check if health checker is executable
if [[ ! -x "$HEALTH_CHECKER" ]]; then
    echo "🔧 Making health checker executable..."
    chmod +x "$HEALTH_CHECKER"
fi

# Display start message
echo "🔍 Running MCP health check..."
notify "Running MCP health check..."

# Run health check with specified format
if [[ "$FORMAT" == "html" ]]; then
    # For HTML, we need to generate markdown first then convert or use template
    echo "📝 Generating HTML report..."
    
    # Run health check to generate markdown
    output_file=$("$HEALTH_CHECKER" --full --format=markdown 2>/dev/null | grep "generated:" | cut -d: -f2- | xargs)
    
    if [[ -z "$output_file" ]]; then
        # Fallback to expected location
        output_file="$REPORTS_DIR/latest_health_check.md"
    fi
    
    if [[ -f "$output_file" ]]; then
        # Convert markdown to HTML using a simple method
        html_file="${output_file%.md}.html"
        
        # Create a simple HTML wrapper
        cat > "$html_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>MCP Health Check Report</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 40px; line-height: 1.6; }
        h1 { color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #f8f9fa; font-weight: 600; }
        tr:nth-child(even) { background-color: #f8f9fa; }
        code { background: #f4f4f4; padding: 2px 4px; border-radius: 3px; }
        pre { background: #f8f9fa; padding: 15px; border-radius: 5px; overflow-x: auto; }
        .status-pass { color: #28a745; }
        .status-warning { color: #ffc107; }
        .status-failed { color: #dc3545; }
    </style>
</head>
<body>
EOF
        
        # Convert markdown to HTML (basic conversion)
        sed -E 's/^# (.*)/\<h1\>\1\<\/h1\>/g; s/^## (.*)/\<h2\>\1\<\/h2\>/g; s/^### (.*)/\<h3\>\1\<\/h3\>/g; s/\*\*(.*)\*\*/\<strong\>\1\<\/strong\>/g; s/\`([^`]*)\`/\<code\>\1\<\/code\>/g' "$output_file" >> "$html_file"
        
        echo "</body></html>" >> "$html_file"
        
        output_file="$html_file"
    else
        echo "❌ Failed to generate markdown report"
        notify "Failed to generate report"
        exit 1
    fi
    
elif [[ "$FORMAT" == "json" ]]; then
    echo "📊 Generating JSON report..."
    output_file=$("$HEALTH_CHECKER" --quick --format=json 2>/dev/null | grep "generated:" | cut -d: -f2- | xargs)
    
    if [[ -z "$output_file" ]]; then
        output_file="$REPORTS_DIR/latest_health_check.json"
    fi
    
else
    # Default to markdown
    echo "📝 Generating markdown report..."
    output_file=$("$HEALTH_CHECKER" --full --format=markdown 2>/dev/null | grep "generated:" | cut -d: -f2- | xargs)
    
    if [[ -z "$output_file" ]]; then
        output_file="$REPORTS_DIR/latest_health_check.md"
    fi
fi

# Check if output file was created
if [[ ! -f "$output_file" ]]; then
    echo "❌ Report file not found: $output_file"
    notify "Failed to generate report file"
    exit 1
fi

# Copy to desktop
echo "📋 Copying report to desktop..."
desktop_file=$(copy_to_desktop "$output_file")

# Get file info
file_size=$(du -h "$desktop_file" | cut -f1)
file_ext="${desktop_file##*.}"

# Open the file
echo "🚀 Opening report..."
case "$file_ext" in
    "md")
        # Try to open with preferred markdown app, fallback to default
        if command -v typora >/dev/null 2>&1; then
            open -a "Typora" "$desktop_file"
        elif command -v marktext >/dev/null 2>&1; then
            open -a "MarkText" "$desktop_file"
        else
            open "$desktop_file"
        fi
        ;;
    "html")
        open "$desktop_file"
        ;;
    "json")
        # Try to open with preferred JSON viewer, fallback to default
        if command -v code >/dev/null 2>&1; then
            code "$desktop_file"
        else
            open "$desktop_file"
        fi
        ;;
    *)
        open "$desktop_file"
        ;;
esac

# Display completion message
echo "✅ Health check complete!"
echo "📁 Report saved to: $(basename "$desktop_file")"
echo "📊 File size: $file_size"

# Show notification with results
notify "Health check complete! Report saved to desktop (${file_size})"

# Quick summary from the report
if [[ -f "$REPORTS_DIR/latest_health_check.md" ]]; then
    total_servers=$(grep "Total Servers" "$REPORTS_DIR/latest_health_check.md" | grep -o '[0-9]\+' | head -1)
    passed_servers=$(grep "✅ Passed" "$REPORTS_DIR/latest_health_check.md" | grep -o '[0-9]\+' | head -1)
    
    if [[ -n "$total_servers" && -n "$passed_servers" ]]; then
        echo "📈 Quick Summary: $passed_servers/$total_servers servers passed"
    fi
fi

echo ""
echo "🔧 Quick Actions:"
echo "• Re-run: raycast mcp-health-check"
echo "• View logs: open '$REPORTS_DIR'"
echo "• Edit config: open '/Users/jacques/Library/Application Support/Claude/claude_desktop_config.json'"