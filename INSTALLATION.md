# Installation

Complete reference for the installation process: the pipeline, what every
script does, ordering, flags, environment variables, prerequisites, the
loose-coupling contract, recovery, and upgrade procedure.

For a human-friendly overview, see [README.md](./README.md). For the
agent-facing install procedure, see [SKILL.md](./SKILL.md). For architecture
and config reference, see [REFERENCE.md](./REFERENCE.md).

---

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash
```

That's it. Bootstrap clones itself into `/home/oh-my-coding-maas-gateway`
(or a directory you choose), shows a colored menu to select what to install,
and prompts for your Huawei MaaS API key. For each secret, it offers an
auto-generated value or custom entry. Prerequisites are installed
automatically as needed.

**Prefer to clone first?** Equivalent:

```bash
git clone https://github.com/wallacelw/oh-my-coding-maas-gateway /home/oh-my-coding-maas-gateway
cd /home/oh-my-coding-maas-gateway
./scripts/bootstrap.sh
```

---

## Pipeline

Bootstrap is a thin sequencer. It resolves the tool selection, ensures core
prerequisites, then runs the numbered steps in order. Each step owns one
domain and is independently runnable.

| Order | Script | Domain | Optional | Description |
|-------|--------|--------|----------|-------------|
| — | `bootstrap.sh` | Orchestration | — | Entry point. Selection → core prereqs → dispatch steps → summary. |
| 01 | `01_env.sh` | Environment & secrets | no | Generate/update `.env` (immutable secrets, MaaS keys, endpoints); configure git hooks. |
| 02 | `02_litellm.sh` | LiteLLM proxy + observability | no | Generate `config.yaml`; port check; Docker Compose up (LiteLLM + PostgreSQL + Prometheus + Grafana); wait for health. |
| 03a | `03a_opencode.sh` | opencode | yes | Install opencode + oh-my-opencode-slim plugin; mint virtual key; write config. |
| 03b | `03b_codex.sh` | Codex CLI | yes | Install Codex CLI; mint virtual key; write config + model catalog. |
| 03c | `03c_claude_code.sh` | Claude Code CLI | yes | Install Claude Code CLI; mint virtual key; write settings; disable VSCode extension. |
| 03d | `03d_pi.sh` | Pi agent | yes | Install Pi agent; mint virtual key; write `~/.pi/agent/models.json`. |
| 04 | `04_skills_mcps.sh` | Skills & MCP bundles | partial | Install the companion skill plus optional agent tool bundles (REA, drawio — MCP servers + skills) into detected coding agents; refreshes stale copies on re-run. Step always runs; bundles declinable via `--no-*`. |
| 05 | `05_validate.sh` | Validation | no | End-to-end validation of all installed components, including bundle registrations (section H). |
| 06 | `06_backup.sh` | PostgreSQL backup & restore | — | Dump the LiteLLM DB (spend history, virtual keys, budgets) to `backups/`; `--restore FILE` rebuilds it. Maintenance — not run by bootstrap. |
| 07 | `07_dashboard_shots.sh` | Grafana visual verification | — | Capture the rendered dashboard as PNG screenshots for vision-model review. Maintenance — not run by bootstrap. |

### Ordering

`01 env` (everything needs `.env`) → `02 litellm` (tools need the proxy live)
→ `03a/03b/03c/03d` tools (independent, optional, any relative order) →
`04 skills & MCP bundles` (companion skill + optional REA/drawio bundles into
installed agents) → `05 validate` (last, checks everything including bundles).

> **Renumbered in v1.35.0:** the old `04_validate.sh` is now `05_validate.sh`,
> and the old `05_skill.sh` became `04_skills_mcps.sh` (expanded with agent
> tool bundles) and now runs **before** validation so bundles are validated
> too. Update any muscle-memory commands accordingly.

`06_backup.sh` and `07_dashboard_shots.sh` are maintenance scripts (like
`update.sh`) — run manually whenever a database backup/restore or a
dashboard screenshot capture is needed; never part of the install
sequence.

### Helpers (`scripts/helpers/`)

Shared libraries sourced by the pipeline steps. Not run directly — except `grafana_shots.py`, which `07_dashboard_shots.sh` executes.

| File | Used by | Provides |
|------|---------|----------|
| `prereqs.sh` | bootstrap, 01–05 | `prereq_ensure_apt`, `prereq_ensure_bun`, `prereq_ensure_npm`, `prereq_ensure_docker`, `prereq_ensure_node_mcp` (soft-fail Node ≥22.23.4 via NodeSource for MCP bundles). Each install runs under a spinner (`  Installing curl... done`). |
| `keys.sh` | 03a-03d | `resolve_master_key` (env → `.env` → prompt), `mint_or_reuse_key` (alias lookup + mint). |
| `common.sh` | all scripts | `is_interactive`, `source_env`, `retry_curl`, `strip_jsonc`, `mask_key`, `backup_with_prune`, logging (`log_step`, `log_desc`, `log_done`, `log_ok`, `log_info`, `log_warn`, `log_error`, `log_dim`), prompts (`prompt_yesno`, `prompt_input`, `prompt_password`), `run_filtered` (subprocess output filtering), `run_with_spinner` (long operations). |
| `models.sh` | 02, 03d, 05, bootstrap | `MODELS` array + `MODEL_COUNT` + `OFF_PEAK_PRICING` array + `REASONING_MODELS` array + `VISION_MODELS` array — model catalog and time-based differential pricing sourced by bootstrap.sh, 02_litellm.sh, 03d_pi.sh, and 05_validate.sh. To add/remove a model: edit `models.sh` plus `config.yaml.template`, `opencode.json.template`, and `model_catalog.json`. Add to `REASONING_MODELS` if the model surfaces reasoning (`reasoning_effort` pass-through or thinking mode); add to `OFF_PEAK_PRICING` if it has off-peak pricing; add to `VISION_MODELS` if it accepts image input (set `modalities` to include `image` in `input` on its `opencode.json.template` entries). Update `configs/opencode/oh-my-opencode-slim.json.template` only if agents should use the new model. |
| `skills.sh` | 04, 05, uninstall | Companion skill install/uninstall helpers for each agent tool (opencode, codex, pi, claude) + directory-based bundle install with per-file drift detection. |
| `mcp.sh` | 04, 05, uninstall | Merge-safe MCP server registration per tool (opencode `.mcp`, codex `[mcp_servers.*]` sentinel blocks, claude/pi `.mcpServers`); register/unregister/verify; backup-before-write, compare-before-write. |
| `versions.sh` | bootstrap, 04, 05 | `show_installed_versions` — component version table for the install summary; bundle pins (`REA_AGENTS_VERSION`, `DRAWIO_MCP_VERSION`, `NODE_MCP_MIN_VERSION`). |
| `grafana_shots.py` | 07 | Headless Playwright dashboard screenshot capture. |

---

## Per-script details

### `bootstrap.sh`

The only script a human runs. Prompts for an install directory (default:
current parent, or `/home` if standalone). If running standalone (no repo
detected), clones the repo to the target location and re-execs. Parses
`--tool=`, `--virtual-key=`, `--api-key=`, `-y`/`--yes`, `--no-skill`,
`--no-bundles`, and `--dry-run`. Ensures core prerequisites (git,
python3, curl, jq). Shows a colored tool-selection menu if `--tool=` is not
given. In interactive menu mode, prints a prerequisite→tools mapping for customer validation. Dispatches
steps 01–05. Prints a colored summary with service URLs, config file paths,
masked virtual keys, a dim key-rotation tip, and advice to restart the shell.

### `01_env.sh`

Owns `.env`. For each secret (`LITELLM_MASTER_KEY`, `LITELLM_SALT_KEY`,
`DB_PASSWORD`, `GRAFANA_ADMIN_PASSWORD`, `PROMETHEUS_RETENTION`), prompts to
use an auto-generated value or enter a custom one (non-interactive defaults to
auto-generated). On re-run, preserves existing secrets (idempotent).
Collects the Huawei MaaS API key from the `HUAWEI_MAAS_API_KEY` environment
variable or an interactive prompt. Collects extra keys for load balancing from
`HUAWEI_MAAS_API_KEY_1..N` / `HUAWEI_MAAS_API_KEY_COUNT` env vars or a prompt.
Configures git hooks to block committing secrets. `--force` regenerates all
secrets (for key rotation).

### `02_litellm.sh`

Generates `configs/litellm/config.yaml` from `.env` — N deployments per model
per format (dual OpenAI + Anthropic), 4N total. Checks ports 4000/5432/9090/
3000 are free. Logs the image versions being deployed, then runs
`docker compose up -d` (LiteLLM + PostgreSQL + Prometheus + Grafana).
Waits up to 90s for LiteLLM to become healthy. Supports
`--routing-strategy=` and `--dry-run` (renders the would-be config to a
temp file, prints a diff summary against the current config, writes
nothing, and skips prereq installs and MaaS key validation).

### `03a_opencode.sh`

Installs the opencode binary (via curl, output filtered with `run_filtered`),
the oh-my-opencode-slim plugin (v3.0.6, via bunx — 2 presets, 8 agents, output
filtered to suppress GitHub star prompts), mints a virtual key (alias
"opencode"), and writes `~/.config/opencode/opencode.json` +
`oh-my-opencode-slim.json`. Supports `--virtual-key=` and `--dry-run`.
Also ensures `OPENCODE_ENABLE_EXA=1` (built-in websearch, EXA-backed, no
API key required) and `OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true`
(slim v3 background orchestration) are set in `~/.bashrc`.

### `03b_codex.sh`

Installs the OpenAI Codex CLI (via npm), mints a virtual key (alias "codex"),
and writes `~/.codex/config.toml` (custom `litellm_proxy` provider,
`wire_api=responses`), `model_catalog.json`, and `.env` with the API key.
Supports `--virtual-key=` and `--dry-run`.

### `03c_claude_code.sh`

Installs the Claude Code CLI (via npm), mints a virtual key (alias
"claude-code"), writes `~/.claude/settings.json` (env block pointing to the
LiteLLM proxy via the Anthropic Messages API), and disables the VSCode
extension auto-install. Supports `--virtual-key=` and `--dry-run`.

### `03d_pi.sh`

Installs the Pi coding agent — via `npm install -g
@earendil-works/pi-coding-agent` when running non-interactive with
Node ≥ 22, otherwise by downloading the installer from pi.dev to a temp
file and executing it — mints a virtual
key (alias "pi"), and writes `~/.pi/agent/models.json` (LiteLLM provider
pointing to the proxy via OpenAI Chat Completions API). Supports
`--virtual-key=` and `--dry-run`.

### `04_skills_mcps.sh`

Installs the **companion skill** plus two optional **agent tool bundles**
into each detected coding agent (opencode, codex, claude, pi). Interactive
runs show a numbered menu (all bundles default-on, comma combos allowed,
scope summary + confirm); `--yes`/non-interactive runs install with defaults.

- **Companion skill** — this repo's SKILL.md (gateway operations guidance).
  Failure is a hard error (status quo).
- **REA bundle** — reverse-engineering MCP server + skill
  (`rea-agents`, pinned in `helpers/versions.sh`). Registers via
  `rea setup --yes --client <id>` per installed tool (REA writes its own
  registration with a pinned absolute Node path and installs its skill).
  Missing analysis engines (Ghidra/IDA/JADX/Kuna) are warnings only —
  static JS/Electron/.NET analysis works without them.
- **drawio bundle** — diagramming MCP server (`@drawio/mcp`, pinned) +
  vendored skill (`skills/drawio/`). Registered with absolute Node +
  entry-script paths so agent-runtime PATH cannot break it.

Bundles are **soft-fail**: a declined Node or curl/jq install, npm outage, or
per-tool
setup failure logs a warning and continues — the step exits 0 unless the
companion skill fails (use `--strict` to make bundle failures non-zero).
Node ≥22.23.4 is ensured automatically when either bundle runs (NodeSource
22.x; pi's bundled Node is never touched). `--refresh-only` refreshes only
already-registered bundles — never adds new ones (used by `update.sh`).

Flags: `--dry-run`, `--no-skill`, `--no-rea`, `--no-drawio`, `--yes`,
`--refresh-only`, `--strict`, `--skip-opencode`, `--skip-codex`,
`--skip-claude-code`, `--skip-pi`.

Skill locations:
- opencode: `~/.config/opencode/skills/<name>/SKILL.md`
- codex: `~/.codex/skills/<name>/SKILL.md`
- pi: `~/.pi/agent/skills/<name>/SKILL.md`
- claude: `~/.claude/skills/<name>/SKILL.md`

(`<name>` is `oh-my-coding-maas-gateway`, `reverse-engineer-anything`
(installed by REA), or `drawio`.)

### `05_validate.sh`

Validates all installed components in sections A–H:
`.env` completeness, Docker services, LiteLLM health + config, Prometheus +
Grafana, each tool's config + API smoke test, and (section H) agent tool
bundles — Node version used by MCP registrations, REA + drawio registrations
per tool, bundle skills, config permissions, TOML parse, and `rea doctor`.
Absent bundles warn (optional); installed-but-broken bundles fail.
Supports `--dry-run`,
`--litellm-only`/`--opencode-only`/`--codex-only`/`--claude-code-only`/`--pi-only`
(scoped), `--skip-opencode`/`--skip-codex`/`--skip-claude-code`/`--skip-pi`
(additive), and `--skip-bundles`.

### `06_backup.sh`

Maintenance script (like `update.sh`) — not part of the install pipeline.
Dumps the LiteLLM PostgreSQL database (spend history, virtual keys,
budgets) to `backups/litellm_YYYYmmdd_HHMMSS.sql`, chmod 600, pruned to
the newest 10 (`--keep N`). `docker compose down -v` destroys the
database volume — run this first.

Flags: `--dry-run`, `--restore FILE` (stops LiteLLM, restores, restarts;
prompts unless `--yes`), `--keep N`.

`backups/` is gitignored (dumps contain spend history and key hashes) and
is removed by `uninstall.sh --repo` / `--all`.

### `07_dashboard_shots.sh`

Maintenance script (like `update.sh`) — not part of the install pipeline.
Captures the rendered Grafana dashboard as PNG screenshots for visual
verification: `full.png` (entire dashboard) plus `band-NN.png` (1100px
vertical bands sized for vision-model review) in the output directory.

Flags: `--out=DIR` (default `/tmp/dashboard-shots`), `--dry-run`.

Requires python3 + playwright + chromium (one-time setup:
`pip3 install --user --break-system-packages playwright && python3 -m playwright install chromium`).

---

## Flags

### `bootstrap.sh`

| Flag | Effect |
|------|--------|
| `--tool=VAL` | `all` (default), `litellm`, `opencode`, `codex`, `claude`, `pi`, or comma combo (e.g. `opencode,codex`). Skips the menu. |
| `--virtual-key=sk-...` | Reuse an existing opencode virtual key, skip minting. |
| `--api-key=KEY` | Huawei MaaS API key (alternative to `HUAWEI_MAAS_API_KEY` env var). |
| `-y`, `--yes` | Auto-accept all prompts, install all tools (non-interactive mode). |
| `--dry-run` | Preview without side effects — no installs, no file writes, no key validation, no proxy required. Bootstrap prints each step header with the command it would run (e.g. `Would run: scripts/02_litellm.sh`); the steps themselves are not executed. |
| `--no-skill` | Skip the companion skill only (step 04); agent bundles still offered. |
| `--no-bundles` | Skip the agent tool bundles (REA + drawio); companion skill still offered. |
| `-h`, `--help` | Print usage and exit 0. |

**Dry-run contract:** `--dry-run` is side-effect-free in every script —
prerequisite installs, file writes, key validation, and the LiteLLM
proxy-reachability check are all skipped, so an existing clone can preview a
full install (with no clone yet, the standalone dry-run stops after the
would-clone step). Standalone step runs print what they would do: the 03x
scripts list the installs, config writes, and key mint they would perform;
`02_litellm.sh` prints the would-be config with a diff summary (see its
section above).

### `01_env.sh`

| Flag | Effect |
|------|--------|
| `--force` | Regenerate all immutable secrets (for key rotation). Invalidates existing virtual keys. |

### `04_skills_mcps.sh`

| Flag | Effect |
|------|--------|
| `--dry-run` | Print the plan (including resolved paths), write nothing. |
| `--yes` | Non-interactive; install all selected bundles with defaults. |
| `--no-skill` | Skip the companion skill only (bundles still offered). |
| `--no-rea` | Skip the REA bundle. |
| `--no-drawio` | Skip the drawio bundle. |
| `--refresh-only` | Refresh only already-registered bundles/skills; never add new ones. |
| `--strict` | Bundle failures exit non-zero (default: warn and exit 0). |
| `--skip-<tool>` | Exclude a tool (`--skip-opencode`, `--skip-codex`, `--skip-claude-code`, `--skip-pi`). |

### `05_validate.sh`

| Flag | Effect |
|------|--------|
| `--dry-run` | Structure checks only, no network calls. |
| `--litellm-only` | Only LiteLLM proxy checks. |
| `--opencode-only` | LiteLLM + opencode config checks. |
| `--codex-only` | LiteLLM + Codex CLI config checks. |
| `--claude-code-only` | LiteLLM + Claude Code CLI config checks. |
| `--pi-only` | LiteLLM + Pi agent config checks. |
| `--skip-opencode` | Skip opencode checks (additive). |
| `--skip-codex` | Skip Codex checks (additive). |
| `--skip-claude-code` | Skip Claude Code checks (additive). |
| `--skip-pi` | Skip Pi agent checks (additive). |
| `--skip-bundles` | Skip the agent tool bundles section (H). |

The `--xxx-only` flags are mutually exclusive. The `--skip-*` flags combine
with anything.

---

## Environment Variables

These control the install when set before running `bootstrap.sh`. When
absent, the scripts prompt interactively (or error in non-interactive mode).

| Variable | Purpose | Read by |
|----------|---------|---------|
| `HUAWEI_MAAS_API_KEY` | Main Huawei MaaS API key (region ap-southeast-1). | `01_env.sh`, `03a_opencode.sh` |
| `HUAWEI_MAAS_API_KEY_COUNT` | Total number of MaaS keys (1 + extras). | `01_env.sh`, `02_litellm.sh` |
| `HUAWEI_MAAS_API_KEY_1..N` | Extra MaaS keys for load balancing. | `01_env.sh`, `02_litellm.sh` |
| `LITELLM_MASTER_KEY` | LiteLLM master key (resolved from env or `.env`). | `03a-03d` via `helpers/keys.sh` |
| `BIND_ADDRESS` | Docker port bind address (`127.0.0.1` localhost, `0.0.0.0` all interfaces). | docker-compose |
| `HUAWEI_MAAS_API_BASE` | MaaS OpenAI-compatible API base URL. Auto-set with default. | `02_litellm.sh` |
| `HUAWEI_MAAS_ANTHROPIC_API_BASE` | MaaS Anthropic-compatible API base URL. Auto-set with default. | `02_litellm.sh` |
| `OPENCODE_ENABLE_EXA` | Enable opencode built-in websearch (EXA) for custom providers. Set to `1`. | `03a_opencode.sh` |
| `OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS` | Enable slim v3 background orchestration on the opencode v1 host line. Set to `true`. | `03a_opencode.sh` |
| `LITELLM_UI_USERNAME` / `LITELLM_UI_PASSWORD` | LiteLLM Admin UI login (DB-backed admin account; env-credential login is disabled — the master key cannot sign in to the UI). Account set once via `/user/update` (first UI visit); `01_env.sh` writes the record slot into `.env` (Proxy Auth section, placeholder until filled) and preserves it on re-run. | LiteLLM Admin UI |

All other secrets (`LITELLM_SALT_KEY`, `DB_PASSWORD`, `GRAFANA_ADMIN_PASSWORD`,
`PROMETHEUS_RETENTION`) are auto-generated by `01_env.sh` and stored in `.env`.

`LITELLM_DISABLE_NO_REDIS_WARNING` is set to `true` in `docker-compose.yml` —
suppresses the Admin UI "no Redis" banner for our deliberate single-worker setup.

---

## Colored Output & Action Labels

All scripts use a shared logging system from `helpers/common.sh`:

- **Colors** auto-enable on TTY, disable on piped/CI output.
- `log_step` — bold green box-drawing section headers (`┌── Title ──┐`)
- `log_desc` — cyan info line before each step
- `log_done` — green dim completion line after each step
- `log_ok` / `log_info` / `log_warn` / `log_error` — green ✓ / blue → / yellow ⚠ / red ✗
- `log_dim` — dim secondary text

Prerequisite installs run under a spinner (`  Installing curl... done`).
Each pipeline script announces itself with a `log_step` header (e.g.
`Step 02 — LiteLLM proxy + observability`), so every line of output is
attributable to its step.

Third-party subprocess output is filtered via `run_filtered` — suppresses
GitHub star prompts, npm warnings, and deprecation notices, showing remaining
lines with a dim `[tag]` prefix.

### Interactive Prompts

- `prompt_yesno "question" [y|n]` — colored `? Question [Y/n]`, auto-defaults on non-TTY
- `prompt_input "question" [default]` — colored input with default hint
- `prompt_password "label" "auto_value" [prefix]` — shows masked auto-generated preview, offers custom entry; when `prefix` is given, custom input is validated and re-prompted on mismatch (e.g. `LITELLM_MASTER_KEY` requires `sk-`)

In `01_env.sh`, each secret prompts: "Use auto-generated value? [Y/n]" or
enter custom. Non-interactive defaults to auto-generated.

**Prompt conventions:**

- Yes/no prompts are **case-insensitive**: `y`, `Y`, `yes`, `YES` all mean
  yes; `n`, `N`, `no`, `NO` all mean no.
- The **uppercase letter** in the hint indicates the default: `[Y/n]` →
  Enter defaults to yes, `[y/N]` → Enter defaults to no.
- Pressing **Enter** without typing accepts the default.

---

## Prerequisites

**OS:** Linux (Debian/Ubuntu with systemd recommended).

Prerequisites are installed **just-in-time, driven by selection**. Each step
ensures only its own prerequisites; skipped steps install nothing. A
`--tool=litellm` install never installs bun, npm, or bubblewrap.

| Step | Ensures |
|------|---------|
| `bootstrap.sh` | git, python3, curl, jq |
| `01_env.sh` | python3, git |
| `02_litellm.sh` | curl, docker + compose + daemon |
| `03a_opencode.sh` | curl, jq, bun |
| `03b_codex.sh` | curl, npm/node, jq, bubblewrap |
| `03c_claude_code.sh` | curl, npm/node, jq |
| `03d_pi.sh` | curl, jq |
| `04_skills_mcps.sh` | curl, jq, node ≥22.23.4 + npm (auto-installed via NodeSource when bundles run) |
| `05_validate.sh` | curl, jq |

Interactive mode prompts before each installation. Non-interactive shells
(piped stdin, CI) auto-confirm. Each install runs under a spinner showing
what is being installed; the calling script's step header identifies which
script triggered it. Bootstrap prints a **prereq→tools mapping**
at the start for customer validation (e.g. `curl — bootstrap, litellm,
validate, opencode, codex, claude`). **Non-Debian systems** (RHEL, Alpine,
Arch): install equivalent packages manually — Docker daemon start requires
systemd.

---

## Loose-Coupling Contract

- Every step **self-sources `.env`** via `helpers/common.sh:source_env`. No
  script depends on another script's exports.
- Every step is **independently runnable** — e.g. `./scripts/03a_opencode.sh`
  works standalone (sources `.env`, resolves the master key, mints, writes
  config).
- **Optional steps (03a-03d)** are skipped per `--tool=`; skipping never
  breaks later steps. `05_validate.sh` receives `--skip-*` for skipped tools.
- Idempotent — safe to re-run. Immutable secrets are preserved; existing
  containers, configs, and valid virtual keys are reused.

---

## Idempotency & Re-run

- If any step's precondition is already met, it skips and verifies the
  postcondition.
- Safe to re-run from any step. Never destroys data or regenerates immutable
  secrets (`LITELLM_MASTER_KEY`, `LITELLM_SALT_KEY`, `DB_PASSWORD`).
- `01_env.sh --force` regenerates all secrets (for key rotation).
- Fail-safe: if any preserved secret is empty or missing in an existing
  `.env`, `01_env.sh` regenerates ALL secrets on the next run (with a
  warning) — a partially-populated `.env` never survives silently.

---

## Recovery

| FAIL pattern | Recovery |
|--------------|----------|
| `.env not found` / `placeholder value` | Re-run `01_env.sh` |
| `services running` + `expected 4` | `docker compose up -d`, wait 30s, retry |
| `liveness probe returned` | `docker compose logs litellm --tail 50` |
| `Inference smoke test` + `did not respond` | Re-validate MaaS key; check logs |
| opencode issues (`opencode not found`, config) | Re-run `03a_opencode.sh` |
| Codex issues (`codex not found`, config) | Re-run `03b_codex.sh` |
| Claude Code issues (`claude not found`, config) | Re-run `03c_claude_code.sh` |
| Pi issues (`pi not found`, config) | Re-run `03d_pi.sh` |
| `Prometheus not reachable` | `docker compose up -d prometheus`, wait 10s |
| `/metrics endpoint not responding` | `docker compose restart litellm`, wait 15s |
| `Grafana not reachable` | `docker compose up -d grafana`, wait 20s |

WARN messages (e.g. `litellm_config.yaml not found`, `unhealthy_count > 0`,
deployment drift) do NOT cause non-zero exit — they are advisory.

After recovery, re-run `05_validate.sh` **once**. If it still fails, escalate
with full output.

---

## Upgrade

```bash
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash
```

Same one-liner as install — bootstrap detects the existing repo, pulls
updates, and re-runs idempotently. Equivalent manual form:

```bash
cd /home/oh-my-coding-maas-gateway
git pull
./scripts/bootstrap.sh
```

- Bootstrap preserves `LITELLM_MASTER_KEY`, `LITELLM_SALT_KEY`, `DB_PASSWORD`,
  `GRAFANA_ADMIN_PASSWORD`, `PROMETHEUS_RETENTION` from existing `.env`.
- Config is regenerated from templates — new options picked up automatically.
- Docker Compose recreates containers; data volumes preserved.
- If `git pull` fails: interactive mode asks "Reset to origin/main? (y/n)".
  In non-interactive mode (`-y` or no TTY), bootstrap prints a loud warning
  counting the local commits and uncommitted changes being discarded, then
  resets to `origin/main` and continues.
- **Grafana dashboard updates:** hard-restart to pick up provisioning:
  `docker compose restart grafana`.

After upgrade, restart opencode if it's running (exit with `/exit` or Ctrl+C,
start fresh — plugin/preset changes are not hot-reloaded).

**Upgrade is complete when `05_validate.sh` exits 0.**

### Updating coding tools

The install scripts skip tools that are already installed. To check and
update individual components, use the standalone update script. Components
are grouped into two categories:

- **Coding Tools** — opencode, oh-my-opencode-slim, Codex CLI, Claude
  Code, Pi agent
- **Infrastructure** — LiteLLM, Grafana, Prometheus (active docker-method
  updates); PostgreSQL (pinned, display-only — never auto-updated)
- **Version display** — shows the project version and a per-component
  current-vs-latest table

```bash
./scripts/update.sh              # interactive: show grouped table, select which to update
./scripts/update.sh --check      # show version table only
./scripts/update.sh --all        # update all with updates available
./scripts/update.sh --dry-run    # show what would be updated, no changes
```

This does NOT touch passwords, API keys, or virtual keys — it updates
binaries, npm packages, and Docker images; the slim and docker methods
also bump pinned versions in tracked files and commit them. After updating Docker images,
the script automatically pulls and restarts the affected service.

---

## Uninstall

`scripts/uninstall.sh` removes all or part of the installation.

| Flags | What it removes |
|-------|-----------------|
| `--tool=opencode` | opencode agent (binary, config, skills, bundle registrations, `.bashrc` entries) |
| `--tool=opencode,codex` | Subset of agent configs |
| `--tool=all` | All agent configs |
| `--bundles` `--tool=<t\|all>` | Remove only REA/drawio bundle artifacts (MCP registrations + skills); binaries/configs intact. |
| `--docker` | Docker containers + volumes + images |
| `--repo` | This repo (`.env`, configs, scripts, `backups/` — copy any DB dumps you want to keep elsewhere first) |
| `--all` | Everything above |
| `--dry-run` | Preview without deleting |
| `--yes` | Skip confirmation |

No flags → interactive menu. Configs and `.bashrc` entries are removed.
Binaries (opencode, codex, claude, pi) and runtimes (bun, pi-node) are
removed where possible — npm binaries installed with sudo may survive
(uninstall warns and prints the remaining path; remove those manually).

```bash
./scripts/uninstall.sh --all --dry-run   # preview
./scripts/uninstall.sh --tool=opencode   # remove one agent
./scripts/uninstall.sh --all --yes       # remove everything, no prompt
```

---

## After Install

Restart your shell (or open a new terminal) to clear exported environment
variables and apply all changes:

```bash
exec "$SHELL"
```

Then run your coding tool:

```bash
opencode          # or:  codex  or:  claude --bare  or:  pi
```

### Using opencode

```bash
opencode
# Available presets:
#   LiteLLM-Default     (default — glm-5.3 orchestrator/oracle, deepseek-v4.1-flash-1017 all other agents)
#   Huawei-MaaS-Default (direct — same agent-model mapping, direct to MaaS)
# Paste a screenshot (Ctrl-V) — observer reads it and reports back structured observations
```

If opencode was already running, exit it first (`/exit` or Ctrl+C).

Websearch is enabled by default — the built-in EXA-backed tool requires no
API key. The `"permission": {"websearch": "allow"}` entry in `opencode.json`
and `OPENCODE_ENABLE_EXA=1` in the environment activate it for custom providers.

### Using Codex CLI

```bash
codex
codex --model deepseek-v4.1-flash-1017  # fast, cost-efficient, accepts image input
codex --model glm-5.3                   # deepest reasoning
```

### Using Claude Code CLI

```bash
claude --bare
claude --bare --model claude-deepseek-v4.1-flash-1017  # fast, cost-efficient, accepts image input
claude --bare --model claude-glm-5.3                   # deepest reasoning
```

### Using Pi agent

```bash
pi
# Switch model at runtime via Pi's model selection UI
# For cost-efficient operation: select deepseek-v4.1-flash-1017 in the model picker
```

### Monitoring

- **Grafana:** `http://127.0.0.1:3000` — 44-panel dashboard (7 row headers +
  37 visualization panels). Login: admin / your Grafana password from .env.
  7 sections: At-a-glance, Errors & Health, Rate Limits & Capacity, Latency,
  Tokens, Cache, Cost & Budget. Time window selectable (default 1h).
