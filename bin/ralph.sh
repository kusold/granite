#!/usr/bin/env bash
# ralph.sh - Ralph Wiggum Loop
# Usage: ./ralph.sh [PROMPT.md] [max_iterations]

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

DEFAULT_BEADS_PROMPT='You are in a Ralph Wiggum loop. Your work persists in files and git between iterations.

## Workflow

1. Run `bd ready` to find a task with no blockers
2. Complete the task
3. Run `bd close <id>` with a summary
4. If blocked, create an issue with `bd create` and set dependencies with `bd dep`
5. Commit your work

## Completion

When `bd ready` returns no tasks:
<promise>DONE</promise>

## Rules

- ONE task per iteration
- Create issues for discovered subtasks
- Commit after each task'

# Determine prompt source
if [[ -n "${1:-}" && -f "$1" ]]; then
  PROMPT=$(cat "$1")
  PROMPT_SOURCE="$1"
  MAX_ITERATIONS="${2:-0}"
elif [[ -e ".beads" ]]; then
  PROMPT="$DEFAULT_BEADS_PROMPT"
  PROMPT_SOURCE="beads (default)"
  MAX_ITERATIONS="${1:-0}"
else
  echo -e "${RED}Error:${RESET} No prompt file provided and no .beads found"
  echo -e "${YELLOW}Usage:${RESET} $0 [PROMPT_FILE] [max_iterations]"
  exit 1
fi

ITERATION=0

echo -e "${BOLD}${MAGENTA}╔════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${MAGENTA}║         RALPH WIGGUM LOOP              ║${RESET}"
echo -e "${BOLD}${MAGENTA}╚════════════════════════════════════════╝${RESET}"
echo -e "${CYAN}Prompt:${RESET} $PROMPT_SOURCE"
echo -e "${CYAN}Max iterations:${RESET} ${MAX_ITERATIONS:-∞}"
echo ""

# Check if bd ready has remaining work
has_beads_work() {
  if [[ -e ".beads" ]]; then
    # bd ready returns non-empty output if there's work to do
    local ready_output
    ready_output=$(bd ready 2>/dev/null) || return 1
    [[ -n "$ready_output" ]]
  else
    return 1
  fi
}

while :; do
  ((ITERATION++))

  echo -e "${BOLD}${BLUE}┌──────────────────────────────────────────┐${RESET}"
  echo -e "${BOLD}${BLUE}│  Iteration ${YELLOW}$ITERATION${BLUE}                           │${RESET}"
  echo -e "${BOLD}${BLUE}└──────────────────────────────────────────┘${RESET}"

  OUTPUT=$(claude --dangerously-skip-permissions --print "$PROMPT" 2>&1) || true
  echo "$OUTPUT"

  # Check for completion promise
  if echo "$OUTPUT" | grep -q '<promise>.*</promise>'; then
    # If .beads exists, check if there's still work to do
    if has_beads_work; then
      echo ""
      echo -e "${BOLD}${CYAN}╔════════════════════════════════════════╗${RESET}"
      echo -e "${BOLD}${CYAN}║  ℹ PROMISE DETECTED BUT WORK REMAINS   ║${RESET}"
      echo -e "${BOLD}${CYAN}║  Continuing (bd ready has tasks)...    ║${RESET}"
      echo -e "${BOLD}${CYAN}╚════════════════════════════════════════╝${RESET}"
    else
      echo ""
      echo -e "${BOLD}${GREEN}╔════════════════════════════════════════╗${RESET}"
      echo -e "${BOLD}${GREEN}║  ✓ PROMISE DETECTED                    ║${RESET}"
      echo -e "${BOLD}${GREEN}║  Completed in ${YELLOW}$ITERATION${GREEN} iterations          ║${RESET}"
      echo -e "${BOLD}${GREEN}╚════════════════════════════════════════╝${RESET}"
      exit 0
    fi
  fi

  # Check max iterations
  if [[ $MAX_ITERATIONS -gt 0 && $ITERATION -ge $MAX_ITERATIONS ]]; then
    echo ""
    echo -e "${BOLD}${YELLOW}╔════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${YELLOW}║  ⚠ MAX ITERATIONS REACHED (${MAX_ITERATIONS})          ║${RESET}"
    echo -e "${BOLD}${YELLOW}╚════════════════════════════════════════╝${RESET}"
    exit 0
  fi

  echo -e "${CYAN}───────────────────────────────────────────${RESET}"
  echo ""
done
