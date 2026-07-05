---
name: oh-my-coding-maas-gateway
description: Operational companion for the oh-my-coding-maas-gateway LiteLLM proxy stack. Helps with installation guidance, upgrades, health diagnosis, key management, model management, and recovery — not a replacement for bootstrap.
---

# oh-my-coding-maas-gateway — Operational Companion

This is a companion guide for agents operating alongside the
oh-my-coding-maas-gateway — a self-hosted LiteLLM proxy routing Huawei
MaaS models to opencode, Codex CLI, Claude Code CLI, and Pi agent with
virtual keys, multi-key load balancing, and Prometheus + Grafana
observability.

Bootstrap is the only installation method. This guide helps you
**install**, **upgrade**, **diagnose**, **manage**, and **recover** the
running stack.

## Services

| Service | URL | Auth |
|---------|-----|------|
| LiteLLM Proxy | `http://127.0.0.1:4000` | Virtual key |
| LiteLLM Admin UI | `http://127.0.0.1:4000/ui` | Master key |
| Grafana Dashboard | `http://127.0.0.1:3000` | Anonymous |
| Prometheus | `http://127.0.0.1:9090` | None |

## Installation

If the gateway is not yet installed, bootstrap handles everything —
prerequisites, Docker stack, coding tools, virtual keys, validation.

```bash
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash
```

Bootstrap will prompt for:
- **MaaS API key** — from Huawei cloud console, region ap-southeast-1.
  Validated at prompt time (invalid keys re-prompt).
- **Install scope** — which coding tools to install (menu or `--tool=`).
- **Extra MaaS keys** — optional, for multi-key load balancing.

Prerequisites (Docker, git, curl, jq, bun, npm) are auto-installed with
explanations before each. Estimated time: ~5 min fresh.

For full install details, see
[INSTALLATION.md](https://github.com/wallacelw/oh-my-coding-maas-gateway/blob/main/INSTALLATION.md).

## Upgrade

Same command — bootstrap detects existing install, compares versions, and
pulls updates. All secrets and data preserved.

```bash
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash
```

After upgrade, restart any running coding tools (opencode, codex, etc.) —
plugin/preset changes are not hot-reloaded.

If Grafana dashboard looks stale after upgrade: `docker compose restart grafana`.

## Health Check

Run the validation script anytime:

```bash
./scripts/04_validate.sh
```

Checks LiteLLM health, config sync, inference smoke test, observability
stack, and each coding tool's configuration. Exit 0 = healthy.

### Quick diagnosis commands

```bash
# Container status
docker compose ps

# LiteLLM logs (last 50 lines)
docker compose logs litellm --tail 50

# Check if all 4 containers are healthy
docker compose ps --format json | jq '[.[] | .State] | unique'

# LiteLLM health endpoint
curl -sf http://127.0.0.1:4000/health/liveliness

# Prometheus targets
curl -sf http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
```

## Key Management

### Rotate MaaS API key

```bash
# 1. Get new key from Huawei cloud console
# 2. Update .env
nano .env  # change HUAWEI_MAAS_API_KEY
# 3. Regenerate LiteLLM config and restart
./scripts/02_litellm.sh
```

### Add load-balancing keys

```bash
# 1. Edit .env — increase HUAWEI_MAAS_API_KEY_COUNT and add keys
HUAWEI_MAAS_API_KEY_COUNT=3
HUAWEI_MAAS_API_KEY_1="sk-new-key-1"
HUAWEI_MAAS_API_KEY_2="sk-new-key-2"
# 2. Regenerate and restart
./scripts/02_litellm.sh
```

### Mint a new virtual key (for an additional tool)

```bash
# Via LiteLLM Admin API
curl -X POST http://127.0.0.1:4000/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"key_alias": "my-new-tool", "models": ["all"], "max_budget": 0}'
```

View existing keys at `http://127.0.0.1:4000/ui` (login: `admin` / master key).

## Model Management

Models are defined in `scripts/helpers/models.sh` — the single source of
truth. Format:

```
model_name:tpm:rpm:max_tokens:max_input:max_output:input_cost:output_cost
```

### Add a model

```bash
# 1. Edit scripts/helpers/models.sh — add entry to MODELS array
# 2. Regenerate LiteLLM config and restart
./scripts/02_litellm.sh
# 3. Verify
./scripts/04_validate.sh
```

### Remove a model

Same process — delete the entry from `models.sh`, regenerate, restart.

## Debug Routing

### Tool getting 401 errors

```bash
# Check the tool's virtual key is valid
curl -sf http://127.0.0.1:4000/key/info?key=<virtual-key> \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"

# Check LiteLLM logs for the error
docker compose logs litellm --tail 100 | grep 401
```

### Model not responding or slow

```bash
# Check deployment health
curl -sf http://127.0.0.1:4000/health/liveliness

# Check Prometheus for latency
curl -sf 'http://127.0.0.1:9090/api/v1/query?query=litellm_request_total_latency_seconds_sum' | jq .

# Check LiteLLM logs
docker compose logs litellm --tail 100 | grep -i error
```

### Inference smoke test

```bash
curl -X POST http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "deepseek-v3.2", "messages": [{"role": "user", "content": "hi"}], "max_tokens": 5}'
```

## Observability

### Grafana dashboard

Open `http://127.0.0.1:3000` — 28-panel dashboard with 6 sections:
At-a-glance, Latency, Errors & Health, Throughput & Capacity, Tokens, Cost.
Default time window: 1h (selectable).

### Prometheus queries

```bash
# Total requests by model
curl -sf 'http://127.0.0.1:9090/api/v1/query?query=litellm_total_requests' | jq .

# Spend by model
curl -sf 'http://127.0.0.1:9090/api/v1/query?query=litellm_spend' | jq .

# Error rate
curl -sf 'http://127.0.0.1:9090/api/v1/query?query=rate(litellm_total_errors[5m])' | jq .
```

## Recovery

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

WARN messages in validation output are advisory — they do not cause
non-zero exit.

## Uninstall

```bash
# Preview what would be removed
./scripts/uninstall.sh --all --dry-run

# Remove one agent
./scripts/uninstall.sh --tool=opencode

# Remove Docker stack only
./scripts/uninstall.sh --docker

# Remove everything (agents + Docker + repo)
./scripts/uninstall.sh --all
```

Removes binaries, runtimes (bun, pi-node), configs, and `.bashrc` entries.

## Remote Access

Ports bind to `127.0.0.1` by default. For remote access from a VM:

**SSH forwarding (recommended):**
```bash
ssh -L 4000:127.0.0.1:4000 -L 3000:127.0.0.1:3000 user@vm
```

**Bind to all interfaces:**
```bash
# In .env: BIND_ADDRESS="0.0.0.0"
# Then: docker compose up -d
```
