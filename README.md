# oh-my-coding-maas-gateway

LiteLLM proxy routing Huawei MaaS models to opencode, Codex CLI, Claude
Code CLI, and Pi agent — with virtual keys, multi-key load balancing,
dual-format endpoints, and Prometheus + Grafana observability.

---

## What Is This?

A self-hosted gateway that sits between your coding tools and Huawei ModelArts
MaaS, giving you load balancing, virtual keys, budget tracking, and
observability — all through a single local proxy.

```
  Tools               LiteLLM (:4000)                  Huawei MaaS
  ─────               ───────────────                  ────────────

  opencode    ──→ /v1/chat/completions ──→ openai/ provider    ──→ MaaS OpenAI endpoint
  Codex CLI   ──→ /v1/responses        ──→ openai/ provider    ──→ MaaS OpenAI endpoint
  Claude Code ──→ /v1/messages         ──→ anthropic/ provider ──→ MaaS Anthropic endpoint
  Pi agent    ──→ /v1/chat/completions ──→ openai/ provider    ──→ MaaS OpenAI endpoint

  LiteLLM: load-balances across N MaaS keys · PostgreSQL (:5432)
  Observability: LiteLLM ──/metrics──→ Prometheus (:9090) ──→ Grafana (:3000)
```

**6 models:** glm-5.2, glm-5.1, glm-5, deepseek-v4-pro, deepseek-v4-flash,
deepseek-v3.2

---

## Install

The bootstrap script is the only installation method. It handles
everything — prerequisites, Docker stack, coding tools, virtual keys,
validation, and optional companion skill.

```bash
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash
```

Bootstrap will:
1. Detect an existing install and offer upgrade (pull updates) or fresh install
2. Prompt for your Huawei MaaS API key (validated at prompt time)
3. Show an interactive menu to select which coding tools to install
4. Auto-install prerequisites (Docker, git, curl, jq, bun, npm) with explanations
5. Deploy the LiteLLM proxy + observability stack
6. Install and configure each selected coding tool with its own virtual key
7. Run end-to-end validation
8. Offer to install the companion skill into your coding agents

Estimated time: ~5 min fresh, ~2 min upgrade.

### Non-interactive (flags)

```bash
# Install LiteLLM + all coding tools
HUAWEI_MAAS_API_KEY="sk-..." curl -fsSL .../bootstrap.sh | bash -s -- --tool=all

# Install LiteLLM only
curl -fsSL .../bootstrap.sh | bash -s -- --tool=litellm

# Custom combo
curl -fsSL .../bootstrap.sh | bash -s -- --tool=opencode,codex
```

### After install

```bash
opencode          # or: codex  or:  claude --bare  or:  pi
```

Monitor at `http://localhost:3000` (Grafana) or `http://localhost:4000/ui`
(LiteLLM Admin).

---

## Upgrade

Same command — bootstrap detects existing install, compares versions, and
pulls updates. All secrets and data preserved.

```bash
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash
```

After upgrade, restart any running coding tools — plugin/preset changes
are not hot-reloaded.

---

## Companion Skill

After installation, bootstrap offers to install
[SKILL.md](./SKILL.md) as a skill into each detected coding agent. This
gives your agents operational guidance for the gateway:

- **Health diagnosis** — run validation, interpret results, check logs
- **Key management** — rotate MaaS keys, add load-balancing keys, mint virtual keys
- **Model management** — add/remove models via `models.sh`
- **Debug routing** — diagnose 401s, latency, failed inference
- **Observability** — read Grafana panels, query Prometheus metrics
- **Recovery** — fix port conflicts, dead containers, failed health checks

