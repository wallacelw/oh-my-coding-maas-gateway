# oh-my-litellm-opencode

One command to deploy a production-ready AI coding stack: **LiteLLM proxy** routing through **Huawei ModelArts MaaS**, with **OpenLit + ClickHouse** observability, **opencode** bootstrap, virtual keys, 4 presets, and multi-key load balancing.

## What You Get

- **5 production models** via a single local proxy (`http://127.0.0.1:4000`)
- **Virtual key auth** — opencode uses a scoped key, not your master key
- **Multi-key load balancing** — add N MaaS keys, effective RPM/TPM = per-key × N
- **Automatic fallback** — if a model fails, the next in the array takes over
- **4 presets** — full/Lite × proxy/direct, switchable at runtime with `/preset`
- **Full observability** — OpenLit dashboards with ITL, TTFT, TPOT, cost, traces
- **30-day analytics** — ClickHouse SQL over all traces and metrics

## Architecture

```
 opencode                    LiteLLM Proxy (:4000)              Huawei MaaS
 ─────────                   ─────────────────────              ─────────────
 orchestrator ─┐                                    ┌───────→ glm-5.1
 oracle ───────┤                                    ├───────→ glm-5
 council ──────┤    virtual key (sk-...)            ├───────→ deepseek-v4-pro
 librarian ────┤──────────────────────→  LiteLLM  ──┤───────→ deepseek-v4-flash
 explorer ─────┤    (scoped, unlimited)   │         └───────→ deepseek-v3.2
 designer ─────┤                        │
 fixer ────────┘                        │    N API keys (load-balanced)
                                        │    LiteLLM fans out each model
                                        │    across N deployments
                                        │
                              ┌─────────┴──────────┐
                              │                    │
                         PostgreSQL (:5432)    OpenLit (:3000)
                         keys · spend · usage   dashboards · traces
                                                │
                                           OTLP (:4317/:4318)
                                                │
                                          ClickHouse (:8123)
                                          30-day SQL analytics
```

Startup: PostgreSQL + ClickHouse (parallel) → LiteLLM + OpenLit (parallel, healthcheck-gated).

## Quick Start

### AI agents

```bash
git clone https://github.com/wallacelw/oh-my-litellm-opencode /home/oh-my-litellm-opencode
cd /home/oh-my-litellm-opencode
export HUAWEI_MAAS_API_KEY="your-key-from-modelarts-console"
./scripts/bootstrap.sh --maas-key="$HUAWEI_MAAS_API_KEY"
opencode
```

With `--maas-key=KEY`, the main key is pre-filled. You'll be prompted for extra keys for load balancing (press Enter to skip). All secrets are auto-generated.

### Humans

```bash
git clone https://github.com/wallacelw/oh-my-litellm-opencode /home/oh-my-litellm-opencode
cd /home/oh-my-litellm-opencode
./scripts/bootstrap.sh          # prompts for MaaS key + extra keys
opencode
```

### Step-by-step

```bash
./scripts/init_env.sh --auto    # generate .env with all secrets
./scripts/generate_config.sh    # build litellm_config.yaml from .env
docker compose up -d            # start all 4 services
./scripts/install.sh            # install opencode + plugin + mint key + write config
./scripts/validate.sh           # verify everything works
```

## Endpoints

| Service | URL | Auth |
|---------|-----|------|
| LiteLLM Proxy | `http://127.0.0.1:4000` | Virtual key (`sk-...`) |
| LiteLLM Admin UI | `http://127.0.0.1:4000/ui` | Master key |
| OpenLit UI | `http://127.0.0.1:3000` | `user@openlit.io` / `openlituser` (change after first login) |
| ClickHouse | `http://127.0.0.1:8123` | `default / OPENLIT_DB_PASSWORD` |

## For AI Agents

The full operational reference is in **[SKILL.md](https://github.com/wallacelw/oh-my-litellm-opencode/blob/main/SKILL.md)**. Read it before making any changes to this repo. It contains:

- **Core Rules** — invariants that must always hold
- **Deployment Workflow** — step-by-step with idempotency guarantees
- **Presets & Agent Assignments** — model routing per agent
- **Models** — specs, costs, and how to add new ones
- **Multi-Key Load Balancing** — how N keys multiply capacity
- **Observability** — OpenLit SDK setup, ITL/TTFT/TPOT metrics
- **Upgrade Paths** — per-service procedures
- **Repair Playbook** — common failures and rollback
- **Determinism Guarantees** — 19 properties ensuring idempotent re-runs
- **Verification Exit Criteria** — 12-point checklist
