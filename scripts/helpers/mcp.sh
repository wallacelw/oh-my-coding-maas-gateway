#!/usr/bin/env bash
# helpers/mcp.sh — MCP registration helpers for the coding agents
#
# Registers MCP servers in each agent's config file, using the native shape
# for that agent:
#   opencode: ~/.config/opencode/opencode.json  → .mcp.<name>
#             { "type": "local", "command": [node, entry], "enabled": true }
#   codex:    ~/.codex/config.toml              → [mcp_servers.<name>]
#             a sentinel-delimited managed block (# >>> mcp:<name> ... # <<<)
#   claude:   ~/.claude.json                    → .mcpServers.<name>
#             { "command": node, "args": [entry], "env": {} }
#   pi:       ~/.pi/agent/mcp.json              → .mcpServers.<name>
#             (same shape as claude; SHARED with REA, so all writes merge)
#
# Contract for every writer:
#   * umask 077; chmod 600 after every write (configs may hold secrets)
#   * backup_with_prune before every write
#   * compare-before-write: skip backup + write when content is unchanged
#   * idempotent: re-running writes nothing when already registered
#
# Sourced by: scripts/04_skills_mcps.sh, scripts/uninstall.sh,
#             scripts/05_validate.sh (verify/parse helpers).
# Requires helpers/common.sh to be sourced first (logging, strip_jsonc,
# backup_with_prune).

# Configs may hold API keys — deny group/world access for anything we write.
umask 077

_mcp_dir_of() { dirname "$1"; }

# ── Write a file only if its content changed ────────────────
# Returns 0 when it wrote (or created) the file, 1 when unchanged.
# Usage: _mcp_write_if_changed <file> <new-content>
_mcp_write_if_changed() {
  local file="$1" new="$2" existing=""
  if [ -f "$file" ]; then
    existing=$(cat "$file")
    if [ "$new" = "$existing" ]; then
      # Content is identical — still enforce 600 (external tools may relax it).
      if [ "$(stat -c '%a' "$file" 2>/dev/null)" != "600" ]; then
        chmod 600 "$file" 2>/dev/null || true
      fi
      return 1
    fi
  fi
  mkdir -p "$(_mcp_dir_of "$file")" 2>/dev/null || true
  backup_with_prune "$file" >/dev/null 2>&1 || true
  printf '%s\n' "$new" > "$file"
  chmod 600 "$file" 2>/dev/null || true
  return 0
}

# Build a JSON array string from shell args (each becomes a JSON string).
# Usage: _mcp_json_array "a" "b" → ["a","b"]  (empty → [])
_mcp_json_array() {
  local out="[" a first=1
  for a in "$@"; do
    [ "$first" -eq 0 ] && out+=","
    out+=$(jq -Rn --arg x "$a" '$x')
    first=0
  done
  out+="]"
  printf '%s' "$out"
}

# Read a JSON file (JSONC-tolerant) and print compact JSON, or "{}" when
# the file is missing/empty. Returns 1 if the file exists but is invalid.
_mcp_read_json() {
  local file="$1" clean
  if [ ! -f "$file" ]; then
    printf '{}'
    return 0
  fi
  if grep -q '/' "$file" 2>/dev/null; then
    clean=$(strip_jsonc "$file")
  else
    clean=$(cat "$file")
  fi
  if [ -z "$clean" ]; then
    printf '{}'
    return 0
  fi
  if ! printf '%s' "$clean" | jq -e . >/dev/null 2>&1; then
    return 1
  fi
  printf '%s' "$clean"
}

# ════════════════════════════════════════════════════════════════
# opencode  →  .mcp.<name>  (command is a JSON array)
# ════════════════════════════════════════════════════════════════
_mcp_opencode_file() { echo "$HOME/.config/opencode/opencode.json"; }

mcp_register_opencode() {
  local name="$1" cmd_json="$2"
  local file; file=$(_mcp_opencode_file)
  local clean new
  if ! clean=$(_mcp_read_json "$file"); then
    log_error "  opencode config is not valid JSON — cannot register MCP '$name'"
    return 1
  fi
  if ! new=$(printf '%s' "$clean" | jq --arg n "$name" --argjson cmd "$cmd_json" \
       '.mcp = (.mcp // {}) | .mcp[$n] = {type: "local", command: $cmd, enabled: true}'); then
    log_error "  failed to merge MCP '$name' into opencode config"
    return 1
  fi
  if _mcp_write_if_changed "$file" "$new"; then
    log_ok "  opencode: registered MCP '$name'"
  else
    log_dim "  opencode: MCP '$name' already registered"
  fi
  return 0
}

mcp_unregister_opencode() {
  local name="$1" file clean new
  file=$(_mcp_opencode_file)
  [ -f "$file" ] || return 0
  clean=$(_mcp_read_json "$file") || return 0
  new=$(printf '%s' "$clean" | jq --arg n "$name" 'if .mcp then del(.mcp[$n]) else . end' 2>/dev/null) || return 0
  [ -n "$new" ] && _mcp_write_if_changed "$file" "$new" >/dev/null 2>&1 || true
  return 0
}

