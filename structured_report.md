# Interactive Prompts and Output Formatting - Structured Report

## 1. scripts/helpers/common.sh - Foundation Functions

### ✅ Good: Consistent prompt and logging functions

**prompt_yesno()** (lines 172-187):
- Format: `  ? Question [Y/n] `
- Colors: `C_BOLD + C_CYAN` for `?`, `C_BOLD` for question, `C_DIM` for hint
- Reads from `/dev/tty`, writes to stderr

**prompt_input()** (lines 191-202):
- Format: `  ? Question (default: value): `
- Colors: `C_BOLD + C_CYAN` for `?`, `C_BOLD` for question, `C_DIM` for default hint

**prompt_password()** (lines 209-235):
- Format: 
  ```
    ? Label
      Auto-generated: masked_key
    ? Use auto-generated value? [Y/n] 
    ? Enter custom value (must start with 'prefix'):
  ```
- Uses `prompt_yesno` internally

**Logging functions** (lines 128-157):
- `log_step`: `\n━━━ title ━━━` (bold cyan)
- `log_ok`: `  ✓ message` (green)
- `log_info`: `  → message` (blue)
- `log_warn`: `  ⚠ message` (yellow, stderr)
- `log_error`: `  ✗ message` (red, stderr)
- `log_dim`: `  message` (dim)
- `log_action`: `  [tag] message` (dim tag)

## 2. scripts/01_env.sh - Issues

### Line 183: Double blank line
**Current:**
```bash
echo ""
while true; do
    echo ""
    MAAS_API_KEY=$(prompt_input "Enter Huawei MaaS API key (region ap-southeast-1)" "")
```

**Fix:** Remove first `echo ""`

### Line 184: Missing context in prompt
**Current:**
```bash
MAAS_API_KEY=$(prompt_input "Enter Huawei MaaS API key (region ap-southeast-1)" "")
```

**Fix:**
```bash
MAAS_API_KEY=$(prompt_input "Enter Huawei MaaS API key for $MAAS_API_BASE" "")
```

### Line 233: Double blank line
**Current:**
```bash
echo ""
while true; do
    echo ""
    EXTRA_NUM=$(( ${#EXTRA_KEYS[@]} + 1 ))
```

**Fix:** Remove first `echo ""`

## 3. scripts/bootstrap.sh - Issues

### Line 103: Missing colors in standalone mode
**Current:**
```bash
echo "  git pull failed. Reset to origin/main? [y/N]: "
```

**Fix:**
```bash
echo -ne "  ${C_BOLD}git pull failed. Reset to origin/main?${C_RESET} ${C_DIM}[y/N]${C_RESET}: "
```

### Line 205: Custom prompt instead of `prompt_input`
**Current:**
```bash
echo -ne "  ${C_BOLD}Choice${C_RESET} ${C_DIM}[1]${C_RESET}: "
read -r existing_choice < /dev/tty || existing_choice="1"
```

**Fix:**
```bash
existing_choice=$(prompt_input "Choice" "1")
```

## 4. scripts/03a_opencode.sh - Issues

### Line 147: Unclear prompt text
**Current:**
```bash
HUAWEI_MAAS_API_KEY=$(prompt_input "Huawei MaaS API key (or press Enter to skip direct provider)" "")
```

**Fix:**
```bash
HUAWEI_MAAS_API_KEY=$(prompt_input "Huawei MaaS API key for direct provider (optional, press Enter to skip)" "")
```

### Line 209: Missing blank line before completion
**Current:**
```bash
log_step "opencode installation complete"
```

**Fix:** Add `echo ""` before line 210

## 5. scripts/03b_codex.sh - Issues

### Line 113: Inconsistent dry run message
**Current:**
```bash
log_ok "Dry run complete — no changes made"
```

**Fix:**
```bash
log_info "Dry run complete — no changes made"
```

## 6. scripts/03c_claude_code.sh - Issues

### Line 112: Inconsistent dry run message
**Current:**
```bash
log_ok "Dry run complete — no changes made"
```

**Fix:**
```bash
log_info "Dry run complete — no changes made"
```

## 7. scripts/03d_pi.sh - Issues

### Line 170: Missing blank line before completion
**Current:**
```bash
log_step "Pi installation complete"
```

**Fix:** Add `echo ""` before line 171

## 8. scripts/02_litellm.sh - Issues

### Line 56: Missing blank line before port warnings
**Current:**
```bash
for port in 4000 5432 9090 3000; do
```

**Fix:** Add `echo ""` before line 57

## 9. Dry Run Message Inconsistency

### Current State:
- **03a_opencode.sh line 138**: `log_step "Dry run complete — no changes made"`
- **03b_codex.sh line 113**: `log_ok "Dry run complete — no changes made"`
- **03c_claude_code.sh line 112**: `log_ok "Dry run complete — no changes made"`
- **03d_pi.sh line 115**: `log_step "Dry run complete — no changes made"`

### Recommended Standard:
```bash
log_info "Dry run complete — no changes made"
```

## 10. Blank Line Patterns

### Good Examples:
- **bootstrap.sh lines 320-326**: Blank line before confirmation prompt
- **bootstrap.sh lines 284-285**: Blank line before scope display
- **03b_codex.sh line 158**: Blank line before completion message
- **03c_claude_code.sh line 183**: Blank line before completion message

### Missing Blank Lines:
- **03a_opencode.sh line 209**: Before `log_step "opencode installation complete"`
- **03d_pi.sh line 170**: Before `log_step "Pi installation complete"`
- **02_litellm.sh line 56**: Before port check warnings

## 11. Color Usage Summary

### Consistent:
- `C_BOLD + C_CYAN`: Prompt `?` and menu numbers
- `C_BOLD`: Question text
- `C_DIM`: Default values, hints, secondary info
- `C_GREEN`: Success (✓)
- `C_BLUE`: Information (→)
- `C_YELLOW`: Warnings (⚠)
- `C_RED`: Errors (✗)

### Inconsistent:
- **bootstrap.sh line 103**: Missing colors in standalone mode
- **04_validate.sh line 758**: Custom yellow border instead of standard format

## 12. Recommendations for New Helper Functions

Add to `common.sh`:

```bash
# Standard dry run notice
log_dry_run() {
    [ "${DRY_RUN:-false}" = true ] && log_warn "DRY RUN — no changes will be made"
}

# Standard completion pattern
log_complete() {
    local tool="$1"
    echo ""
    log_step "$tool installation complete"
}

# Choice prompt for numbered menus
prompt_choice() {
    local question="$1" default="${2:-}" options=("${@:3}")
    if ! is_interactive; then
        echo "$default"
        return
    fi
    echo -e "  ${C_BOLD}${C_CYAN}?${C_RESET} ${C_BOLD}$question${C_RESET} ${C_DIM}[$default]${C_RESET}: " >&2
    read -r answer < /dev/tty
    echo "${answer:-$default}"
}
```

## Implementation Priority

### Immediate (High Impact):
1. Fix double blank lines in 01_env.sh (lines 183, 233)
2. Standardize dry run messages in 03b/c to `log_info`
3. Add missing blank lines (03a line 209, 03d line 170, 02_litellm line 56)

### Short-term (Medium Impact):
4. Use `prompt_input` in bootstrap.sh line 205
5. Add colors to bootstrap.sh line 103
6. Improve prompt text in 01_env.sh line 184 and 03a_opencode.sh line 147

### Long-term (Low Impact):
7. Add helper functions to `common.sh`
8. Standardize 04_validate.sh border formatting