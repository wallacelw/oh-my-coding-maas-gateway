# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.7.0] - 2026-08-24

### Added

- **Websearch enabled** — opencode's built-in EXA-backed websearch tool is now
  enabled for custom providers (LiteLLM/Huawei-MaaS). Added `OPENCODE_ENABLE_EXA=1`
  to environment and `"permission": {"websearch": "allow"}` to opencode config.
  No EXA API key required.

### Fixed

- **Slim template: deprecated fallback config keys** — removed `timeoutMs`,
  `retryDelayMs`, `retry_on_empty` (removed in oh-my-opencode-slim 2.3.x);
  replaced with `fallback.maxRetries`. Fixes startup warning.
- **Slim template: invalid MCP names** — librarian preset referenced
  `websearch` (not an MCP — it's opencode's built-in tool) and `grep_app`
  (wrong name — should be `gh_grep`). Corrected to `["context7", "gh_grep"]`.

### Changed

- **CHANGELOG compacted** — 39 sections → 11 sections, 1104 → 430 lines.
  Pre-1.0, 1.2.x dashboard saga, and 1.4.x component bumps consolidated
  into summary entries. All git tags preserved for rollback.
- **GitHub releases pruned** — 33 → 8 milestone releases. Intermediate
  releases deleted (tags kept for rollback). Kept: v1.6.1, v1.6.0, v1.5.0,
  v1.4.10, v1.3.1, v1.2.0, v1.1.0, v1.0.0.
- **Versioning discipline updated** in AGENTS.md — always bump VERSION +
  CHANGELOG for git tracking; create GitHub releases only for meaningful
  milestones (MINOR, significant PATCH clusters). Batch related changes.

## [1.6.1] - 2026-08-23

### Fixed (regressions from v1.6.0)

- **REFERENCE.md/INSTALLATION.md: dashboard docs done backwards** — previous
  fix read JSON array order instead of gridPos.y render order; corrected
  to Cache(6th)→Cost(7th), Tokens=4, Cost=3, Cache=3
- **bootstrap.sh: invalid menu exit** — `exit 1` on invalid input killed
  entire bootstrap; changed to `continue` to re-prompt inside while loop

### Fixed (new bugs from skeptical review)

- **uninstall.sh: Docker filter AND logic** — `--filter "name=litellm_"
  --filter "name=oh-my-coding"` matched nothing (AND logic); simplified
  to single `--filter "name=litellm_"`
- **uninstall.sh: .bashrc permissions** — `mv "$tmp" "$bashrc"` changed
  .bashrc to 0600; switched to `cat > file` to preserve permissions
- **docker-compose.yml: Grafana password default** — `:-admin` silently
  started with weak password; changed to `:?` fail-fast
- **uninstall.sh: unconditional bun removal** — now prompts
  "Remove bun runtime? (may break other bun projects) [y/N]"
- **01_env.sh: silent .env data loss** — re-run deleted user-added custom
  vars; now preserves unknown vars from existing .env
- **update.sh: relative docker-compose.yml path** — broke when run from
  non-project directory; changed all references to use $PROJECT_DIR

## [1.6.0] - 2026-08-23

### Fixed

- **update.sh: empty version corruption** — slim update used fresh npm
  lookup bypassing validation; now uses pre-validated version with guard
- **uninstall.sh: unquoted glob expansion** — paths with spaces could
  cause rm -rf to delete unintended directories; rewritten with find
- **04_validate.sh: docker missing crash** — docker compose ps under
  set -e killed script with opaque error; added fallback
- **keys.sh: JSON built via string interpolation** — delete request
  body now built with jq -nc for safety
- **keys.sh: silent key deletion failure** — now warns if deletion
  fails before minting
- **04_validate.sh: Grafana password in process args** — credentials
  now passed via curl --config stdin instead of -u CLI arg
- **INSTALLATION.md: misleading --xxx-only flag docs** — clarified
  that these flags include LiteLLM checks

### Fixed (council review)

- **bootstrap.sh: stale Grafana label** — summary said "(anonymous)"
  but login is required; fixed to show login instructions
- **bootstrap.sh: sudo bash recommendation** — removed harmful root
  recommendation that broke file ownership; scripts handle sudo internally
