---
name: oh-my-coding-maas-gateway
description: Deploy LiteLLM proxy (litellm + postgres + prometheus + grafana) routing through Huawei MaaS with multi-key load balancing, then bootstrap opencode + Codex CLI + Claude Code CLI with virtual keys and 4 presets.
---

# oh-my-coding-maas-gateway — Agent Procedure

You are the intermediary between the user and the bootstrap script.
Run bootstrap, answer its prompts on stdin, handle failures, stop when
validation passes. For full details: **[INSTALLATION.md](./INSTALLATION.md)**.

## Procedure

1. Run the one-liner. It handles both fresh install and upgrade —
   detects an existing repo, pulls if present, clones if not:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash
   ```

   Optional flags: `--tool=all|litellm|opencode|codex|claude` (skip menu),
   `--dry-run` (preview). Env var overrides: `HUAWEI_MAAS_API_KEY`,
   `HUAWEI_MAAS_API_KEY_COUNT`, `HUAWEI_MAAS_API_KEY_1..N`.

2. Answer bootstrap's prompts on stdin:
   - **Fresh install** — ask the user for:
     - Install mode (default: all)
     - Huawei MaaS API key (region ap-southeast-1)
     - Extra MaaS keys for load balancing (default: 0)
   - **Upgrade** — read the MaaS key from `.env`. Do not ask the user.
     If `.env` is missing, stop and report.
   - Sudo password if the system prompts for it.

3. Complete when `06_validate.sh` exits 0. Do NOT launch opencode.

## Recovery

If `06_validate.sh` fails, match the FAIL pattern and run the recovery:

| FAIL pattern | Recovery |
|--------------|----------|
| `.env not found` / `placeholder value` | Re-run `01_env.sh` |
| `services running` + `expected 4` | `docker compose up -d`, wait 30s, retry |
| `liveness probe returned` | `docker compose logs litellm --tail 50` |
| `Inference smoke test` + `did not respond` | Re-validate MaaS key; check logs |
| opencode issues (`opencode not found`, config) | Re-run `03_opencode.sh` |
| Codex issues (`codex not found`, config) | Re-run `04_codex.sh` |
| Claude Code issues (`claude not found`, config) | Re-run `05_claude_code.sh` |
| `Prometheus not reachable` | `docker compose up -d prometheus`, wait 10s |
| `/metrics endpoint not responding` | `docker compose restart litellm`, wait 15s |
| `Grafana not reachable` | `docker compose up -d grafana`, wait 20s |

WARN messages are advisory — they do not cause non-zero exit. After recovery,
re-run `06_validate.sh` **once**. If it still fails, stop and report full output.

## Rules

- Do not skip steps. Do not improvise. Do not launch opencode.
- If `git pull` fails during upgrade, ask: "Reset to origin/main? (y/n)".
- If anything is unclear, ask the user before proceeding.
- After completion: user will rotate MaaS keys if they were shared with you.
