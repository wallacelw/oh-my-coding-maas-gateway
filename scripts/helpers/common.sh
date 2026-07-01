#!/usr/bin/env bash
# common.sh — Shared utility helpers
#
# Source from any script:
#   source "$(dirname "${BASH_SOURCE[0]}")/helpers/common.sh"
#
# Provides:
#   source_env <project_dir>   — load .env into the environment (no-op if absent)
#   retry_curl [-o] curl_args  — retry curl with backoff (-o captures body)
#   strip_jsonc <file>         — strip // and /* */ comments outside strings
#   mask_key <key>             — print first8...last4 of a key

# Load .env (if present) into the environment so scripts are self-sufficient.
# Usage: source_env "$PROJECT_DIR"
source_env() {
  local project_dir="$1"
  if [ -f "$project_dir/.env" ]; then
    # shellcheck source=/dev/null
    set -a; source "$project_dir/.env"; set +a
  fi
}

# Retry curl with backoff (3 attempts, 2s/4s delays).
# Usage: retry_curl [-o] curl_args...
#   -o  capture and echo response body (otherwise just check exit code)
retry_curl() {
  local capture=false
  if [ "$1" = "-o" ]; then capture=true; shift; fi
  local max_attempts=3 delay=2 attempt=1 response="" err=""
  while [ $attempt -le $max_attempts ]; do
    if [ "$capture" = true ]; then
      response=$(curl "$@" 2>/dev/null) && [ -n "$response" ] && echo "$response" && return 0
    else
      err=$(curl "$@" 2>&1) && return 0
    fi
    [ $attempt -lt $max_attempts ] && sleep $delay
    ((attempt++))
  done
  [ -n "$err" ] && echo "  curl error: $err" >&2
  return 1
}

# Strip JSONC comments (// and /* */) outside of quoted strings.
# Usage: strip_jsonc <file>   (prints cleaned JSON to stdout)
strip_jsonc() {
  python3 -c "
import sys
text = open(sys.argv[1]).read()
result = []
in_string = False
escape = False
i = 0
while i < len(text):
    c = text[i]
    if escape:
        result.append(c)
        escape = False
        i += 1
        continue
    if in_string:
        result.append(c)
        if c == '\\\\':
            escape = True
        elif c == '\"':
            in_string = False
        i += 1
        continue
    if c == '\"':
        in_string = True
        result.append(c)
        i += 1
        continue
    if c == '/' and i + 1 < len(text):
        if text[i+1] == '/':
            while i < len(text) and text[i] != '\\n':
                i += 1
            continue
        elif text[i+1] == '*':
            i += 2
            while i + 1 < len(text) and not (text[i] == '*' and text[i+1] == '/'):
                i += 1
            if i + 1 >= len(text):
                break
            i += 2
            continue
    result.append(c)
    i += 1
sys.stdout.write(''.join(result))
" < "$1" 2>/dev/null || cat "$1"
}

# Print a masked form of a key: first8...last4
# Usage: mask_key "sk-abcdef..."
mask_key() {
  local key="$1"
  if [ -n "$key" ] && [ ${#key} -ge 12 ]; then
    echo "${key:0:8}...${key: -4}"
  else
    echo "$key"
  fi
}
