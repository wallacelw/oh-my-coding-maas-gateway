# Interactive Prompts and Output Formatting Review

## Summary

Review of all install scripts for consistency in interactive prompts, output formatting, spacing, indentation, and color usage.

## 1. Common Helper Functions (scripts/helpers/common.sh)

### Prompt Functions Analysis

**prompt_yesno()** (lines 172-187):
- Format: `  ? Question [Y/n] `
- Colors: Cyan bold `?`, bold question, dim hint
- Consistent with `prompt_input()` and `prompt_password()`

**prompt_input()** (lines 191-202):
- Format: `  ? Question (default: value): `
- Colors: Cyan bold `?`, bold question, dim default hint
- Consistent with `prompt_yesno()`

**prompt_password()** (lines 209-235):
- Format: 
  ```
    ? Label
      Auto-generated: masked_key
  ```
- Colors: Cyan bold `?`, bold label, dim auto-generated line
- Additional prompt: `  Enter custom value (must start with '$prefix'): ` or `  Enter custom value: `
- Uses `prompt_yesno()` internally with format: `  ? Use auto-generated value? [Y/n] `

**Issues found:**
1. Line 179: `prompt_yesno` uses `>&2` for the prompt but reads from `/dev/tty`
2. Line 198: `prompt_input` uses `>&2` for the prompt
3. Line 214: `prompt_password` uses `>&2` for the initial prompt
4. Line 216: Uses `prompt_yesno` which also outputs to stderr
5. Lines 222, 224: Custom value prompt uses `>&2`
- **Consistency**: All prompts write to stderr (good), all read from `/dev/tty` (good)

### Logging Functions Analysis

**log_step()** (line 129):
- Format: `\n━━━ title ━━━` (bold cyan)
- Consistent across all scripts

**log_ok()** (line 133):
- Format: `  ✓ message` (green)
- Consistent across all scripts

**log_info()** (line 137):
- Format: `  → message` (blue)
- Consistent across all scripts

**log_warn()** (line 141):
- Format: `  ⚠ message` (yellow, stderr)
- Consistent across all scripts

**log_error()** (line 145):
- Format: `  ✗ message` (red, stderr)
- Consistent across all scripts

**log_dim()** (line 149):
- Format: `  message` (dim)
- Consistent across all scripts

**log_action()** (line 155):
- Format: `  [tag] message` (dim tag)
- Used in `run_filtered()` for subprocess output

## 2. scripts/01_env.sh

### Prompts:
1. Line 144: `prompt_password "LITELLM_MASTER_KEY (proxy auth)" "$AUTO_MASTER_KEY" "sk-"`
   - Shows auto-generated key masked
   - Has prefix validation for "sk-"
   - No blank line after? (Actually line 145 has `echo ""`)

2. Line 146: `prompt_password "LITELLM_SALT_KEY (virtual key signing)" "$AUTO_SALT_KEY"`
   - No prefix validation

3. Line 148: `prompt_password "DB_PASSWORD (PostgreSQL)" "$AUTO_DB_PASSWORD"`
   - No prefix validation

4. Line 150: `prompt_password "GRAFANA_ADMIN_PASSWORD" "$AUTO_GRAFANA_PASSWORD"`
   - No prefix validation

5. Line 153: `prompt_input "PROMETHEUS_RETENTION (e.g. 30d, 14d, 7d)" "$AUTO_PROM_RETENTION"`
   - Has default value hint

6. Line 184: `prompt_input "Enter Huawei MaaS API key (region ap-southeast-1)" ""`
   - No default value (empty string)
   - Uses while loop for validation

7. Line 235: `prompt_input "MaaS API key #$EXTRA_NUM (or press Enter to finish)" ""`
   - No default value
   - Loop for multiple keys

### Issues:
1. **Inconsistent spacing**: 
   - Lines 144-154: Each `prompt_password` followed by `echo ""` (good)
   - Line 181: `echo ""` before while loop (good)
   - Line 183: `echo ""` inside while loop (creates double blank line on retry)
   - Line 227: `echo ""` before extra keys section (good)
   - Line 233: `echo ""` inside while loop (creates double blank line)

