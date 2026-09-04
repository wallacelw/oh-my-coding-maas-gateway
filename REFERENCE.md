# oh-my-coding-maas-gateway — Reference

Reference documentation for both humans and agents. For the install procedure and per-script details, see **[INSTALLATION.md](./INSTALLATION.md)**. For the deterministic install procedure,
see **[SKILL.md](./SKILL.md)**. For a human-friendly overview, see
**[README.md](./README.md)**.

---

## Overview

### Key Contract

**Environment variables (`.env`):**

| Env var | Set by | Read by | Format | Rotate risk |
|---------|--------|---------|--------|------------|
| `HUAWEI_MAAS_API_KEY` | User (env var or prompt) | `01_env.sh`, `03a_opencode.sh` | Non-empty, no placeholders | Low — update `.env` + restart LiteLLM |
| `HUAWEI_MAAS_API_KEY_COUNT` | `01_env.sh` (from env vars or prompt) | `01_env.sh`, `02_litellm.sh` | Integer ≥ 1 | Low — update `.env` + regenerate config |
| `HUAWEI_MAAS_API_KEY_0` | `01_env.sh` (auto, = main key) | `01_env.sh`, `02_litellm.sh` | Non-empty | Low — auto-set from main key |
| `HUAWEI_MAAS_API_KEY_1..N` | User (env var or prompt) | `01_env.sh`, `02_litellm.sh` | Non-empty | Low — update `.env` + regenerate config |
| `LITELLM_MASTER_KEY` | `01_env.sh` (auto or custom) | `03a-03d` via `helpers/keys.sh` | Must start with `sk-` | **High** — invalidates all virtual keys (`--force` to regenerate) |
| `LITELLM_SALT_KEY` | `01_env.sh` (auto or custom) | LiteLLM container | Random string | **High** — invalidates all virtual keys (`--force` to regenerate) |
| `DB_PASSWORD` | `01_env.sh` (auto or custom) | docker-compose, postgres | Random string | **High** — breaks DB auth (`--force` to regenerate) |
| `GRAFANA_ADMIN_PASSWORD` | `01_env.sh` (auto or custom) | docker-compose, `04_validate.sh` | Random string | Low — changes dashboard login only |
| `PROMETHEUS_RETENTION` | `01_env.sh` (default `30d`) | docker-compose | Prometheus duration (`Nd`/`Nh`/`Nw`) | None — config value |
| `HUAWEI_MAAS_ANTHROPIC_API_BASE` | `01_env.sh` (default `https://api-ap-southeast-1.modelarts-maas.com/anthropic`) | `02_litellm.sh` | URL | None — config value |
| `HUAWEI_MAAS_API_BASE` | `01_env.sh` (default `https://api-ap-southeast-1.modelarts-maas.com/openai/v1`) | `02_litellm.sh` | URL | None — config value |
| `BIND_ADDRESS` | `01_env.sh` (default `127.0.0.1`) | docker-compose | `127.0.0.1` or `0.0.0.0` | None — config value |
| `OPENCODE_ENABLE_EXA` | `01_env.sh` (default `1`) | `03a_opencode.sh`, opencode runtime | `1` or unset | None — feature flag |
| `LITELLM_DISABLE_NO_REDIS_WARNING` | `docker-compose.yml` (fixed `true`) | LiteLLM container | `true` or unset | None — suppresses no-Redis banner for single-worker setup |

**Virtual keys (stored in tool config files, not `.env`):**

| Key | Minted by | Stored in | Tied to |
|-----|-----------|-----------|---------|
| opencode virtual key | `03a_opencode.sh` | `~/.config/opencode/opencode.json` (provider apiKey) | `LITELLM_MASTER_KEY` |
| Codex virtual key | `03b_codex.sh` | `~/.codex/.env` as `LITELLM_CODEX_API_KEY` | `LITELLM_MASTER_KEY` |
| Claude Code virtual key | `03c_claude_code.sh` | `~/.claude/settings.json` env block as `ANTHROPIC_API_KEY` | `LITELLM_MASTER_KEY` |
| Pi virtual key | `03d_pi.sh` | `~/.pi/agent/models.json` (providers.LiteLLM.apiKey) | `LITELLM_MASTER_KEY` |

**Rules:**

- User/agent must NOT set `HUAWEI_MAAS_API_KEY_0` — `01_env.sh` sets it from the
  main key automatically.
- User/agent must export `HUAWEI_MAAS_API_KEY_COUNT` = 1 + number of extra keys.
- User/agent must export `HUAWEI_MAAS_API_KEY_1` through `HUAWEI_MAAS_API_KEY_N` for
  extra keys only.

### Architecture

