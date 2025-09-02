#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title New Text File
# @raycast.mode compact

# Optional parameters:
# @raycast.icon 📄
# @raycast.packageName Quick Notes

# Documentation:
# @raycast.description Creates a text file in the current Finder folder

# Try to get frontmost Finder folder
DIR=$(osascript <<EOD
tell application "Finder"
    if exists (front window) then
        set thePath to POSIX path of (target of front window as alias)
    else
        set thePath to POSIX path of (path to desktop folder)
    end if
end tell
return thePath
EOD
)

# Set filename with timestamp
FILENAME="NewNote_$(date +%Y%m%d_%H%M%S).txt"

# Create and open the file
touch "$DIR/$FILENAME"
open "$DIR/$FILENAME"