2. **Prompt context**: 
   - Line 184: Prompt says "region ap-southeast-1" but doesn't show the actual base URL
   - Could be clearer: "Enter Huawei MaaS API key for $MAAS_API_BASE"

3. **Validation feedback**:
   - Lines 192-194: Good color-coded validation feedback
   - Lines 240-243: Good color-coded validation feedback for extra keys

4. **Summary output** (lines 345-353):
   - Uses `log_dim` for key/value pairs
   - Good spacing with `echo ""` between items
   - Shows masked keys appropriately

## 3. scripts/bootstrap.sh

### Prompts:
1. Line 69 (standalone mode): `echo -n "  Where to install? [$default_parent]: "`
   - Not using `prompt_input` (standalone mode before helpers loaded)
   - Uses `read -r install_parent < /dev/tty`
   - No colors in standalone mode

2. Line 82 (standalone mode): `echo -ne "  ${C_BOLD}Choice${C_RESET} ${C_DIM}[1]${C_RESET}: "`
   - Custom prompt with colors (standalone mode)

3. Line 103 (standalone mode): `echo "  git pull failed. Reset to origin/main? [y/N]: "`
   - Plain echo, no colors

4. Line 192: `prompt_input "Install directory (project will be in \$INSTALL_DIR/$REPO_NAME)" "$current_parent"`
   - Uses `prompt_input` with default
   - Good descriptive text

5. Line 205: `echo -ne "  ${C_BOLD}Choice${C_RESET} ${C_DIM}[1]${C_RESET}: "`
   - Custom prompt (not using `prompt_input`)
   - Inconsistent with other prompts

6. Lines 272-275: `prompt_yesno "Install opencode?" n` (and others)
   - Consistent usage
   - All default to "n" for custom selection

7. Line 322: `prompt_yesno "Proceed with this selection?" y`
   - Default "y" for final confirmation

### Issues:
1. **Mixed prompt styles**:
   - Standalone mode (lines 69, 82, 103) uses custom `echo -n`/`echo -ne` with manual color codes
   - Main mode uses `prompt_input`/`prompt_yesno` functions
   - Line 205 uses custom prompt instead of `prompt_input`

2. **Color inconsistency in standalone mode**:
   - Lines 80-81: Uses `C_BOLD`, `C_RESET`, `C_DIM` for menu
   - Line 82: Uses same for prompt
   - Line 103: No colors at all

3. **Menu formatting**:
   - Lines 253-260: Menu uses `echo -e` with `C_BOLD`, `C_DIM`
   - Good visual hierarchy
   - Line 260: Prompt uses same style as line 82

4. **Scope display** (lines 289-293):
   - Uses `printf` with `C_DIM` and `C_GREEN`/`C_DIM`
   - Good alignment

5. **Prerequisite summary** (lines 310-317):
   - Uses `printf` with `C_DIM`
   - Good alignment

6. **Final summary** (lines 409-435):
   - Uses `printf` with `C_DIM` for key/value pairs
   - Good alignment
   - Lines 439-442: Uses `printf` with `C_DIM` and `C_CYAN` for commands

## 4. scripts/02_litellm.sh

### No interactive prompts
- Uses only logging functions
- Good consistent logging throughout

### Issues:
1. Line 58: `log_warn "Port $port is already in use. Docker Compose may fail."`
   - No blank line before/after port check warnings

2. Lines 196-208: Effective capacity display
   - Uses `log_info` then `log_dim` for each model
   - Good indentation

3. Line 222: `log_warn` for unreachable endpoint
4. Line 239: `log_warn` for restart failure
5. Line 247: `log_info` for waiting message
6. Line 260: `log_error` for timeout

## 5. scripts/03a_opencode.sh

### Prompts:
1. Line 147: `prompt_input "Huawei MaaS API key (or press Enter to skip direct provider)" ""`
   - Only prompt in this script
   - Good descriptive text

