# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.4] - 2026-08-05

### Changed

- **Redesigned model presets based on Huawei MaaS reasoning effort docs** —
  `reasoning_effort` only supports `high` (no `low`/`medium`/`max`). Updated
  all presets to use valid variants only.
- Oracle variant: `max` → `high` (MaaS doesn't support `max`)
- Fixer model: `[glm-5.1, deepseek-v4-flash]` → `deepseek-v4-flash` only
  (glm-5.1 doesn't support `reasoning_effort`; deepseek-v4-flash is faster
  and does support it)
- Core preset explorer: variant `medium` → `low` (consistent with Full)
- Codex model catalog: reasoning levels `[high, max]` → `[high]` for all
  models that support reasoning effort

### Fixed

- REFERENCE.md agent→model table synced with new preset assignments

## [1.4.3] - 2026-08-04

### Changed

- **Grafana upgraded 11.5.2 → 13.1.2** — two major version jump. Dynamic
  dashboards, Git Sync, Grafana Assistant, revamped gauge visualization,
  quick filters, data grouping. File-based provisioning, anonymous auth,
  and Prometheus datasource all work without changes. Health check
  (`/api/health`) still functional despite `/api` path deprecation.

## [1.4.2] - 2026-08-04

### Changed

- **LiteLLM upgraded v1.89.3 → v1.95.0** — Claude Opus 5 support, Rust
  backend for Anthropic messages API, shadcn UI migration, SAML 2.0 SSO,
  cost optimization page, enhanced MCP support, atomic cache increments,
  improved streaming performance. Validation improved from 82/84 to
  83/84 (unhealthy_count warning resolved). WebSocket bridging bug
  workaround retained (uses HTTP SSE via `wire_api = "responses"`).

## [1.4.1] - 2026-08-04

### Changed

- **oh-my-opencode-slim upgraded v2.2.5 → v2.2.9** — removes redundant
  plugin websearch MCP (opencode has built-in), fixes smartfetch CSS
  TUI corruption, improves task reconciliation to prevent self-amplifying
  loops, adds webfetch config for enable/disable and dedicated model,
  guards disabled_* config fields against non-array values, places
  AGENTS.md before orchestrator prompt in system order. No breaking
  changes for this project's configuration.

## [1.4.0] - 2026-08-04

### Changed

- **Prometheus upgraded v3.2.1 → v3.13.2 (LTS)** — security fixes
  (CVE-2025-4673, CVE-2023-45289), 2x faster case-insensitive regex
  matching, 50% reduced heap allocations for WAL decoder, XOR2 encoding
  for better disk compression, native histogram support, experimental
  search API for metric/label discovery. v3.13 is a Long Term Support
  release. Project config fully compatible — no breaking changes apply.

## [1.3.1] - 2026-07-22

### Consolidated release — dashboard overhaul, cache panels, plugin upgrade

Consolidates all changes from v1.2.0–v1.3.0 into a single validated
release. All 38 Grafana panels verified: queries return data,
descriptions match, units consistent, no bugs.

### Added

- **Cache section** — new Grafana dashboard section with 3 panels:
  Provider cache reads (timeseries, tok/min), Cache misses/min
  (timeseries, req/min), Cache hit ratio (stat with threshold
  coloring, one per model).
- **Cache hit ratio panel** — `1 - (sum by (model) (rate(cache_misses)) / sum by (model) (rate(total_requests)))`. Thresholds: red → yellow(10%) → green(30%).

### Changed

- **oh-my-opencode-slim plugin upgraded v2.0.5 → v2.2.5** — custom
  subagent permissions, project-local customization, native
  cmux/kitty multiplexer, Windows path normalization, flatten council
  dispatch, task rejection contracts. No breaking changes.
- **Deployment state panel** — timeseries → state-timeline (colored
  blocks). 0=Healthy (green), 1=Degraded (orange), 2=Outage (red).
- **Cache panel queries** — added `sum by (model)` + `* 60` to match
  token panel pattern (per-minute, grouped by model).
- **Cache panel units** — `short` → `tok/min` / `req/min`.
- **Stat panel thresholds** — added yellow/red to RPS, RPM, TPS, TPM,
  Total cost.
- **Tokens section** — Input, Cached input, Output, Reasoning (4
  panels in one row).
- **Dashboard layout** — 39 panels across 7 sections.
- **Documentation** — INSTALLATION.md, SKILL.md, REFERENCE.md synced
  with 39-panel / 7-section layout.

### Fixed

- **Total Requests undercounting** — query only counted success.
  Fixed to sum success + failure.
- **Cache hit ratio label mismatch** — divided metrics with
  incompatible label sets. Fixed with `sum by (model)` aggregation.
- **Cache panel legendFormat** — escaped braces → `{{model}}`.
- **Gauge panel not rendering** — gauge/bargauge types don't render
  in Grafana 11.5.2. Settled on `stat` with area graph.

## [1.3.0] - 2026-07-22

### Changed

- **Cache hit ratio panel** — settled on `stat` type with area graph
  and threshold coloring. Gauge and bargauge panel types do not render
  in Grafana 11.5.2 (only model names appear, no visual dial/bars).
  The stat panel shows one colored value per model (red → yellow 10% →
  green 30%) with a mini sparkline, distributed horizontally.

## [1.2.9] - 2026-07-22

### Changed

- **Cache hit ratio gauge** — removed "No hits" blue threshold step
  (user request). Restored simple red → yellow(10%) → green(30%)
  thresholds. Gauges distributed horizontally, one per model.

## [1.2.8] - 2026-07-22

### Fixed

- **Cache hit ratio gauge not rendering** — the `mappings` and `noValue`
  fields added in v1.2.5 were incompatible with the gauge panel type
  in Grafana 11.5.2, causing the panel to render blank. Removed both
  fields and replaced the "No hits" indicator with a threshold step
  (blue at 0). Gauge now renders correctly.

## [1.2.7] - 2026-07-22

### Changed

- **New Cache section** — separated cache panels from Tokens into their
  own section. Tokens now shows only Input, Cached input, Output, and
  Reasoning tokens. The Cache section contains Provider cache reads
  (timeseries), Cache misses/min (timeseries), and Cache hit ratio
  (stat, full-width line of per-model values).
- **Cache hit ratio panel type** — converted from `gauge` (not
  rendering in Grafana 11.5.2) to `stat` with area graph and threshold
  coloring. Shows one colored value per model in a horizontal row.

## [1.2.6] - 2026-07-22

### Fixed

- **Cache hit ratio gauge showing "010.10"** — threshold labels were
  enabled, causing threshold values to overlap on the gauge display.
  Disabled `showThresholdLabels`.

### Changed

- **Cache hit ratio gauge layout** — moved to its own full-width row
  (w=24) so the per-model gauges arrange in a 2-column grid instead of
  a single cramped column. Provider cache reads and Cache misses/min
  panels widened to w=12 each.

## [1.2.5] - 2026-07-22

### Changed

- **Cache hit ratio gauge thresholds** — lowered green threshold from
  80% to 30% and yellow from 50% to 10%. Production cache hit ratios
  are typically 10–30%, so 80% green was unrealistic.
- **Cache hit ratio no-data indicator** — value 0 now shows "No hits"
  in blue (distinct from the red/yellow/green threshold scale). Empty
  data shows "No cache activity".

## [1.2.4] - 2026-07-22

### Changed

- **Deployment state panel** — converted from `timeseries` (jagged
  lines for binary data) to `state-timeline` (colored blocks). Values
  mapped to labels: 0=Healthy (green), 1=Degraded (orange), 2=Outage
  (red).

## [1.2.3] - 2026-07-22

### Fixed

- **Cache panel query inconsistency** — cached input tokens, provider
  cache reads, and cache misses were missing `sum by (model)` wrapper
  and `* 60` scaling. Now match the pattern used by Input/Output/
  Reasoning token panels (per-minute, grouped by model).
- **Total Requests panel undercounting** — query only counted
  successful responses. Fixed to sum success + failure responses.
- **Cache panel units** — Cached input tokens and Provider cache reads
  changed from `short` to `tok/min`. Cache misses changed from
  `short` to `req/min`.

### Changed

- **Cache hit ratio panel** — converted from `stat` to `gauge` type
  for better visual communication of percentage.
- **Cache panel titles** — "Provider cache reads/s" → "Provider cache
  reads", "Cache miss rate" → "Cache misses/min" (now per-minute).
- **Stat panel thresholds** — added yellow/red thresholds to RPS,
  RPM, TPS, TPM, and Total cost panels for at-a-glance severity
  indication.

## [1.2.2] - 2026-07-22

### Fixed

- **Cache hit ratio panel showing no data** — the PromQL divided two
  metrics with incompatible label sets, causing vector matching to
  fail. Fixed by aggregating both numerator and denominator with
  `sum by (model)` before division.

## [1.2.1] - 2026-07-22

### Fixed

- **Cache dashboard panels not rendering** — `legendFormat` had escaped
  braces (`\{\{model\}\}`) instead of `{{model}}`, causing Grafana to
  show the literal template instead of the model name. Fixed on all 4
  cache panels.

### Changed

- **Merged cache panels into Tokens section** — removed the separate
  "Cache" row. The Tokens section now shows Input tokens, Cached input
  tokens, Output tokens, and Reasoning tokens in one row, with Provider
  cache reads/s, Cache miss rate, and Cache hit ratio in a second row.
  This lets users compare cached vs uncached tokens at a glance.

## [1.2.0] - 2026-07-21

### Added

- **Cache hit dashboard panels** — new "Cache" section in the Grafana
  dashboard with 4 panels: Cache miss rate, Cached tokens/s, Provider
  cache reads/s, and Cache hit ratio. Visualizes LiteLLM proxy cache
  and provider-side prompt caching effectiveness per model.

### Changed

- **oh-my-opencode-slim plugin upgraded from v2.0.5 to v2.2.5** —
  brings custom subagent permissions, project-local customization,
  native cmux/kitty multiplexer support, Windows path normalization,
  flatten council dispatch, and task rejection contracts. No breaking
  changes for our config template (already uses modern `multiplexer`
  format, no deprecated `fallback.chains` or `council.master*` keys).

## [1.1.6] - 2026-07-16

### Added

- **Non-root warning** — bootstrap now warns when not running as root,
  listing the steps that may fail (apt-get, npm install -g, Docker) and
  showing the recommended sudo oneliner. Non-blocking — the pipeline
  continues regardless.

## [1.1.5] - 2026-07-09

### Fixed

- **bun install fails without unzip** — the bun installer
  (`bun.sh/install`) requires `unzip` to extract the binary, but it was
  never checked. On systems without `unzip`, `prereq_ensure_bun` would
  abort with a cryptic error. Now auto-installs `unzip` via
  `prereq_ensure_apt` before running the bun installer.

## [1.1.4] - 2026-07-07

### Changed

- **macOS/BSD portability** — replaced all `grep -oP`/`grep -qP` (GNU
  PCRE, breaks on macOS/BSD) with portable `sed`/`grep -E` equivalents.
  No impact on Linux compatibility — POSIX `sed` and ERE are universally
  supported.

### Fixed

- **CHANGELOG corrections** — fixed [1.1.3] date (was 2026-07-06,
  should be 2026-07-07). Moved GLM rate-limit entry from [1.1.2] to
  [1.1.1] where it actually shipped (v1.1.2 had no code changes).
- **`resolve_master_key` diagnostic on stdout** — `keys.sh:47`
  `log_info` was going to stdout (regression from v1.1.1). Added `>&2`
  to match the documented contract. No functional impact (no caller
  captures via `$(...)`), but prevents future regressions.

## [1.1.3] - 2026-07-07

### Fixed

- **Uninstall skill scoping** — `uninstall.sh --tool=claude` (or any
  single agent) no longer removes the companion skill from the other
  agents. Skill removal is now scoped to only the agent(s) being
  uninstalled. Previously uninstalling one agent stripped the skill
  from all four.
- **Key-mint stdout pollution** — `mint_or_reuse_key` diagnostics
  (`log_info`/`log_dim`) were going to stdout, polluting the captured
  return value in `VIRTUAL_KEY=$(mint_or_reuse_key ...)` and causing
  key minting to fail in steps 03a–03d. Redirected diagnostics to
  stderr, restoring the documented contract (key on stdout, logs on
  stderr). Regression from v1.1.1 helper-output refactor.

## [1.1.2] - 2026-07-06

### Changed

- **CHANGELOG attribution correction** — moved the GLM rate-limit
  entry from v1.1.0 (where it was incorrectly attributed — the commit
  postdated the v1.1.0 tag) to v1.1.1 (where it first shipped). No
  code changes in this release.

## [1.1.1] - 2026-07-06

### Changed

- **GLM model rate limits updated** — `glm-5`, `glm-5.1`, and `glm-5.2`
  now all use 100 RPM and 1M TPM (was 30 RPM / 500K TPM for glm-5 and
  glm-5.1, and 198K TPM for glm-5.2). Prices and context windows
  unchanged. Updated `helpers/models.sh`,
  `configs/litellm/config.yaml.template`, and REFERENCE.md model table.
- **Standalone bootstrap pre-flight summary** — `curl | bash` opening
  now shows what will be installed, prerequisites, and bound ports
  (4000/9090/3000/5432) before prompting for an install directory.
  Previously showed only a bare header with no context.

### Fixed

- **Helper library output consistency** — `keys.sh` and `prereqs.sh`
  used raw `echo "ERROR:..."` for status output, inconsistent with the
  `log_*` functions used everywhere else. Replaced with
  `log_error`/`log_warn`/`log_info`/`log_dim`. Added `common.sh` source
  guard for standalone robustness. Removed erroneous `set -euo pipefail`
  from `prereqs.sh` (helpers are sourced, not executed).
- **Documentation accuracy** — REFERENCE.md: "Three" → "Four" virtual
  keys (table lists 4). INSTALLATION.md: pipeline "01–06" → "01–05"
  (no step 06); dropped "+ observability" (it is section C). SKILL.md:
  added missing `--virtual-key=`, `--xxx-only`, `--routing-strategy=`
  flags. AGENTS.md: `configs/claude-code/` label → ".env template"
  (no config template exists there).
- **CHANGELOG de-duplication** — removed companion-skill claims
  duplicated between v1.0.0 and v1.1.0 (git history confirms they
  shipped in v1.1.0).

## [1.1.0] - 2026-07-06

### Added

- **Companion skill installation** (`scripts/05_skill.sh`) — after
  validation, bootstrap prompts to install SKILL.md as a skill into each
  detected coding agent. Idempotent, skips agents that already have it.
  `--no-skill` flag to skip.
- **`scripts/install-skill.sh`** — install ANY skill (not just this
  companion) into all detected coding agents. Takes `--name=` and
  `--source=` (local path or URL). Supports `--dry-run`.
- **`helpers/skills.sh`** — install/uninstall helpers for each agent tool.
  All four tools use the same Agent Skills standard (SKILL.md with YAML
  frontmatter): opencode `~/.config/opencode/skills/`, codex
  `~/.codex/skills/`, pi `~/.pi/agent/skills/`, claude `~/.claude/skills/`.
- **SKILL.md redesigned** — operational companion with interactive menu
  (6 options + context-only default):
  1) Health check  2) Validation  3) Upgrade  4) Uninstall
  5) Install skill  6) Mint new keys  (Enter = context only)
  Includes step-by-step instructions for adding MaaS load-balancing keys
  and minting LiteLLM virtual keys.