```
  Tools               LiteLLM (:4000)                  Huawei MaaS
  ─────               ───────────────                  ────────────

  opencode    ──→ /v1/chat/completions ──→ openai/ provider    ──→ /openai/v1/chat/completions
  Codex CLI   ──→ /v1/responses        ──→ openai/ provider    ──→ /openai/v1/chat/completions
  Claude Code ──→ /v1/messages         ──→ anthropic/ provider ──→ /anthropic/v1/messages
  Pi agent    ──→ /v1/chat/completions ──→ openai/ provider    ──→ /openai/v1/chat/completions

  opencode: 7 agents (1 disabled), 4 presets (LiteLLM-Default default)
  Codex CLI: Responses API bridged to Chat Completions by LiteLLM
  Claude Code: Anthropic Messages API forwarded to MaaS Anthropic endpoint
  Pi agent: OpenAI Chat Completions API, all models from models.sh

  Each tool: separate virtual key (sk-...) · unlimited budget · all 4 models
  LiteLLM: load-balances across N MaaS API keys · PostgreSQL (:5432)
  Models: glm-5.2 · glm-5.1 · deepseek-v4-pro · deepseek-v4-flash

  Observability: LiteLLM ──/metrics──→ Prometheus (:9090) ──→ Grafana (:3000)
```

### Endpoints

**LiteLLM Proxy (local):**

| Endpoint | URL | Auth |
|----------|-----|------|
| Proxy base | `http://127.0.0.1:4000` | Virtual key (`sk-...`) |
| Chat Completions | `http://127.0.0.1:4000/v1/chat/completions` | Virtual key |
| Responses API | `http://127.0.0.1:4000/v1/responses` | Virtual key |
| Anthropic Messages | `http://127.0.0.1:4000/v1/messages` | Virtual key |
| Admin UI | `http://127.0.0.1:4000/ui` | Master key |
| Liveness | `http://127.0.0.1:4000/health/liveliness` | None |
| Health | `http://127.0.0.1:4000/health` | Master key |
| Metrics | `http://127.0.0.1:4000/metrics` | None (Prometheus format) |

**Observability (local):**

| Service | URL | Auth |
|----------|-----|------|
| Prometheus | `http://127.0.0.1:9090` | None (bound to localhost) |
| Grafana | `http://127.0.0.1:3000` | admin password (from .env) |

**Tool connections (what each tool points to):**

| Tool | Endpoint | API Format | Auth source |
|------|----------|------------|-------------|
| opencode (default) | `http://127.0.0.1:4000` → `/v1/chat/completions` | OpenAI Chat Completions | `~/.config/opencode/opencode.json` (provider apiKey) |
| opencode (direct preset) | `https://api-ap-southeast-1.modelarts-maas.com/openai/v1` | OpenAI Chat Completions | `~/.config/opencode/opencode.json` (provider apiKey) |
| Codex CLI | `http://127.0.0.1:4000/v1` → `/v1/responses` | OpenAI Responses (bridged to Chat Completions by LiteLLM) | `~/.codex/.env` (`LITELLM_CODEX_API_KEY`) |
| Claude Code CLI | `http://127.0.0.1:4000` → `/v1/messages` | Anthropic Messages | `~/.claude/settings.json` (env.ANTHROPIC_API_KEY) |
| Pi agent | `http://127.0.0.1:4000` → `/v1/chat/completions` | OpenAI Chat Completions | `~/.pi/agent/models.json` (providers.LiteLLM.apiKey) |

**Huawei MaaS upstream (remote):**

| Endpoint | URL | Auth |
|----------|-----|------|
| MaaS OpenAI-compatible | `https://api-ap-southeast-1.modelarts-maas.com/openai/v1/chat/completions` | MaaS API key (`Authorization: Bearer`) |
| MaaS Anthropic-compatible | `https://api-ap-southeast-1.modelarts-maas.com/anthropic/v1/messages` | MaaS API key (`x-api-key` header) |

### Scripts

