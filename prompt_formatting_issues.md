# Interactive Prompts and Output Formatting Issues

## Summary of Issues

### 1. Inconsistent Spacing and Blank Lines

**01_env.sh:**
- Line 183: `echo ""` - Creates double blank line when combined with line 181
- Line 233: `echo ""` - Creates double blank line when combined with line 231

**bootstrap.sh:**
- Line 103: Missing color formatting in standalone mode prompt

**03a_opencode.sh:**
- Line 209: Missing blank line before `log_step` at line 210

**03d_pi.sh:**
- Line 170: Missing blank line before `log_step` at line 171

**02_litellm.sh:**
- Line 56: Missing blank line before port check warnings starting at line 57

### 2. Inconsistent Dry Run Completion Messages

**03a_opencode.sh line 138:**
- `log_step "Dry run complete — no changes made"`

**03b_codex.sh line 113:**
- `log_ok "Dry run complete — no changes made"`

**03c_claude_code.sh line 112:**
- `log_ok "Dry run complete — no changes made"`

**03d_pi.sh line 115:**
- `log_step "Dry run complete — no changes made"`

### 3. Mixed Prompt Styles in bootstrap.sh

**Line 205:**
```bash
echo -ne "  ${C_BOLD}Choice${C_RESET} ${C_DIM}[1]${C_RESET}: "
```
Should use `prompt_input` for consistency.

**Line 103 (standalone mode):**
```bash
echo "  git pull failed. Reset to origin/main? [y/N]: "
```
Missing color formatting.

### 4. Missing Context in Prompts

**01_env.sh line 184:**
```bash
MAAS_API_KEY=$(prompt_input "Enter Huawei MaaS API key (region ap-southeast-1)" "")
```
Should show actual base URL: `$MAAS_API_BASE`

**03a_opencode.sh line 147:**
```bash
HUAWEI_MAAS_API_KEY=$(prompt_input "Huawei MaaS API key (or press Enter to skip direct provider)" "")
```
Could be clearer about optional nature.

### 5. Validation Output Formatting

**04_validate.sh line 758:**
Custom border instead of using `log_step` format.

## Detailed Fix Recommendations

### File: scripts/01_env.sh

**Issue 1:** Double blank lines in interactive loops
- Line 183: Remove `echo ""` (keep line 181 only)
- Line 233: Remove `echo ""` (keep line 231 only)

**Issue 2:** Prompt missing context
- Line 184: Change to:
  ```bash
  MAAS_API_KEY=$(prompt_input "Enter Huawei MaaS API key for $MAAS_API_BASE" "")
  ```

### File: scripts/bootstrap.sh

**Issue 1:** Inconsistent prompt style
- Line 205: Replace with:
  ```bash
  existing_choice=$(prompt_input "Choice" "1")
  ```

**Issue 2:** Missing colors in standalone mode
- Line 103: Change to:
  ```bash
  echo -ne "  ${C_BOLD}git pull failed. Reset to origin/main?${C_RESET} ${C_DIM}[y/N]${C_RESET}: "
  ```

### File: scripts/03a_opencode.sh

**Issue 1:** Missing blank line
- Line 209: Add `echo ""` before line 210

**Issue 2:** Unclear prompt
- Line 147: Change to:
  ```bash
  HUAWEI_MAAS_API_KEY=$(prompt_input "Huawei MaaS API key for direct provider (optional, press Enter to skip)" "")
  ```

### File: scripts/03b_codex.sh

**Issue 1:** Inconsistent dry run message
- Line 113: Change to:
  ```bash
  log_info "Dry run complete — no changes made"
  ```

### File: scripts/03c_claude_code.sh

**Issue 1:** Inconsistent dry run message
- Line 112: Change to:
  ```bash
  log_info "Dry run complete — no changes made"
  ```

### File: scripts/03d_pi.sh

**Issue 1:** Missing blank line
- Line 170: Add `echo ""` before line 171

### File: scripts/02_litellm.sh

**Issue 1:** Missing blank line
- Line 56: Add `echo ""` before line 57

### File: scripts/04_validate.sh

**Issue 1:** Custom border instead of standard format
- Line 758: Consider using `log_step` style or create consistent border function

## Consistency Improvements

### 1. Create Standard Dry Run Message Function
Could add to `common.sh`:
```bash
log_dry_run() {
    [ "$DRY_RUN" = true ] && log_warn "DRY RUN — no changes will be made"
}
```

### 2. Create Standard Completion Message
All 03* scripts could use:
```bash
log_step "$TOOL installation complete"
```

### 3. Standardize Menu Prompts
Create `prompt_choice` function in `common.sh`:
```bash
prompt_choice() {
    local question="$1"
    local default="${2:-}"
    local options=("${@:3}")
    # Display numbered options and prompt for choice
}
```

## Color Usage Analysis

### Consistent Colors:
- `log_step`: `C_BOLD + C_CYAN` (bold cyan)
- `log_ok`: `C_GREEN` (green ✓)
- `log_info`: `C_BLUE` (blue →)
- `log_warn`: `C_YELLOW` (yellow ⚠)
- `log_error`: `C_RED` (red ✗)
- `log_dim`: `C_DIM` (dim)
- Prompts: `C_BOLD + C_CYAN` for `?`, `C_BOLD` for question, `C_DIM` for hint

### Issues Found:
- bootstrap.sh standalone mode inconsistent color usage
- 04_validate.sh uses custom yellow border instead of standard formatting

## Readability Assessment

### Good Practices:
1. Consistent indentation (2 spaces)
2. Color coding for different message types
3. Clear section headers with `log_step`
4. Proper use of stderr for prompts
5. Masked keys for security

### Areas for Improvement:
1. Some prompts lack context (which API endpoint)
2. Inconsistent spacing between sections
3. Mixed prompt styles in bootstrap.sh
4. Inconsistent dry run completion messages

## Priority Fixes

### High Priority:
1. **01_env.sh lines 183, 233** - Remove duplicate `echo ""`
2. **bootstrap.sh line 205** - Use `prompt_input` instead of custom echo
3. **03b/c dry run messages** - Standardize to `log_info`

### Medium Priority:
4. **bootstrap.sh line 103** - Add colors to standalone prompt
5. **01_env.sh line 184** - Add base URL to prompt
6. **Missing blank lines** in 03a, 03d, 02_litellm

### Low Priority:
7. **04_validate.sh border** - Consider standardization
8. **Create helper functions** for dry run and choice prompts