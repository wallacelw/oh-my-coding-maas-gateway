# AGENTS.md — Development Rules for Coding Agents

## Workflow

1. Make changes.
2. Validate end-to-end from multiple perspectives (see below).
3. Quality pass: spawn a fresh subagent to review all changes (see below).
4. Commit with a clear message (see below).
5. Push: `git push origin main`.
6. Repeat.

**Always commit and push after completing a unit of work.** Do not accumulate
multiple unrelated changes in one commit. Do not leave uncommitted changes.

## End-to-End Validation

Before committing, validate the change from **all** relevant perspectives:

1. **Script validation:** Run `./scripts/04_validate.sh` (or
   `--litellm-only` / `--opencode-only` / `--skip-*` as appropriate).
   Must pass (or fail only on expected checks like placeholder MaaS key).

2. **Cross-file consistency:** If you changed one file, check every file
   that references it:
   - Changed a script? Check INSTALLATION.md pipeline/per-script tables,
     SKILL.md steps, REFERENCE.md script table.
   - Changed a config template? Check the generated config, validation
     checks, and CHANGELOG.
   - Changed presets? Check REFERENCE.md agent→model table, CHANGELOG.
   - Changed ports/services? Check docker-compose.yml, INSTALLATION.md
     per-script details, REFERENCE.md endpoints, .githooks/pre-commit.
   - Changed env vars? Check configs/.env.template, 01_env.sh, bootstrap.sh,
     docker-compose.yml, REFERENCE.md Key Contract table,
     INSTALLATION.md env-var table.

3. **Documentation accuracy:** Read the affected documentation sections
   and verify they match the actual code output. Summaries, tables, and
   examples should reflect current behavior — not stale descriptions.

4. **Edge cases:** Consider:
   - Interactive mode vs env-var override (HUAWEI_MAAS_API_KEY + --tool=)
   - `--tool=` mode variants (litellm, opencode, codex, claude, custom combos)
   - `--litellm-only` vs full mode (on 04_validate.sh)
   - `--dry-run` mode
   - Idempotent re-run (existing .env, running containers)
    - Upgrade path (existing installation, missing vars)

## Quality Pass

After validation passes, spawn a **fresh `@oracle` session** (new session,
no prior context) to do a thorough quality pass through all changes. Oracle
reviews only the diff and changed files — not the conversation history —
ensuring an independent, unbiased review.

### Why fresh context

A subagent with prior context knows what was *intended* and may overlook
issues a fresh reviewer would catch. A new session reviews only what the
code actually does, not what it was supposed to do.

### Process

1. Spawn a fresh `@oracle` with the diff (`git diff`) and a one-sentence
   summary of what changed. Oracle reviews without any prior context.
2. Oracle reports findings (HIGH / MEDIUM / LOW).
3. The same `@fixer` session uses oracle's findings to fix HIGH and
   MEDIUM issues.
4. Re-validate: `./scripts/04_validate.sh`.
5. LOW findings may be deferred to a follow-up.
6. Commit only after fixes are validated.

### Review for

- **Bugs:**
  - Logic errors (wrong variable, inverted condition, off-by-one)
  - Unhandled edge cases (empty input, missing files, non-zero exits)
  - Race conditions (concurrent access, ordering dependencies)
  - Resource leaks (unclosed handles, orphaned processes, temp files)

- **Error handling:**
  - Failures degrade gracefully, not just crash
  - Error messages are actionable (tell user how to fix)
  - Exit codes correct (0=success, non-zero=failure)
  - Cleanup runs on failure (trap handlers, finally blocks)

- **Security:**
  - No secrets in logs, process list, or error messages
  - User input validated and sanitized
  - File permissions appropriate (not world-readable for secrets)
  - No command injection (quoted variables, no eval on user input)

- **Simplicity:**
  - No over-engineering (YAGNI)
  - No unnecessary abstractions or indirection
  - Dead code removed
  - Complex logic has explanatory comments

- **Maintainability:**
  - Functions do one thing (single responsibility)
  - No magic numbers that should be configurable
  - Dependencies are explicit, not hidden
  - Changes don't require touching unrelated code

- **Modularity:**
  - Clear separation of concerns
  - Shared logic extracted into reusable helpers
  - No circular dependencies
  - Modules can be tested independently

- **Consistency:**
  - Naming conventions followed throughout
  - Style alignment (indentation, quoting, formatting)
  - Cross-file references valid (names, paths, flags)
  - Patterns match existing codebase conventions

- **Quality of life:**
  - Output formatted consistently (alignment, colors, spacing)
  - Dry-run/preview mode accurate
  - Help text matches actual flags and behavior
  - Interactive prompts have sensible defaults