mcp_verify_opencode() {
  local name="$1" file clean
  file=$(_mcp_opencode_file)
  [ -f "$file" ] || return 1
  clean=$(_mcp_read_json "$file") || return 1
  printf '%s' "$clean" | jq -e --arg n "$name" '.mcp[$n] != null' >/dev/null 2>&1
}

# ════════════════════════════════════════════════════════════════
# claude  →  .mcpServers.<name>  (command + args)
# ════════════════════════════════════════════════════════════════
_mcp_claude_file() { echo "$HOME/.claude.json"; }

mcp_register_claude() {
  local name="$1" cmd="$2"; shift 2
  local args_json; args_json=$(_mcp_json_array "$@")
  local file clean new
  file=$(_mcp_claude_file)
  if ! clean=$(_mcp_read_json "$file"); then
    log_error "  ~/.claude.json is not valid JSON — cannot register MCP '$name'"
    return 1
  fi
  if ! new=$(printf '%s' "$clean" | jq --arg n "$name" --arg c "$cmd" --argjson a "$args_json" \
       '.mcpServers = (.mcpServers // {}) | .mcpServers[$n] = {command: $c, args: $a, env: {}}'); then
    log_error "  failed to merge MCP '$name' into ~/.claude.json"
    return 1
  fi
  if _mcp_write_if_changed "$file" "$new"; then
    log_ok "  claude: registered MCP '$name'"
  else
    log_dim "  claude: MCP '$name' already registered"
  fi
  return 0
}

mcp_unregister_claude() {
  local name="$1" file clean new
  file=$(_mcp_claude_file)
  [ -f "$file" ] || return 0
  clean=$(_mcp_read_json "$file") || return 0
  new=$(printf '%s' "$clean" | jq --arg n "$name" 'if .mcpServers then del(.mcpServers[$n]) else . end' 2>/dev/null) || return 0
  [ -n "$new" ] && _mcp_write_if_changed "$file" "$new" >/dev/null 2>&1 || true
  return 0
}

mcp_verify_claude() {
  local name="$1" file clean
  file=$(_mcp_claude_file)
  [ -f "$file" ] || return 1
  clean=$(_mcp_read_json "$file") || return 1
  printf '%s' "$clean" | jq -e --arg n "$name" '.mcpServers[$n] != null' >/dev/null 2>&1
}

# ════════════════════════════════════════════════════════════════
# pi  →  .mcpServers.<name>  (SHARED with REA; merge, never clobber)
# ════════════════════════════════════════════════════════════════
_mcp_pi_file() { echo "$HOME/.pi/agent/mcp.json"; }

mcp_register_pi() {
  local name="$1" cmd="$2"; shift 2
  local args_json; args_json=$(_mcp_json_array "$@")
  local file clean new
  file=$(_mcp_pi_file)
  # Create the file (and its dir) if missing so jq has a JSON base.
  if [ ! -f "$file" ]; then
    mkdir -p "$(_mcp_dir_of "$file")" 2>/dev/null || true
  fi
  if ! clean=$(_mcp_read_json "$file"); then
    log_error "  ~/.pi/agent/mcp.json is not valid JSON — cannot register MCP '$name'"
    return 1
  fi
  if ! new=$(printf '%s' "$clean" | jq --arg n "$name" --arg c "$cmd" --argjson a "$args_json" \
       '.mcpServers = (.mcpServers // {}) | .mcpServers[$n] = {command: $c, args: $a, env: {}}'); then
    log_error "  failed to merge MCP '$name' into ~/.pi/agent/mcp.json"
    return 1
  fi
  if _mcp_write_if_changed "$file" "$new"; then
    log_ok "  pi: registered MCP '$name'"
  else
    log_dim "  pi: MCP '$name' already registered"
  fi
  return 0
}