### Issues:
1. Line 49: `[ "$DRY_RUN" = true ] && log_warn "DRY RUN — no changes will be made"`
   - Consistent with other 03* scripts

2. Line 210: `log_step "opencode installation complete"`
   - No blank line before
   - Lines 211-212: `log_dim` for preset info

## 6. scripts/03b_codex.sh

### No interactive prompts
- Uses only logging functions

### Issues:
1. Line 44: `[ "$DRY_RUN" = true ] && log_warn "DRY RUN — no changes will be made"`
   - Consistent with 03a

2. Line 113: `log_ok "Dry run complete — no changes made"`
   - Different message than 03a (line 138: `log_step "Dry run complete — no changes made"`)

3. Line 158: `echo ""` before completion message
4. Lines 159-161: Completion messages with `log_ok` and `log_info`

## 7. scripts/03c_claude_code.sh

### No interactive prompts
- Uses only logging functions

### Issues:
1. Line 43: `[ "$DRY_RUN" = true ] && log_warn "DRY RUN — no changes will be made"`
   - Consistent

2. Line 112: `log_ok "Dry run complete — no changes made"`
   - Same as 03b, different from 03a

3. Line 183: `echo ""` before completion message
4. Lines 184-186: Completion messages with `log_ok` and `log_info`

## 8. scripts/03d_pi.sh

### No interactive prompts
- Uses only logging functions

### Issues:
1. Line 44: `[ "$DRY_RUN" = true ] && log_warn "DRY RUN — no changes will be made"`
   - Consistent

2. Line 115: `log_step "Dry run complete — no changes made"`
   - Same as 03a, different from 03b/03c

3. Lines 171-173: Completion messages with `log_step` and `log_dim`

## 9. scripts/04_validate.sh

### No interactive prompts
- Uses logging functions via wrapper functions: `pass()`, `fail()`, `warn()`, `skip()`

### Issues:
1. Line 127: `log_step` with project name
2. Line 128: `log_dim` for dry run notice
3. Sections A-F: Each starts with `log_step` and has consistent structure
4. Line 758: Custom border with `C_YELLOW`
5. Lines 759-765: Summary with color-coded counts

## 10. scripts/uninstall.sh

### Prompts:
1. Line 188: `prompt_yesno "Proceed with uninstall?" n`
   - Default "n" for safety

## Key Findings

### Strengths:
1. **Color consistency**: All scripts use the same color scheme from `common.sh`
2. **Logging consistency**: `log_*` functions used consistently across all scripts
3. **Prompt functions**: `prompt_yesno`, `prompt_input`, `prompt_password` used consistently (except standalone mode in bootstrap.sh)
4. **Error handling**: `log_error` for errors, `log_warn` for warnings
5. **Dry run notices**: Consistent `[ "$DRY_RUN" = true ] && log_warn "DRY RUN — no changes will be made"`

### Issues:

#### 1. Inconsistent Spacing
- **01_env.sh**: 
  - Lines 183, 233: `echo ""` inside while loops creates double blank lines on retry
  - Should be `echo` without arguments or remove one `echo ""`
  
- **bootstrap.sh**:
  - Line 285: `echo ""` before scope display (good)
  - Line 296: `log_dim` then `echo ""` (good)
  - Line 321: `echo ""` before confirmation (good)

- **03* scripts**:
  - 03a: Line 210: `log_step` without preceding blank line
  - 03b: Line 158: `echo ""` before completion (consistent)
  - 03c: Line 183: `echo ""` before completion (consistent)
  - 03d: Line 171: No blank line before `log_step` completion

#### 2. Inconsistent Dry Run Completion Messages
- 03a_opencode.sh (line 138): `log_step "Dry run complete — no changes made"`
- 03b_codex.sh (line 113): `log_ok "Dry run complete — no changes made"`
- 03c_claude_code.sh (line 112): `log_ok "Dry run complete — no changes made"`
- 03d_pi.sh (line 115): `log_step "Dry run complete — no changes made"`

