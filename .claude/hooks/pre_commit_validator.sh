#!/bin/bash
# =============================================================================
# Pre-Hook 3: Commit Message Validator
# Purpose:    Validate git commit messages follow conventional commit format.
#             Suggests a prefix if one is missing based on staged diff heuristics.
# Input:      JSON on stdin: {"tool_name":"Bash","tool_input":{"command":"..."},...}
# Exit codes: 0 = allow, 2 = block (invalid commit message)
# =============================================================================

#!/bin/bash

# define the paths
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX_FILE="$HOOK_DIR/config/commit_prefixes.txt"

# Reading the JSON and extracting the command
INPUT="$(cat)"
COMMAND=$(printf '%s' "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"//')

# Check if this is even a commit command
if [[ ! "$COMMAND" =~ "git commit" ]]; then
    exit 0
fi

# If there is no -m, it is impossible to check - confirm
if [[ ! "$COMMAND" =~ "-m" ]]; then
    exit 0
fi

# Extract the commit message (looking for what is between the quotes after the "m")
COMMIT_MSG=$(echo "$COMMAND" | sed -E 's/.*-m[[:space:]]*["'\'']([^"'\'']*)["'\''].*/\1/')

# Loading prefixes and building Regex
if [ -f "$PREFIX_FILE" ]; then
    # Turns the file into a | separated list 
    PREFIX_LIST=$(paste -sd "|" "$PREFIX_FILE")
    REGEX="^($PREFIX_LIST): .*"
else
    # Default if file is missing
    REGEX="^(feat|fix|docs|refactor|test|chore): .*"
fi

# Check if the message matches the format
if [[ ! "$COMMIT_MSG" =~ $REGEX ]]; then
    # Checking for modified files
    STAGED_FILES=$(git diff --cached --name-only)
    STAGED_STATUS=$(git diff --cached --name-status)
    
    if echo "$STAGED_FILES" | grep -qE "test|spec"; then
        SUGGESTION="test"
    elif echo "$STAGED_FILES" | grep -qE "README|\.md"; then
        SUGGESTION="docs"
    elif echo "$STAGED_STATUS" | grep -q "^A"; then
        SUGGESTION="feat"
    else
        # Checking deletions versus insertions
        STATS=$(git diff --cached --shortstat)
        INSERTIONS=$(echo "$STATS" | grep -o "[0-9]* insertion" | awk '{print $1}')
        DELETIONS=$(echo "$STATS" | grep -o "[0-9]* deletion" | awk '{print $1}')
        
        if [ "${DELETIONS:-0}" -gt "${INSERTIONS:-0}" ]; then
            SUGGESTION="refactor"
        else
            SUGGESTION="feat"
        fi
    fi

    # Print the blocking message and offer
    VALID_PREFIXES=$(tr '\n' ',' < "$PREFIX_FILE" | sed 's/,$//')
    printf "BLOCKED: Missing prefix. Based on your changes, try: '%s: %s'. Valid prefixes: %s\n" "$SUGGESTION" "$COMMIT_MSG" "$VALID_PREFIXES" >&2
    exit 2
fi

# Length check (10-72 characters)
MSG_LEN=${#COMMIT_MSG}
if [ "$MSG_LEN" -lt 10 ] || [ "$MSG_LEN" -gt 72 ]; then
    printf "BLOCKED: Commit message length (%d) is out of range (10-72).\n" "$MSG_LEN" >&2
    exit 2
fi

# Check point at the end
if [[ "$COMMIT_MSG" =~ \.$ ]]; then
    printf "BLOCKED: Commit message must not end with a period.\n" >&2
    exit 2
fi

exit 0