- **Documentation:**
  - Docs match current behavior, not stale descriptions
  - Examples are correct and runnable
  - No duplication across docs (each topic documented once)
  - Text is direct and objective

- **Stale references:**
  - No references to removed files, models, or flags
  - Version numbers current
  - Config values match actual defaults
  - Comments match code (not outdated TODOs)

- **Performance:**
  - No redundant calls or repeated parsing
  - No blocking operations where async would work
  - Startup/shutdown time reasonable
  - Resource usage proportional to workload

- **Backwards compatibility:**
  - No breaking changes without migration path
  - Deprecated features have upgrade instructions
  - Config format backward-compatible
  - Upgrade path tested (old → new version)

### When to skip

Trivial changes only (one-line typo, doc-only edit with no code impact).
When in doubt, run the quality pass.

## Commit Messages

Use imperative mood, capitalized first word, no trailing period:

```
Add Prometheus retention validation
Fix duplicate key count message in agent mode
Update agent preset model assignments based on benchmarks
```

For conventional commit style (optional but encouraged):

```
feat: add Prometheus + Grafana observability stack
fix: resolve datasource UID mismatch in Grafana dashboard
docs: sync SKILL.md with observability stack changes
```

Multi-line messages: first line is the summary (≤72 chars), blank line,
then body with `-` bullets for details:

```
Fix bugs found in end-to-end review

- bootstrap.sh: duplicate key count message in agent mode
- 04_validate.sh: --litellm-only --opencode-only silent no-op
- helpers/keys.sh: empty duration display
```

Note: `04_validate.sh` uses `--xxx-only` flags (still valid). `bootstrap.sh`
uses `--tool=` flags.

## Git Author

Before committing, verify the git author matches the GitHub account:

```bash
git config user.name   # must match gh auth account
git config user.email  # must match gh auth account email
```

If they don't match, fix the global config (not local):

```bash
git config --global user.name  "$(gh api user --jq .login)"
git config --global user.email "$(gh api user/emails --jq '.[0].email')"
```

Never set a local `user.name`/`user.email` that differs from the global
config. If a local override exists, remove it:

```bash
git config --local --unset user.name
git config --local --unset user.email
```

## Versioning

This project uses semantic versioning (`MAJOR.MINOR.PATCH`):

- **MAJOR** — big refactoring, architecture changes, breaking changes
- **MINOR** — new features, new components, significant behavioral changes
- **PATCH** — bug fixes, error corrections, documentation fixes

### Version bumps (always)

Every unit of work gets a version bump for git-level tracking and rollback:

1. Bump the version in `VERSION`.
2. Add a `CHANGELOG.md` entry.
3. Commit and push.

This applies to **all** changes, including trivial fixes and doc-only
edits. The version bump is the progress signal — it does not require a
GitHub release or tag.

### GitHub releases (milestones only)

Create a GitHub release with `gh release create` only for **meaningful
milestones**:

- MINOR versions (new features, new components)
- Significant PATCH clusters (security hardening, multi-bug fix rounds)
- User-visible behavior changes worth announcing

Do **not** create a release or tag for routine PATCH fixes (doc-only,
config tweaks, trivial bug fixes). The `VERSION` bump + `CHANGELOG` entry
is sufficient — git history provides rollback.

### Batching

Batch related changes into one version bump instead of releasing each
incremental step. For example, a dashboard iteration across 10 commits
should be one CHANGELOG entry and one version bump, not 10 separate
releases.

## Never Commit

- `.env` — contains secrets (blocked by .gitignore + pre-commit hook)
- `configs/litellm/config.yaml` — auto-generated from `.env`
- API keys, passwords, tokens, or any secret material
- Backup files (`*.bak.*`)

## Before Committing

- Check `git status` — only stage intended files.
- Check `git diff --cached` — review what you're about to commit.
- Run the full End-to-End Validation section above — not just one perspective.
- All changes must be validated before pushing. No exceptions.

## Code Style

- Shell scripts: `set -euo pipefail`, 2-space indent, snake_case.
- YAML: 2-space indent, double quotes for strings with special chars.
- JSON: 2-space indent, no trailing commas.
- Markdown: 2-space indent for nested lists, sentences end with period.

## CLI UX Standards

The install pipeline is the primary user interface. Keep it clean,
consistent, and readable. These standards apply to ALL scripts.

### Interactive Prompts

- **Use `is_interactive()`, never `[ -t 0 ]`.** `is_interactive`
  checks `/dev/tty` (controlling terminal), not stdin. Under
  `curl | bash`, stdin is the curl pipe — `[ -t 0 ]` is always
  false, breaking every prompt. `is_interactive` works because
  `/dev/tty` is still the terminal.