| Tool | Skill location | How to invoke |
|------|---------------|---------------|
| opencode | `~/.config/opencode/skills/oh-my-coding-maas-gateway/SKILL.md` | Automatic (agent reads skill) |
| Codex CLI | `~/.codex/skills/oh-my-coding-maas-gateway/SKILL.md` | Automatic (agent reads skill) |
| Pi agent | `~/.pi/agent/skills/oh-my-coding-maas-gateway/SKILL.md` | `/skill:oh-my-coding-maas-gateway` |
| Claude Code | `~/.claude/commands/oh-my-gateway.md` | `/oh-my-gateway` (slash command) |

You can also install the skill manually anytime:

```bash
./scripts/05_skill.sh --yes
```

---

## What You Get

| Service | URL | Auth | Purpose |
|---------|-----|------|---------|
| LiteLLM Proxy | `http://127.0.0.1:4000` | Virtual key | API gateway |
| LiteLLM Admin UI | `http://127.0.0.1:4000/ui` | Master key | View keys, spend, deployments |
| Grafana Dashboard | `http://127.0.0.1:3000` | Anonymous | 28-panel observability dashboard |
| Prometheus | `http://127.0.0.1:9090` | None | Metrics storage |
| PostgreSQL | `localhost:5432` (internal) | — | LiteLLM database |

**Coding tools installed:**

| Tool | Activate | API Format | Config location |
|------|----------|------------|-----------------|
| opencode | `opencode` | OpenAI Chat Completions | `~/.config/opencode/opencode.json` |
| Codex CLI | `codex` | OpenAI Responses (bridged) | `~/.codex/config.toml` |
| Claude Code CLI | `claude --bare` | Anthropic Messages | `~/.claude/settings.json` |
| Pi agent | `pi` | OpenAI Chat Completions | `~/.pi/agent/models.json` |

Each tool gets its own virtual key with unlimited budget and access to all
models. opencode also gets 4 presets and 7 agents via the
oh-my-opencode-slim plugin.

---

## Install Modes

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

---

## Prerequisites

**OS:** Linux (Debian/Ubuntu with systemd recommended).

**Auto-installed** by the scripts as needed (no manual setup required):
git, python3, curl, jq, docker + compose, bun, npm/node, bubblewrap.

In interactive mode, you'll be prompted before each installation. Non-interactive
shells (piped stdin, CI) auto-confirm.

**Non-Debian systems** (RHEL, Alpine, Arch): Install the equivalent packages
manually — see the prerequisite table in [INSTALLATION.md](./INSTALLATION.md).
Docker daemon start requires systemd.

---

## After Install

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

### Remote Access (from another machine)

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

---

## Uninstall

Remove all or part of the installation. Interactive menu if no flags.

```bash
# Remove one agent's config + companion skill
./scripts/uninstall.sh --tool=opencode

# Remove a subset
./scripts/uninstall.sh --tool=opencode,codex

# Remove all agent configs + companion skills
./scripts/uninstall.sh --tool=all

# Remove Docker stack (containers + volumes + images)
./scripts/uninstall.sh --docker

# Remove everything (agents + skills + Docker + this repo)
./scripts/uninstall.sh --all

# Preview without deleting
./scripts/uninstall.sh --all --dry-run
```

Binaries (opencode, codex, claude, pi), runtimes (bun, pi-node), configs,
companion skills, and `.bashrc` entries are all removed. Use `--dry-run`
first to see exactly what would be deleted.

---

## Documentation

| File | For | Description |
|------|-----|-------------|
| **[INSTALLATION.md](./INSTALLATION.md)** | Everyone | Install process, pipeline, per-script details, flags, env vars, prerequisites, recovery, upgrade |
| **[SKILL.md](./SKILL.md)** | Agents | Operational companion: install, upgrade, diagnose, key/model management, recovery |
| **[REFERENCE.md](./REFERENCE.md)** | Everyone | Architecture, config, env vars, tool integration, repair guide, lifecycle |
| **[CHANGELOG.md](./CHANGELOG.md)** | Everyone | Version history |
| **[AGENTS.md](./AGENTS.md)** | Contributors | Development rules, validation, commit conventions |