mcp_unregister_pi() {
  local name="$1" file clean new
  file=$(_mcp_pi_file)
  [ -f "$file" ] || return 0
  clean=$(_mcp_read_json "$file") || return 0
  new=$(printf '%s' "$clean" | jq --arg n "$name" \
    'if .mcpServers then del(.mcpServers[$n]) else . end
     | if (.mcpServers? // {}) == {} and (.mcp? // {}) == {} then del(.mcpServers) else . end' 2>/dev/null) || return 0
  if [ -n "$new" ]; then
    if _mcp_write_if_changed "$file" "$new"; then :; fi
  fi
  # Remove the file entirely if it became empty (REA may have created it).
  if [ -f "$file" ]; then
    local keys
    keys=$(jq -r 'keys | length' "$file" 2>/dev/null || echo 1)
    if [ "$keys" = "0" ]; then
      rm -f "$file"
      log_dim "  pi: removed empty ~/.pi/agent/mcp.json"
    fi
  fi
  return 0
}

mcp_verify_pi() {
  local name="$1" file clean
  file=$(_mcp_pi_file)
  [ -f "$file" ] || return 1
  clean=$(_mcp_read_json "$file") || return 1
  printf '%s' "$clean" | jq -e --arg n "$name" '.mcpServers[$n] != null' >/dev/null 2>&1
}

# ════════════════════════════════════════════════════════════════
# codex  →  [mcp_servers.<name>]  sentinel-delimited managed block
# ════════════════════════════════════════════════════════════════
_mcp_codex_file() { echo "$HOME/.codex/config.toml"; }

# Emit the managed block text for a codex MCP entry (no trailing newline).
_mcp_codex_block() {
  local name="$1" cmd="$2"; shift 2
  local start="# >>> mcp:$name" end="# <<< mcp:$name"
  local esc_cmd esc_a arr="" a
  esc_cmd=$(printf '%s' "$cmd" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '%s\n' "$start"
  printf '[mcp_servers.%s]\n' "$name"
  printf 'command = "%s"\n' "$esc_cmd"
  if [ "$#" -gt 0 ]; then
    for a in "$@"; do
      esc_a=$(printf '%s' "$a" | sed 's/\\/\\\\/g; s/"/\\"/g')
      [ -n "$arr" ] && arr+=", "
      arr+="\"$esc_a\""
    done
    printf 'args = [%s]\n' "$arr"
  fi
  printf '%s' "$end"
}

# Upsert (replace-in-place or append) the managed block, preserving all other
# content (foreign REA sections included). Idempotent.
mcp_register_codex() {
  local name="$1" cmd="$2"; shift 2
  local file; file=$(_mcp_codex_file)
  mkdir -p "$(_mcp_dir_of "$file")" 2>/dev/null || true
  local block; block=$(_mcp_codex_block "$name" "$cmd" "$@")
  local existing="" new
  [ -f "$file" ] && existing=$(cat "$file")
  if [ -n "$existing" ]; then
    # Pass the (multiline) block through ENVIRON, not -v, so awk does not
    # apply escape processing to TOML backslashes/quotes in the paths.
    new=$(printf '%s' "$existing" | BLK="$block" awk -v s="# >>> mcp:$name" -v e="# <<< mcp:$name" '
      BEGIN { blk=ENVIRON["BLK"]; done=0; skip=0 }
      $0 == s { if (!done) { print blk; done=1 }; skip=1; next }
      $0 == e { skip=0; next }
      skip { next }
      { print }
      END { if (!done) { if (NR>0) print ""; print blk } }
    ')
  else
    new="$block"
  fi
  if _mcp_write_if_changed "$file" "$new"; then
    log_ok "  codex: registered MCP '$name'"
  else
    log_dim "  codex: MCP '$name' already registered"
  fi
  return 0
}

mcp_unregister_codex() {
  local name="$1" file new
  file=$(_mcp_codex_file)
  [ -f "$file" ] || return 0
  new=$(cat "$file" | awk -v s="# >>> mcp:$name" -v e="# <<< mcp:$name" '
    BEGIN { skip=0 }
    $0 == s { skip=1; next }
    $0 == e { skip=0; next }
    skip { next }
    { print }
  ')
  [ -n "$new" ] && _mcp_write_if_changed "$file" "$new" >/dev/null 2>&1 || true
  return 0
}

mcp_verify_codex() {
  local name="$1" file
  file=$(_mcp_codex_file)
  [ -f "$file" ] || return 1
  grep -qE "^\[mcp_servers\.${name//./\\.}\]" "$file" 2>/dev/null
}

# ════════════════════════════════════════════════════════════════
# TOML sanity / parse checks for ~/.codex/config.toml
# ════════════════════════════════════════════════════════════════

# True when python3 provides tomllib (>= 3.11).
mcp_python_has_tomllib() {
  python3 -c 'import tomllib' >/dev/null 2>&1
}

# Validate that a TOML file parses. Uses tomllib when python3 >= 3.11, else a
# regex sanity check (no duplicate table headers). Returns 0 when valid.
# Usage: mcp_toml_parse_ok <file>
mcp_toml_parse_ok() {
  local file="$1"
  [ -f "$file" ] || return 0
  if mcp_python_has_tomllib; then
    python3 -c 'import tomllib,sys; tomllib.load(open(sys.argv[1],"rb"))' "$file" >/dev/null 2>&1
    return $?
  fi
  # Fallback: duplicate table headers are the common malformed-merge symptom.
  local dup
  dup=$(grep -oE '^\[[^]]+\]' "$file" 2>/dev/null | sort | uniq -d)
  [ -z "$dup" ]
}

# Count how many `[mcp_servers.<name>]` header lines the file contains.
# Usage: mcp_toml_count_header <file> <name>
mcp_toml_count_header() {
  local file="$1" name="$2" cnt
  [ -f "$file" ] || { echo 0; return 0; }
  cnt=$(grep -cE "^\[mcp_servers\.${name//./\\.}\]" "$file" 2>/dev/null || true)
  echo "${cnt:-0}"
}
