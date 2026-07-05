---
name: oh-my-coding-maas-gateway
description: Operational companion for the oh-my-coding-maas-gateway LiteLLM proxy stack. When invoked, presents an interactive menu of operations: health check, validation, upgrade, key/model management, debug routing, metrics, and more. Can also be loaded as passive context.
---

# oh-my-coding-maas-gateway — Operational Companion

This is an operational companion for the oh-my-coding-maas-gateway — a
self-hosted LiteLLM proxy routing Huawei MaaS models to opencode, Codex
CLI, Claude Code CLI, and Pi agent with virtual keys, multi-key load
balancing, and Prometheus + Grafana observability.

Bootstrap is the only installation method. This skill helps operate the
running stack.

## When Invoked

When the user invokes this skill, present the following menu. Ask them to
choose a number (or describe what they need). If the request is already
specific (e.g. "check health" or "rotate my key"), skip the menu and go
straight to that option.

```
What would you like to do?

  1) Health check         — quick status of all services
  2) Run validation       — full end-to-end validation
  3) Upgrade              — check for and apply updates
  4) Key management       — rotate, add, or mint keys
  5) Model management     — list, add, or remove models
  6) Debug routing        — diagnose 401s, latency, errors
  7) View metrics         — Prometheus queries + Grafana link
  8) Install skill        — install this skill into all agents
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
# Container status
docker compose ps

# LiteLLM health
curl -sf http://127.0.0.1:4000/health/liveliness && echo "healthy" || echo "unhealthy"

# Prometheus targets
curl -sf http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Grafana health
curl -sf http://127.0.0.1:3000/api/health
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
```bash
# 1. Get new key from Huawei cloud console (region ap-southeast-1)
# 2. Update .env — change HUAWEI_MAAS_API_KEY
# 3. Regenerate and restart:
./scripts/02_litellm.sh
```

**b) Add load-balancing keys**
```bash
# 1. Edit .env:
#    HUAWEI_MAAS_API_KEY_COUNT=3
#    HUAWEI_MAAS_API_KEY_1="sk-new-key-1"
#    HUAWEI_MAAS_API_KEY_2="sk-new-key-2"
# 2. Regenerate and restart:
./scripts/02_litellm.sh
```

**c) Mint a new virtual key** (for an additional tool)
```bash
curl -X POST http://127.0.0.1:4000/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"key_alias": "my-new-tool", "models": ["all"], "max_budget": 0}'
```

**d) List existing keys** — point user to `http://127.0.0.1:4000/ui`
(login: `admin` / master key from `.env`).

## Option 5: Model Management

Models are defined in `scripts/helpers/models.sh`. Format:
```
model_name:tpm:rpm:max_tokens:max_input:max_output:input_cost:output_cost
```

Ask which sub-action:

**a) List models**
```bash
grep -oP '^\s*"\K[^:]+' scripts/helpers/models.sh
```

**b) Add a model** — edit `models.sh`, add entry to `MODELS` array, then:
```bash
./scripts/02_litellm.sh && ./scripts/04_validate.sh
```

**c) Remove a model** — delete the entry from `models.sh`, then same
regenerate + validate.

## Option 6: Debug Routing

Ask what the user is experiencing:

**a) Tool getting 401 errors**
```bash
# Check the tool's virtual key is valid
curl -sf http://127.0.0.1:4000/key/info?key=<virtual-key> \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"

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
curl -X POST http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
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

Install this companion skill into all detected coding agents:

```bash
./scripts/05_skill.sh --yes
```

Skill locations:
- opencode: `~/.config/opencode/skills/oh-my-coding-maas-gateway/SKILL.md`
- codex: `~/.codex/skills/oh-my-coding-maas-gateway/SKILL.md`
- pi: `~/.pi/agent/skills/oh-my-coding-maas-gateway/SKILL.md`
- claude: `~/.claude/skills/oh-my-coding-maas-gateway/SKILL.md`

## Option 9: Uninstall

Ask what to remove:

```bash
# Preview
./scripts/uninstall.sh --all --dry-run

# One agent
./scripts/uninstall.sh --tool=opencode

# Docker stack only
./scripts/uninstall.sh --docker

# Everything
./scripts/uninstall.sh --all
```

Removes binaries, runtimes, configs, companion skills, and `.bashrc` entries.

## Option 10: Just Load Context

No action. The agent now has the operational context loaded and can answer
questions about the gateway, suggest commands, or help with issues using
the reference tables below.

---

## Reference

### Services

| Service | URL | Auth |
|---------|-----|------|
| LiteLLM Proxy | `http://127.0.0.1:4000` | Virtual key |
| LiteLLM Admin UI | `http://127.0.0.1:4000/ui` | Master key |
| Grafana Dashboard | `http://127.0.0.1:3000` | Anonymous |
| Prometheus | `http://127.0.0.1:9090` | None |

### Installation

```bash
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash
```

Bootstrap prompts for MaaS API key (validated at prompt time), install
scope (menu or `--tool=`), and optional extra keys for load balancing.
Prerequisites auto-installed. ~5 min fresh, ~2 min upgrade.

### Recovery

| Symptom | Fix |
|---------|-----|
| `.env not found` / `placeholder value` | Re-run `scripts/01_env.sh` |
| Fewer than 4 containers running | `docker compose up -d`, wait 30s |
| LiteLLM liveness probe fails | `docker compose logs litellm --tail 50` |
| Inference smoke test fails | Check MaaS key validity; `docker compose logs litellm --tail 100` |
| `opencode not found` / config issues | Re-run `scripts/03a_opencode.sh` |
| `codex not found` / config issues | Re-run `scripts/03b_codex.sh` |
| `claude not found` / config issues | Re-run `scripts/03c_claude_code.sh` |
| `pi not found` / config issues | Re-run `scripts/03d_pi.sh` |
| Prometheus not reachable | `docker compose up -d prometheus`, wait 10s |
| `/metrics` endpoint not responding | `docker compose restart litellm`, wait 15s |
| Grafana not reachable | `docker compose up -d grafana`, wait 20s |
| Docker daemon not running | `systemctl start docker` |
| Port 4000/3000/9090 in use | `lsof -i :<port>`, stop conflicting process |
| `git pull` conflicts on upgrade | `git stash && git pull && git stash pop` |

### Remote Access

**SSH forwarding (recommended):**
```bash
ssh -L 4000:127.0.0.1:4000 -L 3000:127.0.0.1:3000 user@vm
```

**Bind to all interfaces:**
```bash
# In .env: BIND_ADDRESS="0.0.0.0"
# Then: docker compose up -d
```

### Models

`glm-5.2`, `glm-5.1`, `glm-5`, `deepseek-v4-pro`, `deepseek-v4-flash`,
`deepseek-v3.2` — defined in `scripts/helpers/models.sh`.
