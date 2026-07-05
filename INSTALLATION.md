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
| 04 | `04_validate.sh` | Validation | no | End-to-end validation of all installed components. |
| 05 | `05_skill.sh` | Companion skill | yes | Install SKILL.md into detected coding agents (opencode, codex, claude, pi). |

### Ordering

`01 env` (everything needs `.env`) → `02 litellm` (tools need the proxy live)
→ `03a/03b/03c/03d` tools (independent, optional, any relative order) → `04 validate`
(last, checks everything) → `05 skill` (companion skill into installed agents).

### Helpers (`scripts/helpers/`)

Shared libraries sourced by the pipeline steps. Not run directly.

| File | Used by | Provides |
|------|---------|----------|
| `prereqs.sh` | all steps | `prereq_ensure_apt`, `prereq_ensure_bun`, `prereq_ensure_npm`, `prereq_ensure_docker`. Each install labeled with `[LOG_TAG]`. |
| `keys.sh` | 03a-03d | `resolve_master_key` (env → `.env` → prompt), `mint_or_reuse_key` (alias lookup + mint). |
| `common.sh` | all scripts | `source_env`, `retry_curl`, `strip_jsonc`, `mask_key`, logging (`log_step`, `log_desc`, `log_done`, `log_ok`, `log_info`, `log_warn`, `log_error`, `log_dim`, `log_action`), prompts (`prompt_yesno`, `prompt_input`, `prompt_password`), `run_filtered` (subprocess output filtering), `run_with_spinner` (long operations). |
| `models.sh` | 02, 04 | `MODELS` array + `MODEL_COUNT` — single source of truth for the model catalog. To add/remove a model: edit this file only. |
| `skills.sh` | 05 | Companion skill install/uninstall helpers for each agent tool (opencode, codex, pi, claude). |

---

## Per-script details

### `bootstrap.sh`

The only script a human runs. Prompts for an install directory (default:
current parent, or `/home` if standalone). If running standalone (no repo
detected), clones the repo to the target location and re-execs. Parses
`--tool=`, `--virtual-key=`, `--dry-run`. Ensures core prerequisites (git,
python3, curl, jq). Shows a colored tool-selection menu if `--tool=` is not
given. Prints a prerequisite→tools mapping for customer validation. Dispatches
steps 01–06. Prints a colored summary with service URLs, config file paths,
masked virtual keys, a security warning, and advice to restart the shell.

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
per format (dual OpenAI + Anthropic), 12N total. Checks ports 4000/5432/9090/
3000 are free. Runs `docker compose up -d` (LiteLLM + PostgreSQL + Prometheus
+ Grafana). Waits up to 90s for LiteLLM to become healthy. Supports
`--routing-strategy=` and `--dry-run`.

### `03a_opencode.sh`

Installs the opencode binary (via curl, output filtered with `run_filtered`),
the oh-my-opencode-slim plugin (v2.0.5, via bunx — 4 presets, 7 agents, output
filtered to suppress GitHub star prompts), mints a virtual key (alias
"opencode"), and writes `~/.config/opencode/opencode.json` +
`oh-my-opencode-slim.json`. Supports `--virtual-key=` and `--dry-run`.

### `03b_codex.sh`

Installs the OpenAI Codex CLI (via npm), mints a virtual key (alias "codex"),
and writes `~/.codex/config.toml` (custom `litellm_proxy` provider,
`wire_api=responses`), `model_catalog.json`, and `.env` with the API key.
Supports `--dry-run`.

### `03c_claude_code.sh`

Installs the Claude Code CLI (via npm), mints a virtual key (alias
"claude-code"), writes `~/.claude/settings.json` (env block pointing to the
LiteLLM proxy via the Anthropic Messages API), and disables the VSCode
extension auto-install. Supports `--dry-run`.

### `03d_pi.sh`

Installs the Pi coding agent (via `curl | sh` from pi.dev), mints a virtual
key (alias "pi"), and writes `~/.pi/agent/models.json` (LiteLLM provider
pointing to the proxy via OpenAI Chat Completions API). Supports `--dry-run`.

### `04_validate.sh`

Validates all installed components in sections A–F + observability:
`.env` completeness, Docker services, LiteLLM health + config, Prometheus +
Grafana, and each tool's config + API smoke test. Supports `--dry-run`,
`--litellm-only`/`--opencode-only`/`--codex-only`/`--claude-code-only`/`--pi-only`
(scoped), and `--skip-opencode`/`--skip-codex`/`--skip-claude-code`/`--skip-pi` (additive).