- **LiteLLM Admin UI:** `http://127.0.0.1:4000/ui` — view deployments, virtual
  keys, spend, budgets. Login: the admin account you create once via the UI's
  `/user/update` (e.g. `admin@localhost.dev`) — record its password in `.env`
  as `LITELLM_UI_PASSWORD` (Proxy Auth section; placeholder until filled).
  Env-credential login is disabled; the master key cannot sign in to the UI.
- **Prometheus:** `http://127.0.0.1:9090` — raw metrics.

### Remote Access

All ports bind to `127.0.0.1` by default (localhost only). Two ways to access
from another machine (e.g. your laptop when the stack runs on a VM):

**Option A — SSH port forwarding (recommended, no config change):**

```bash
ssh -L 4000:127.0.0.1:4000 -L 3000:127.0.0.1:3000 -L 9090:127.0.0.1:9090 user@vm
```

Then open `http://localhost:4000/ui` and `http://localhost:3000` on your
local machine. Traffic is encrypted via SSH. No ports exposed to the network.

**Option B — Bind to all interfaces (direct access, less secure):**

```bash
# In .env:
BIND_ADDRESS="0.0.0.0"

# Restart:
docker compose up -d
```

Then access via `http://<vm-ip>:4000/ui` and `http://<vm-ip>:3000` from any
machine on the network. Ensure firewall rules limit access (e.g. security
group, `ufw allow from <your-ip> to any port 4000`).