- **bootstrap.sh: invalid menu choice** — typing `q` or invalid input
  silently triggered full install; now exits with error
- **REFERENCE.md: false binary removal claim** — docs said binaries
  aren't removed by uninstall, but they are; corrected
- **REFERENCE.md: dashboard docs errors** — fixed section order
  (Cost/Cache swapped), panel counts (32 viz panels, not 39), per-section
  counts (Tokens=3, Cost=7, Cache=0)
- **INSTALLATION.md: dashboard panel count** — corrected 39→32 panel
  references and section order
- **uninstall.sh: bun removal warning** — now warns before removing
  ~/.bun (may break other bun projects)
- **uninstall.sh: destructive docker down warning** — now warns before
  `docker compose down -v --rmi all` (irreversible data loss)
- **update.sh: repo file mutation** — now backs up files before sed -i
  and logs a visible warning
- **models.sh: false SSOT claim** — docs said "edit this file only"
  but 5+ files needed; corrected in models.sh, INSTALLATION.md, REFERENCE.md
- **prereqs.sh: sudo guard at source time** — moved from source-time
  exit to function-call-time check; validation no longer crashes without sudo

### Changed

- **Grafana: anonymous access disabled** — login now required
  (admin user + password from .env). Health endpoint still unauthenticated.
- **Docker container hardening** — added init:true,
  no-new-privileges, cap_drop:ALL to all services

### Updated

- LiteLLM v1.95.0 → v1.98.0 (credential header redaction, SSE keepalive, spend perf)
- Prometheus v3.13.2 → v3.14.0 (stack overflow fix, shutdown CPU bug)
- Grafana 13.1.2 → 13.2.0 (CVE-2026-17183 security fix, new dashboard features)
- oh-my-opencode-slim v2.2.10 → v2.2.15
- Codex CLI 0.146.0 → 0.149.0 (agents dashboard, codex doctor)
- Claude Code 2.1.232 → 2.1.241
- Pi agent 0.83.0 → 0.84.2
- entrypoint.sh health-check patch is now a no-op (LiteLLM v1.97.0+
  removed the probe text; patch kept for backward compatibility)

## [1.5.0] - 2026-08-06

### Fixed (council review)

- **Validation thresholds**: replaced hardcoded `>= 6` with `$MODEL_COUNT`
  in `04_validate.sh` — validation now self-adjusts to catalog size
- **Docker image tag generation in update.sh**: `tag_prefix` was parsed
  but never used in sed, producing invalid image references — now correctly
  interpolates `:v` prefix for LiteLLM/Prometheus and `:` for Grafana
- **run_filtered return values**: update.sh now checks exit codes and
  reports failures instead of false success
- **opencode.json permissions**: regenerated to 600 (was 644, exposed
  virtual key)
- **Stale model references removed**: regenerated opencode.json and
  pi models.json via `03a_opencode.sh` + `03d_pi.sh` — removed `glm-5`
  and `deepseek-v3.2` that were no longer in catalog
- **Slim template version synced**: `@2.2.9` → `@2.2.10` in
  `oh-my-opencode-slim.json.template`

### Added

- **Unknown flag rejection** in update.sh (project rule compliance)
- **npm_latest timeout** (15s) to prevent hanging on slow registry
- **Repo file mutation warnings** in update.sh before editing
  `docker-compose.yml` and `03a_opencode.sh`
- **Stale model recovery** entry in SKILL.md Recovery table
- **--dry-run** documented in README.md
- **Repo file mutation** documented in README.md

### Council Review

Three councillors (alpha/gpt-5.6-luna, beta/gemini-3-pro, gamma/claude-opus-5)
reviewed the project from code quality, architecture, and security/UX
perspectives. All agreed on the fixes above. See council report for details.

## [1.4.0] - 2026-08-04

Consolidates v1.4.0–v1.4.10: component upgrades, preset redesign,
update.sh script, and coding tool updates.

### Changed

- **Prometheus upgraded v3.2.1 → v3.13.2 (LTS)** — security fixes
  (CVE-2025-4673, CVE-2023-45289), 2x faster regex matching, XOR2 encoding,
  native histogram support. v3.13 is a Long Term Support release.
