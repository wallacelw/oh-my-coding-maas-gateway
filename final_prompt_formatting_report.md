# Interactive Prompts and Output Formatting Report

## Executive Summary

The scripts show good overall consistency in prompt and output formatting, with a few areas needing standardization. The `common.sh` helper functions provide a solid foundation, but some scripts deviate from the standard patterns.

## 1. scripts/helpers/common.sh - Foundation Functions

### Prompt Functions (All Good)
- `prompt_yesno`: `  ? Question [Y/n] ` (cyan ? + bold question + dim hint)
- `prompt_input`: `  ? Question (default: value): ` (cyan ? + bold question + dim default)
- `prompt_password`: Multi-line with auto-generated value display
- All write to stderr, read from `/dev/tty`

### Logging Functions (All Good)
- `log_step`: `\n━━━ title ━━━` (bold cyan)
- `log_ok`: `  ✓ message` (green)
- `log_info`: `  → message` (blue)  
- `log_warn`: `  ⚠ message` (yellow, stderr)
- `log_error`: `  ✗ message` (red, stderr)
- `log_dim`: `  message` (dim)
- `log_action`: `  [tag] message` (dim tag)

## 2. Specific Issues by Script

### scripts/01_env.sh

**Line 183:** Remove duplicate blank line
```bash
# Current (creates double blank line):
echo ""
while true; do
    echo ""
    MAAS_API_KEY=$(prompt_input "Enter Huawei MaaS API key (region ap-southeast-1)" "")
```

**Line 184:** Add base URL to prompt for clarity
```bash
# Change from:
MAAS_API_KEY=$(prompt_input "Enter Huawei MaaS API key (region ap-southeast-1)" "")
# To:
MAAS_API_KEY=$(prompt_input "Enter Huawei MaaS API key for $MAAS_API_BASE" "")
```

**Line 233:** Remove duplicate blank line
```bash
# Current (creates double blank line):
echo ""
while true; do
    echo ""
    EXTRA_NUM=$(( ${#EXTRA_KEYS[@]} + 1 ))
```

### scripts/bootstrap.sh

**Line 103 (standalone mode):** Add color formatting
```bash
# Change from:
echo "  git pull failed. Reset to origin/main? [y/N]: "
# To:
echo -ne "  ${C_BOLD}git pull failed. Reset to origin/main?${C_RESET} ${C_DIM}[y/N]${C_RESET}: "
```

**Line 205:** Use `prompt_input` for consistency
```bash
# Change from:
echo -ne "  ${C_BOLD}Choice${C_RESET} ${C_DIM}[1]${C_RESET}: "
read -r existing_choice < /dev/tty || existing_choice="1"
# To:
existing_choice=$(prompt_input "Choice" "1")
```

### scripts/03a_opencode.sh

**Line 147:** Clarify prompt text
```bash
# Change from:
HUAWEI_MAAS_API_KEY=$(prompt_input "Huawei MaaS API key (or press Enter to skip direct provider)" "")
# To:
HUAWEI_MAAS_API_KEY=$(prompt_input "Huawei MaaS API key for direct provider (optional, press Enter to skip)" "")
```

**Line 209:** Add blank line before completion
```bash
# Add before line 210:
echo ""
log_step "opencode installation complete"
```

### scripts/03b_codex.sh

**Line 113:** Standardize dry run message
```bash
# Change from:
log_ok "Dry run complete — no changes made"
# To:
log_info "Dry run complete — no changes made"
```

### scripts/03c_claude_code.sh

**Line 112:** Standardize dry run message
```bash
# Change from:
log_ok "Dry run complete — no changes made"
# To:
log_info "Dry run complete — no changes made"
```

### scripts/03d_pi.sh

**Line 170:** Add blank line before completion
```bash
# Add before line 171:
echo ""
log_step "Pi installation complete"
```

### scripts/02_litellm.sh

**Line 56:** Add blank line before port warnings
```bash
# Add before line 57:
echo ""
for port in 4000 5432 9090 3000; do
```

## 3. Inconsistent Patterns Across Scripts