| # | Script | Purpose |
|---|--------|---------|
| — | `bootstrap.sh` | End-to-end orchestrator: selection → core prereqs → dispatch steps → summary. Use --tool=all\|litellm\|opencode\|codex\|claude\|pi (comma-separated for combos) |
| 01 | `01_env.sh` | Generate `.env` with secrets + MaaS keys; configure git hooks |
| 02 | `02_litellm.sh` | Generate `configs/litellm/config.yaml` from `.env` + deploy Docker Compose |
| 03a | `03a_opencode.sh` | Install opencode + plugin + mint key + write config |
| 03b | `03b_codex.sh` | Install Codex CLI + mint key + write config + model catalog |
| 03c | `03c_claude_code.sh` | Install Claude Code CLI + mint key + write settings + disable VSCode ext |
| 03d | `03d_pi.sh` | Install Pi agent + mint key + write models.json |
| 04 | `04_validate.sh` | Validate all components (--litellm-only, --opencode-only, --codex-only, --claude-code-only, --pi-only for scoped checks; --skip-opencode, --skip-codex, --skip-claude-code, --skip-pi for partial runs) |
| 05 | `05_skill.sh` | Install companion skill into detected coding agents (--dry-run, --no-skill, --yes) |
| — | `update.sh` | Check and update installed components (--check, --all, --dry-run). Groups into Coding Tools (opencode, slim, Codex, Claude Code, Pi) and Infrastructure (LiteLLM, Grafana, Prometheus). Does not touch keys or passwords |
| — | `helpers/prereqs.sh` | Shared prerequisite installation helpers (prereq_ensure_apt/bun/npm/docker) |
| — | `helpers/keys.sh` | Key resolution + virtual key minting (resolve_master_key, mint_or_reuse_key) |
| — | `helpers/common.sh` | Shared utilities (logging, prompts, is_interactive, run_filtered, run_with_spinner, source_env, retry_curl, strip_jsonc, mask_key) |
| — | `helpers/models.sh` | Model catalog (MODELS array, sourced by 02_litellm.sh + 04_validate.sh). Also update `config.yaml.template`, `opencode.json.template`, `model_catalog.json`, and `slim.json.template` when adding models. |
| — | `helpers/skills.sh` | Companion skill install/uninstall helpers for each agent tool |

### Models

| Name | Input/Output | RPM | Cost (in/out per token) | Cache hit |
|------|-------------|-----|------------------------|----------|
| `glm-5.2` | 192K/128K | 100 | $1.400 / $4.400 × 10⁻⁶ | $0.260 × 10⁻⁶ |
| `glm-5.1` | 192K/128K | 100 | $1.078 / $3.774 × 10⁻⁶ | $0.270 × 10⁻⁶ |
| `deepseek-v4-pro` | 1M/128K | 3 | $1.617 / $3.235 × 10⁻⁶ | — |
| `deepseek-v4-flash` | 1M/128K | 15 | $0.135 / $0.270 × 10⁻⁶ | — |