### Changed

- **README slimmed** (292 → 107 lines) — detailed flags, per-tool usage,
  monitoring, remote access moved to INSTALLATION.md.
- **INSTALLATION.md expanded** — After Install section now includes
  per-tool usage, monitoring, remote access, services table, coding tools
  table, install modes table, companion skill table.
- **Pipeline extended** — 01 → 02 → 03a-03d → 04 → 05 (companion skill).

### Fixed

- **Standalone mode unbound variable** — `version_compare` crashed when
  `PROJECT_VERSION="unknown"` (no VERSION file in curl|bash temp dir).
  Guarded with non-numeric check and early return in `show_version_info`.
- **Claude skill path** — was using legacy `~/.claude/commands/` (slash
  commands, no frontmatter). Now uses `~/.claude/skills/` (Agent Skills
  standard with frontmatter and auto-loading), same as all other tools.
- **curl|bash argument passing** — `bash --` → `bash -s --` in README
  examples (need `-s` to read script from stdin).
- **Stale docs** — uninstall now removes binaries + runtimes (not just
  configs); `log_step` draws green box (not `━━━` lines); `models.sh`
  used by steps 02 and 04 (not 02 and 06).

## [1.0.0] - 2026-07-06

### Added

- **`VERSION` file** — bootstrap reads and displays version in banner and
  summary. Existing-install detection compares local vs installed version,
  showing "Update available" or "up to date" with color-coded arrow.