### `05_skill.sh`

Prompts the user to install SKILL.md as a skill/command into each detected
coding agent. Detects which tools are installed (opencode, codex, claude, pi)
and installs only into those present. Idempotent — skips agents that already
have the skill.

Flags: `--dry-run`, `--no-skill`, `--yes`.

Skill locations:
- opencode: `~/.config/opencode/skills/oh-my-coding-maas-gateway/SKILL.md`
- codex: `~/.codex/skills/oh-my-coding-maas-gateway/SKILL.md`
- pi: `~/.pi/agent/skills/oh-my-coding-maas-gateway/SKILL.md`
- claude: `~/.claude/commands/oh-my-gateway.md` (slash command: `/oh-my-gateway`)

---

## Flags

### `bootstrap.sh`

| Flag | Effect |
|------|--------|
| `--tool=VAL` | `all` (default), `litellm`, `opencode`, `codex`, `claude`, `pi`, or comma combo (e.g. `opencode,codex`). Skips the menu. |
| `--virtual-key=sk-...` | Reuse an existing opencode virtual key, skip minting. |
| `--dry-run` | Preview actions without modifying anything. |
| `--no-skill` | Skip companion skill installation (step 05). |

### `01_env.sh`

| Flag | Effect |
|------|--------|
| `--force` | Regenerate all immutable secrets (for key rotation). Invalidates existing virtual keys. |

### `04_validate.sh`

| Flag | Effect |
|------|--------|
| `--dry-run` | Structure checks only, no network calls. |
| `--litellm-only` | Only LiteLLM proxy checks. |
| `--opencode-only` | Only opencode config checks. |
| `--codex-only` | Only Codex CLI config checks. |
| `--claude-code-only` | Only Claude Code CLI config checks. |
| `--pi-only` | Only Pi agent config checks. |
| `--skip-opencode` | Skip opencode checks (additive). |
| `--skip-codex` | Skip Codex checks (additive). |
| `--skip-claude-code` | Skip Claude Code checks (additive). |
| `--skip-pi` | Skip Pi agent checks (additive). |

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

All other secrets (`LITELLM_SALT_KEY`, `DB_PASSWORD`, `GRAFANA_ADMIN_PASSWORD`,
`PROMETHEUS_RETENTION`) are auto-generated by `01_env.sh` and stored in `.env`.

---

## Colored Output & Action Labels

All scripts use a shared logging system from `helpers/common.sh`:

- **Colors** auto-enable on TTY, disable on piped/CI output.
- `log_step` — bold green box-drawing section headers (`┌── Title ──┐`)
- `log_desc` — cyan info line before each step
- `log_done` — green dim completion line after each step
- `log_ok` / `log_info` / `log_warn` / `log_error` — green ✓ / blue → / yellow ⚠ / red ✗
- `log_dim` — dim secondary text
- `log_action "who" "msg"` — dim `[tag]` prefix showing who's acting

Each script sets a `LOG_TAG` (e.g. `bootstrap`, `env`, `litellm`, `opencode`,
`codex`, `claude`, `validate`). Prerequisite installs are labeled:
`→ [opencode] Installing curl (curl)...`.

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
| `04_validate.sh` | curl, jq |

Interactive mode prompts before each installation. Non-interactive shells
(piped stdin, CI) auto-confirm. Each install is labeled with `[LOG_TAG]`
showing which script triggered it. Bootstrap prints a **prereq→tools mapping**
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
  breaks later steps. `04_validate.sh` receives `--skip-*` for skipped tools.
- Idempotent — safe to re-run. Immutable secrets are preserved; existing
  containers, configs, and valid virtual keys are reused.

---

## Idempotency & Re-run

- If any step's precondition is already met, it skips and verifies the
  postcondition.
- Safe to re-run from any step. Never destroys data or regenerates immutable
  secrets (`LITELLM_MASTER_KEY`, `LITELLM_SALT_KEY`, `DB_PASSWORD`).
- Only `01_env.sh --force` regenerates secrets (for key rotation).

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

