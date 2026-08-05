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

**4 models:** glm-5.2, glm-5.1, deepseek-v4-pro, deepseek-v4-flash

---

## Install

The bootstrap script is the only installation method. It handles
everything — prerequisites, Docker stack, coding tools, virtual keys,
validation, and optional companion skill.

```bash
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash
```

Bootstrap will prompt for your Huawei MaaS API key, show an interactive
menu to select which coding tools to install, auto-install prerequisites,
deploy the proxy + observability stack, configure each tool with its own
virtual key, run validation, and offer to install the companion skill.

Estimated time: ~5 min fresh, ~2 min upgrade. For flags and non-interactive
usage, see [INSTALLATION.md](./INSTALLATION.md).

### After install

```bash
opencode          # or:  codex  or:  claude --bare  or:  pi
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

### Update coding tools only

To check and update individual components (opencode, Codex, Claude Code,
Pi, LiteLLM, Grafana, Prometheus) without re-running the full pipeline:

```bash
./scripts/update.sh              # interactive: show versions, select which to update
./scripts/update.sh --check      # show version table only
./scripts/update.sh --all        # update all with updates available
```

Does not touch passwords, API keys, or virtual keys.

---

## Companion Skill

After installation, bootstrap offers to install
[SKILL.md](./SKILL.md) as a skill into each detected coding agent. This
gives your agents operational guidance — health diagnosis, key/model
management, debug routing, observability, and recovery.

```bash
./scripts/05_skill.sh --yes    # install manually anytime
```

---

## Uninstall

```bash
./scripts/uninstall.sh --all --dry-run   # preview
./scripts/uninstall.sh --tool=opencode   # remove one agent
./scripts/uninstall.sh --all             # remove everything
```

---

## Documentation

| File | For | Description |
|------|-----|-------------|
| **[INSTALLATION.md](./INSTALLATION.md)** | Everyone | Install process, pipeline, flags, env vars, prerequisites, per-tool usage, monitoring, remote access, recovery, upgrade |
| **[SKILL.md](./SKILL.md)** | Agents | Operational companion: install, upgrade, diagnose, key/model management, recovery |
| **[REFERENCE.md](./REFERENCE.md)** | Everyone | Architecture, config, env vars, tool integration, repair guide, lifecycle |
| **[CHANGELOG.md](./CHANGELOG.md)** | Everyone | Version history |
| **[AGENTS.md](./AGENTS.md)** | Contributors | Development rules, validation, commit conventions |