- **All prompts read from `/dev/tty`**, not stdin. This is already
  handled in `prompt_yesno`, `prompt_input`, `prompt_password`.
- **Blank line before each prompt.** Add `echo ""` before every
  `prompt_*` call so each prompt is visually separated from prior
  output. This includes re-prompts inside loops.
- **Case-insensitive yes/no.** `y`, `Y`, `yes`, `YES` → yes;
  `n`, `N`, `no`, `NO` → no. The `prompt_yesno` function handles
  this via `[Yy]*` / `[Nn]*` case patterns.
- **Uppercase letter = default.** `[Y/n]` → Enter defaults to yes;
  `[y/N]` → Enter defaults to no. Always show the hint.
- **Validate at prompt time.** When a value has a format requirement
  (e.g. `sk-` prefix) or can be tested against an API (e.g. MaaS
  key), validate immediately and re-prompt on failure. Do not defer
  to a later validation step. Use `prompt_password` with the `prefix`
  arg for format checks.
- **`set -e` + non-zero returns.** When calling a function that
  returns non-zero inside a `set -e` script, use
  `cmd && rc=0 || rc=$?` to capture the exit code without
  triggering `set -e` termination.

### Output Formatting

- **`log_step`** — section headers (green box-drawing `┌── Title ──┐`). Each step
  script prints its own header. Bootstrap must NOT also print it
  (causes duplicate headers). Bootstrap only prints headers in
  `--dry-run` mode (when the script doesn't run).
- **`log_ok` / `log_info` / `log_warn` / `log_error` / `log_dim`** —
  use consistently: ✓ success, → info, ⚠ warning, ✗ error, dim
  secondary detail. Never use raw `echo` for status lines.
- **Alignment.** Use `printf "  ${C_DIM}%-Ns${C_RESET} %s\n"` for
  label-value pairs in summaries and scope displays. Never hardcode
  spaces for alignment — they drift when labels change.
- **Blank lines between sections.** Every `log_step` already adds a
  leading `\n`. Add `echo ""` between grouped output items (env vars,
  scope lines, prerequisite lists) for readability.
- **Dynamic banners.** When drawing box-drawing characters, size
  them to the content width, not hardcoded. Use a loop to build the
  border string.
- **Dry-run paths.** Show relative paths (`scripts/02_litellm.sh`)
  not absolute, for consistency across environments.
- **Color setup before sourcing.** In standalone mode (before
  `common.sh` is sourced), define `C_BOLD`, `C_RESET`, etc. inline
  if colors are needed. Match `common.sh`'s logic.

### Menu Design

- **Numbered options** with `C_BOLD` number, plain text description,
  `C_DIM` for default hint: `  1) Description [default]`
- **Comma-separated combos.** Allow `1,2,6` syntax for multi-select.
- **Confirm selection.** After showing the full scope/prereq
  summary, prompt `Proceed with this selection? [Y/n]` before
  starting the pipeline.
- **Existing install detection.** When an existing install is found,
  offer: pull updates (preserve) vs fresh install (uninstall +
  reclone). Default to pull updates.

### Summary Sections

- **Single completion line.** Use `✓ Bootstrap complete` or
  `⚠ Bootstrap completed with validation failures` — not a
  hardcoded box drawing.
- **Label-value pairs.** Use `printf %-20s` for labels in the
  final summary. Consistent column alignment.
- **Next steps.** Show how to use each installed tool with the
  exact command. Use `printf %-12s` for tool names.
- **Key rotation tip.** Show a dim tip after install reminding users
  to rotate keys if shared with agents or CI systems.

## Project Structure

```
scripts/          — install pipeline (bootstrap + numbered steps 01-05, 03a-03d)
scripts/helpers/   — shared helper libraries (prereqs, keys, common, models, skills)
configs/          — component configs grouped by service
configs/litellm/   — LiteLLM config, entrypoint, template
configs/prometheus/ — Prometheus config
configs/grafana/   — Grafana dashboards and provisioning
configs/opencode/  — opencode + slim plugin templates
configs/codex/     — Codex CLI config template + model catalog
configs/claude-code/ — Claude Code CLI .env template
root              — INSTALLATION.md, SKILL.md, REFERENCE.md, README.md, CHANGELOG.md, AGENTS.md
```

## When Unsure

- Ask the user before making architectural decisions.
- Ask before changing Docker images, model definitions, or preset assignments.
- Ask before modifying the upgrade path or install procedure.
- Do not guess — clarify first.
