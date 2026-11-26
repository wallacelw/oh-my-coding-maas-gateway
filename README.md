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

  LiteLLM: load-balances across N MaaS keys · PostgreSQL (internal :5432, not published)
  Observability: LiteLLM ──/metrics──→ Prometheus (:9090) ──→ Grafana (:3000)
```

**2 models:** glm-5.3 (reasoning core), deepseek-v4.1-flash-1017 (accepts image
input — first multimodal model)

---

## Install

The bootstrap script is the only installation method. It handles
everything — prerequisites, Docker stack, coding tools, virtual keys,
companion skill + agent tool bundles (default-on), then validation.

```bash
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash
```

Bootstrap will collect your Huawei MaaS API key (validated prompt, or
`--api-key=` / env var), show an interactive
menu to select which coding tools to install, auto-install prerequisites,
deploy the proxy + observability stack, configure each tool with its own
virtual key, install (default-on; opt out with `--no-skill`/`--no-bundles`)
the companion skill
and agent tool bundles, then run validation. Bootstrap's menus are the only
interactive part — the pipeline itself runs non-interactive.

### Non-interactive

```bash
# Fresh install with API key (no prompts)
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash -s -- -y --api-key=sk-xxxx

# Upgrade existing install (pull updates, regenerate configs)
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash -s -- -y

# Non-interactive with specific tools only
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash -s -- -y --api-key=sk-xxxx --tool=litellm,opencode
```

Non-interactive upgrades discard local repo changes if `git pull` fails —
bootstrap prints a warning counting what is being discarded before
resetting to `origin/main`. `.env`, the generated LiteLLM config, and
Docker volumes are preserved; tracked repo files, including config
templates, are reset.

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

Same command as install — bootstrap detects the existing install, pulls
updates, then re-runs idempotently; all secrets and data are preserved.
Restart any running coding tools afterward (plugin/preset changes are not
hot-reloaded). See [INSTALLATION.md § Upgrade](./INSTALLATION.md#upgrade)
for the full procedure, including non-interactive reset behavior, and
[§ Updating coding tools](./INSTALLATION.md#updating-coding-tools) for
`./scripts/update.sh`.

---

## Companion Skill

During installation (step 04), bootstrap installs (default-on) [SKILL.md](./SKILL.md)
(plus the REA/drawio bundles) into each detected coding agent — without a menu
(opt out via `--no-skill`/`--no-bundles`); only standalone interactive runs of
step 04 show the bundle menu. These include two agent tool bundles: **REA** (reverse-engineering MCP +
skill) and **drawio** (diagramming MCP + skill). The companion skill gives your agents
operational guidance — health diagnosis, key/model management, debug
routing, observability, and recovery. Bundles are default-on and can be
declined with `--no-bundles`; everything runs locally (see the data-flow
audit in [REFERENCE.md](./REFERENCE.md)).

```bash
./scripts/04_skills_mcps.sh --yes    # install skills + bundles manually anytime
```

---

## Uninstall

`./scripts/uninstall.sh` removes all or part of the installation. See
[INSTALLATION.md § Uninstall](./INSTALLATION.md#uninstall) for the full flag
reference and examples.

---

## Backup

`./scripts/06_backup.sh` dumps the LiteLLM database (spend history, keys,
budgets); `--restore FILE` rebuilds it. Back up before `docker compose down -v`
— the volume is destroyed otherwise. See [INSTALLATION.md § 06_backup](./INSTALLATION.md#06_backupsh)
for the full procedure.

---

## Documentation

| File | For | Description |
|------|-----|-------------|
| **[INSTALLATION.md](./INSTALLATION.md)** | Everyone | Install process, pipeline, flags, env vars, prerequisites, per-tool usage, monitoring, remote access, recovery, upgrade |
| **[SKILL.md](./SKILL.md)** | Agents | Operational companion: install, upgrade, diagnose, key/model management, recovery |
| **[REFERENCE.md](./REFERENCE.md)** | Everyone | Architecture, config, env vars, tool integration, repair guide, lifecycle |
| **[CHANGELOG.md](./CHANGELOG.md)** | Everyone | Version history |
| **[AGENTS.md](./AGENTS.md)** | Contributors | Development rules, validation, commit conventions |
