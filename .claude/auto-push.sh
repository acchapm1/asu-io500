#!/usr/bin/env bash
# PostToolUse hook: auto-commit and push files in the asu-io500 repo.
#
# Behavior:
#   - Reads tool input JSON from stdin (Claude Code PostToolUse contract).
#   - Extracts the touched file_path; bails out silently if it's not under REPO_DIR.
#   - Bails out if REPO_DIR/NO_AUTO_PUSH exists or $CLAUDE_DISABLE_AUTOPUSH is set.
#   - git adds the file, commits with an "auto:" message, pushes to origin/main.
#   - Always exits 0 so a hook failure never blocks the parent tool call.
#   - Logs to REPO_DIR/.claude/auto-push.log for debugging.

set -u

REPO_DIR="/home/acchapm1/io/asu-io500"
LOG="$REPO_DIR/.claude/auto-push.log"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG" 2>/dev/null || true
}

# Read entire stdin into a variable (may be empty if invoked manually).
input="$(cat 2>/dev/null || true)"

# Extract file_path from the JSON. Use python3 if available for robust parsing;
# fall back to a grep/sed line for hosts without python3.
file_path=""
if command -v python3 >/dev/null 2>&1; then
  file_path="$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = data.get("tool_input") or data.get("toolInput") or {}
fp = ti.get("file_path") or ti.get("filePath") or ""
print(fp)
' 2>/dev/null)"
else
  file_path="$(printf '%s' "$input" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
fi

if [[ -z "$file_path" ]]; then
  log "no file_path in tool input; skipping"
  exit 0
fi

# Resolve to absolute path so the prefix check is reliable.
abs_path="$(readlink -f -- "$file_path" 2>/dev/null || echo "$file_path")"

case "$abs_path" in
  "$REPO_DIR"/*) ;;
  *)
    log "skip: $abs_path not under $REPO_DIR"
    exit 0
    ;;
esac

# Honor explicit opt-out signals.
if [[ -n "${CLAUDE_DISABLE_AUTOPUSH:-}" ]]; then
  log "skip: CLAUDE_DISABLE_AUTOPUSH set ($abs_path)"
  exit 0
fi
if [[ -e "$REPO_DIR/NO_AUTO_PUSH" ]]; then
  log "skip: NO_AUTO_PUSH marker present ($abs_path)"
  exit 0
fi

# Stage, commit, push. Tolerate every failure (exit 0 at the end).
{
  cd "$REPO_DIR" || { log "cd failed"; exit 0; }

  if ! git diff --quiet -- "$abs_path" 2>/dev/null \
     || ! git diff --cached --quiet -- "$abs_path" 2>/dev/null \
     || [[ -n "$(git ls-files --others --exclude-standard -- "$abs_path" 2>/dev/null)" ]]; then
    git add -- "$abs_path" >>"$LOG" 2>&1 || log "git add failed"
  fi

  if git diff --cached --quiet; then
    log "nothing staged for $abs_path"
    exit 0
  fi

  msg="auto: update $(basename -- "$abs_path")"
  if git commit -m "$msg" >>"$LOG" 2>&1; then
    log "committed: $msg"
    if git push origin main >>"$LOG" 2>&1; then
      log "pushed to origin/main"
    else
      log "git push failed"
    fi
  else
    log "git commit failed"
  fi
}

exit 0
