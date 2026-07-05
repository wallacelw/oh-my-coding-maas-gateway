---
name: oh-my-coding-maas-gateway
description: Operational companion for the oh-my-coding-maas-gateway LiteLLM proxy stack. When invoked, presents an interactive menu of operations: health check, validation, upgrade, key/model management, debug routing, metrics, and more. Can also be loaded as passive context.
---

# oh-my-coding-maas-gateway — Operational Companion

Operational companion for a self-hosted LiteLLM proxy routing Huawei MaaS
models to opencode, Codex CLI, Claude Code CLI, and Pi agent with virtual
keys, multi-key load balancing, and Prometheus + Grafana observability.

Bootstrap is the only installation method. This skill helps operate the
running stack.

## Project Location

The gateway is installed at `$HOME/oh-my-coding-maas-gateway` (or wherever
the user chose during install). All scripts below are relative to this
directory. If you're not in the project dir, `cd` there first:

```bash
cd ~/oh-my-coding-maas-gateway
```

## Available Scripts

| Script | Purpose | Key flags |
|--------|---------|-----------|
| `scripts/bootstrap.sh` | Install or upgrade the entire stack | `--tool=`, `--dry-run`, `--no-skill` |
| `scripts/04_validate.sh` | End-to-end validation (run anytime) | `--skip-opencode`, `--skip-codex`, `--skip-claude-code`, `--skip-pi`, `--dry-run` |
| `scripts/05_skill.sh` | Install THIS companion skill into agents | `--yes`, `--dry-run`, `--no-skill` |
| `scripts/install-skill.sh` | Install ANY skill into all detected agents | `--name=`, `--source=`, `--dry-run` |
| `scripts/uninstall.sh` | Remove all or part of the gateway | `--tool=`, `--docker`, `--all`, `--dry-run`, `--yes` |
| `scripts/02_litellm.sh` | Regenerate LiteLLM config + restart (after editing `.env` or `models.sh`) | `--dry-run` |
| `scripts/01_env.sh` | Regenerate `.env` (after key changes) | `--force` |

## Services

| Service | URL | Auth |
|---------|-----|------|
| LiteLLM Proxy | `http://127.0.0.1:4000` | Virtual key |
| LiteLLM Admin UI | `http://127.0.0.1:4000/ui` | Master key (from `.env`) |
| Grafana Dashboard | `http://127.0.0.1:3000` | Anonymous |
| Prometheus | `http://127.0.0.1:9090` | None |

## When Invoked

When the user invokes this skill, present the following menu. If the
user's request is already specific (e.g. "check health" or "rotate my
key"), skip the menu and go straight to that option.

```
What would you like to do?

  1) Health check         — quick status of all services
  2) Run validation       — full end-to-end validation
  3) Upgrade              — check for and apply updates
  4) Key management       — rotate, add, or mint keys
  5) Model management     — list, add, or remove models
  6) Debug routing        — diagnose 401s, latency, errors
  7) View metrics         — Prometheus queries + Grafana link
  8) Install skill        — install a new skill into all agents
  9) Uninstall            — remove all or part of the gateway
 10) Just load context    — no action, I just need the reference info

  Choice [1-10]:
```

After completing an action, ask if the user wants to do anything else.
Loop until they're done.

---

## Option 1: Health Check

Run these commands and report the status:

```bash
docker compose ps
curl -sf http://127.0.0.1:4000/health/liveliness && echo "LiteLLM: healthy" || echo "LiteLLM: unhealthy"
curl -sf http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
curl -sf http://127.0.0.1:3000/api/health && echo "Grafana: healthy" || echo "Grafana: unhealthy"
```

Report: how many containers are running, which are healthy, any issues.
If problems found, suggest fixes from the Recovery table below.

## Option 2: Run Validation

```bash
./scripts/04_validate.sh
```

Interpret the results:
- **All passed** — report healthy, show summary.
- **Failures** — for each failure, match the Recovery table, suggest the
  fix, and offer to run it.
- **Warnings** — advisory only, report but don't act unless asked.

## Option 3: Upgrade

```bash
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash
```

Bootstrap detects existing install, compares versions, pulls updates.
After upgrade, remind the user to restart any running coding tools.

If Grafana looks stale: `docker compose restart grafana`.

## Option 4: Key Management

Ask which sub-action:

**a) Rotate MaaS API key**

The MaaS key is in `.env` as `HUAWEI_MAAS_API_KEY`. To rotate:
1. Get a new key from Huawei cloud console (region ap-southeast-1)
2. Edit `.env`: replace `HUAWEI_MAAS_API_KEY` value
3. Regenerate config and restart:
```bash
./scripts/02_litellm.sh
```

**b) Add load-balancing keys**

1. Edit `.env`:
   - Set `HUAWEI_MAAS_API_KEY_COUNT=3` (or however many total keys)
   - Add `HUAWEI_MAAS_API_KEY_1="sk-..."`, `HUAWEI_MAAS_API_KEY_2="sk-..."`
2. Regenerate and restart:
```bash
./scripts/02_litellm.sh
```

**c) Mint a new virtual key** (for an additional tool)

```bash
# Read master key from .env
MASTER_KEY=$(grep '^LITELLM_MASTER_KEY=' .env | cut -d= -f2 | tr -d '"')

# Mint a new key
curl -X POST http://127.0.0.1:4000/key/generate \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"key_alias": "my-new-tool", "models": ["all"], "max_budget": 0}'
```

**d) List existing keys** — point user to `http://127.0.0.1:4000/ui`
(login: `admin` / master key from `.env`).

## Option 5: Model Management

Models are defined in `scripts/helpers/models.sh` — the single source of
truth. Each line in the `MODELS` array has this format:

```
model_name:tpm:rpm:max_tokens:max_input:max_output:input_cost:output_cost
```

Current models: `glm-5.2`, `glm-5.1`, `glm-5`, `deepseek-v4-pro`,
`deepseek-v4-flash`, `deepseek-v3.2`.

Ask which sub-action:

**a) List models**
```bash
grep -oP '^\s*"\K[^:]+' scripts/helpers/models.sh
```

**b) Add a model**

1. Edit `scripts/helpers/models.sh` — add a new line to the `MODELS` array
   with the model details
2. Regenerate config and validate:
```bash
./scripts/02_litellm.sh
./scripts/04_validate.sh
```

**c) Remove a model**

1. Edit `scripts/helpers/models.sh` — delete the line from `MODELS`
2. Same regenerate + validate as above.

## Option 6: Debug Routing

Ask what the user is experiencing:

**a) Tool getting 401 errors**
```bash
MASTER_KEY=$(grep '^LITELLM_MASTER_KEY=' .env | cut -d= -f2 | tr -d '"')

# Check the tool's virtual key is valid
curl -sf http://127.0.0.1:4000/key/info?key=<virtual-key> \
  -H "Authorization: Bearer $MASTER_KEY"

# Check LiteLLM logs
docker compose logs litellm --tail 100 | grep 401
```

**b) Model not responding or slow**
```bash
# Deployment health
curl -sf http://127.0.0.1:4000/health/liveliness

# Latency from Prometheus
curl -sf 'http://127.0.0.1:9090/api/v1/query?query=litellm_request_total_latency_seconds_sum' | jq .

# Error logs
docker compose logs litellm --tail 100 | grep -i error
```

**c) Inference smoke test**
```bash
MASTER_KEY=$(grep '^LITELLM_MASTER_KEY=' .env | cut -d= -f2 | tr -d '"')

curl -X POST http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "deepseek-v3.2", "messages": [{"role": "user", "content": "hi"}], "max_tokens": 5}'
```

## Option 7: View Metrics

Show the Grafana link and run Prometheus queries:

```bash
# Total requests by model
curl -sf 'http://127.0.0.1:9090/api/v1/query?query=litellm_total_requests' | jq .

# Spend by model
curl -sf 'http://127.0.0.1:9090/api/v1/query?query=litellm_spend' | jq .

# Error rate (5m window)
curl -sf 'http://127.0.0.1:9090/api/v1/query?query=rate(litellm_total_errors[5m])' | jq .
```

Grafana: `http://127.0.0.1:3000` — 28-panel dashboard (anonymous).
LiteLLM Admin: `http://127.0.0.1:4000/ui` — keys, spend, deployments.

## Option 8: Install Skill

Install a **new** skill (not this one) into all detected coding agents.
Ask the user for:

1. **Skill name** — directory name (e.g. `my-deploy-skill`)
2. **Skill source** — a local file path or URL to a SKILL.md file

Then run:

```bash
# From a local file
./scripts/install-skill.sh --name=my-skill --source=/path/to/SKILL.md

# From a URL
./scripts/install-skill.sh --name=my-skill --source=https://example.com/SKILL.md

# Preview first
./scripts/install-skill.sh --name=my-skill --source=... --dry-run
```

This installs into all detected agents (`~/.config/opencode/skills/`,
`~/.codex/skills/`, `~/.pi/agent/skills/`, `~/.claude/skills/`).

The SKILL.md file should have YAML frontmatter with `name` and `description`.

After installing, remind the user to restart their coding agents for the
new skill to be discovered.

## Option 9: Uninstall

Ask what to remove:

```bash
# Preview everything that would be removed
./scripts/uninstall.sh --all --dry-run

# Remove one agent only
./scripts/uninstall.sh --tool=opencode

# Remove Docker stack only
./scripts/uninstall.sh --docker

# Remove everything (agents + skills + Docker + repo)
./scripts/uninstall.sh --all
```

Removes binaries, runtimes (bun, pi-node), configs, companion skills,
and `.bashrc` entries.

## Option 10: Just Load Context

No action. The agent now has the operational context loaded and can answer
questions about the gateway, suggest commands, or help with issues using
the reference tables in this skill.

---

## Recovery

| Symptom | Fix |
|---------|-----|
| `.env not found` / `placeholder value` | `./scripts/01_env.sh` |
| Fewer than 4 containers running | `docker compose up -d`, wait 30s |
| LiteLLM liveness probe fails | `docker compose logs litellm --tail 50` |
| Inference smoke test fails | Check MaaS key in `.env`; `docker compose logs litellm --tail 100` |
| `opencode not found` / config issues | `./scripts/03a_opencode.sh` |
| `codex not found` / config issues | `./scripts/03b_codex.sh` |
| `claude not found` / config issues | `./scripts/03c_claude_code.sh` |
| `pi not found` / config issues | `./scripts/03d_pi.sh` |
| Prometheus not reachable | `docker compose up -d prometheus`, wait 10s |
| `/metrics` endpoint not responding | `docker compose restart litellm`, wait 15s |
| Grafana not reachable | `docker compose up -d grafana`, wait 20s |
| Docker daemon not running | `systemctl start docker` |
| Port 4000/3000/9090 in use | `lsof -i :<port>`, stop conflicting process |
| `git pull` conflicts on upgrade | `git stash && git pull && git stash pop` |

WARN messages in validation output are advisory — they do not cause
non-zero exit.

## Remote Access

**SSH forwarding (recommended):**
```bash
ssh -L 4000:127.0.0.1:4000 -L 3000:127.0.0.1:3000 user@vm
```

**Bind to all interfaces:**
```bash
# In .env: BIND_ADDRESS="0.0.0.0"
# Then: docker compose up -d
```