- **LiteLLM upgraded v1.89.3 → v1.95.0** — Claude Opus 5 support, Rust
  backend for Anthropic API, SAML 2.0 SSO, cost optimization page,
  improved streaming performance.
- **Grafana upgraded 11.5.2 → 13.1.2** — two major version jump. Dynamic
  dashboards, Git Sync, revamped gauge visualization, quick filters.
- **oh-my-opencode-slim upgraded v2.0.5 → v2.2.10** — custom subagent
  permissions, project-local customization, native cmux/kitty multiplexer,
  task reconciliation improvements, webfetch config.
- **Presets redesigned and renamed** — `Full`/`Core` → `Default`/`Extended`
  based on model composition. Default uses GLM only (reliable, RPM=100);
  Extended adds deepseek-v4-flash for faster exploration. `deepseek-v4-pro`
  removed from all presets (too expensive, RPM=3). Variants updated to
  valid Huawei MaaS reasoning_effort values (`high` only, no `max`).
- **deepseek-v4-flash rate limits** — RPM 3 → 15, TPM 30,000 → 60,000
  (Huawei MaaS revised quotas).

### Added

- **`scripts/update.sh`** — component update script with interactive
  multi-select, `--check`, `--all`, `--dry-run` flags. Supports 8
  components (opencode, slim, Codex, Claude Code, Pi, LiteLLM, Grafana,
  Prometheus). Integrated into bootstrap.sh for existing installs.
- **Coding tools updated**: opencode 1.17.17 → 1.18.13, Codex CLI
  0.144.5 → 0.146.0, Claude Code 2.1.218 → 2.1.222, Pi agent 0.80.3 →
  0.83.0. Re-minted stale Claude Code virtual key.

### Updated

- REFERENCE.md: preset table, agent→model mapping, update.sh entry
- INSTALLATION.md: preset descriptions, updating coding tools section
- SKILL.md: update instructions, grouped layout documentation
- scripts/04_validate.sh: preset name checks

## [1.3.0] - 2026-07-22

Consolidates v1.2.0–v1.3.1: dashboard overhaul, cache panels, plugin upgrade.

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

## [1.1.0] - 2026-07-06

Consolidates v1.1.0–v1.1.6: companion skill, portability, rate limits.

### Added

- **Companion skill installation** (`scripts/05_skill.sh`) — after
  validation, bootstrap prompts to install SKILL.md as a skill into each
  detected coding agent. Idempotent, `--no-skill` flag to skip.
- **`scripts/install-skill.sh`** — install ANY skill into all detected
  coding agents. Supports `--name=`, `--source=`, `--dry-run`.
- **`helpers/skills.sh`** — install/uninstall helpers for each agent tool.
- **SKILL.md redesigned** — operational companion with interactive menu
  (6 options + context-only default).
- **Non-root warning** — bootstrap warns when not running as root (v1.1.6).

### Changed

- **GLM model rate limits** — `glm-5`, `glm-5.1`, `glm-5.2` now all use
  100 RPM and 1M TPM (was 30 RPM / 500K TPM). (v1.1.1)
- **README slimmed** (292 → 107 lines) — details moved to INSTALLATION.md.
- **INSTALLATION.md expanded** — per-tool usage, monitoring, remote access,
  services table, coding tools table, companion skill table.
- **Pipeline extended** — 01 → 02 → 03a-03d → 04 → 05 (companion skill).
- **macOS/BSD portability** — replaced `grep -oP`/`grep -qP` with
  portable `sed`/`grep -E` equivalents. (v1.1.4)

### Fixed

- **bun install fails without unzip** — auto-installs `unzip` before
  running bun installer. (v1.1.5)
- **Uninstall skill scoping** — `uninstall.sh --tool=claude` no longer
  removes companion skill from other agents. (v1.1.3)
- **Key-mint stdout pollution** — diagnostics redirected to stderr,
  restoring key-on-stdout contract. (v1.1.3)
- **Helper output consistency** — `keys.sh`/`prereqs.sh` switched from
  raw `echo` to `log_*` functions. (v1.1.1)
- **Standalone mode unbound variable** — `version_compare` crash when
  `PROJECT_VERSION="unknown"`. (v1.1.0)
