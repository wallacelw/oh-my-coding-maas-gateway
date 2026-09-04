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

# ── opencode ──
skill_install_opencode() {
  local src; src=$(skill_source_path)
  local dest_dir="$HOME/.config/opencode/skills/$SKILL_NAME"
  mkdir -p "$dest_dir"
  cp "$src" "$dest_dir/SKILL.md"
  echo "$dest_dir/SKILL.md"
}

skill_uninstall_opencode() {
  rm -rf "$HOME/.config/opencode/skills/$SKILL_NAME"
}

skill_exists_opencode() {
  [ -f "$HOME/.config/opencode/skills/$SKILL_NAME/SKILL.md" ]
}

# ── codex ──
skill_install_codex() {
  local src; src=$(skill_source_path)
  local dest_dir="$HOME/.codex/skills/$SKILL_NAME"
  mkdir -p "$dest_dir"
  cp "$src" "$dest_dir/SKILL.md"
  echo "$dest_dir/SKILL.md"
}

skill_uninstall_codex() {
  rm -rf "$HOME/.codex/skills/$SKILL_NAME"
}

skill_exists_codex() {
  [ -f "$HOME/.codex/skills/$SKILL_NAME/SKILL.md" ]
}

# ── pi ──
skill_install_pi() {
  local src; src=$(skill_source_path)
  local dest_dir="$HOME/.pi/agent/skills/$SKILL_NAME"
  mkdir -p "$dest_dir"
  cp "$src" "$dest_dir/SKILL.md"
  echo "$dest_dir/SKILL.md"
}

skill_uninstall_pi() {
  rm -rf "$HOME/.pi/agent/skills/$SKILL_NAME"
}

skill_exists_pi() {
  [ -f "$HOME/.pi/agent/skills/$SKILL_NAME/SKILL.md" ]
}

# ── claude ──
skill_install_claude() {
  local src; src=$(skill_source_path)
  local dest_dir="$HOME/.claude/skills/$SKILL_NAME"
  mkdir -p "$dest_dir"
  cp "$src" "$dest_dir/SKILL.md"
  echo "$dest_dir/SKILL.md"
}

skill_uninstall_claude() {
  rm -rf "$HOME/.claude/skills/$SKILL_NAME"
}

skill_exists_claude() {
  [ -f "$HOME/.claude/skills/$SKILL_NAME/SKILL.md" ]
}

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
