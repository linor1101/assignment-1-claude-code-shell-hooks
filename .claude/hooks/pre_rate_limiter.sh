#!/bin/bash
# =============================================================================
# Pre-Hook 2: Rate Limiter
# Purpose:    Track command count per session, block after exceeding limit.
# Input:      JSON on stdin: {"tool_name":"Bash","tool_input":{"command":"..."},"session_id":"..."}
# Exit codes: 0 = allow (possibly with warning), 2 = blocked (limit exceeded)
# State file: data/.command_count — format per line: session_id|total|type1:N,type2:N,...
# =============================================================================

#!/bin/bash

# define paths
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$HOOK_DIR/config/hooks.conf"
DATA_FILE="$HOOK_DIR/data/.command_count"
RESET_FILE="$HOOK_DIR/data/.reset_commands"

# Creating the data folder if it does not exist
mkdir -p "$HOOK_DIR/data"

# call JSON
INPUT="$(cat)"
SESSION_ID=$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')
COMMAND=$(printf '%s' "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"//')

# If there is no session_id, we will use "default"
SESSION_ID=${SESSION_ID:-default}

# Extract the first word of the command 
CMD_TYPE=$(echo "$COMMAND" | awk '{print $1}')

# Retrieve constraints (with default values ​​if the file does not exist)
MAX_COMMANDS=$(grep "MAX_COMMANDS=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2)
WARNING_THRESHOLD=$(grep "WARNING_THRESHOLD=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2)

MAX_COMMANDS=${MAX_COMMANDS:-50}
WARNING_THRESHOLD=${WARNING_THRESHOLD:-40}

# check reset
if [ -f "$RESET_FILE" ]; then
    # # Delete the current session row from the data file (if it exists)
    if [ -f "$DATA_FILE" ]; then
        sed -i "/^$SESSION_ID|/d" "$DATA_FILE"
    fi
    # delete the reset file
    rm -f "$RESET_FILE"
fi

# Search for the current session line in a file
# grep will return the entire line if it exists
EXISTING_LINE=$(grep "^$SESSION_ID|" "$DATA_FILE" 2>/dev/null)

if [ -z "$EXISTING_LINE" ]; then
    # If there is no such line - start from zero
    TOTAL_COUNT=0
    BREAKDOWN=""
else
    # If there is a row - extract the data (separate by |
    TOTAL_COUNT=$(echo "$EXISTING_LINE" | cut -d'|' -f2)
    BREAKDOWN=$(echo "$EXISTING_LINE" | cut -d'|' -f3)
fi

# update the general count
TOTAL_COUNT=$((TOTAL_COUNT + 1))

# Update the Breakdown 
# Check if the current command type already exists in the Breakdown
if echo "$BREAKDOWN" | grep -q "$CMD_TYPE:"; then
    # If it exists - we will use sed to replace the old number with the new one
    CURRENT_CMD_COUNT=$(echo "$BREAKDOWN" | grep -o "$CMD_TYPE:[0-9]*" | cut -d':' -f2)
    NEW_CMD_COUNT=$((CURRENT_CMD_COUNT + 1))
    BREAKDOWN=$(echo "$BREAKDOWN" | sed "s@$CMD_TYPE:$CURRENT_CMD_COUNT@$CMD_TYPE:$NEW_CMD_COUNT@")
else
    # If it doesn't exist - just add it to the end 
    if [ -z "$BREAKDOWN" ]; then
        BREAKDOWN="$CMD_TYPE:1"
    else
        BREAKDOWN="$BREAKDOWN,$CMD_TYPE:1"
    fi
fi

#  Assembling the new line and saving it to a file
NEW_LINE="$SESSION_ID|$TOTAL_COUNT|$BREAKDOWN"
TEMP_FILE=$(mktemp)

if [ -f "$DATA_FILE" ]; then
    # Copy all lines except the current session to a temporary file
    grep -v "^$SESSION_ID|" "$DATA_FILE" > "$TEMP_FILE"
fi

# add the new line
echo "$NEW_LINE" >> "$TEMP_FILE"

# Replace the original data file
mv "$TEMP_FILE" "$DATA_FILE"

# Exception checking
if [ "$TOTAL_COUNT" -gt "$MAX_COMMANDS" ]; then
    # block
    printf "BLOCKED: Rate limit exceeded for session '%s'. Total: %d, Limit: %d\n" "$SESSION_ID" "$TOTAL_COUNT" "$MAX_COMMANDS" >&2
    printf "Breakdown: %s\n" "$BREAKDOWN" >&2
    exit 2
elif [ "$TOTAL_COUNT" -gt "$WARNING_THRESHOLD" ]; then
    # warning
    printf "WARNING: Approaching rate limit for session '%s'. Total: %d, Limit: %d\n" "$SESSION_ID" "$TOTAL_COUNT" "$MAX_COMMANDS" >&2
    exit 0
fi

exit 0