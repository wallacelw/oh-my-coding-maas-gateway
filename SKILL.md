---
name: oh-my-coding-maas-gateway
description: Operational companion for the oh-my-coding-maas-gateway LiteLLM proxy stack. Provides context and commands for health checks, validation, upgrades, key/model management, debug routing, metrics, and recovery.
---

# oh-my-coding-maas-gateway — Operational Companion

Operational companion for a self-hosted LiteLLM proxy routing Huawei MaaS
models to opencode, Codex CLI, Claude Code CLI, and Pi agent with virtual
keys, multi-key load balancing, and Prometheus + Grafana observability.

## When Invoked

Present this menu. Default (just press Enter) loads context without action:

```
What would you like to do?

  1) Health check     — quick status of all services
  2) Run validation   — full end-to-end validation
  3) Upgrade          — check for and apply updates
  4) Uninstall        — remove all or part of the gateway

  Choice [1-4] or Enter for context only:
```

After completing an action, ask if they need anything else. For anything
not in the menu (key management, model management, debug routing, metrics,
install skill), respond using the reference sections below.

## Project Location

The gateway is at `~/oh-my-coding-maas-gateway`. `cd` there first:

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

---

## Option 1: Health Check

```bash
docker compose ps
curl -sf http://127.0.0.1:4000/health/liveliness && echo "LiteLLM: healthy" || echo "LiteLLM: unhealthy"
curl -sf http://127.0.0.1:3000/api/health && echo "Grafana: healthy" || echo "Grafana: unhealthy"
```

Report: how many containers are running, which are healthy, any issues.
If problems found, suggest fixes from the Recovery table below.

## Option 2: Run Validation

```bash
./scripts/04_validate.sh
```

If failures occur, match them against the Recovery table, suggest the fix,
and offer to run it. WARN messages are advisory only.

## Option 3: Upgrade

```bash
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash
```

After upgrade, remind user to restart any running coding tools.
If Grafana looks stale: `docker compose restart grafana`.

## Option 4: Uninstall

Ask what to remove:

```bash
./scripts/uninstall.sh --all --dry-run   # preview
./scripts/uninstall.sh --tool=opencode   # one agent
./scripts/uninstall.sh --all             # everything
```

---

## Key Management

Read the master key from `.env` when needed:
```bash
MASTER_KEY=$(grep '^LITELLM_MASTER_KEY=' .env | cut -d= -f2 | tr -d '"')
```

**Rotate MaaS key**: edit `.env` (change `HUAWEI_MAAS_API_KEY`), then:
```bash
./scripts/02_litellm.sh
```

**Add load-balancing keys**: edit `.env` — set `HUAWEI_MAAS_API_KEY_COUNT=N`
and add `HUAWEI_MAAS_API_KEY_1`, `_2`, etc. Then:
```bash
./scripts/02_litellm.sh
```

**Mint a virtual key**:
```bash
curl -X POST http://127.0.0.1:4000/key/generate \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"key_alias": "my-tool", "models": ["all"], "max_budget": 0}'
```

**List keys**: point user to `http://127.0.0.1:4000/ui` (login: `admin` /
master key).

## Model Management

Models are in `scripts/helpers/models.sh`. Format:
```
model_name:tpm:rpm:max_tokens:max_input:max_output:input_cost:output_cost
```

Current models: `glm-5.2`, `glm-5.1`, `glm-5`, `deepseek-v4-pro`,
`deepseek-v4-flash`, `deepseek-v3.2`.

**List models**:
```bash
grep -oP '^\s*"\K[^:]+' scripts/helpers/models.sh
```

**Add a model**: add a line to the `MODELS` array in `scripts/helpers/models.sh`,
then regenerate (this creates N deployments per model, one per API key):
```bash
./scripts/02_litellm.sh
./scripts/04_validate.sh
```

**Remove a model**: delete the line from `MODELS`, then same regenerate +
validate.

## Debug Routing

**401 errors**:
```bash
docker compose logs litellm --tail 100 | grep 401
```

**Slow/no response**:
```bash
curl -sf http://127.0.0.1:4000/health/liveliness
docker compose logs litellm --tail 100 | grep -i error
curl -sf 'http://127.0.0.1:9090/api/v1/query?query=litellm_request_total_latency_seconds_sum' | jq .
```

**Inference smoke test**:
```bash
MASTER_KEY=$(grep '^LITELLM_MASTER_KEY=' .env | cut -d= -f2 | tr -d '"')
curl -X POST http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "deepseek-v3.2", "messages": [{"role": "user", "content": "hi"}], "max_tokens": 5}'
```

## View Metrics

```bash
curl -sf 'http://127.0.0.1:9090/api/v1/query?query=litellm_total_requests' | jq .
curl -sf 'http://127.0.0.1:9090/api/v1/query?query=litellm_spend' | jq .
curl -sf 'http://127.0.0.1:9090/api/v1/query?query=rate(litellm_total_errors[5m])' | jq .
```

Grafana: `http://127.0.0.1:3000` — 28-panel dashboard.

## Install a New Skill

Ask for skill name and source (local path or URL), then:
```bash
./scripts/install-skill.sh --name=<name> --source=<path-or-url>
```

Remind user to restart their coding agents afterward.

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

## Remote Access

**SSH forwarding (recommended):**
```bash
ssh -L 4000:127.0.0.1:4000 -L 3000:127.0.0.1:3000 user@vm
```

**Bind to all interfaces:** set `BIND_ADDRESS="0.0.0.0"` in `.env`, then
`docker compose up -d`.
