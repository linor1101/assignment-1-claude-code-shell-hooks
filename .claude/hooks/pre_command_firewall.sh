#!/bin/bash
# =============================================================================
# Pre-Hook 1: Command Firewall
# Purpose:    Block dangerous bash commands before execution.
# Input:      JSON on stdin: {"tool_name":"Bash","tool_input":{"command":"..."},...}
# Exit codes: 0 = allow, 2 = block (dangerous pattern matched)
# =============================================================================

#!/bin/bash

# Finding the path of the current script
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$HOOK_DIR/config/dangerous_patterns.txt"

# to read the JSON from the stdin
INPUT="$(cat)"

# Extracting the data
TOOL_NAME=$(printf '%s' "$INPUT" | grep -o '"tool_name":"[^"]*"' | head -1 | sed 's/"tool_name":"//;s/"//')
COMMAND=$(printf '%s' "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"//')

# If the tool is not Bash, we don't need to block anything.
if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

# Check that the configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
    exit 0
fi

# Reading the file line by line
while IFS= read -r pattern; do
    # Ignore empty lines or comments
    case "$pattern" in
        '#'*|'') continue ;;
    esac

    # Check if the command contains the pattern
    if echo "$COMMAND" | grep -qE "$pattern"; then
        # If there is a match - print an error to stderr and exit with code 2
        printf "BLOCKED: Command matches dangerous pattern '%s'. Please use a safer alternative.\n" "$pattern" >&2
        exit 2
    fi
done < "$CONFIG_FILE"

# We reached the end and were not blocked
exit 0