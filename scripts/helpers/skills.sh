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
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
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

# ── Unified install/uninstall ──
# Usage: skill_install_all "opencode codex pi" → installs into each
#        Returns count of successfully installed skills
skill_install_all() {
  local tools="$1"
  local count=0
  for tool in $tools; do
    if "skill_install_$tool" 2>/dev/null; then
      count=$((count + 1))
    fi
  done
  echo "$count"
}

skill_uninstall_all() {
  local tools="$1"
  for tool in $tools; do
    "skill_uninstall_$tool" 2>/dev/null || true
  done
}