- **`scripts/uninstall.sh`** — customizable uninstall: remove single agent,
  subset, all agent configs, Docker stack, or everything (including repo).
  Supports `--tool=`, `--docker`, `--repo`, `--all`, `--dry-run`, `--yes`,
  and interactive menu. Removes binaries, runtimes (bun, pi-node), configs,
  and `.bashrc` entries.
- **MaaS API key validation at prompt time** — invalid keys (HTTP 401/403)
  trigger a warning and re-prompt instead of failing later. Applies to
  both the main key and extra load-balancing keys. Unreachable endpoints
  (transient) are accepted with a warning. `sk-` prefix validation via
  `prompt_password` prefix arg.
- **`is_interactive()`** — checks `/dev/tty` (not stdin) so prompts work
  under `curl | bash`. All prompts read from `/dev/tty`.
- **`run_with_spinner()`** — animated spinner for long operations (Docker
  start, apt install, bun install).
- **`log_desc` / `log_done`** — cyan info line before each step, green dim
  completion line after.
- **Prereq explanations** — each prerequisite shows a reason explaining
  what it is and why it's needed, replacing `[system] Installing...`.
- **`refresh_path()`** — adds `~/.opencode/bin`, `~/.bun/bin`,
  `~/.local/bin`, nvm, pi-node paths after install (compensates for
  installers only updating `.bashrc`).