- **Claude skill path** — legacy `~/.claude/commands/` → `~/.claude/skills/`.
- **curl|bash argument passing** — `bash --` → `bash -s --` in README.

## [1.0.0] - 2026-07-06

First stable release.

### Added

- **`VERSION` file** — bootstrap reads and displays version in banner and
  summary. Existing-install detection compares local vs installed version.
- **`scripts/uninstall.sh`** — customizable uninstall: remove single agent,
  subset, all configs, Docker stack, or everything. Supports `--tool=`,
  `--docker`, `--repo`, `--all`, `--dry-run`, `--yes`, interactive menu.
- **MaaS API key validation at prompt time** — invalid keys trigger
  warning and re-prompt instead of failing later.
- **`is_interactive()`** — checks `/dev/tty` (not stdin) so prompts work
  under `curl | bash`.
- **`run_with_spinner()`** — animated spinner for long operations.
- **`log_desc` / `log_done`** — cyan info line before each step, green dim
  completion line after.
- **Prereq explanations** — each prerequisite shows a reason explaining
  what it is and why it's needed.
- **`refresh_path()`** — adds `~/.opencode/bin`, `~/.bun/bin`,
  `~/.local/bin`, nvm, pi-node paths after install.
- **Fresh install option** — existing install detection offers pull updates
  vs fresh install (uninstall + reclone). Default: pull updates.
- **Port conflict handling** — detects and stops stale containers on
  required ports.
- **`flock` locking** via `.bootstrap.lock` to prevent concurrent corruption.
- **AGENTS.md CLI UX Standards** — documented interactive prompt standards,
  output formatting, menu design, summary sections.

### Changed

- **`log_step`** — bold green box-drawing header (`┌── Title ──┐`).
- **`mint_or_reuse_key`** — deletes existing key by `key_id` before minting.
- **Docker compose down** in uninstall runs directly with fallback `docker rm -f`.

### Fixed

- `strip_jsonc` was non-functional — Python read `sys.argv[1]` but file
  was passed via stdin. Fixed to `sys.stdin.read()`.
- Invalid MaaS API key accepted at install time — pre-flight check now
  hard-fails on HTTP 401/403.
- `curl` calls in `prereqs.sh` had no timeout — added `--max-time 60/120`.
- `grep -c ... || echo "0"` produced `"0\n0"` on zero matches.
- `04_validate.sh`: extracted helpers to eliminate duplication.
- `LOG_TAG="system"` for prereq installs (was leaking into filtered output).
- Docker prompt default changed to `y` (was `n`, blocking non-interactive).

## [0.6.0] - 2026-07-02

### Added

- **Pi coding agent support** (`scripts/03d_pi.sh`) — install, virtual key
  minting, config generation. Bootstrap menu option 6, `--tool=pi` flag.
- Validation Section F: pi binary, config, provider, and smoke test checks.
- **`BIND_ADDRESS` env var** for remote access (default `127.0.0.1`).

### Changed

- **Tool scripts renumbered** to group under step 03 with letter suffixes
  (`03a_opencode.sh`, `03b_codex.sh`, `03c_claude_code.sh`, `03d_pi.sh`).
  Adding a new tool is now `03e_*.sh` — no renumbering needed.

### Fixed

- Pi model field mapping: `contextWindow` uses `max_tokens`, `maxTokens`
  uses `max_output`.
- Stale script references in docs updated for new names.

## [0.5.0] - 2026-07-02

Major refactor: interactive-first thin-sequencer model.

### Changed

- **Install pipeline refactored** — bootstrap is now a thin orchestrator;
  installation is interactive by default for both humans and agents.
- **Scripts renamed** to numbered domain-owned names (`01_env.sh`,
  `02_litellm.sh`, etc.). `scripts/lib/` → `scripts/helpers/`.
- Every step self-sources `.env` and is independently runnable.
- **curl|bash is now the default install and upgrade method.** Bootstrap
  detects existing repo and pulls updates, or clones fresh.
- **SKILL.md rewritten** as agent supervisor+wrapper procedure (105 lines).
- `05_claude_code.sh` merges existing `~/.claude/settings.json` instead
  of destructively overwriting.