### Services

| Service | URL | Auth | Purpose |
|---------|-----|------|---------|
| LiteLLM Proxy | `http://127.0.0.1:4000` | Virtual key | API gateway |
| LiteLLM Admin UI | `http://127.0.0.1:4000/ui` | DB-backed admin account (created via /user/update) | View keys, spend, deployments |
| Grafana Dashboard | `http://127.0.0.1:3000` | admin password (from .env) | 44-panel observability dashboard |
| Prometheus | `http://127.0.0.1:9090` | None | Metrics storage |
| PostgreSQL | `db:5432` (compose network only — port not published; host access via `docker compose exec db psql`) | — | LiteLLM database |

### Coding Tools

| Tool | Activate | API Format | Config location |
|------|----------|------------|-----------------|
| opencode | `opencode` | OpenAI Chat Completions | `~/.config/opencode/opencode.json` |
| Codex CLI | `codex` | OpenAI Responses (bridged) | `~/.codex/config.toml` |
| Claude Code CLI | `claude --bare` | Anthropic Messages | `~/.claude/settings.json` |
| Pi agent | `pi` | OpenAI Chat Completions | `~/.pi/agent/models.json` |

Each tool gets its own virtual key with unlimited budget and access to all
models. opencode also gets 2 presets and 8 agents via the
oh-my-opencode-slim plugin.