- **Fresh install option** — existing install detection offers pull updates
  (preserve) vs fresh install (uninstall + reclone). Default: pull updates.
- **Port conflict handling** — `02_litellm.sh` detects and stops stale
  containers on required ports; uninstall waits for ports to be freed.
- **Prometheus scrape retry** — C3 check retries 3× with 5s waits.
- **Terminal restart hint** — dim hint before Next steps commands.
- **Conditional security disclaimer** — only shown when `KEYS_FROM_ENV=true`
  (keys passed via env vars, not interactive prompts).
- **Custom toggle defaults** — menu option 7 defaults to `[Y/n]` for all
  tools.
- **AGENTS.md CLI UX Standards** — documented all interactive prompt
  standards, output formatting, menu design, summary sections.

### Changed

- **`log_step`** now draws a bold green box-drawing header (`┌── Title ──┐`)
  instead of `━━━ Title ━━━` lines.
- **Pi installer runs directly** (not through `run_filtered`) — needs TTY
  for interactive Node.js 22 upgrade prompt.
- **opencode next step** simplified to just `opencode` (not "exit any
  running session...").
- **Extra MaaS key prompt** shows "Extra MaaS API key #N" instead of
  "MaaS API key #N".
- **`mint_or_reuse_key`** deletes existing key by `key_id` (not masked
  `key_name`) before minting — LiteLLM rejects duplicate aliases.
- **Docker compose down** in uninstall runs directly (not `run_filtered`)
  with fallback `docker rm -f` for lingering containers.
- **`npm uninstall`** wrapped in `set +e` — may fail silently, fallback
  `rm -f` all binary paths + `rm -rf` node_modules.
- **Documentation** — README, INSTALLATION, REFERENCE, AGENTS updated for
  `log_step` box style, `log_desc`/`log_done`, `run_with_spinner`,
  `is_interactive`, uninstall binary removal, helper function list.

### Fixed

- `strip_jsonc` was non-functional — Python read `sys.argv[1]` but file was
  passed via stdin. Fixed to `sys.stdin.read()`.
- Concurrent bootstrap runs could corrupt `.env` and `config.yaml`. Added
  `flock` locking via `.bootstrap.lock`.
- Invalid MaaS API key was accepted at install time, causing a vague error
  2–3 minutes later during validation. Pre-flight check now hard-fails on
  HTTP 401/403 with a clear message.
- `curl` calls in `prereqs.sh` (bun, docker install) had no timeout — could
  hang indefinitely on stalled network. Added `--max-time 60/120`.
- `grep -c ... || echo "0"` in `04_validate.sh` produced `"0\n0"` on zero
  matches. Fixed to `|| true` with `:-0` default.
- `04_validate.sh`: extracted `file_perms()`, `check_jq()`, `fail_n()` helpers
  to eliminate duplication (6× stat, 2× identical checker, 5× magic FAIL count).
- `common.sh`: removed dead `retry_curl -o` capture branch.
- All 03x scripts normalized: `LOG_TAG` before `source_env`, `log_warn` for
  dry-run and invalid key, unnumbered steps.
- `03a_opencode.sh`: added `trap` for tmpfile cleanup.
- `.env.template`: removed nonexistent virtual key vars, fixed stale script
  references.
- `configs/pi/models.json.template`: deleted (dead file, 03d generates from
  scratch).
- `LOG_TAG="system"` for prereq installs (was leaking into filtered output).
- Docker prompt default changed to `y` (was `n`, blocking non-interactive).
- `log_step` box border fix (`border+=` not `border +=`).
- `_prereq_sudo` export fix (was not exported for use in subshells).
- Pi binary PATH search expanded to `~/.local/share/pi-node/current/bin`
  and versioned dirs.
- `printf %s` → `%b` for Next steps color codes.
- Delete curl stdout leak in `mint_or_reuse_key` fixed with `&>/dev/null`.

## [0.6.0] - 2026-07-02

### Added

- **Pi coding agent support** (`scripts/03d_pi.sh`). Install via
  `curl -fsSL https://pi.dev/install.sh | sh`, mint a LiteLLM virtual key
  (alias "pi", unlimited budget), and write `~/.pi/agent/models.json`
  pointing to the LiteLLM proxy with all models from `models.sh`.
- `configs/pi/models.json.template` — reference template for pi config.
- Bootstrap menu option 6 (LiteLLM + Pi), `--tool=pi` flag.
- Validation Section F: pi binary, config, provider, and smoke test checks.
  `--skip-pi` and `--pi-only` flags in `04_validate.sh`.
- **`BIND_ADDRESS` env var** for remote access to VM-deployed stacks.
  Default `127.0.0.1` (localhost only, secure). Set `0.0.0.0` to expose
  ports to all interfaces. Documented SSH port forwarding alternative.
- `--virtual-key=` flag in `03d_pi.sh` for standalone key reuse (parity
  with 03b/03c).

### Changed

- **Tool scripts renumbered** to group under step 03 with letter suffixes:
  `03_opencode.sh` → `03a_opencode.sh`,
  `04_codex.sh` → `03b_codex.sh`,
  `05_claude_code.sh` → `03c_claude_code.sh`,
  `06_validate.sh` → `04_validate.sh`.
  Adding a new tool is now `03e_*.sh` — no renumbering needed.
- All doc references updated for new script names and pi entries
  (INSTALLATION.md, REFERENCE.md, SKILL.md, README.md, AGENTS.md).
- Architecture diagrams aligned (fixed-width columns for tool name,
  endpoint, provider).
- SKILL.md frontmatter clarified: 4 presets are opencode-only, not all tools.

### Fixed

- Pi model field mapping: `contextWindow` now uses `max_tokens` (was
  `max_input`), `maxTokens` now uses `max_output` (was `max_tokens`).
- Pi validation F1 error hint: `curl|sh` from pi.dev (was `pip install`).
- Removed unnecessary npm prereq for pi (installs via curl|sh, not npm).
- Stale `Order: 06` header in `04_validate.sh` → `Order: 04`.
- Stale `03/04/05` references in INSTALLATION.md → `03a-03d`.

## [0.5.0] - 2026-07-02

### Changed

- **Install pipeline refactored to interactive-first thin-sequencer model.**
  Bootstrap is now a thin orchestrator; installation is interactive by default
  for both humans and agents (agent drives stdin). Non-interactive consumers
  use env-var overrides (HUAWEI_MAAS_API_KEY) + --tool=.
- Scripts renamed to numbered domain-owned names: `0_bootstrap.sh` →
  `bootstrap.sh`, `1_init_env.sh` → `01_env.sh`, `2_deploy_litellm.sh` →
  `02_litellm.sh`, `4a/4b/4c_install_*.sh` → `03/04/05_*.sh`,
  `5_validate.sh` → `06_validate.sh`.
- `scripts/lib/` → `scripts/helpers/` (prereqs.sh, keys.sh, common.sh, models.sh).
- Every step now self-sources `.env` and is independently runnable
  (loose-coupling contract).
- Prerequisites installed just-in-time, driven by selection — skipped steps
  install nothing.
- Bootstrap summary now advises restarting the shell to clear env vars.
- **curl|bash is now the default install and upgrade method.** Bootstrap
  detects existing repo and pulls updates, or clones fresh if not found.
  No manual clone needed.
- **SKILL.md rewritten as agent supervisor+wrapper procedure** (105 lines).
  Agent reads project docs, presents summary, asks install or upgrade,
  relays every bootstrap prompt with context, delivers final summary.
- **README.md merged install and upgrade into one section** with single
  agent prompt pointing to SKILL.md.
- `05_claude_code.sh` now merges existing `~/.claude/settings.json` instead
  of destructively overwriting (preserves user settings).
- `03_opencode.sh` omits `Huawei-MaaS` direct provider when no MaaS key
  available (no more silent placeholder writes).
- `helpers/keys.sh` uses free `/v1/models` probe instead of paid inference
  call for virtual key validation.
- `01_env.sh` preserves MaaS base URLs unconditionally (outside IS_FRESH
  guard) — no longer resets custom region endpoints when secrets are empty.
- `01_env.sh` sets `chmod 600` on `.env.tmp` before `mv` (no permissions race).
- `configs/litellm/entrypoint.sh` detects Python version dynamically instead
  of hardcoding `python3.13`.
- `03_opencode.sh` substitutes slim schema version dynamically from
  `SLIM_VERSION` (no manual sync with template).
- REFERENCE.md Key Contract table: virtual keys relabeled as config values
  (not env vars); "Immutable?" column renamed to "Rotate risk".
- REFERENCE.md: Grafana description corrected (28 panels, 1h default time
  window), `HUAWEI_MAAS_API_BASE` default fixed (`/openai/v1`).
- `02_litellm.sh` port check uses word-boundary grep pattern (more robust).

### Added

- `INSTALLATION.md` — canonical install reference (pipeline, per-script
  details, flags, env vars, prerequisites, recovery, upgrade).
- `scripts/helpers/keys.sh` — `resolve_master_key` + `mint_or_reuse_key`
  (replaces `3_mint_key.sh`).
- `scripts/helpers/common.sh` — `source_env`, `retry_curl`, `strip_jsonc`,
  `mask_key`, logging, prompts, `run_filtered` (DRYs duplicated code).
- `scripts/helpers/models.sh` — `MODELS` array, single source of truth for
  model catalog (sourced by `02_litellm.sh` + `06_validate.sh`).
- Selection-driven prerequisite summary in bootstrap.
- Standalone clone-and-re-exec support in bootstrap (curl|bash works for
  both fresh install and upgrade).
- `06_validate.sh` runs inference smoke test regardless of opencode install
  (previously skipped when `--skip-opencode`).
- `06_validate.sh` disables observability checks for `--xxx-only` modes.
- `06_validate.sh` warns if Claude model doesn't start with `claude-`.
- `01_env.sh` validates `HUAWEI_MAAS_API_KEY_COUNT` is numeric.
- `01_env.sh` warns on declared count vs actual extra-keys mismatch.
- `01_env.sh` trap cleans up `.env.tmp` on interruption.
- `.gitignore` adds `*.tmp` pattern.
- All scripts reject unknown flags with error (no silent swallowing).

### Fixed

- `bootstrap.sh`: `git pull --ff-only` failure in standalone mode now prompts
  "Reset to origin/main?" instead of dying under `set -e`.
- `bootstrap.sh`: double install-dir prompt in standalone mode eliminated.
- `bootstrap.sh`: "Bootstrap complete" banner now shows failure message when
  validation fails.
- `bootstrap.sh`: `&&...||` antipattern in menu replaced with `if/else`.
- `05_claude_code.sh`: cleans up `.claude.json.tmp` on write failure.
- `helpers/keys.sh`: warns when key lookup hits 50-key cap.
- `helpers/common.sh`: `retry_curl` no longer retries on empty 200 responses.
- `02_litellm.sh`: warns if LiteLLM restart fails (health check still verifies).
- Stale script names fixed in `configs/.env.template` and
  `configs/litellm/config.yaml.template`.
- `06_validate.sh`: `MODEL_COUNT` variable shadowing fixed (renamed to
  `LITELLM_MODEL_COUNT` in Section B5).
- CHANGELOG duplicate `### Added` section under `[0.4.0]` merged.

### Removed

- `--agent` flag and all fail-fast/non-interactive branches in bootstrap.
- `--maas-key=` flag and legacy `--litellm-only`/`--opencode-only`/
  `--codex-only`/`--claude-code-only` aliases on bootstrap.
- `3_mint_key.sh` (folded into `helpers/keys.sh`).
- `1_init_env.sh` `--auto` mode (interactive-first is now the default).

## [0.4.0] - 2026-06-29

### Changed

- **Distributed prerequisite installation** — each script now installs its own
  prerequisites via shared `scripts/lib/prereqs.sh` library instead of
  centralized check in `0_bootstrap.sh`. Scripts are independently runnable.
  `PREREQ_MODE=auto` installs without prompting (CI / non-interactive); `prompt` asks first.
- `2_deploy_litellm.sh` now ensures Docker engine + compose plugin + daemon
  are running via `prereq_ensure_docker` (previously assumed pre-installed).
- Port check in `0_bootstrap.sh` now exits with error in `--agent` mode
  (previously only warned).
- **SKILL.md restructured** — 825 → 372 lines. 10 steps → 8 steps in 4 phases
  (Pre-flight, Execute, Verify, Confirm). Step 10 summary spec replaced with
  brief description. Recovery table grouped by script. Key Contract table
  moved to REFERENCE.md. Non-Debian package mapping table added.
- **README.md rewritten** — human-first comprehensive page. Architecture
  diagram, Quick Start, What You Get (service URLs + tool activation),
  install modes, prerequisites (auto-install), after-install usage guide,
  upgrade, troubleshooting, agent install prompts. 148 → 215 lines.
- REFERENCE.md: dashboard description updated (25→34 panels, 5m→15m),
  stale Prometheus rules repair entry removed, intro updated.

### Added

- `scripts/lib/prereqs.sh` — shared prerequisite installation helper library.
  Provides `prereq_ensure_apt`, `prereq_ensure_bun`, `prereq_ensure_npm`,
  `prereq_ensure_docker`. Idempotent, with sudo wrapper and apt-update-once.
- Tool selection menu in `0_bootstrap.sh` — interactive 6-option menu
  (default all, litellm-only, litellm+opencode, litellm+codex, litellm+claude,
  custom toggle). Use `--tool=all|litellm|opencode|codex|claude` for
  non-interactive selection (comma-separated for custom combos).
  Legacy `--litellm-only`/`--opencode-only`/`--codex-only`/`--claude-code-only`
  flags still work as aliases.
- Just-in-time prerequisite checking in `0_bootstrap.sh` — core prereqs
  checked first, then tool-specific prereqs checked after selection.
- `--skip-opencode`/`--skip-codex`/`--skip-claude-code` flags for
  `5_validate.sh` (additive, combinable with existing --xxx-only flags).
- Claude Code CLI integration via `4c_install_claude_code.sh` — installs
  Claude Code CLI, mints virtual key (alias "claude-code", unlimited budget),
  writes `~/.claude/settings.json`, disables VSCode extension auto-install
  (`~/.claude.json` + `CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL=1`), uninstalls
  existing VSCode extension if present.
- `configs/claude-code/.env.template` — reference template documenting
  `~/.claude/settings.json` format (`env` block with `ANTHROPIC_BASE_URL`,
  `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`, `ANTHROPIC_SMALL_FAST_MODEL`).
- Huawei MaaS Anthropic-compatible endpoint support
  (`HUAWEI_MAAS_ANTHROPIC_API_BASE`).
- `2_deploy_litellm.sh` now generates dual-format deployments: OpenAI
  (`openai/` prefix, `/openai/v1/chat/completions`) + Anthropic
  (`anthropic/` prefix, `/anthropic/v1/messages`) for all 6 models.
- `--claude-code-only` flag for `0_bootstrap.sh` and `5_validate.sh`.
- `CLAUDE_CODE_VIRTUAL_KEY` placeholder in `.env.template`.
- Validation Section E: Claude Code CLI checks (binary, config, provider,
  Messages API smoke test).
- Claude Code config written to `~/.claude/settings.json` (native settings
  file with `env` block, read automatically on startup — no
  `source`/`export` needed).
- `REFERENCE.md`: added Claude Code CLI section, Anthropic endpoint to
  architecture diagram and endpoints table, dual-format architecture
  documentation.

### Removed

- Prometheus alerting rules (`alerts.yml`) — removed, no Alertmanager configured.
- Prometheus recording rules (`rules.yml`) — removed, no 7-day baselines needed.
- 7-day baseline lines from Grafana dashboard panels (TTFT, TPOT, RPM, TPM).
- `PROMETHEUS_RETENTION` minimum 7d requirement — any valid duration now accepted.
- "Annotations & Alerts" annotation from Grafana dashboard.

### Changed

- Total deployment count doubled: 6 OpenAI + 6 Anthropic per API key
  (12 × N total, was 6 × N).
- Anthropic deployments use `claude-` prefixed model names (e.g.,
  `claude-glm-5.2`) to avoid LiteLLM routing conflicts. OpenAI deployments
  keep base names (e.g., `glm-5.2`). Claude Code uses `claude-glm-5.2`
  as `ANTHROPIC_MODEL`.
- Script renumbering for modularity: `2_generate_config.sh` →
  `2_deploy_litellm.sh` (now also deploys Docker Compose),
  `4_mint-virtual-key.sh` → `3_mint_key.sh` (now precedes tool installs),
  `3a/3b/3c_install_*.sh` → `4a/4b/4c_install_*.sh`.

## [0.3.0] - 2026-06-28

### Added

- Codex CLI integration via `3b_install_codex.sh` — installs Codex CLI, mints
  virtual key, writes config + model catalog.
- `configs/codex/model_catalog.json` — metadata for all 6 Huawei MaaS models
  (context window, max output tokens, reasoning effort levels).
- `configs/codex/config.toml.template` — Codex CLI config with custom
  `litellm_proxy` model provider (`wire_api = "responses"`, HTTP SSE).
- `--codex-only` flag for `0_bootstrap.sh` and `5_validate.sh`.
- `CODEX_VIRTUAL_KEY` placeholder in `.env.template`.

### Changed

- LiteLLM models use `openai/` prefix with `use_chat_completions_api: true`
  (documented LiteLLM feature for bridging Responses API → Chat Completions).
- Codex CLI API key stored in `~/.codex/.env` (auto-loaded by Codex CLI via
  dotenvy) instead of shell profile or `auth.json`.
- `multi_agent` feature disabled in Codex CLI config (sends `type: "namespace"`
  tools that Huawei MaaS rejects).
- `3_install.sh` renamed to `3a_install_opencode.sh` for consistency with
  `3b_install_codex.sh`.
- opencode model keys use LiteLLM `model_name` directly (no `openai/` prefix).

### Fixed

- Codex CLI WebSocket transport avoided — LiteLLM v1.89.3 has a bug in the
  WebSocket Responses API bridge (`litellm_params` passed to
  `AsyncCompletions.create()`). Custom provider with `wire_api = "responses"`
  forces HTTP SSE.

## [0.2.0] - 2026-06-27

### Added

- Prometheus + Grafana observability stack with pre-provisioned 12-panel
  dashboard, 4 recording rules (7-day rolling baselines), and 3 alerting
  rules (TTFT anomaly, budget low, deployment outage).
- `PROMETHEUS_RETENTION` env var (default `30d`, min `7d`) — configurable
  Prometheus TSDB retention via `.env`.
- `GRAFANA_ADMIN_PASSWORD` auto-generated by `1_init_env.sh`, stored in
  `.env`, idempotent on re-run.
- Dashboard variables `$model` and `$api_key` with per-metric label mapping
  (`model` vs `requested_model` vs `litellm_model_name`).
- Validation Section C: 6 observability checks (Prometheus reachable, rules
  loaded, /metrics active, scraping LiteLLM, Grafana dashboard, datasource).
- One-click agent upgrade prompt in `README.md` — copy-paste for updating
  an existing installation to the latest version.
- Section D (Upgrade Procedure) in `SKILL.md` — concise upgrade path with
  delta table showing differences from fresh install.
- Port conflict check now covers all 4 services (4000, 5432, 9090, 3000).
- Grafana credentials and restart opencode warning in bootstrap summary
  and SKILL.md Step 10.

### Changed

- All ports bound to `127.0.0.1` (was `0.0.0.0`) — Prometheus, Grafana,
  and LiteLLM /metrics no longer exposed to network.
- Service count validation updated from 2 to 4 services.
- LiteLLM config: `callbacks: ["prometheus"]`,
  `prometheus_initialize_budget_metrics: true`,
  `require_auth_for_metrics_endpoint: false`.
- Docker Compose: added `prometheus` (prom/prometheus:v3.2.1) and `grafana`
  (grafana/grafana:11.5.2) services with health checks and resource limits.
- `SKILL.md` Step 6: "Check Port 4000 Free" → "Check Ports Free" (all 4).
- `SKILL.md` Step 7: Docker Compose service lists updated to 4 services.
- `SKILL.md` Step 9: recovery table expanded with Prometheus/Grafana entries.
- `REFERENCE.md`: added Observability section, updated architecture diagram,
  endpoints table, and repair guide.
- `SKILL.md` Step 10: summary synced with actual bootstrap output (header,
  Grafana credentials, restart warning).
- `SKILL.md` Section D: added Grafana hard restart instruction for upgrades.
- Agent preset model assignments updated based on benchmark research:
  - **oracle**: `glm-5.2` primary (was `deepseek-v4-pro`) — best deep
    reasoning with tools (HLE +6.5, MCP +3.4, SWE-bench Pro +6.7).
  - **designer**: `glm-5.1` primary (was `glm-5`) with `deepseek-v3.2`
    fallback — +28% coding over glm-5, sustained long-horizon productivity.
  - **fixer**: `glm-5` primary (was `deepseek-v4-flash`) with
    `deepseek-v3.2` fallback — 30 RPM vs 3 RPM, 10× more throughput.
  - **explorer**: `deepseek-v3.2` primary (was `deepseek-v4-flash`) —
    700 RPM, eliminates fallback latency.

### Fixed

- Grafana datasource UID mismatch — dashboard referenced `uid: "prometheus"`
  but datasource didn't set `uid`. Added `uid: prometheus` to provisioning.
- Panel 14 (RPM by model) used non-existent `model` label on
  `litellm_proxy_total_requests_metric` — changed to `requested_model`.
- Subquery syntax in dashboard panels 14/15: `avg_over_time(expr)[7d:5m]`
  → `avg_over_time((expr)[7d:5m])` — subquery must be inside the function.
- Dashboard variables `$model`/`$api_key` were defined but never used in
  queries — added label filters selectors to all applicable panels.
- Panel 12 (Budget gauge) threshold mode: `percentage` → `absolute`.
- Section C validation ran in `--opencode-only` mode without LiteLLM —
  now guarded by `if [ "$OPENCODE_ONLY" = false ]`.
- `5_validate.sh` C2 check indentation (extra leading spaces).
- Prometheus recording rules subquery syntax: `expr * 60 [7d:5m]` →
  `(expr * 60)[7d:5m]` — parentheses required before subquery operator.
- `curl -sf` without `-L` on LiteLLM /metrics (307 redirect to /metrics/).
- `curl` without `-g` on Prometheus query `up{job="litellm"}` (URL globbing).
- Duplicate "MAAS API keys total" message in agent mode bootstrap output.
- `5_validate.sh --litellm-only --opencode-only` was a silent no-op — now
  errors with mutual exclusion message.
- Empty duration display in `4_mint-virtual-key.sh` — now shows "unlimited".
- Removed `.master-key` cache file — all secrets now live in `.env` only.
  `0_bootstrap.sh` resolves `LITELLM_MASTER_KEY` from env var → `.env`
  (removed `.master-key` lookup and cache-write logic).

## [0.1.0] - 2026-06-26

Initial release.

### Added

- Deterministic 10-step install procedure (`SKILL.md`) — any agent can
  install by following steps 1–10 with preconditions, actions,
  postconditions, and recovery actions.
- One-click agent install prompt in `README.md` — copy-paste into any
  coding agent for fully automated installation.
- `--litellm-only` mode: deploy the LiteLLM proxy without opencode.
  Skips bun/jq prerequisites, opencode installation, and runs a
  standalone inference smoke test.
- `--agent` mode: non-interactive installation with mandatory key
  rotation security warning in the summary.
- `--dry-run` mode: preview all steps without making changes.
- 6 Huawei MaaS models: `glm-5.2`, `glm-5.1`, `glm-5`, `deepseek-v4-pro`,
  `deepseek-v4-flash`, `deepseek-v3.2`.
- 4 presets:
  - `LiteLLM-Huawei-MaaS-Full` — 6 models via LiteLLM proxy (default).
  - `LiteLLM-Huawei-MaaS-Core` — 4 models via LiteLLM (no v4-pro/v4-flash).
  - `Huawei-MaaS-Full` — 6 models direct (bypass proxy).
  - `Huawei-MaaS-Core` — 4 models direct.
- 3-councillor council system (alpha/beta/gamma) with distinct goals:
  deep reasoning, architecture, and practical implementation.
- Virtual key auto-minting with idempotent reuse — re-running bootstrap
  reuses the existing key if valid, mints a new one if expired.
- Multi-key load balancing (`HUAWEI_MAAS_API_KEY_0..N`) with
  simple-shuffle routing strategy.
- Comprehensive validation: 54 checks (full mode) / 14 checks
  (litellm-only mode) covering .env, Docker, LiteLLM health, config
  correctness, opencode configuration, presets, and inference.
- Idempotent installation — safe to re-run; existing containers, configs,
  and keys are detected and reused.
- `REFERENCE.md` with architecture, endpoint reference, script
  documentation, preset/model mapping table, and repair guide.

### Fixed

- `set -e` traps in `3a_install_opencode.sh` and `5_validate.sh` — command
  substitutions in assignments could trigger `set -e` before error
  handlers could print messages, causing silent script death on API
  failures (virtual key minting, model catalog fetch, liveness probe).
- Key rotation warning now shows even when validation fails — previously
  `set -e` exited before the summary could print.
- Agent-mode key rotation warning is definitive ("keys were shared with
  the agent") rather than conditional ("if any keys were visible").
- Warning covers all MaaS keys (`HUAWEI_MAAS_API_KEY` and
  `HUAWEI_MAAS_API_KEY_1..N`), not just the primary key.
- LiteLLM-only + agent mode now shows the key rotation warning (was
  missing entirely in v0.1.0-pre).

### Known Limitations

- **Linux only** — no macOS or Windows support.
- **Requires Docker + Docker Compose v2** — not bundled.
- **Requires a Huawei MaaS API key** (ap-southeast-1 region) — not
  included; obtain from the ModelArts MaaS console.
- **Inference smoke test requires a valid MaaS key** — placeholder or
  invalid keys will fail validation (all other checks still pass).
- **Pre-1.0 stability** — script flags, config schema, and preset
  definitions may change before v1.0. Pin to a tag for reproducibility.
