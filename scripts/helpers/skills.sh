#!/usr/bin/env bash
# helpers/skills.sh — Companion skill installation helpers
#
# Installs SKILL.md as a skill into each coding agent tool:
#   opencode: ~/.config/opencode/skills/<name>/SKILL.md
#   codex:    ~/.codex/skills/<name>/SKILL.md
#   pi:       ~/.pi/agent/skills/<name>/SKILL.md
#   claude:   ~/.claude/skills/<name>/SKILL.md
#
# All four tools use the same Agent Skills standard:
# SKILL.md with YAML frontmatter (name, description).

SKILL_NAME="oh-my-coding-maas-gateway"

# ── Get skill source path ──
# Usage: skill_source_path → echoes path to SKILL.md in project
skill_source_path() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "$(cd "$script_dir/../.." && pwd)/SKILL.md"
}

# ── Installed skill path per tool ──
# Usage: skill_dest_path opencode → echoes installed SKILL.md path
skill_dest_path() {
  case "$1" in
    opencode) echo "$HOME/.config/opencode/skills/$SKILL_NAME/SKILL.md" ;;
    codex)    echo "$HOME/.codex/skills/$SKILL_NAME/SKILL.md" ;;
    pi)       echo "$HOME/.pi/agent/skills/$SKILL_NAME/SKILL.md" ;;
    claude)   echo "$HOME/.claude/skills/$SKILL_NAME/SKILL.md" ;;
    *)        return 1 ;;
  esac
}

# ── Shared install/exists/uninstall (paths come from skill_dest_path) ──
_skill_install_one() {
  local tool="$1" src dest
  src=$(skill_source_path)
  dest=$(skill_dest_path "$tool")
  mkdir -p "$(dirname "$dest")" || return 1
  cp "$src" "$dest" || return 1
  echo "$dest"
}

_skill_exists_one() {
  [ -f "$(skill_dest_path "$1")" ]
}

_skill_uninstall_one() {
  rm -rf "$(dirname "$(skill_dest_path "$1")")"
}

# ── opencode ──
skill_install_opencode()   { _skill_install_one opencode; }
skill_exists_opencode()    { _skill_exists_one opencode; }
skill_uninstall_opencode() { _skill_uninstall_one opencode; }

# ── codex ──
skill_install_codex()   { _skill_install_one codex; }
skill_exists_codex()    { _skill_exists_one codex; }
skill_uninstall_codex() { _skill_uninstall_one codex; }

# ── pi ──
skill_install_pi()   { _skill_install_one pi; }
skill_exists_pi()    { _skill_exists_one pi; }
skill_uninstall_pi() { _skill_uninstall_one pi; }

# ── claude ──
skill_install_claude()   { _skill_install_one claude; }
skill_exists_claude()    { _skill_exists_one claude; }
skill_uninstall_claude() { _skill_uninstall_one claude; }

# ── Directory-based bundles (REA + drawio skills) ─────────────
# Unlike the single-file companion functions above, a bundle is a whole skill
# directory (e.g. skills/drawio/ with SKILL.md + scripts/find-shapes.js).
# Drift detection compares EVERY file in the tree, so edits to any vendored
# file (not just SKILL.md) are detected.
#
# Installed skill dirs per tool:
#   opencode: ~/.config/opencode/skills/<name>
#   codex:    ~/.codex/skills/<name>
#   pi:       ~/.pi/agent/skills/<name>
#   claude:   ~/.claude/skills/<name>

# Echo the installed bundle dir for <tool> <name>. Returns 1 for unknown tool.
bundle_dest_dir() {
  case "$1" in
    opencode) echo "$HOME/.config/opencode/skills/$2" ;;
    codex)    echo "$HOME/.codex/skills/$2" ;;
    pi)       echo "$HOME/.pi/agent/skills/$2" ;;
    claude)   echo "$HOME/.claude/skills/$2" ;;
    *)        return 1 ;;
  esac
}

# True when the bundle dir exists for <tool> <name>.
bundle_exists_one() {
  local dir
  dir=$(bundle_dest_dir "$1" "$2") || return 1
  [ -d "$dir" ]
}

# True when the installed bundle matches the source tree exactly (every file).
# Returns 1 when any file is missing or differs (NEW/STALE both → not current).
bundle_is_current() {
  local tool="$1" name="$2" src="$3" dest f rel
  dest=$(bundle_dest_dir "$tool" "$name") || return 1
  [ -d "$dest" ] || return 1
  while IFS= read -r -d '' f; do
    rel="${f#"$src"/}"
    cmp -s "$f" "$dest/$rel" || return 1
  done < <(find "$src" -type f -print0 2>/dev/null)
  return 0
}

# Install a bundle directory into <tool> <name>. Echoes the dest dir.
# Preserves 600 on files and 700 on dirs (skill trees hold no secrets, but
# keep them owner-only for consistency with the rest of the pipeline).
bundle_install_one() {
  local tool="$1" name="$2" src="$3" dest
  dest=$(bundle_dest_dir "$tool" "$name") || return 1
  [ -d "$src" ] || return 1
  mkdir -p "$(dirname "$dest")" || return 1
  rm -rf "$dest"
  cp -r "$src" "$dest" || return 1
  find "$dest" -type f -exec chmod 600 {} + 2>/dev/null || true
  find "$dest" -type d -exec chmod 700 {} + 2>/dev/null || true
  echo "$dest"
}

# Remove the installed bundle dir for <tool> <name>.
bundle_uninstall_one() {
  local dir
  dir=$(bundle_dest_dir "$1" "$2") || return 1
  rm -rf "$dir"
}