**Pricing notes:**
- Prices are peak (Period 1: 08:00–20:59 GMT+8). Off-peak (Period 2: 21:00–07:59) is 70% of peak.
- glm-5.1 uses ≥32K token tier. <32K tier: input $0.809, output $2.265, cache hit $0.175 (per 1M tokens).
- Cache hit pricing applies only to glm-5.2 and glm-5.1. DeepSeek models have no cache support.
- Source: [Huawei MaaS pricing](https://support.huaweicloud.com/intl/en-us/price-maas/price-maas-0002.html)

### Core Rules

- Never commit `.env` or real keys
- Never change `LITELLM_SALT_KEY` after virtual keys exist
- Model names are case-sensitive — must match MaaS console exactly
- Config is generated by `02_litellm.sh` — never edit `configs/litellm/config.yaml` directly
- Master key is admin-only — opencode, Codex CLI, Claude Code CLI, and Pi agent use separate virtual keys
- LiteLLM baseURL: `http://127.0.0.1:4000` (no `/v1`)
- MaaS region-locked to `ap-southeast-1`

---

## LiteLLM

`configs/litellm/config.yaml` is generated by `02_litellm.sh` from `.env`.
Never edit it directly — change `.env` and re-run `02_litellm.sh`.

### config.yaml Structure

```yaml
model_list:
  # ── OpenAI deployments (for opencode + Codex CLI) ──
  - model_name: glm-5.2                    # base name
    litellm_params:
      model: openai/glm-5.2                # provider prefix
      api_base: os.environ/HUAWEI_MAAS_API_BASE
      api_key: os.environ/HUAWEI_MAAS_API_KEY_0
      use_chat_completions_api: true       # bridge Responses → Chat Completions
      tpm: 1000000
      rpm: 100
    model_info:
      max_tokens: 198000
      max_input_tokens: 192000
      max_output_tokens: 128000
      input_cost_per_token: 0.0000014
      output_cost_per_token: 0.0000044

  # ── Anthropic deployments (for Claude Code CLI) ──
  - model_name: claude-glm-5.2             # claude- prefix
    litellm_params:
      model: anthropic/glm-5.2             # provider prefix
      api_base: os.environ/HUAWEI_MAAS_ANTHROPIC_API_BASE
      api_key: os.environ/HUAWEI_MAAS_API_KEY_0
      tpm: 1000000
      rpm: 100
    model_info:
      max_tokens: 198000
      max_input_tokens: 192000
      max_output_tokens: 128000
      input_cost_per_token: 0.0000014
      output_cost_per_token: 0.0000044

litellm_settings:
  num_retries: 3
  request_timeout: 600
  stream_timeout: 60
  callbacks: ["prometheus"]
  prometheus_initialize_budget_metrics: true
  require_auth_for_metrics_endpoint: false

router_settings:
  cooldown_time: 30                        # seconds to cool down a failed deployment
  allowed_fails: 3                         # failures before cooldown kicks in
```

### Provider Types

Two provider types, each pointing to a different Huawei MaaS endpoint:

| Provider | Prefix | MaaS Endpoint | Auth Header | Used by |
|----------|--------|---------------|-------------|---------|
| OpenAI | `openai/` | `/openai/v1/chat/completions` | `Authorization: Bearer` | opencode, Codex CLI |
| Anthropic | `anthropic/` | `/anthropic/v1/messages` | `x-api-key` | Claude Code CLI |

### Dual-Format Deployments

Each model has two deployments — one OpenAI, one Anthropic — so all three tools
can use the same underlying MaaS models:

| Type | `model_name` | Provider model | Example |
|------|------------|----------------|---------|
| OpenAI | `{model}` | `openai/{model}` | `glm-5.2` → `openai/glm-5.2` |
| Anthropic | `claude-{model}` | `anthropic/{model}` | `claude-glm-5.2` → `anthropic/glm-5.2` |

The `claude-` prefix on Anthropic `model_name` avoids routing conflicts.
LiteLLM routes by `model_name`, not by request format. Without the prefix,
a `/v1/messages` request could hit the OpenAI deployment, triggering a broken
Anthropic→OpenAI→Anthropic translation that drops content.

### OpenAI Bridge

`use_chat_completions_api: true` on OpenAI deployments tells LiteLLM to bridge
Responses API → Chat Completions. This lets Codex CLI use `/v1/responses`
(which LiteLLM converts to `/v1/chat/completions` before forwarding to MaaS).

### Load Balancing

N MaaS API keys → N deployments per model per format. LiteLLM uses
`simple-shuffle` routing (round-robin with retry across deployments).

Total deployments: 4 models × N keys × 2 formats = 8N.

### model_info

Each deployment includes metadata for budget tracking and LiteLLM UI:

| Field | Purpose |
|-------|---------|
| `max_tokens` | Total token limit |
| `max_input_tokens` | Input token limit |
| `max_output_tokens` | Output token limit |
| `input_cost_per_token` | Cost per input token (USD) |
| `output_cost_per_token` | Cost per output token (USD) |
| `cache_read_input_token_cost` | Cost per cached input token on cache hit (USD) |
| `cache_creation_input_token_cost` | Cost per token for cache creation (USD) |

### Settings

| Setting | Value | Purpose |
|---------|-------|---------|
| `num_retries` | 3 | Retry across deployments on failure |
| `request_timeout` | 600 | Full request timeout (10 min) |
| `stream_timeout` | 60 | TTFT timeout (60s) |
| `callbacks` | `["prometheus"]` | Enable Prometheus metrics export |
| `prometheus_initialize_budget_metrics` | true | Emit budget metrics for all keys |
| `require_auth_for_metrics_endpoint` | false | Allow unauthenticated `/metrics` |
| `router_settings.cooldown_time` | 30 | Seconds to cool down a failed deployment |
| `router_settings.allowed_fails` | 3 | Failures before cooldown kicks in |

### Virtual Keys

Four virtual keys, all minted via `helpers/keys.sh` and tied to
`LITELLM_MASTER_KEY`. Changing the master key invalidates all virtual keys.

| Alias | Minted by | Stored in | Budget | Scope |
|-------|-----------|-----------|--------|-------|
| `opencode` | `03a_opencode.sh` | `~/.config/opencode/opencode.json` (provider apiKey) | Unlimited | All models |
| `codex` | `03b_codex.sh` | `~/.codex/.env` (`LITELLM_CODEX_API_KEY`) | Unlimited | All models |
| `claude-code` | `03c_claude_code.sh` | `~/.claude/settings.json` (env.ANTHROPIC_API_KEY) | Unlimited | All models |
| `pi` | `03d_pi.sh` | `~/.pi/agent/models.json` (providers.LiteLLM.apiKey) | Unlimited | All models |

Each installer checks its own config file for an existing valid key first
(tool-specific path), then calls `mint_or_reuse_key` from `helpers/keys.sh`
which does alias lookup via `/key/list` + `/key/info` and mints a new key only
if no valid key is found.

### Observability

LiteLLM exposes a `/metrics` endpoint (Prometheus format). Prometheus
scrapes it every 15s. Grafana visualizes the data with a pre-provisioned
dashboard.

| Service | Port | Purpose |
|---------|------|---------|
| Prometheus | 9090 | Metrics storage + querying |
| Grafana | 3000 | Dashboard visualization (admin login required) |

Prometheus TSDB retention is configurable via `PROMETHEUS_RETENTION` in `.env`
(default: `30d`).

**Dashboard** (`configs/grafana/dashboards/main.json`) — 39 panels (7 row
headers + 32 visualization panels) across 7 sections, default 1h time
window, 30s refresh:

1. **At-a-glance** — Active Requests, RPS, RPM, Error %, TPS, TPM, Models Healthy, Spend (window) (8 stat panels)
2. **Latency** — TTFT by model, TPOT by model, End-to-end latency, LLM API latency, Proxy overhead, Queue wait (6 timeseries)
3. **Errors & Health** — Errors by model, Error status codes (pie), Deployment state (state-timeline) (3 panels)
4. **Throughput & Capacity** — Total/Successful/Failed Requests (window), RPM by model, TPM by model (5 panels)
5. **Tokens** — Input tokens, Output tokens, Reasoning tokens, Cached input tokens (4 timeseries)
6. **Cache** — Cache misses/min, Provider cache reads, Cache hit ratio (stat) (3 panels)
7. **Cost** — Total cost, Cost per model, Spend rate (3 panels)

Variables: `$model` (filter by model), `$provider` (filter by openai/anthropic),
`$window` (rate window: 1m/5m/15m/1h, default 15m).

### Container Security

All 4 Docker services run with container hardening:

| Setting | Value | Purpose |
|---------|-------|---------|
| `init` | `true` | PID 1 signal handling via tini (graceful shutdown) |
| `security_opt` | `no-new-privileges:true` | Prevents privilege escalation inside containers |
| `cap_drop` | `ALL` | Drops all Linux capabilities |

The PostgreSQL container adds back only the capabilities it needs for
startup: `CHOWN`, `SETUID`, `SETGID`, `DAC_OVERRIDE`, `FOWNER`.



---

## opencode

**Connection:** opencode → `/v1/chat/completions` → `openai/` provider → `/openai/v1/chat/completions`

opencode connects to LiteLLM via the OpenAI Chat Completions API. The
`oh-my-opencode-slim` plugin (installed via `bunx`) configures 4 presets and
agent→model mappings.

### Config Files

| File | Purpose |
|------|---------|
| `~/.config/opencode/opencode.json` | Provider config (LiteLLM + Huawei-MaaS direct), API key |
| `~/.config/opencode/oh-my-opencode-slim.json` | Plugin config: presets, agents, council |

The `LiteLLM` provider uses `@ai-sdk/openai-compatible` with
`baseURL: http://127.0.0.1:4000`. Models use base names (e.g., `glm-5.2`)
without provider prefix — the preset name (`LiteLLM/` vs `Huawei-MaaS/`)
determines routing.

### Plugin: oh-my-opencode-slim

`oh-my-opencode-slim` (v2.2.18) installed via `bunx`. Provides:

- **4 presets** — control routing (proxy vs direct) and model selection
- **7 agents** (1 disabled) — orchestrator, oracle, council, librarian, explorer, designer, fixer (observer disabled)
- **Council** — 3 councillors running in parallel for consensus decisions
- **Fallback chains** — each agent has a primary model and optional fallback
- **Websearch** — opencode's built-in EXA-backed web search tool (no API key required). Enabled via `OPENCODE_ENABLE_EXA=1` (env) + `"permission": {"websearch": "allow"}` (config). Required for custom providers; automatic with the default OpenCode provider.

### Presets

| Preset | Route | Models |
|--------|-------|--------|
| **LiteLLM-Default** (default) | Proxy → MaaS | GLM only (glm-5.2, glm-5.1) |
| **LiteLLM-Extended** | Proxy → MaaS | GLM + deepseek-v4-flash |
| **Huawei-MaaS-Default** | Direct → MaaS | GLM only (glm-5.2, glm-5.1) |
| **Huawei-MaaS-Extended** | Direct → MaaS | GLM + deepseek-v4-flash |

Switch at runtime: `/preset LiteLLM-Extended`

### Agent → Model Mapping

`A → B` = fallback chain. `(variant)` = reasoning effort. Model names omit
the provider prefix (preset name indicates LiteLLM proxy vs direct MaaS).

| Agent | LiteLLM-Default | LiteLLM-Extended | MaaS-Default | MaaS-Extended |
|-------|-----------------|------------------|--------------|---------------|
| orchestrator | `glm-5.2` (high) | `glm-5.2` (high) | `glm-5.2` (high) | `glm-5.2` (high) |
| oracle | `glm-5.2` → `glm-5.1` (high) | `glm-5.2` → `deepseek-v4-flash` (high) | `glm-5.2` → `glm-5.1` (high) | `glm-5.2` → `deepseek-v4-flash` (high) |
| council | `glm-5.2` → `glm-5.1` (high) | `glm-5.2` → `deepseek-v4-flash` (high) | `glm-5.2` → `glm-5.1` (high) | `glm-5.2` → `deepseek-v4-flash` (high) |
| librarian | `glm-5.1` (low) | `deepseek-v4-flash` (low) | `glm-5.1` (low) | `deepseek-v4-flash` (low) |
| explorer | `glm-5.1` (low) | `deepseek-v4-flash` (low) | `glm-5.1` (low) | `deepseek-v4-flash` (low) |
| designer | `glm-5.1` → `glm-5.2` (medium) | `glm-5.1` → `deepseek-v4-flash` (medium) | `glm-5.1` → `glm-5.2` (medium) | `glm-5.1` → `deepseek-v4-flash` (medium) |
| fixer | `glm-5.1` (high) | `deepseek-v4-flash` → `glm-5.1` (high) | `glm-5.1` (high) | `deepseek-v4-flash` → `glm-5.1` (high) |

### Council

3 councillors run in parallel, all using glm-5.2, each with a different focus:

| Councillor | Model | Focus |
|------------|-------|-------|
| **alpha** | glm-5.2 | Deep reasoning, logical correctness, subtle bugs/edge cases |
| **beta** | glm-5.2 | Architecture, maintainability, trade-offs, long-term implications |
| **gamma** | glm-5.2 | Practical implementation, cost-efficiency, verification steps |

### Prerequisites

- `bun` — for `bunx oh-my-opencode-slim install`
- `jq` — for config parsing

---

## Codex CLI

**Connection:** Codex CLI → `/v1/responses` → `openai/` provider (bridged to Chat Completions by LiteLLM) → `/openai/v1/chat/completions`

Codex CLI connects to LiteLLM via the OpenAI Responses API. LiteLLM bridges
this to Chat Completions using `use_chat_completions_api: true`, then forwards
to Huawei MaaS's OpenAI endpoint.

### Config Files

| File | Purpose |
|------|---------|
| `~/.codex/config.toml` | Model provider config, default model, feature flags |
| `~/.codex/model_catalog.json` | Model metadata (context window, max tokens, reasoning levels) |
| `~/.codex/.env` | API key (`LITELLM_CODEX_API_KEY=sk-...`), auto-loaded by Codex CLI |

### Custom Provider

Codex CLI uses a custom `litellm_proxy` model provider instead of the
built-in `openai` provider:

```toml
[model_providers.litellm_proxy]
name = "LiteLLM Proxy"
base_url = "http://127.0.0.1:4000/v1"
env_key = "LITELLM_CODEX_API_KEY"
wire_api = "responses"
```

Why a custom provider:
- Codex CLI rejects overriding the reserved `openai` provider name.
- The built-in `openai` provider defaults to `wire_api = "responses_websocket"`
  (WebSocket), which had a bug in LiteLLM v1.89.3 when bridging to Chat
  Completions. Setting `wire_api = "responses"` forces HTTP SSE instead.
- The `env_key` field lets Codex CLI read the API key from `~/.codex/.env`
  automatically (via dotenvy), no shell exports needed.

### Feature Flags

- `multi_agent = false` — disabled because it sends `type: "namespace"` tools
  that Huawei MaaS rejects (only `type: "function"` is accepted).

### Model Selection

Models use base names (e.g., `glm-5.2`). All 4 models are available. Switch
at runtime with `--model`:

```bash
codex --model deepseek-v4-pro    # deep reasoning
codex --model glm-5.2            # general purpose (default)
codex --model deepseek-v4-flash      # fast
```

### Prerequisites

- `npm` — for `npm install -g @openai/codex`
- `jq` — for parsing LiteLLM API responses
- `bubblewrap` (`bwrap`) — Codex CLI requires it for sandboxing

---

## Claude Code CLI

**Connection:** Claude Code → `/v1/messages` → `anthropic/` provider → `/anthropic/v1/messages`

Claude Code CLI connects to LiteLLM via the Anthropic Messages API. LiteLLM
forwards directly to Huawei MaaS's Anthropic-compatible endpoint using the
`anthropic/` provider prefix — no format conversion needed.

### Config Files

| File | Purpose |
|------|---------|
| `~/.claude/settings.json` | Runtime config: env vars, model selection (chmod 600) |
| `~/.claude.json` | IDE integration settings: `autoInstallIdeExtension: false` |

Claude Code reads `settings.json` automatically on startup — no `source` or
`export` needed. Run with `--bare` flag to skip keychain/OAuth checks:

```bash
claude --bare
```

Or add an alias: `alias claude='claude --bare'`

### Environment Variables

Set in the `env` block of `~/.claude/settings.json`:

| Variable | Value | Purpose |
|----------|-------|---------|
| `ANTHROPIC_BASE_URL` | `http://127.0.0.1:4000` | LiteLLM proxy URL (no `/v1`) |
| `ANTHROPIC_API_KEY` | `sk-...` (virtual key) | LiteLLM auth (alias: claude-code) |
| `ANTHROPIC_MODEL` | `claude-glm-5.2` | Primary model |
| `ANTHROPIC_SMALL_FAST_MODEL` | `claude-deepseek-v4-flash` | Fast model for background tasks |
| `CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL` | `1` | Prevent VSCode extension auto-install |

### VSCode Extension Disabled

Claude Code auto-installs its VSCode extension when run from a VS Code terminal.
The installer prevents this two ways:

1. **`~/.claude.json`** — sets `autoInstallIdeExtension: false` (controls IDE integration)
2. **`CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL=1`** in settings.json env block (runtime override)

The installer also uninstalls the extension if already present (`code --uninstall-extension anthropic.claude-code`).

### Why `claude-` Prefix

LiteLLM routes requests by `model_name`, not by request format. If OpenAI
and Anthropic deployments share the same `model_name` (e.g., `glm-5.2`),
a `/v1/messages` request might randomly hit the OpenAI deployment, triggering
a broken Anthropic→OpenAI→Anthropic translation that drops content. The
`claude-` prefix (e.g., `claude-glm-5.2`) ensures `/v1/messages` always
routes to the Anthropic deployment directly.

### Model Selection

Models use `claude-` prefixed names (e.g., `claude-glm-5.2`) for the
Anthropic endpoint. All 4 models are available. Switch at runtime with
`--model`:

```bash
claude --bare --model claude-deepseek-v4-pro    # deep reasoning
claude --bare --model claude-glm-5.2            # general purpose (default)
claude --bare --model claude-deepseek-v4-flash      # fast
```

### Prerequisites

- `npm` — for `npm install -g @anthropic-ai/claude-code`
- `jq` — for parsing LiteLLM API responses and writing settings.json

---

## Pi Agent

**Connection:** Pi → `/v1/chat/completions` → `openai/` provider → `/openai/v1/chat/completions`

Pi agent connects to LiteLLM via the OpenAI Chat Completions API. LiteLLM
forwards to Huawei MaaS using the `openai/` provider prefix.

### Config Files

| File | Purpose |
|------|---------|
| `~/.pi/agent/models.json` | Provider config: LiteLLM baseUrl, apiKey, model list (chmod 600) |

### Model Selection

Pi reads `models.json` on startup. The `providers.LiteLLM` block defines:
- `baseUrl`: `http://127.0.0.1:4000/v1`
- `api`: `openai-completions`
- `apiKey`: virtual key (minted by `03d_pi.sh`, alias "pi")
- `models[]`: all models from `models.sh` with `contextWindow` and `maxTokens`

### Prerequisites

- `curl` — for downloading the pi installer
- `jq` — for generating models.json from the model catalog

---

## Repair

| Symptom | Fix |
|---------|-----|
| LiteLLM won't start | `docker compose logs litellm --tail 50` |
| `litellm` keeps restarting | Check `docker compose logs db`, verify `DB_PASSWORD` |
| 401 Unauthorized | Key must start with `sk-` |
| 404 model not found | Model name case-sensitive |
| MaaS 403 | Verify key at https://console.huaweicloud.com/modelarts/ — region must be `ap-southeast-1` |
| `unhealthy_count > 0` | Check MaaS key/model/region — may be transient |
| Virtual key 403 | Check with `/key/info` — may be expired |
| Port conflict | `ss -tlnp \| grep -E ':(4000\|5432\|9090\|3000) '` |
| Validation fails | `./scripts/04_validate.sh` — see recovery table in [SKILL.md](./SKILL.md) Step 7 |
| Prometheus not scraping | Check `docker compose logs prometheus --tail 20`; verify `litellm:4000` reachable from Prometheus container |
| Grafana dashboard blank | Check datasource UID: `curl http://127.0.0.1:3000/api/datasources/name/Prometheus \| jq .uid` — must be `prometheus` |
| Grafana not loading | `docker compose restart grafana` |
| Grafana dashboard stale after upgrade | `docker compose restart grafana` — hard restart picks up provisioning changes |
| Claude Code `claude not found` | `npm install -g @anthropic-ai/claude-code` |
| Claude Code 401 | Check `ANTHROPIC_API_KEY` in `~/.claude/settings.json` env block — must start with `sk-` |
| Claude Code model rejected | Model name case-sensitive — use `claude-` prefixed names (e.g., `claude-glm-5.2`) |

### Lifecycle

| Action | Command |
|--------|---------|
| Graceful stop | `docker compose down` (preserves data volumes) |
| Start | `docker compose up -d` |
| Restart one service | `docker compose restart <service>` |
| Restart all | `docker compose restart` |
| View logs | `docker compose logs <service> --tail 50 -f` |
| Full reset | `docker compose down -v; rm -f .env` (destroys all data) |

### Key Rotation (`--force`)

Rotating immutable secrets invalidates all virtual keys — the tools will need
re-configuration after rotation.

```bash
# 1. Regenerate all secrets (master key, salt, DB password, Grafana password)
./scripts/01_env.sh --force

# 2. Regenerate LiteLLM config with new master key
./scripts/02_litellm.sh

# 3. Re-mint virtual keys for each installed tool
./scripts/03a_opencode.sh    # mints new key, updates opencode.json
./scripts/03b_codex.sh       # mints new key, updates config.toml
./scripts/03c_claude_code.sh # mints new key, updates settings.json
./scripts/03d_pi.sh          # mints new key, updates models.json

# 4. Verify
./scripts/04_validate.sh
```

**What changes:**
- `LITELLM_MASTER_KEY` — new value, all old virtual keys stop working
- `LITELLM_SALT_KEY` — new value, LiteLLM internal encryption rotated
- `DB_PASSWORD` — new value, PostgreSQL re-authenticated
- `GRAFANA_ADMIN_PASSWORD` — new value, Grafana login changes

**What's preserved:**
- `HUAWEI_MAAS_API_KEY` and all extra keys
- `PROMETHEUS_RETENTION`, `BIND_ADDRESS`, endpoint URLs
- All Docker volumes (PostgreSQL data, Prometheus data, Grafana data)

---

## Uninstall

`scripts/uninstall.sh` removes all or part of the installation.

| Artifact | Path | Removed by |
|----------|------|------------|
| opencode config | `~/.config/opencode/opencode.json` | `--tool=opencode` |
| slim plugin config | `~/.config/opencode/oh-my-opencode-slim.json` | `--tool=opencode` |
| codex config | `~/.codex/config.toml` | `--tool=codex` |
| codex model catalog | `~/.codex/model_catalog.json` | `--tool=codex` |
| codex env | `~/.codex/.env` | `--tool=codex` |
| claude settings | `~/.claude/settings.json` | `--tool=claude` |
| claude global config | `~/.claude.json` | `--tool=claude` |
| pi config | `~/.pi/agent/models.json` | `--tool=pi` |
| Docker containers + volumes + images | — | `--docker` |
| Repository (`.env`, configs, scripts) | `$PROJECT_DIR` | `--repo` |

Binaries (opencode, codex, claude, pi), runtimes (bun, pi-node), configs,
and `.bashrc` entries are all removed. Backup files (`*.bak.*`) are also
removed. Use `--dry-run` to preview before running.

```bash
./scripts/uninstall.sh --all --dry-run        # preview
./scripts/uninstall.sh --tool=opencode,codex  # subset
./scripts/uninstall.sh --all --yes            # everything, no prompt
```

---

## Remote Access

All ports bind to `127.0.0.1` by default (localhost only). To access from
another machine (e.g. your laptop when the stack runs on a VM):

### Option A — SSH Port Forwarding (recommended)

No config change needed. Forward remote ports to your local machine:

```bash
ssh -L 4000:127.0.0.1:4000 \
    -L 3000:127.0.0.1:3000 \
    -L 9090:127.0.0.1:9090 \
    user@vm-host
```

| Local URL | Service |
|-----------|---------|
| `http://localhost:4000/ui` | LiteLLM Admin UI |
| `http://localhost:4000/v1/chat/completions` | LiteLLM proxy API |
| `http://localhost:3000` | Grafana dashboard |
| `http://localhost:9090` | Prometheus |

Traffic is encrypted via SSH. No ports exposed to the network.

### Option B — Bind to All Interfaces

Set `BIND_ADDRESS` in `.env` to expose ports to all network interfaces:

```bash
# In .env:
BIND_ADDRESS="0.0.0.0"

# Apply:
docker compose up -d
```

Then access via the VM's IP address:

| URL | Service |
|-----|---------|
| `http://<vm-ip>:4000/ui` | LiteLLM Admin UI |
| `http://<vm-ip>:3000` | Grafana dashboard |
| `http://<vm-ip>:9090` | Prometheus |

**Security:** Ensure firewall rules limit access to trusted IPs only:

```bash
# Example: ufw (Ubuntu)
ufw allow from <your-laptop-ip> to any port 4000
ufw allow from <your-laptop-ip> to any port 3000
ufw allow from <your-laptop-ip> to any port 9090
```
