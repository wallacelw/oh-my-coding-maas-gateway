# Interactive Prompts and Output Formatting Review

## Overview
Review of all install scripts for consistency in interactive prompts, output formatting, spacing, indentation, and color usage.

## Key Findings

### ✅ Strengths
1. **Color consistency**: All scripts use the same color scheme from `common.sh`
2. **Logging consistency**: `log_*` functions used consistently across all scripts
3. **Prompt functions**: `prompt_yesno`, `prompt_input`, `prompt_password` used consistently (except standalone mode)
4. **Error handling**: Consistent use of `log_error` and `log_warn`
5. **Dry run notices**: Consistent pattern across all scripts

### ⚠️ Issues Found

#### 1. Inconsistent Spacing
- **01_env.sh lines 183, 233**: Double blank lines in interactive loops
- **03a_opencode.sh line 209**: Missing blank line before `log_step`
- **03d_pi.sh line 170**: Missing blank line before `log_step`
- **02_litellm.sh line 56**: Missing blank line before port warnings

#### 2. Inconsistent Dry Run Messages
- 03a_opencode.sh: `log_step "Dry run complete — no changes made"`
- 03b_codex.sh: `log_ok "Dry run complete — no changes made"`
- 03c_claude_code.sh: `log_ok "Dry run complete — no changes made"`
- 03d_pi.sh: `log_step "Dry run complete — no changes made"`

#### 3. Mixed Prompt Styles
- **bootstrap.sh line 205**: Uses custom `echo -ne` instead of `prompt_input`
- **bootstrap.sh line 103**: Missing colors in standalone mode prompt

#### 4. Missing Context in Prompts
- **01_env.sh line 184**: Doesn't show actual API endpoint URL
- **03a_opencode.sh line 147**: Could be clearer about optional nature

## Specific Fixes Needed

### High Priority
1. **01_env.sh lines 183, 233**: Remove duplicate `echo ""`
2. **bootstrap.sh line 205**: Use `prompt_input "Choice" "1"`
3. **03b/c dry run messages**: Change to `log_info "Dry run complete — no changes made"`

### Medium Priority
4. **bootstrap.sh line 103**: Add colors: `echo -ne "  ${C_BOLD}git pull failed. Reset to origin/main?${C_RESET} ${C_DIM}[y/N]${C_RESET}: "`
5. **01_env.sh line 184**: Show URL: `"Enter Huawei MaaS API key for $MAAS_API_BASE"`
6. **Missing blank lines**: Add before completions in 03a, 03d, and before port warnings in 02_litellm

### Low Priority
7. **04_validate.sh border**: Consider standardizing with `log_step` style
8. **Create helper functions**: For dry run notices and choice prompts

## Recommendations

1. **Add to common.sh**:
   ```bash
   log_dry_run() {
       [ "${DRY_RUN:-false}" = true ] && log_warn "DRY RUN — no changes will be made"
   }
   ```

2. **Standardize completion pattern**:
   ```bash
   echo ""
   log_step "Tool installation complete"
   log_dim "Additional info..."
   ```

3. **Always use `prompt_*` functions** instead of manual `echo`/`read`

4. **Maintain consistent spacing**:
   - Blank line before `log_step` sections
   - Blank line after `log_info` groups
   - No double blank lines in loops

## Impact
These are minor consistency issues that don't affect functionality but improve user experience and maintainability. The fixes are straightforward and low-risk.