After recovery, re-run `04_validate.sh` **once**. If it still fails, escalate
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
- If `git pull` fails: ask "Reset to origin/main? (y/n)".
- **Grafana dashboard updates:** hard-restart to pick up provisioning:
  `docker compose restart grafana`.

After upgrade, restart opencode if it's running (exit with `/exit` or Ctrl+C,
start fresh — plugin/preset changes are not hot-reloaded).

**Upgrade is complete when `04_validate.sh` exits 0.**

---

## Uninstall

`scripts/uninstall.sh` removes all or part of the installation.

| Flags | What it removes |
|-------|-----------------|
| `--tool=opencode` | opencode config only |
| `--tool=opencode,codex` | Subset of agent configs |
| `--tool=all` | All agent configs |
| `--docker` | Docker containers + volumes + images |
| `--repo` | This repo (`.env`, configs, scripts) |
| `--all` | Everything above |
| `--dry-run` | Preview without deleting |
| `--yes` | Skip confirmation |

No flags → interactive menu. Binaries (opencode, codex, claude, pi),
runtimes (bun, pi-node), configs, and `.bashrc` entries are all removed.

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
# Switch preset: /preset LiteLLM-Huawei-MaaS-Core
# Available presets:
#   LiteLLM-Huawei-MaaS-Full  (default, all 6 models via proxy)
#   LiteLLM-Huawei-MaaS-Core  (4 models, no v4-pro/v4-flash)
#   Huawei-MaaS-Full          (direct, bypass proxy)
#   Huawei-MaaS-Core          (direct, bypass proxy)
```

If opencode was already running, exit it first (`/exit` or Ctrl+C).

### Using Codex CLI

```bash
codex
codex --model deepseek-v4-pro    # deep reasoning
codex --model deepseek-v3.2      # fast
```

### Using Claude Code CLI

```bash
claude --bare
claude --bare --model claude-deepseek-v4-pro    # deep reasoning
```

### Using Pi agent

```bash
pi
# Switch model at runtime via Pi's model selection UI
```

### Monitoring

- **Grafana:** `http://127.0.0.1:3000` — 28-panel dashboard (anonymous, no
  login). 6 sections: At-a-glance, Latency, Errors & Health, Throughput &
  Capacity, Tokens, Cost. Time window selectable (default 1h).
- **LiteLLM Admin UI:** `http://127.0.0.1:4000/ui` — view deployments, virtual
  keys, spend, budgets. Login: `admin` / your master key.
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
| LiteLLM Admin UI | `http://127.0.0.1:4000/ui` | Master key | View keys, spend, deployments |
| Grafana Dashboard | `http://127.0.0.1:3000` | Anonymous | 28-panel observability dashboard |
| Prometheus | `http://127.0.0.1:9090` | None | Metrics storage |
| PostgreSQL | `localhost:5432` (internal) | — | LiteLLM database |

### Coding Tools

| Tool | Activate | API Format | Config location |
|------|----------|------------|-----------------|
| opencode | `opencode` | OpenAI Chat Completions | `~/.config/opencode/opencode.json` |
| Codex CLI | `codex` | OpenAI Responses (bridged) | `~/.codex/config.toml` |
| Claude Code CLI | `claude --bare` | Anthropic Messages | `~/.claude/settings.json` |
| Pi agent | `pi` | OpenAI Chat Completions | `~/.pi/agent/models.json` |

Each tool gets its own virtual key with unlimited budget and access to all
models. opencode also gets 4 presets and 7 agents via the
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
| 7 | `--tool=opencode,codex` | Custom combo (comma-separated) |

### Companion Skill

After installation, bootstrap offers to install SKILL.md as a skill into
each detected coding agent. This gives your agents operational guidance
for the gateway.

| Tool | Skill location | How to invoke |
|------|---------------|---------------|
| opencode | `~/.config/opencode/skills/oh-my-coding-maas-gateway/SKILL.md` | Automatic (agent reads skill) |
| Codex CLI | `~/.codex/skills/oh-my-coding-maas-gateway/SKILL.md` | Automatic (agent reads skill) |
| Pi agent | `~/.pi/agent/skills/oh-my-coding-maas-gateway/SKILL.md` | `/skill:oh-my-coding-maas-gateway` |
| Claude Code | `~/.claude/commands/oh-my-gateway.md` | `/oh-my-gateway` (slash command) |

```bash
./scripts/05_skill.sh --yes    # install manually anytime
```
