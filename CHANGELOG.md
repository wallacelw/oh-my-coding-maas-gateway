# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Changed

- **Tool scripts renumbered** to group under step 03 with letter suffixes:
  `03_opencode.sh` → `03a_opencode.sh`,
  `04_codex.sh` → `03b_codex.sh`,
  `05_claude_code.sh` → `03c_claude_code.sh`,
  `06_validate.sh` → `04_validate.sh`.
  Adding a new tool is now `03e_*.sh` — no renumbering needed.
- All doc references updated for new script names and pi entries
  (INSTALLATION.md, REFERENCE.md, SKILL.md, README.md, AGENTS.md).

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