### Install Modes

Interactive menu appears when you run bootstrap. Or use `--tool=` flag:

| Choice | Flag | What gets installed |
|--------|------|-------------------|
| 1 (default) | `--tool=all` | LiteLLM + all coding tools |
| 2 | `--tool=litellm` | LiteLLM proxy only |
| 3 | `--tool=opencode` | LiteLLM + opencode |
| 4 | `--tool=codex` | LiteLLM + Codex CLI |
| 5 | `--tool=claude` | LiteLLM + Claude Code CLI |
| 6 | `--tool=pi` | LiteLLM + Pi agent |
| 7 | Interactive | Custom — toggle each component on/off |

### Companion Skill

During installation (step 04), bootstrap installs (default-on; interactive runs
confirm) SKILL.md (plus the REA/drawio bundles) into each detected coding agent.
This gives your agents operational guidance for the gateway.

| Tool | Skill location | How to invoke |
|------|---------------|---------------|
| opencode | `~/.config/opencode/skills/oh-my-coding-maas-gateway/SKILL.md` | Automatic (agent reads skill) |
| Codex CLI | `~/.codex/skills/oh-my-coding-maas-gateway/SKILL.md` | Automatic (agent reads skill) |
| Pi agent | `~/.pi/agent/skills/oh-my-coding-maas-gateway/SKILL.md` | `/skill:oh-my-coding-maas-gateway` |
| Claude Code | `~/.claude/skills/oh-my-coding-maas-gateway/SKILL.md` | Automatic (agent reads skill) |

```bash
./scripts/04_skills_mcps.sh --yes    # install skills + bundles manually anytime
```