### Dry Run Completion Messages
- **03a_opencode.sh line 138:** `log_step "Dry run complete — no changes made"`
- **03b_codex.sh line 113:** `log_ok "Dry run complete — no changes made"` 
- **03c_claude_code.sh line 112:** `log_ok "Dry run complete — no changes made"`
- **03d_pi.sh line 115:** `log_step "Dry run complete — no changes made"`

**Recommendation:** Standardize to `log_info "Dry run complete — no changes made"`

### Blank Line Before Completion Sections
- **03a_opencode.sh:** Missing before line 210
- **03b_codex.sh:** Has `echo ""` before line 159 ✓
- **03c_claude_code.sh:** Has `echo ""` before line 184 ✓  
- **03d_pi.sh:** Missing before line 171

### Port Check Warning Formatting
- **02_litellm.sh lines 57-60:** No blank line before warnings
- Should have visual separation from previous content

## 4. Color Usage Analysis

### Consistent Patterns:
- **Prompts:** `C_BOLD + C_CYAN` for `?`, `C_BOLD` for question, `C_DIM` for hint
- **Menus:** `C_BOLD` for numbers, `C_DIM` for `[default]`
- **Success:** `C_GREEN` with ✓
- **Info:** `C_BLUE` with →
- **Warnings:** `C_YELLOW` with ⚠
- **Errors:** `C_RED` with ✗
- **Secondary:** `C_DIM` for less important info

### Inconsistencies:
- **bootstrap.sh line 103:** Missing colors in standalone mode
- **04_validate.sh line 758:** Custom yellow border instead of standard formatting

## 5. Spacing and Layout Issues

### Good Examples:
- **01_env.sh lines 140-154:** Good spacing between password prompts with `echo ""`
- **bootstrap.sh lines 285-294:** Good spacing around scope display
- **All scripts:** Consistent 2-space indentation for continuation lines

### Issues:
1. **Double blank lines:** 01_env.sh lines 181-183, 231-233
2. **Missing blank lines:** 02_litellm.sh line 56, 03a_opencode.sh line 209, 03d_pi.sh line 170
3. **Inconsistent section spacing:** Some scripts use `echo ""` before `log_step`, others don't

## 6. User Experience Recommendations

### Prompt Clarity:
1. **Show URLs in prompts:** When asking for API keys, show the endpoint URL
2. **Be explicit about defaults:** `prompt_input` already shows `(default: value)`
3. **Consistent optional indicators:** Use "(optional)" or "(press Enter to skip)"

### Visual Hierarchy:
1. **Section headers:** All use `log_step` consistently ✓
2. **Subsections:** Use `log_info` or `log_dim` with indentation
3. **Results/Summaries:** Use `log_dim` for key-value pairs

### Error Handling:
1. **Validation feedback:** 01_env.sh has good color-coded validation
2. **Retry prompts:** Clear instructions on what went wrong
3. **Exit conditions:** Clear error messages with `log_error`

## 7. Proposed Standardization

### Add to common.sh:
```bash
# Standard dry run notice
log_dry_run() {
    [ "${DRY_RUN:-false}" = true ] && log_warn "DRY RUN — no changes will be made"
}

# Standard completion message
log_complete() {
    local tool="$1"
    echo ""
    log_step "$tool installation complete"
}

# Choice prompt for numbered menus
prompt_choice() {
    local question="$1" default="${2:-}" options=("${@:3}")
    # Implementation for numbered choice prompts
}
```

### Update Patterns:
1. **Dry run:** Always use `log_dry_run` at script start
2. **Completion:** Use `log_complete "Tool Name"` with tool-specific details after
3. **Menus:** Use `prompt_choice` for numbered selections
4. **Blank lines:** Always add `echo ""` before `log_step` for section transitions

## 8. Implementation Priority

### High (Affects user experience):
1. Fix double blank lines in 01_env.sh
2. Add missing blank lines before completion sections
3. Standardize dry run completion messages

### Medium (Consistency improvements):
4. Use `prompt_input` in bootstrap.sh line 205
5. Add colors to bootstrap.sh standalone prompt
6. Clarify prompt text in 01_env.sh and 03a_opencode.sh

### Low (Cosmetic):
7. Consider standardizing 04_validate.sh border
8. Add helper functions to common.sh for future use