- `helpers/keys.sh` uses free `/v1/models` probe instead of paid inference
  for virtual key validation.

### Added

- **`INSTALLATION.md`** — canonical install reference.
- **`helpers/keys.sh`** — `resolve_master_key` + `mint_or_reuse_key`.
- **`helpers/common.sh`** — `source_env`, `retry_curl`, `strip_jsonc`,
  `mask_key`, logging, prompts, `run_filtered`.
- **`helpers/models.sh`** — `MODELS` array, single source of truth.
- All scripts reject unknown flags with error.

### Removed

- `--agent` flag and all fail-fast/non-interactive branches.
- `3_mint_key.sh` (folded into `helpers/keys.sh`).

## [0.4.0] - 2026-06-29

### Added

- **Claude Code CLI integration** (`4c_install_claude_code.sh`) — installs
  CLI, mints virtual key, writes `~/.claude/settings.json`, disables VSCode
  extension auto-install.
- **Huawei MaaS Anthropic-compatible endpoint** — dual-format deployments:
  OpenAI (`openai/` prefix) + Anthropic (`anthropic/` prefix) for all models.
- **Distributed prerequisite installation** — each script installs its own
  prereqs via `scripts/lib/prereqs.sh`. Scripts are independently runnable.
- **Tool selection menu** in bootstrap — interactive 6-option menu with
  `--tool=all|litellm|opencode|codex|claude` for non-interactive selection.
- `configs/claude-code/.env.template` — reference for Claude Code config.
- Validation Section E: Claude Code CLI checks.

### Changed

- **SKILL.md restructured** — 825 → 372 lines. 10 steps → 8 steps in 4
  phases.
- **README.md rewritten** — human-first comprehensive page with architecture
  diagram, Quick Start, install modes.

### Removed

- Prometheus alerting rules (`alerts.yml`) — no Alertmanager configured.
- 7-day baseline lines from Grafana dashboard panels.

## [0.1.0] - 2026-06-26

Initial release plus early iterations (v0.2.0–v0.3.0: Prometheus/Grafana
observability stack, Codex CLI integration).

### Added

- Deterministic install procedure (`SKILL.md`) with preconditions, actions,
  postconditions, and recovery actions.
- One-click agent install prompt in `README.md`.
- `--litellm-only`, `--agent`, `--dry-run` modes.
- 6 Huawei MaaS models: `glm-5.2`, `glm-5.1`, `glm-5`, `deepseek-v4-pro`,
  `deepseek-v4-flash`, `deepseek-v3.2`.
- 4 presets (LiteLLM/Huawei-MaaS × Full/Core).
- 3-councillor council system (alpha/beta/gamma).
- Virtual key auto-minting with idempotent reuse.
- Multi-key load balancing (`HUAWEI_MAAS_API_KEY_0..N`).
- Comprehensive validation: 54 checks (full) / 14 (litellm-only).
- Idempotent installation — safe to re-run.
- `REFERENCE.md` with architecture, endpoints, preset/model mapping, repair guide.
- **Prometheus + Grafana observability stack** (v0.2.0) — 12-panel dashboard,
  recording rules, `PROMETHEUS_RETENTION` env var, `GRAFANA_ADMIN_PASSWORD`
  auto-generation, validation Section C (6 observability checks).
- **Codex CLI integration** (v0.3.0) — `3b_install_codex.sh`, model catalog,
  custom `litellm_proxy` provider with `wire_api = "responses"` (HTTP SSE).

### Fixed

- `set -e` traps in install/validate scripts — command substitutions could
  trigger `set -e` before error handlers, causing silent script death.
- Key rotation warning now shows even when validation fails.
- Grafana datasource UID mismatch, subquery syntax, dashboard variable
  filters (v0.2.0).
- Codex CLI WebSocket transport avoided — LiteLLM v1.89.3 WebSocket bug
  workaround with HTTP SSE (v0.3.0).

### Known Limitations

- **Linux only** — no macOS or Windows support.
- **Requires Docker + Docker Compose v2** — not bundled.
- **Requires a Huawei MaaS API key** (ap-southeast-1 region).
- **Inference smoke test requires a valid MaaS key**.