#### 3. Mixed Prompt Styles in bootstrap.sh
- Standalone mode uses manual `echo -n`/`echo -ne` with color codes
- Main mode uses `prompt_input`/`prompt_yesno`
- Line 205 uses custom prompt instead of `prompt_input`

#### 4. Missing Context in Some Prompts
- 01_env.sh line 184: "Enter Huawei MaaS API key (region ap-southeast-1)" 
  - Could show actual base URL: `$MAAS_API_BASE`
  
- 03a_opencode.sh line 147: "Huawei MaaS API key (or press Enter to skip direct provider)"
  - Could mention this is optional for direct provider fallback

#### 5. Inconsistent Menu Numbering
- bootstrap.sh lines 80-81 (standalone): Uses `1)` and `2)` 
- bootstrap.sh lines 202-203 (main): Uses `1)` and `2)`
- bootstrap.sh lines 253-259: Uses `1)` through `7)`
- All consistent with `C_BOLD` for numbers

#### 6. Validation Output Formatting
- 04_validate.sh uses custom border `══════════════════════════════════════════════════════`
- Other scripts use `log_step` with `━━━ title ━━━`
- Could be standardized

## Recommendations

### 1. Fix Spacing Issues
- **01_env.sh**: Remove duplicate `echo ""` inside while loops (lines 183, 233)
- **03a_opencode.sh**: Add blank line before `log_step "opencode installation complete"` (line 210)
- **03d_pi.sh**: Add blank line before `log_step "Pi installation complete"` (line 171)

### 2. Standardize Dry Run Messages
- Use `log_info "Dry run complete — no changes made"` consistently
- Or use `log_dim` for less prominence

### 3. Standardize bootstrap.sh Prompts
- Update line 205 to use `prompt_input` with default "1"
- Or create a `prompt_choice` function for numbered menus

### 4. Improve Prompt Context
- 01_env.sh line 184: Show base URL: `"Enter Huawei MaaS API key for $MAAS_API_BASE"`
- 03a_opencode.sh line 147: Clarify: `"Huawei MaaS API key for direct provider (optional, press Enter to skip)"`

### 5. Standardize Validation Border
- 04_validate.sh line 758: Use `log_step` style or create `log_border` function
- Or keep as-is since it's only in validation summary

### 6. Add Missing Blank Lines
- 02_litellm.sh line 57: Add blank line before port check warnings
- 03a_opencode.sh line 210: Add blank line before completion `log_step`

### 7. Color Consistency in Standalone Mode
- bootstrap.sh line 103: Add colors to "git pull failed" prompt
- Or use `prompt_yesno` if helpers were loaded earlier

## Specific Line Fixes

### 01_env.sh
- Line 183: Remove `echo ""` (already have blank line at 181)
- Line 233: Remove `echo ""` (already have blank line at 231)
- Line 184: Change prompt to show URL: `"Enter Huawei MaaS API key for $MAAS_API_BASE"`

### bootstrap.sh
- Line 205: Replace with `prompt_input "Choice" "1"`
- Line 103: Add colors: `echo -ne "  ${C_BOLD}git pull failed. Reset to origin/main?${C_RESET} ${C_DIM}[y/N]${C_RESET}: "`

### 03a_opencode.sh
- Line 209: Add `echo ""` before line 210
- Line 147: Improve prompt text

### 03b_codex.sh
- Line 113: Change to `log_info "Dry run complete — no changes made"`

### 03c_claude_code.sh
- Line 112: Change to `log_info "Dry run complete — no changes made"`

### 03d_pi.sh
- Line 170: Add `echo ""` before line 171

### 02_litellm.sh
- Line 56: Add `echo ""` before line 57

## Conclusion

Overall good consistency with minor issues in spacing, dry run messages, and prompt styles. The logging framework is well-implemented and used consistently. The main improvements needed are in spacing consistency and standardizing a few message formats.