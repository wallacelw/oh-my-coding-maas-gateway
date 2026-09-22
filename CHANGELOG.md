# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.21.2] - 2026-09-23

### Fixed

- **Observer could not read images natively** — opencode's read tool
  refused image files ("this model does not support image input") because
  the provider config did not declare image support, so the observer
  degraded to external OCR (tesseract). Added `"attachment": true` to the
  deepseek-v4.1-flash entries in `opencode.json.template` (both provider
  blocks), verified against the opencode config schema. Image routing
  itself was already working (plugin intercept → @observer delegation).
- **Deprecated `multiplexer.zellij_pane_mode` removed** from the slim
  template — the plugin warned the key is ignored (the warning was visible
  in the test screenshot that motivated this fix).
- Add-a-model instructions (models.sh header, INSTALLATION.md,
  REFERENCE.md, SKILL.md) now mention setting `"attachment": true` in
  `opencode.json.template` for image-capable models.

## [1.21.1] - 2026-09-23

### Fixed

- **05_skill.sh never refreshed installed skill content** — the script
  skipped any agent that already had the skill, so installed SKILL.md
  copies drifted stale on every upgrade (the v1.21.0 SKILL.md changes
  never reached installed copies). The script now compares each installed
  copy against the repo SKILL.md: identical copies are skipped ("Up to
  date"), stale copies are refreshed in place, and `--dry-run` previews
  the refresh without writing. `helpers/skills.sh` gained a shared
  `skill_dest_path()` plus generic install/exists/uninstall helpers,
  removing the per-tool path duplication.

## [1.21.0] - 2026-09-23

### Added

- **Observer agent enabled** (8th agent, from the oh-my-opencode-slim
  plugin) — read-only visual analysis specialist ("The Silent Witness"):
  interprets images/screenshots/PDFs/diagrams, OCR-extracts exact text,
  returns structured observations. Runs on deepseek-v4.1-flash (the only
  vision model), single-model by design — a blind glm fallback would
  hallucinate confident-looking "observations"; LiteLLM already provides
  key-level resilience via 2N deployments.
- **Image auto-routing** — paste a screenshot and the plugin intercepts
  the image bytes, saves them to disk, strips them from the orchestrator
  message, and nudges delegation to @observer; structured text returns to
  the orchestrator (raw image bytes stay out of the main context window).
  `image_routing` omitted → auto-resolves to "auto". Zero cost in
  text-only sessions.
- **deepseek-v4.1-flash primary for explorer + librarian (both tiers)
  and fixer (Balanced only)** — 1M context vs glm-5.1's 192K max input,
  3.6× cheaper input, 9× cheaper cache hits. Fallback is glm-5.2 (not
  glm-5.1) to preserve 1M context on failover. Designer unchanged
  (observer owns vision, designer owns taste); orchestrator/oracle/
  council unchanged (glm reasoning core).

### Changed

- **Preset cost profile** — Default −22%, Balanced −32% (modeled, peak
  pricing; cache-hit and off-peak amplify).
- **B4 validation** — 36 → 45 preset checks (+2 observer checks
  replacing the disabled check, +8 deepseek drift assertions).

### Removed

- **Deprecated council config keys** — `timeout`,
  `councillor_execution_mode`, `councillor_retries`: absent from the
  pinned 2.2.21 schema, dead config (tolerated but meaningless).

### Migration

- Re-run `./scripts/03a_opencode.sh` to apply the new presets; restart
  opencode (preset changes are not hot-reloaded).

## [1.20.0] - 2026-09-22

### Added

- **deepseek-v4.1-flash** — 1M context, 1M max input, 384K max output, 96K
  max reasoning, 1M TPM / 100 RPM. Pricing: $0.30/M input, $1.20/M output,
  $0.03/M cache-hit; off-peak (13:00–00:00 UTC = 21:00–07:59 GMT+8) at 50%:
  $0.15/M input, $0.60/M output, $0.015/M cache-hit. First multimodal
  model — image input (JPEG/PNG/GIF/WebP) verified end-to-end through the
  gateway in both formats: OpenAI `image_url` content blocks and Anthropic
  base64 `image` source blocks (the LiteLLM bridge translates correctly).
  Thinking mode via `thinking: {"type": "enabled"|"disabled"}`; reasoning
  surfaces as `reasoning_content`. `reasoning_effort` is accepted (HTTP 200)
  but honoring is unverified — the codex catalog keeps
  `supports_reasoning_effort: false` (conservative).
- **VISION_MODELS catalog array** (models.sh) — plain-name list of models
  accepting image input, mirroring REASONING_MODELS. `validate_catalog`
  checks membership; `emit_deployment` emits `supports_vision: true/false`;
  04_validate.sh adds `EXPECTED_VISION_TRUE/FALSE` checks.
- **Dynamic capability validation** — 04_validate.sh A4 expected counts
  (off-peak blocks, capability flags, reasoning true/false) are now derived
  from catalog array lengths (MODEL_COUNT / OFF_PEAK_COUNT /
  REASONING_COUNT / VISION_COUNT) instead of hardcoded model counts.

### Removed

- **deepseek-v4-pro, deepseek-v4-flash** — replaced by deepseek-v4.1-flash.
  Catalog is now 4 models; total deployments are 4 models × N keys ×
  2 formats = 8N (was 10N).

### Migration

- Rename `--model deepseek-v4-pro` / `deepseek-v4-flash` references to
  `deepseek-v4.1-flash` (`claude-` prefixed variants likewise).
- Regenerate the gateway config: `./scripts/02_litellm.sh`.
- Re-run the tool config steps (`./scripts/03a_opencode.sh` … `03d_pi.sh`)
  or the full bootstrap to refresh `opencode.json`, `model_catalog.json`,
  and `models.json`.

## [1.19.2] - 2026-09-21

### Fixed

- **SKILL.md `\s` portability fix actually applied** — v1.19.1 CHANGELOG
  claimed this fix but the sed command failed due to quoting; `\s`
  remained in SKILL.md:237. Now correctly replaced with `[[:space:]]`.
- **pg_dump stderr redirect order** — `> file 2>&1` sent both streams
  to the dump file, so DUMP_ERR was always empty. Changed to
  `2>&1 > file` so stderr is captured and stdout goes to the file.
- **emit_deployment local vars** — added `OFF_PEAK` and `op_*` to local
  declaration (v1.19.1 only declared model-field vars).
- **INSTALLATION.md "sections A–F"** → "A–G" (section G cross-tool key
  isolation exists since v1.9.4).
- **SKILL.md "one per API key"** → "two per API key — one per format"
  (2N = N OpenAI + N Anthropic per key).
- **REFERENCE.md stale SKILL.md description** — "deterministic install
  procedure" → "operational tasks (health checks, recovery, debugging)".
- **REFERENCE.md stale "Step 7"** → "Recovery table" (SKILL.md has no
  numbered steps).
- **REFERENCE.md scripts table** — added `install-skill.sh` row.
- **INSTALLATION.md helpers table** — added `is_interactive`.
- **README.md** — added Backup section with 06_backup.sh commands.

## [1.19.1] - 2026-09-21

### Fixed

- **Restore into non-empty DB** — `06_backup.sh` used plain `pg_dump` (no
  DROP statements); restore into a populated DB failed on existing objects
  despite the prompt saying "REPLACE". Added `--clean --if-exists` to
  pg_dump so the dump includes DROP-then-CREATE.
- **B4b crash on corrupt config** — unguarded `jq` under `set -euo pipefail`
  killed validation with no summary if the slim config was corrupt JSON.
  Added guard with `2>/dev/null` and fail message.
- **validate_catalog OFF_PEAK gap** — missing field-count check for
  OFF_PEAK_PRICING entries; malformed entry could generate invalid YAML
  → gateway down. Added 5-field shape validation.
- **`((errors++))` set -e landmine** — post-increment returns exit 1 when
  errors=0; future bare callers under `set -e` would die silently. Changed
  to `errors=$((errors + 1))`.
- **update.sh slim $schema drift** — slim version bump sed'd 03a_opencode.sh
  but not the template `$schema` pin, recreating the stale-template bug
  on every bump. Now seds both files and commits them together.
- **SKILL.md stale metric name** — `litellm_request_total_latency_seconds_sum`
  (4th occurrence missed by v1.17.2). Fixed to
  `litellm_request_total_latency_metric_sum`.
- **Backup EXIT trap signals** — trap didn't cover Ctrl-C/SIGTERM. Added
  `trap 'exit 130' INT` and `trap 'exit 143' TERM` so EXIT trap fires
  exactly once on any exit path.
- **pg_dump stderr discarded** — `2>/dev/null` threw away actionable
  diagnostics. Now captured and printed on failure.
- **A0 stderr suppressed** — validate_catalog errors were hidden; failure
  message said "run validate_catalog" (a function, not a command). Now
  prints stderr inline.
- **fail_n 33 stale** — B4 now has 36 checks; updated count and message.
- **Stale log_action references** — removed from INSTALLATION.md helpers
  table and syntax docs (function removed in v1.9.8).
- **"8N total" → "10N"** — INSTALLATION.md:106 stale from 4-model era.
- **GNU \s portability** — SKILL.md list-models command used GNU-only
  `\s`; changed to `[[:space:]]` for BSD/macOS compatibility.
- **emit_deployment local vars** — `read` variables weren't `local`,
  leaking to global scope. Added `local` declaration.

## [1.19.0] - 2026-09-20

### Added

- **emit_deployment() function** — extracted 60-line duplication in
  02_litellm.sh (OpenAI/Anthropic blocks were copy-pasted). Config output
  verified byte-identical.
- **validate_catalog()** — cross-validates MODELS/OFF_PEAK_PRICING/
  REASONING_MODELS arrays in models.sh. Checks field counts, name
  membership (OFF_PEAK/REASONING ⊆ MODELS). Wired into 02_litellm.sh
  (pre-generation guard) and 04_validate.sh (A0 check).
- **Preset drift validation** — B4b checks verify Huawei-MaaS-* presets
  match LiteLLM-* with prefix substitution. Catches drift when one
  preset is updated but the other isn't.
- **Council fallback arrays** — councillors now have 2-model fallback
  arrays (e.g., `["LiteLLM/glm-5.3", "LiteLLM/glm-5.2"]`) matching the
  v1.13.0 fallback treatment every other agent received. Schema-verified
  (slim @2.2.21 `additionalProperties: {}` allows arrays).

### Changed

- **02_litellm.sh** — emit_deployment() takes 6 params (model_entry,
  key_idx, name_prefix, provider_prefix, api_base_env, bridge). Both
  config generation loops are now one-liners.
- **04_validate.sh** — council model assertions updated from string
  equality to array index + length checks.

## [1.18.0] - 2026-09-20

### Added

- **PostgreSQL backup script** (`scripts/06_backup.sh`) — `pg_dump` to
  `backups/litellm_YYYYmmdd_HHMMSS.sql` with chmod 600, prune to `--keep N`
  (default 10), `--restore FILE` with `ON_ERROR_STOP=1` and EXIT trap to
  ensure LiteLLM restarts, `--dry-run` mode. `umask 077` prevents
  world-readable tmp files. `backups/` added to `.gitignore`.
- **Postgres in update.sh components** — display-only ("pinned — major
  upgrades are manual; use 06_backup.sh restore procedure"). Never
  auto-updated (PGDATA compatibility).

### Fixed

- **Restore false success** — psql without `ON_ERROR_STOP=1` exits 0 on
  SQL errors; restore would report success even on corrupt dumps. Added
  `-v ON_ERROR_STOP=1`.
- **Dump tmp world-readable** — `${OUT}.tmp` created with default umask
  (644); sensitive data readable during dump. Added `umask 077`.
- **Restore can leave LiteLLM down** — abnormal exit between stop/restart
  left gateway down. Added EXIT trap.
- **`--keep 08` octal crash** — `$((KEEP + 1))` treated leading zero as
  octal. Fixed with `$((10#$KEEP + 1))`.
- **`--restore=` empty value** — silently ran backup instead of erroring.
  Added empty-value check.
- **AGENTS.md project structure** — updated `01-05` → `01-06`.

## [1.17.3] - 2026-09-20

### Fixed

- **Smoke-test model switched to glm-5.1** — validation and install scripts
  used deepseek-v4-flash (RPM 3) for smoke tests; back-to-back runs caused
  429s misread as "key invalid" → unnecessary key rotation. Switched to
  glm-5.1 (RPM 100) in 04_validate.sh (B5/D4/E4/F4) and 03a/03b/03c/03d
  key-reuse probes. A5 all-models loop unchanged.
- **backup_with_prune() helper** — .bak files accumulated at 9 sites
  without pruning (only 02_litellm.sh capped at 3). Extracted shared
  helper to common.sh with glob-based prune (space-safe). Replaced all
  9 call sites. Accumulated .bak piles pruned to 3.
- **SKILL.md runbook smoke model** — example still used
  deepseek-v4-flash; switched to glm-5.1.
- **Helpers tables** — added backup_with_prune to common.sh description
  in INSTALLATION.md and REFERENCE.md.

## [1.17.2] - 2026-09-20

### Fixed

- **SKILL.md list-models command broken** — `grep -E '^\s*"'` matched
  OFF_PEAK_PRICING/REASONING_MODELS entries, producing garbage like
  `glm-5.2|13`. Replaced with array-scoped `sed -n '/^MODELS=(/,/^)/p'`.
- **SKILL.md metric names wrong** — `litellm_total_requests` etc. →
  `litellm_proxy_total_requests_metric_total` etc. (verified against live
  Prometheus: 17/21/12 series respectively).
- **SKILL.md add-model instructions** — missing REASONING_MODELS and
  OFF_PEAK_PRICING steps. Added to SKILL.md, models.sh header, REFERENCE.md
  and INSTALLATION.md helpers tables.
- **INSTALLATION.md stale panel count** — "39-panel" → "44-panel" (line
  475 already said 44).
- **REFERENCE.md config.yaml example stale** — predates v1.15/v1.16;
  added off_peak_pricing, capability flags, description, organization.
- **REFERENCE.md model_info table** — added 7 missing field rows.
- **SKILL.md off-peak verification runbook** — new "Verify Spend and
  Off-Peak Discount" section with live-verified `/spend/logs` endpoint
  docs, off-peak window math, and real examples.
- **REFERENCE.md glm-5.1 tier bias** — documented that tracked spend
  uses ≥32K-tier rates for all requests; actual bill ~25-40% cheaper
  for <32K requests.
- **INSTALLATION.md cost-efficient usage** — added `--model glm-5.1`
  examples for Codex, Claude Code, and Pi.
- **SKILL.md deployment count** — "N deployments" → "2N deployments"
  (N OpenAI + N Anthropic per model).
- **Helpers table** — added 03d_pi.sh and REASONING_MODELS to models.sh
  description in INSTALLATION.md and REFERENCE.md.

## [1.17.1] - 2026-09-20

### Fixed

- **02_litellm.sh guard exit propagation** — `exit 1` inside
  `echo | while read` pipeline only exited the subshell; script continued
  to `docker compose up -d` which failed opaquely on foreign containers.
  Replaced with `for` loop in main shell so `exit 1` terminates the script.
- **03d_pi.sh stale 8-field comment/read** — documented and parsed 8 fields
  while `models.sh` uses 10 since v1.9.0; `output_cost` silently absorbed
  cache cost fields. Updated to 10-field format matching `models.sh:11`.
- **Slim template $schema pin stale** — `oh-my-opencode-slim@2.2.18` in
  committed template while `SLIM_VERSION="2.2.21"`; self-correcting at
  install via sed but repo template was stale. Updated to `@2.2.21`.
- **model_catalog.json reasoning contradictions** — deepseek-v4-pro/flash
  had `supports_reasoning_effort: true` but `models.sh` and generated
  `config.yaml` set `supports_reasoning: false`. Codex users saw reasoning
  options for models that don't support them. Fixed to `false`/`[]`.
- **glm-5.3 missing `low` reasoning level** — Huawei docs say high+low;
  catalog listed only `high`. Added `low`.
- **glm-5.2 missing reasoning levels** — `models.sh` documents 7 levels
  (max/xhigh/high/medium/low/minimal/none); catalog listed only `high`.
  Added all 7 levels. Verified against live MaaS API: all 7 return
  HTTP 200 with reasoning_content.

## [1.17.0] - 2026-09-20

### Fixed

- **Pre-commit hook was a no-op** — `grep -qF "^${file}$"` treated `^`/`$`
  as literal characters; the `.env`-blocking control never fired. Fixed
  to `grep -qxF "$file"` (exact fixed-string match).
- **M6 catalog checks were dead code** — `04_validate.sh` re-fetched
  `/v1/models` without auth header (401 → empty → 10 checks silently
  skipped). Fixed to reuse the authenticated response. 10 previously-
  skipped per-model catalog checks now run and pass.
- **G1 shared-key detection never fired** — tool names concatenated
  without separator but detection grepped for a space. Fixed with comma
  separator and awk-based detection.
- **update.sh auto-commits swept entire git index** — `git add && git
  commit` committed all staged work, not just the bumped file. Changed
  to `git commit --only`. Removed `|| true` that swallowed hook
  rejections.
- **Validation skipped on partial update failure** — `update.sh` gated
  validation on `FAILED -eq 0`, skipping it exactly when most needed.
  Now offers validation whenever any update ran.
- **Grafana dashboard layout broken** — "Rate Limits & Budget" row at
  y=76 collided with Cache panels (y=76–96). Row headers appeared after
  their panels, breaking collapse grouping. Re-sequenced y-coordinates,
  moved Cache row header before its panels. Fixed spend table query
  (`instant: true`, `range: false`).

### Added

- **23 new validation checks** for v1.15/v1.16 features:
  - Off-peak pricing block count (4×KEY_COUNT)
  - Capability flag counts (mode, supports_function_calling,
    supports_prompt_caching, supports_reasoning, description,
    organization — each 10×KEY_COUNT)
  - Off-peak placement verification (present for glm-5.2/glm-5.1,
    absent for glm-5.3/deepseek)
  - Balanced preset exact-match assertions (glm-5.1 primary, 2-model
    fallback arrays, oracle fallback is glm-5.3)
  - Default preset exact-match assertions (glm-5.3 primary, all 7
    agents have 2-model arrays)
  - Grafana panel count check (== 44)

### Verified

- **Off-peak billing empirically verified** — natural experiment across
  the peak/off-peak boundary (07:49 → 08:23 Beijing):
  - Off-peak request: spend exactly matched 70% rates (input, output,
    AND cache_read)
  - Peak request: spend matched standard rates
  - The `"13:00-00:00"` UTC string format and midnight wrap work
    correctly in LiteLLM 1.101.0

## [1.16.0] - 2026-09-20

### Added

- **Model capability flags** — All models now have explicit `mode: chat`,
  `supports_function_calling: true`, `supports_prompt_caching`, and
  `supports_reasoning` in `model_info`. Enables LiteLLM parameter
  validation and capability-aware routing.
  - `supports_reasoning`: true for glm-5.3 and glm-5.2 (support
    `reasoning_effort`), false for glm-5.1 and DeepSeek.
  - `supports_prompt_caching`: true for GLM models (cache hit pricing),
    false for DeepSeek (no cache support).
- **Model metadata** — `description` and `organization: Huawei Cloud`
  fields added to all model_info blocks. Visible in LiteLLM Admin UI
  and `/v1/model/info` endpoint.
- `models.sh`: `REASONING_MODELS` array for reasoning_effort support
  lookup.

### Changed

- `02_litellm.sh`: `supports_reasoning()` lookup function added; both
  OpenAI and Anthropic loops now emit capability flags + metadata.
- `config.yaml.template`: Updated all 5 model entries with capability
  flags and metadata for consistency with generated config.
- `models.sh`: Cleaned up duplicate `OFF_PEAK_PRICING` arrays (caused
  by interrupted fixer tasks).

## [1.15.0] - 2026-09-20

### Added

- **Off-peak billing** — Huawei MaaS time-based differential pricing now
  modeled via LiteLLM `off_peak_pricing` in `model_info`. GLM-5.2 and
  GLM-5.1 have off-peak rates (70% of peak) during 21:00–07:59 GMT+8
  (13:00–00:00 UTC). GLM-5.3 and DeepSeek models have flat pricing.
  Configured in `models.sh` via `OFF_PEAK_PRICING` array, emitted by
  `02_litellm.sh` for both OpenAI and Anthropic deployments.
- **Grafana dashboard: Rate Limits & Budget row** — 4 new panels:
  - Deployment TPM limits (stat) — per-model TPM ceiling from config
  - Deployment RPM limits (stat) — per-model RPM ceiling from config
  - Spend by tool (piechart) — USD spend per API key alias (opencode,
    codex, claude-code, pi)
  - Spend by tool × model (table) — granular cost attribution

### Changed

- Dashboard panel count: 39 → 44 (8 row headers + 36 visualization panels).
- `models.sh` now defines `OFF_PEAK_PRICING` array for time-based
  differential pricing (format: `model_name|hours_utc|input|output|cache`).
- `REFERENCE.md` pricing notes updated to document off-peak modeling.

## [1.14.0] - 2026-09-19

### Security

- **LiteLLM 1.98.0 → 1.101.0** — Critical fix: virtual key no longer
  forwarded to Anthropic on the `/anthropic` passthrough route (#29609).
  Also fixes spend updates silently dropped on Postgres deadlocks (#34887)
  and multiple secret-leak paths in verbose logging (#37391, #37373).
- **Grafana 13.2.0 → 13.2.2** — CVE-2026-15815, CVE-2026-76154,
  CVE-2026-79656. Also fixes provisioning folder-rename UID collision.

### Changed

- **Component updates** (via `./scripts/update.sh --all`):
  - LiteLLM 1.98.0 → 1.101.0 — Anthropic `/v1/messages` streaming fixes
    (thinking blocks, tool calls, document blocks), per-key/per-team
    Prometheus rate-limit gauges, fail-closed budget enforcement,
    streaming cost on usage, model deprecation alerts.
  - oh-my-opencode-slim 2.2.18 → 2.2.21 — per-agent `skills_add`/
    `skills_remove` directives, configurable fallback retry delays,
    fix for spaces in provider model names.
  - Codex CLI 0.149.0 → 0.155.1 — reasoning summaries disabled by
    default for new sessions (fixes request rejections from non-OpenAI
    providers like our LiteLLM proxy), experimental worktree support,
    `@`-mention tasks.
  - Pi agent 0.84.2 → 0.85.1 — fixed proxied plain-HTTP requests hanging
    after tool calls (CONNECT tunneling), OpenAI-compatible stream fixes.
    Skips 0.85.0 (bad npm publish).

### Fixed

- `update.sh`: "Skipping validation" answer now actually skips validation
  (previously logged the skip message but ran validation anyway).
- `update.sh`: slim plugin updates now re-apply opencode configs from
  repo templates — the slim installer preserves the existing config
  (leaving a stale `$schema` version) and rewrites `opencode.json` with
  looser permissions; configs are regenerated and `chmod 600`
  re-enforced after every slim update.
- `03a_opencode.sh`: config file permissions are now fixed to 600 even
  when content is unchanged (previously the write was skipped entirely,
  leaving loose permissions set by external installers).

## [1.13.0] - 2026-09-19

### Changed

- **Preset restructure** — Removed LiteLLM-Extended and Huawei-MaaS-Extended
  presets (they relied on deepseek-v4-flash which has very low rate limits:
  TPM 30K, RPM 3). Added LiteLLM-Balanced and Huawei-MaaS-Balanced presets
  (cost-effective: glm-5.1 primary, glm-5.2/glm-5.3 fallback, no deepseek).
- **All agents now have fallbacks** — orchestrator, librarian, explorer, and
  fixer previously had single models with no fallback. All agents now have
  a primary + fallback chain for reliability.
- **Designer variant medium → low** — glm-5.3 doesn't support `medium`
  reasoning_effort (only `high` and `low`). Changed to `low` (enhanced
  reasoning) for compatibility.
- **small_model changed to glm-5.1** — Was deepseek-v4-flash (rate limit
  issues). Now uses glm-5.1 (TPM 1M, RPM 100) for lightweight tasks.
- **ANTHROPIC_SMALL_FAST_MODEL changed to claude-glm-5.1** — Same rationale.

### Added

- **LiteLLM-Balanced preset** — Cost-effective preset using glm-5.1 as
  primary for all agents (~23% cheaper than glm-5.3). Oracle fallback is
  glm-5.3 for critical reasoning quality. All other fallbacks are glm-5.2.
- **Huawei-MaaS-Balanced preset** — Direct MaaS version of the above.

## [1.12.0] - 2026-09-19

### Changed

- **Agent presets reassigned to glm-5.3** — Quality-biased default preset.
  glm-5.3 is now the primary model for orchestrator, oracle, council,
  designer, fixer, and all 3 councillors. glm-5.2 is the fallback (where
  glm-5.1 was before). Librarian and explorer stay on glm-5.1 /
  deepseek-v4-flash for cost efficiency. Updated default models for
  opencode, Codex CLI, and Claude Code CLI. Updated in:
  `oh-my-opencode-slim.json.template`, `opencode.json.template`,
  `config.toml.template`, `03a_opencode.sh`, `03b_codex.sh`,
  `03c_claude_code.sh`, `04_validate.sh`, `REFERENCE.md`,
  `INSTALLATION.md`.

## [1.11.0] - 2026-09-19

### Added

- **glm-5.3 model** — New GLM generation added to the model catalog.
  Specs: 1M context, 128K max output, TPM 1M, RPM 100, cache read support.
  Pricing: $1.40/$4.40 per 1M tokens (input/output), $0.26 cache hit —
  identical to glm-5.2. Updated in: `models.sh`, `config.yaml.template`,
  `opencode.json.template`, `model_catalog.json`, `REFERENCE.md`,
  `README.md`, `SKILL.md`, `bootstrap.sh`.

## [1.10.11] - 2026-09-14

### Fixed

- `02_litellm.sh`: "integer expression expected" error when LiteLLM was
  not already running. `grep -c litellm || echo 0` produced `"0\n0"` (grep
  outputs `0` on no-match AND exits 1, triggering the `|| echo 0` fallback).
  Changed to `|| true` to suppress the exit code without duplicating output.

## [1.10.10] - 2026-09-11

### Added

- **Quality Pass standard in AGENTS.md** — After validation passes,
  spawn a fresh `@oracle` session (no prior context) to review all
  changes. Oracle reports findings, `@fixer` fixes HIGH/MEDIUM issues,
  re-validate, then commit. 12 review categories: bugs, error handling,
  security, simplicity, maintainability, modularity, consistency, QoL,
  documentation, stale references, performance, backwards compatibility.

### Fixed

- Updated stale "Security reminder" note in AGENTS.md to match the
  soft key rotation tip from v1.10.9.

## [1.10.9] - 2026-09-11

### Changed

- **Security warning → tip** — Replaced the alarming 5-step key rotation
  warning with a simple dim tip shown after every install: "If you shared
  your MaaS API key with a coding agent or CI system, consider rotating
  it." Shows in all modes (interactive and non-interactive).

## [1.10.8] - 2026-09-11

### Fixed

- **Suppress security warning in non-interactive mode** — The API key
  rotation reminder no longer shows when `-y`/`--yes` is used (user
  explicitly chose to pass keys via CLI/env).

## [1.10.7] - 2026-09-11

### Fixed

- **Pi installer broken pipe with `-y`** — `yes` infinite stream caused
  SIGPIPE when installer exited, killing it mid-install under `set -e`.
  Replaced with `printf 'y\ny\ny\ny\ny\n'` (finite input, no broken pipe).

## [1.10.6] - 2026-09-11

### Improved

- **Pi install with `-y`** — When Node.js 22+ is already available, Pi is
  now installed directly via `npm install -g` (bypassing the installer
  script entirely, zero prompts). The `script` pseudo-terminal fallback
  only activates when Node.js 22+ needs to be installed by the installer.

## [1.10.5] - 2026-09-11

### Fixed

- **Pi installer prompts with `-y`** — Previous `setsid` approach removed
  tty entirely, causing installer to abort ("No terminal detected; install
  Node.js... then run again"). Now uses `script` to create a pseudo-terminal
  with `yes` piped to auto-answer all prompts (Node.js install, action
  choice, PATH update).

## [1.10.4] - 2026-09-11

### Fixed

- **Pi installer prompts with `-y`** — Pi installer reads from `/dev/tty`
  (not stdin), so `yes |` pipe didn't work. Now uses `setsid` to start
  installer without a controlling terminal — installer detects "No
  terminal" and skips all confirmation prompts automatically.

## [1.10.3] - 2026-09-11

### Fixed

- **Pi installer prompts suppressed with `-y`** — Pi's internal prompts
  ("Install Node.js?", "Choose action") now auto-answered via `yes` pipe
  when `AUTO_YES=true`
- **01_env.sh MaaS key prompt** — errors with clear message when
  `AUTO_YES=true` and no key provided (instead of prompting)
- **uninstall.sh bun/pi-node prompts** — auto-remove when `AUTO_YES=true`
- **update.sh "Run validation?" prompt** — auto-proceeds when
  `AUTO_YES=true`
- **keys.sh fallback prompt** — errors instead of prompting when
  `AUTO_YES=true`
- **docker-compose.yml** — removed redundant env_file comment
- **SKILL.md** — added `-y`/`--yes` and `--api-key=` to bootstrap flags table
- **README.md** — added non-interactive upgrade example

## [1.10.2] - 2026-09-10

### Fixed

- **`-y` flag now suppresses prerequisite install prompts** —
  `helpers/prereqs.sh` `_prereq_prompt()` now checks `AUTO_YES` before
  prompting to install Docker, git, curl, jq, bun, npm, etc.

## [1.10.1] - 2026-09-10

### Fixed

- **`-y` flag now suppresses prompts in child scripts** — Previously only
  guarded bootstrap.sh prompts; child scripts (`01_env.sh`, `03a_opencode.sh`,
  `05_skill.sh`) still prompted for secrets, API keys, and skill install.
  Now exports `AUTO_YES` to children and guards all prompts:
  - `01_env.sh`: auto-accepts generated secrets, skips extra-key collection
  - `03a_opencode.sh`: skips direct-provider API key prompt
  - `05_skill.sh`: auto-installs companion skill

## [1.10.0] - 2026-09-10

### Added

- **`-y` / `--yes` flag** — Non-interactive mode for `bootstrap.sh`.
  Auto-accepts all prompts: install directory, existing install upgrade,
  tool selection (all tools), git pull reset, and companion skill.
  Enables fully automated installs and upgrades via one-liner.
- **`--api-key=KEY` flag** — Pass Huawei MaaS API key via CLI.
  Alternative to `HUAWEI_MAAS_API_KEY` env var. Exported to child scripts.

### Non-interactive usage

```bash
# Fresh install
curl -fsSL .../bootstrap.sh | bash -s -- -y --api-key=sk-xxxx

# Upgrade existing install
curl -fsSL .../bootstrap.sh | bash -s -- -y
```

## [1.9.9] - 2026-09-10

### Fixed

- **INSTALLATION.md** — Updated `03d_pi.sh` description: downloads to temp
  file instead of `curl | sh` pipe (reflects M5 fix)
- **README.md** — Updated `update.sh` note: changes are auto-committed
  instead of requiring manual commit (reflects H4 fix)

## [1.9.8] - 2026-09-10

### Fixed

- **M1: flock availability guard** — `bootstrap.sh` warns and continues if
  `flock` is missing (macOS) instead of misleading "already running" error
- **M3: Config backup rotation** — `02_litellm.sh` keeps only last 3
  backups, preventing indefinite accumulation
- **M4: env_file scope warning** — Added NOTE comments in `docker-compose.yml`
  and `.env.template` about secret leakage via `env_file: .env`
- **M5: Pi installer download** — `03d_pi.sh` downloads to temp file before
  executing instead of `curl | sh` pipe
- **M6: Secret newline validation** — `01_env.sh` rejects secrets containing
  newline characters before heredoc write
- **L1: nvm path detection** — `bootstrap.sh` tries `nvm which default`
  first, falls back to directory listing
- **L2: Grafana password exposure** — `04_validate.sh` uses `--config -`
  heredoc instead of `-u` flag (password not visible in `ps`)
- **L3: Quote KEY_COUNT** — `01_env.sh` now quotes
  `HUAWEI_MAAS_API_KEY_COUNT` in .env heredoc
- **L4: Redundant restart** — `02_litellm.sh` skips restart on fresh
  install (when container wasn't previously running)
- **D8: REFERENCE.md config examples** — Updated glm-5.2 examples to
  show 1M context window (was 198K)
- Removed dead `log_action()` from `common.sh`
- Added `.env.template` comment clarifying `OPENCODE_ENABLE_EXA` is set
  by `03a_opencode.sh` in `~/.bashrc`
- Cleaned stale legacy models (`glm-5`, `deepseek-v3.2`) from local
  codex `model_catalog.json`
- Cleaned old config backups (kept last 3)

## [1.9.7] - 2026-09-10

### Changed

- **Model catalog updated** to match latest Huawei MaaS specs:
  - `glm-5.2`: context window 198K → **1M** (max_tokens and max_input
    198000→1000000)
  - `deepseek-v4-flash`: TPM 60000→30000, RPM 15→3, max_output
    128K → **384K** (128000→384000)
  - `glm-5.1` and `deepseek-v4-pro`: unchanged
- Updated in: `models.sh`, `config.yaml.template`, `model_catalog.json`,
  `opencode.json.template`, `REFERENCE.md`
- Regenerated `config.yaml` and restarted LiteLLM container

## [1.9.6] - 2026-09-10

### Fixed

- **C1: Foreign container destruction guard** — `02_litellm.sh` now only
  removes `litellm_*` containers on occupied ports; foreign containers
  trigger an error instead of being force-removed
- **C2: Key deletion ordering race** — `keys.sh` now mints the new virtual
  key before deleting the old one, preventing auth failures on transient
  minting errors
- **H1: Env-var key validation** — `01_env.sh` now validates extra MaaS
  keys from env vars for placeholder values (matching interactive path)
- **H2: DB_PASSWORD URL-special char check** — `01_env.sh` rejects
  passwords containing `@`, `:`, `/`, `#` that would break DATABASE_URL
- **H3: pi-node removal confirmation** — `uninstall.sh` now prompts before
  removing `~/.local/share/pi-node` (may break other projects)
- **H4: update.sh tracked file mutation** — `update.sh` now warns and
  auto-commits when modifying tracked files (`03a_opencode.sh`,
  `docker-compose.yml`) to prevent future `git pull` failures
- **H5: npm install -g sudo detection** — `03b_codex.sh` and
  `03c_claude_code.sh` detect non-writable npm prefix and use sudo
- **D1: Env var typo** — `HUAWEI_MAAS.ANTHROPIC_API_BASE` → underscore
  in INSTALLATION.md and CHANGELOG.md
- **D2-D3: Helpers table** — models.sh and skills.sh "Used by" columns
  updated in INSTALLATION.md
- **D4: SSH port forwarding** — SKILL.md now includes port 9090 for
  Prometheus
- **D5: PROMETHEUS_RETENTION** — REFERENCE.md "Read by" updated to
  include `04_validate.sh`
- **D6: EXA .bashrc cleanup** — `uninstall.sh` now removes
  `OPENCODE_ENABLE_EXA` from `~/.bashrc`
- **D7: CHANGELOG check count** — Clarified "24 at runtime (32 defined)"

## [1.9.5] - 2026-09-09

### Added

- **24 new validation checks at runtime** in `04_validate.sh` (96 → 120 total, 32 defined — some skipped by conditionals):
  - M1: Slim plugin version match (installed vs `03a_opencode.sh`)
  - M2: Container security hardening applied at runtime (8 checks)
  - M3: Router settings in config (routing_strategy, prometheus callback)
  - M4: Prometheus retention applied (matches `.env`)
  - M5: Grafana dashboard has panels (>0)
  - M6: Model catalog matches `models.sh` (8 checks, 4 models × 2 formats)
  - M7: Virtual key aliases match tool names (4 checks)
  - L1: Docker Compose file validity
  - L2: Container restart policy (4 checks)
  - L3: `LITELLM_SALT_KEY` strength (≥32 chars)
  - L4: Prometheus self-monitoring active

## [1.9.4] - 2026-09-09

### Fixed

- **update.sh npm_latest() crash on bun-only hosts** (GitHub issue #4) —
  `npm view` returned exit 127 when npm not installed (default on bun-only
  hosts), causing `set -e` to abort silently. Added `command -v npm` guard
  with curl-based npm registry fallback so version table populates without npm.

### Added

- **12 new validation checks** in `04_validate.sh` (84 → 96 total):
  - C1: `BIND_ADDRESS` exposure warning (0.0.0.0 vs 127.0.0.1)
  - C2: Git hooks installed (`core.hooksPath` = `.githooks`)
  - H1: Container health status (healthy/unhealthy/starting, not just running)
  - H2: All `HUAWEI_MAAS_API_KEY_N` present in `.env`
  - H3: All-models inference smoke test (was single-model `deepseek-v4-flash`)
  - H4: Cross-tool virtual key isolation (no shared keys between tools)
  - H5: Config freshness (`.env` vs `config.yaml` mtime comparison)

## [1.9.3] - 2026-09-05

### Fixed

- **04_validate.sh grep portability** — replaced GNU-specific `\s` with
  POSIX `[[:space:]]` in 4 grep patterns for portability across systems.
- **uninstall.sh ss guard** — added `command -v ss` check before using
  `ss` for port-wait loop; falls through gracefully if `ss` is absent.
- **uninstall.sh fractional sleep** — `sleep 0.5` → `sleep 1` for
  compatibility with systems lacking GNU coreutils fractional sleep.
- **pre-commit hook fixed-string match** — `grep -q` → `grep -qF` to
  treat filenames as literal strings, not regex patterns.
- **Helper file permissions** — `helpers/models.sh` and `helpers/skills.sh`
  set to 755 for consistency with other helper scripts.

## [1.9.2] - 2026-09-05

### Fixed

- **SKILL.md key-adding formula** — `NEW_INDEX=$((CURRENT_COUNT - 1))`
  would overwrite an existing key. Fixed to `NEW_INDEX=$CURRENT_COUNT`
  (the next available index).
- **SKILL.md model format** — updated to include `cache_read_cost` and
  `cache_creation_cost` fields (stale since v1.9.0 added cache pricing).
- **SKILL.md add-model instructions** — now lists all 5 files that need
  updating: `models.sh`, `config.yaml.template`, `opencode.json.template`,
  `model_catalog.json`, `slim.json.template`.
- **SKILL.md grep portability** — replaced `grep -oP` (Perl regex) with
  portable `grep -E` + `sed` equivalent.
- **SKILL.md uninstall flags** — added missing `--repo` flag to the
  uninstall.sh command table.
- **REFERENCE.md OPENCODE_ENABLE_EXA attribution** — "Set by" column
  corrected from `01_env.sh` to `03a_opencode.sh` (01_env.sh does not
  write this variable).
- **INSTALLATION.md panel count** — "32-panel" corrected to "39-panel
  (7 row headers + 32 visualization panels)" for consistency with
  REFERENCE.md and SKILL.md.
- **INSTALLATION.md choice 7** — corrected from `--tool=opencode,codex`
  to "Interactive — Custom toggle each component on/off".
- **INSTALLATION.md env-var table** — added missing `HUAWEI_MAAS_API_BASE`
  and `HUAWEI_MAAS_ANTHROPIC_API_BASE` entries.
- **02_litellm.sh KEY_COUNT validation** — added numeric check before
  arithmetic comparison to prevent crash on non-numeric `.env` value.
- **04_validate.sh KEY_COUNT validation** — same numeric guard added
  before deployment count calculation.
- **docker-compose.yml Prometheus healthcheck** — added `wget`-based
  healthcheck for consistency with other services.

## [1.9.1] - 2026-09-05

### Fixed

- **Council model validation hardened** — `04_validate.sh` now checks that
  councillor models equal `LiteLLM/glm-5.2` (equality check) instead of
  merely verifying the key exists (truthiness check). Prevents a silent
  model-substitution regression from passing validation.
- **Council labeling caveat documented** — added a note in REFERENCE.md
  explaining that council report labels may show hardcoded example model
  names from the plugin's Council Mode prompt template (`gpt-5.6-luna`,
  `gemini-3-pro`), not the actual configured model. The councillors run
  with `glm-5.2`; verify via LiteLLM logs or Grafana.

## [1.9.0] - 2026-09-05

### Added

- **Cache hit pricing** — added `cache_read_input_token_cost` to glm-5.2
  ($0.26/M) and glm-5.1 ($0.27/M) in LiteLLM config. Enables accurate cost
  tracking when Huawei MaaS serves cached tokens at a discount.
- **Pricing documentation** — updated REFERENCE.md with cache hit column,
  peak/off-peak time intervals (Period 1/2), and glm-5.1 tiered pricing
  (<32K vs ≥32K tokens). Source: Huawei MaaS pricing page.

### Changed

- `helpers/models.sh` — extended model format with `cache_read_cost` and
  `cache_creation_cost` fields.
- `scripts/02_litellm.sh` — emits cache pricing fields when non-zero.
- `configs/litellm/config.yaml.template` — added cache fields for reference.

## [1.8.0] - 2026-09-03

### Changed

- **Disabled LiteLLM no-Redis warning** — set `LITELLM_DISABLE_NO_REDIS_WARNING=true`
  in `docker-compose.yml` for our deliberate single-worker setup. PostgreSQL alone
  is sufficient; Redis is only needed for multi-worker/replica deployments.
  Validation now passes 84/84 with 0 warnings.

### Added

- Documented `LITELLM_DISABLE_NO_REDIS_WARNING` in `INSTALLATION.md` and
  `REFERENCE.md` Key Contract table.

## [1.7.2] - 2026-09-03

### Changed

- **oh-my-opencode-slim pinned v2.2.15 → v2.2.18** — updated SLIM_VERSION
  in `03a_opencode.sh`, `$schema` URL in slim template, and doc references
  in INSTALLATION.md + REFERENCE.md. No breaking changes (same MCP names,
  same default agent MCPS; one new deprecated key `runtimeOverride` which
  we don't use).

### Fixed

- **`.env` missing `OPENCODE_ENABLE_EXA`** — added to actual `.env` file
  (was only in template).

## [1.7.1] - 2026-08-24

### Fixed

- **CHANGELOG section count** — corrected "39→11 sections" to "39→12 sections"
  and added line count (1104→460).
- **CHANGELOG version claim** — deprecated fallback keys are deprecated in
  2.2.15 (not "removed in 2.3.x").

### Added

- **OPENCODE_ENABLE_EXA documented** — added to `configs/.env.template`,
  `INSTALLATION.md` env var table, `REFERENCE.md` Key Contract table.
- **03a_opencode.sh** — ensures `OPENCODE_ENABLE_EXA=1` is persisted to
  `~/.bashrc` during install for custom providers.
- **Websearch documentation** — added to `INSTALLATION.md` (Using opencode
  section) and `REFERENCE.md` (opencode plugin section).

## [1.7.0] - 2026-08-24

### Added

- **Websearch enabled** — opencode's built-in EXA-backed websearch tool is now
  enabled for custom providers (LiteLLM/Huawei-MaaS). Added `OPENCODE_ENABLE_EXA=1`
  to environment and `"permission": {"websearch": "allow"}` to opencode config.
  No EXA API key required.

### Fixed

- **Slim template: deprecated fallback config keys** — removed `timeoutMs`,
  `retryDelayMs`, `retry_on_empty` (deprecated in oh-my-opencode-slim 2.2.15);
  replaced with `fallback.maxRetries`. Fixes startup warning.
- **Slim template: invalid MCP names** — librarian preset referenced
  `websearch` (not an MCP — it's opencode's built-in tool) and `grep_app`
  (wrong name — should be `gh_grep`). Corrected to `["context7", "gh_grep"]`.

### Changed

- **CHANGELOG compacted** — 39 sections → 12 sections, 1104 → 460 lines.
  Pre-1.0, 1.2.x dashboard saga, and 1.4.x component bumps consolidated
  into summary entries. All git tags preserved for rollback.
- **GitHub releases pruned** — 33 → 8 milestone releases. Intermediate
  releases deleted (tags kept for rollback). Kept: v1.6.1, v1.6.0, v1.5.0,
  v1.4.10, v1.3.1, v1.2.0, v1.1.0, v1.0.0.
- **Versioning discipline updated** in AGENTS.md — always bump VERSION +
  CHANGELOG for git tracking; create GitHub releases only for meaningful
  milestones (MINOR, significant PATCH clusters). Batch related changes.

## [1.6.1] - 2026-08-23

### Fixed (regressions from v1.6.0)

- **REFERENCE.md/INSTALLATION.md: dashboard docs done backwards** — previous
  fix read JSON array order instead of gridPos.y render order; corrected
  to Cache(6th)→Cost(7th), Tokens=4, Cost=3, Cache=3
- **bootstrap.sh: invalid menu exit** — `exit 1` on invalid input killed
  entire bootstrap; changed to `continue` to re-prompt inside while loop

### Fixed (new bugs from skeptical review)

- **uninstall.sh: Docker filter AND logic** — `--filter "name=litellm_"
  --filter "name=oh-my-coding"` matched nothing (AND logic); simplified
  to single `--filter "name=litellm_"`
- **uninstall.sh: .bashrc permissions** — `mv "$tmp" "$bashrc"` changed
  .bashrc to 0600; switched to `cat > file` to preserve permissions
- **docker-compose.yml: Grafana password default** — `:-admin` silently
  started with weak password; changed to `:?` fail-fast
- **uninstall.sh: unconditional bun removal** — now prompts
  "Remove bun runtime? (may break other bun projects) [y/N]"
- **01_env.sh: silent .env data loss** — re-run deleted user-added custom
  vars; now preserves unknown vars from existing .env
- **update.sh: relative docker-compose.yml path** — broke when run from
  non-project directory; changed all references to use $PROJECT_DIR

## [1.6.0] - 2026-08-23

### Fixed

- **update.sh: empty version corruption** — slim update used fresh npm
  lookup bypassing validation; now uses pre-validated version with guard
- **uninstall.sh: unquoted glob expansion** — paths with spaces could
  cause rm -rf to delete unintended directories; rewritten with find
- **04_validate.sh: docker missing crash** — docker compose ps under
  set -e killed script with opaque error; added fallback
- **keys.sh: JSON built via string interpolation** — delete request
  body now built with jq -nc for safety
- **keys.sh: silent key deletion failure** — now warns if deletion
  fails before minting
- **04_validate.sh: Grafana password in process args** — credentials
  now passed via curl --config stdin instead of -u CLI arg
- **INSTALLATION.md: misleading --xxx-only flag docs** — clarified
  that these flags include LiteLLM checks

### Fixed (council review)

- **bootstrap.sh: stale Grafana label** — summary said "(anonymous)"
  but login is required; fixed to show login instructions
- **bootstrap.sh: sudo bash recommendation** — removed harmful root
  recommendation that broke file ownership; scripts handle sudo internally
- **bootstrap.sh: invalid menu choice** — typing `q` or invalid input
  silently triggered full install; now exits with error
- **REFERENCE.md: false binary removal claim** — docs said binaries
  aren't removed by uninstall, but they are; corrected
- **REFERENCE.md: dashboard docs errors** — fixed section order
  (Cost/Cache swapped), panel counts (32 viz panels, not 39), per-section
  counts (Tokens=3, Cost=7, Cache=0)
- **INSTALLATION.md: dashboard panel count** — corrected 39→32 panel
  references and section order
- **uninstall.sh: bun removal warning** — now warns before removing
  ~/.bun (may break other bun projects)
- **uninstall.sh: destructive docker down warning** — now warns before
  `docker compose down -v --rmi all` (irreversible data loss)
- **update.sh: repo file mutation** — now backs up files before sed -i
  and logs a visible warning
- **models.sh: false SSOT claim** — docs said "edit this file only"
  but 5+ files needed; corrected in models.sh, INSTALLATION.md, REFERENCE.md
- **prereqs.sh: sudo guard at source time** — moved from source-time
  exit to function-call-time check; validation no longer crashes without sudo

### Changed

- **Grafana: anonymous access disabled** — login now required
  (admin user + password from .env). Health endpoint still unauthenticated.
- **Docker container hardening** — added init:true,
  no-new-privileges, cap_drop:ALL to all services

### Updated

- LiteLLM v1.95.0 → v1.98.0 (credential header redaction, SSE keepalive, spend perf)
- Prometheus v3.13.2 → v3.14.0 (stack overflow fix, shutdown CPU bug)
- Grafana 13.1.2 → 13.2.0 (CVE-2026-17183 security fix, new dashboard features)
- oh-my-opencode-slim v2.2.10 → v2.2.15
- Codex CLI 0.146.0 → 0.149.0 (agents dashboard, codex doctor)
- Claude Code 2.1.232 → 2.1.241
- Pi agent 0.83.0 → 0.84.2
- entrypoint.sh health-check patch is now a no-op (LiteLLM v1.97.0+
  removed the probe text; patch kept for backward compatibility)

## [1.5.0] - 2026-08-06

### Fixed (council review)

- **Validation thresholds**: replaced hardcoded `>= 6` with `$MODEL_COUNT`
  in `04_validate.sh` — validation now self-adjusts to catalog size
- **Docker image tag generation in update.sh**: `tag_prefix` was parsed
  but never used in sed, producing invalid image references — now correctly
  interpolates `:v` prefix for LiteLLM/Prometheus and `:` for Grafana
- **run_filtered return values**: update.sh now checks exit codes and
  reports failures instead of false success
- **opencode.json permissions**: regenerated to 600 (was 644, exposed
  virtual key)
- **Stale model references removed**: regenerated opencode.json and
  pi models.json via `03a_opencode.sh` + `03d_pi.sh` — removed `glm-5`
  and `deepseek-v3.2` that were no longer in catalog
- **Slim template version synced**: `@2.2.9` → `@2.2.10` in
  `oh-my-opencode-slim.json.template`

### Added

- **Unknown flag rejection** in update.sh (project rule compliance)
- **npm_latest timeout** (15s) to prevent hanging on slow registry
- **Repo file mutation warnings** in update.sh before editing
  `docker-compose.yml` and `03a_opencode.sh`
- **Stale model recovery** entry in SKILL.md Recovery table
- **--dry-run** documented in README.md
- **Repo file mutation** documented in README.md

### Council Review

Three councillors (alpha/gpt-5.6-luna, beta/gemini-3-pro, gamma/claude-opus-5)
reviewed the project from code quality, architecture, and security/UX
perspectives. All agreed on the fixes above. See council report for details.

## [1.4.0] - 2026-08-04

Consolidates v1.4.0–v1.4.10: component upgrades, preset redesign,
update.sh script, and coding tool updates.

### Changed

- **Prometheus upgraded v3.2.1 → v3.13.2 (LTS)** — security fixes
  (CVE-2025-4673, CVE-2023-45289), 2x faster regex matching, XOR2 encoding,
  native histogram support. v3.13 is a Long Term Support release.
- **LiteLLM upgraded v1.89.3 → v1.95.0** — Claude Opus 5 support, Rust
  backend for Anthropic API, SAML 2.0 SSO, cost optimization page,
  improved streaming performance.
- **Grafana upgraded 11.5.2 → 13.1.2** — two major version jump. Dynamic
  dashboards, Git Sync, revamped gauge visualization, quick filters.
- **oh-my-opencode-slim upgraded v2.0.5 → v2.2.10** — custom subagent
  permissions, project-local customization, native cmux/kitty multiplexer,
  task reconciliation improvements, webfetch config.
- **Presets redesigned and renamed** — `Full`/`Core` → `Default`/`Extended`
  based on model composition. Default uses GLM only (reliable, RPM=100);
  Extended adds deepseek-v4-flash for faster exploration. `deepseek-v4-pro`
  removed from all presets (too expensive, RPM=3). Variants updated to
  valid Huawei MaaS reasoning_effort values (`high` only, no `max`).
- **deepseek-v4-flash rate limits** — RPM 3 → 15, TPM 30,000 → 60,000
  (Huawei MaaS revised quotas).

### Added

- **`scripts/update.sh`** — component update script with interactive
  multi-select, `--check`, `--all`, `--dry-run` flags. Supports 8
  components (opencode, slim, Codex, Claude Code, Pi, LiteLLM, Grafana,
  Prometheus). Integrated into bootstrap.sh for existing installs.
- **Coding tools updated**: opencode 1.17.17 → 1.18.13, Codex CLI
  0.144.5 → 0.146.0, Claude Code 2.1.218 → 2.1.222, Pi agent 0.80.3 →
  0.83.0. Re-minted stale Claude Code virtual key.

### Updated

- REFERENCE.md: preset table, agent→model mapping, update.sh entry
- INSTALLATION.md: preset descriptions, updating coding tools section
- SKILL.md: update instructions, grouped layout documentation
- scripts/04_validate.sh: preset name checks

## [1.3.0] - 2026-07-22

Consolidates v1.2.0–v1.3.1: dashboard overhaul, cache panels, plugin upgrade.

### Added

- **Cache section** — new Grafana dashboard section with 3 panels:
  Provider cache reads (timeseries, tok/min), Cache misses/min
  (timeseries, req/min), Cache hit ratio (stat with threshold
  coloring, one per model).
- **Cache hit ratio panel** — `1 - (sum by (model) (rate(cache_misses)) / sum by (model) (rate(total_requests)))`. Thresholds: red → yellow(10%) → green(30%).

### Changed

- **oh-my-opencode-slim plugin upgraded v2.0.5 → v2.2.5** — custom
  subagent permissions, project-local customization, native
  cmux/kitty multiplexer, Windows path normalization, flatten council
  dispatch, task rejection contracts. No breaking changes.
- **Deployment state panel** — timeseries → state-timeline (colored
  blocks). 0=Healthy (green), 1=Degraded (orange), 2=Outage (red).
- **Cache panel queries** — added `sum by (model)` + `* 60` to match
  token panel pattern (per-minute, grouped by model).
- **Cache panel units** — `short` → `tok/min` / `req/min`.
- **Stat panel thresholds** — added yellow/red to RPS, RPM, TPS, TPM,
  Total cost.
- **Tokens section** — Input, Cached input, Output, Reasoning (4
  panels in one row).
- **Dashboard layout** — 39 panels across 7 sections.
- **Documentation** — INSTALLATION.md, SKILL.md, REFERENCE.md synced
  with 39-panel / 7-section layout.

### Fixed

- **Total Requests undercounting** — query only counted success.
  Fixed to sum success + failure.
- **Cache hit ratio label mismatch** — divided metrics with
  incompatible label sets. Fixed with `sum by (model)` aggregation.
- **Cache panel legendFormat** — escaped braces → `{{model}}`.
- **Gauge panel not rendering** — gauge/bargauge types don't render
  in Grafana 11.5.2. Settled on `stat` with area graph.

## [1.1.0] - 2026-07-06

Consolidates v1.1.0–v1.1.6: companion skill, portability, rate limits.

### Added

- **Companion skill installation** (`scripts/05_skill.sh`) — after
  validation, bootstrap prompts to install SKILL.md as a skill into each
  detected coding agent. Idempotent, `--no-skill` flag to skip.
- **`scripts/install-skill.sh`** — install ANY skill into all detected
  coding agents. Supports `--name=`, `--source=`, `--dry-run`.
- **`helpers/skills.sh`** — install/uninstall helpers for each agent tool.
- **SKILL.md redesigned** — operational companion with interactive menu
  (6 options + context-only default).
- **Non-root warning** — bootstrap warns when not running as root (v1.1.6).

### Changed

- **GLM model rate limits** — `glm-5`, `glm-5.1`, `glm-5.2` now all use
  100 RPM and 1M TPM (was 30 RPM / 500K TPM). (v1.1.1)
- **README slimmed** (292 → 107 lines) — details moved to INSTALLATION.md.
- **INSTALLATION.md expanded** — per-tool usage, monitoring, remote access,
  services table, coding tools table, companion skill table.
- **Pipeline extended** — 01 → 02 → 03a-03d → 04 → 05 (companion skill).
- **macOS/BSD portability** — replaced `grep -oP`/`grep -qP` with
  portable `sed`/`grep -E` equivalents. (v1.1.4)

### Fixed

- **bun install fails without unzip** — auto-installs `unzip` before
  running bun installer. (v1.1.5)
- **Uninstall skill scoping** — `uninstall.sh --tool=claude` no longer
  removes companion skill from other agents. (v1.1.3)
- **Key-mint stdout pollution** — diagnostics redirected to stderr,
  restoring key-on-stdout contract. (v1.1.3)
- **Helper output consistency** — `keys.sh`/`prereqs.sh` switched from
  raw `echo` to `log_*` functions. (v1.1.1)
- **Standalone mode unbound variable** — `version_compare` crash when
  `PROJECT_VERSION="unknown"`. (v1.1.0)
- **Claude skill path** — legacy `~/.claude/commands/` → `~/.claude/skills/`.
- **curl|bash argument passing** — `bash --` → `bash -s --` in README.

## [1.0.0] - 2026-07-06

First stable release.

### Added

- **`VERSION` file** — bootstrap reads and displays version in banner and
  summary. Existing-install detection compares local vs installed version.
- **`scripts/uninstall.sh`** — customizable uninstall: remove single agent,
  subset, all configs, Docker stack, or everything. Supports `--tool=`,
  `--docker`, `--repo`, `--all`, `--dry-run`, `--yes`, interactive menu.
- **MaaS API key validation at prompt time** — invalid keys trigger
  warning and re-prompt instead of failing later.
- **`is_interactive()`** — checks `/dev/tty` (not stdin) so prompts work
  under `curl | bash`.
- **`run_with_spinner()`** — animated spinner for long operations.
- **`log_desc` / `log_done`** — cyan info line before each step, green dim
  completion line after.
- **Prereq explanations** — each prerequisite shows a reason explaining
  what it is and why it's needed.
- **`refresh_path()`** — adds `~/.opencode/bin`, `~/.bun/bin`,
  `~/.local/bin`, nvm, pi-node paths after install.
- **Fresh install option** — existing install detection offers pull updates
  vs fresh install (uninstall + reclone). Default: pull updates.
- **Port conflict handling** — detects and stops stale containers on
  required ports.
- **`flock` locking** via `.bootstrap.lock` to prevent concurrent corruption.
- **AGENTS.md CLI UX Standards** — documented interactive prompt standards,
  output formatting, menu design, summary sections.

### Changed

- **`log_step`** — bold green box-drawing header (`┌── Title ──┐`).
- **`mint_or_reuse_key`** — deletes existing key by `key_id` before minting.
- **Docker compose down** in uninstall runs directly with fallback `docker rm -f`.

### Fixed

- `strip_jsonc` was non-functional — Python read `sys.argv[1]` but file
  was passed via stdin. Fixed to `sys.stdin.read()`.
- Invalid MaaS API key accepted at install time — pre-flight check now
  hard-fails on HTTP 401/403.
- `curl` calls in `prereqs.sh` had no timeout — added `--max-time 60/120`.
- `grep -c ... || echo "0"` produced `"0\n0"` on zero matches.
- `04_validate.sh`: extracted helpers to eliminate duplication.
- `LOG_TAG="system"` for prereq installs (was leaking into filtered output).
- Docker prompt default changed to `y` (was `n`, blocking non-interactive).

## [0.6.0] - 2026-07-02

### Added

- **Pi coding agent support** (`scripts/03d_pi.sh`) — install, virtual key
  minting, config generation. Bootstrap menu option 6, `--tool=pi` flag.
- Validation Section F: pi binary, config, provider, and smoke test checks.
- **`BIND_ADDRESS` env var** for remote access (default `127.0.0.1`).

### Changed

- **Tool scripts renumbered** to group under step 03 with letter suffixes
  (`03a_opencode.sh`, `03b_codex.sh`, `03c_claude_code.sh`, `03d_pi.sh`).
  Adding a new tool is now `03e_*.sh` — no renumbering needed.

### Fixed

- Pi model field mapping: `contextWindow` uses `max_tokens`, `maxTokens`
  uses `max_output`.
- Stale script references in docs updated for new names.

## [0.5.0] - 2026-07-02

Major refactor: interactive-first thin-sequencer model.

### Changed

- **Install pipeline refactored** — bootstrap is now a thin orchestrator;
  installation is interactive by default for both humans and agents.
- **Scripts renamed** to numbered domain-owned names (`01_env.sh`,
  `02_litellm.sh`, etc.). `scripts/lib/` → `scripts/helpers/`.
- Every step self-sources `.env` and is independently runnable.
- **curl|bash is now the default install and upgrade method.** Bootstrap
  detects existing repo and pulls updates, or clones fresh.
- **SKILL.md rewritten** as agent supervisor+wrapper procedure (105 lines).
- `05_claude_code.sh` merges existing `~/.claude/settings.json` instead
  of destructively overwriting.
- `helpers/keys.sh` uses free `/v1/models` probe instead of paid inference
  for virtual key validation.

### Added

- **`INSTALLATION.md`** — canonical install reference.
- **`helpers/keys.sh`** — `resolve_master_key` + `mint_or_reuse_key`.
- **`helpers/common.sh`** — `source_env`, `retry_curl`, `strip_jsonc`,
  `mask_key`, logging, prompts, `run_filtered`.
- **`helpers/models.sh`** — `MODELS` array, single source of truth.
- All scripts reject unknown flags with error.

### Removed

- `--agent` flag and all fail-fast/non-interactive branches.
- `3_mint_key.sh` (folded into `helpers/keys.sh`).

## [0.4.0] - 2026-06-29

### Added

- **Claude Code CLI integration** (`4c_install_claude_code.sh`) — installs
  CLI, mints virtual key, writes `~/.claude/settings.json`, disables VSCode
  extension auto-install.
- **Huawei MaaS Anthropic-compatible endpoint** — dual-format deployments:
  OpenAI (`openai/` prefix) + Anthropic (`anthropic/` prefix) for all models.
- **Distributed prerequisite installation** — each script installs its own
  prereqs via `scripts/lib/prereqs.sh`. Scripts are independently runnable.
- **Tool selection menu** in bootstrap — interactive 6-option menu with
  `--tool=all|litellm|opencode|codex|claude` for non-interactive selection.
- `configs/claude-code/.env.template` — reference for Claude Code config.
- Validation Section E: Claude Code CLI checks.

### Changed

- **SKILL.md restructured** — 825 → 372 lines. 10 steps → 8 steps in 4
  phases.
- **README.md rewritten** — human-first comprehensive page with architecture
  diagram, Quick Start, install modes.

### Removed

- Prometheus alerting rules (`alerts.yml`) — no Alertmanager configured.
- 7-day baseline lines from Grafana dashboard panels.

## [0.1.0] - 2026-06-26

Initial release plus early iterations (v0.2.0–v0.3.0: Prometheus/Grafana
observability stack, Codex CLI integration).

### Added

- Deterministic install procedure (`SKILL.md`) with preconditions, actions,
  postconditions, and recovery actions.
- One-click agent install prompt in `README.md`.
- `--litellm-only`, `--agent`, `--dry-run` modes.
- 6 Huawei MaaS models: `glm-5.2`, `glm-5.1`, `glm-5`, `deepseek-v4-pro`,
  `deepseek-v4-flash`, `deepseek-v3.2`.
- 4 presets (LiteLLM/Huawei-MaaS × Full/Core).
- 3-councillor council system (alpha/beta/gamma).
- Virtual key auto-minting with idempotent reuse.
- Multi-key load balancing (`HUAWEI_MAAS_API_KEY_0..N`).
- Comprehensive validation: 54 checks (full) / 14 (litellm-only).
- Idempotent installation — safe to re-run.
- `REFERENCE.md` with architecture, endpoints, preset/model mapping, repair guide.
- **Prometheus + Grafana observability stack** (v0.2.0) — 12-panel dashboard,
  recording rules, `PROMETHEUS_RETENTION` env var, `GRAFANA_ADMIN_PASSWORD`
  auto-generation, validation Section C (6 observability checks).
- **Codex CLI integration** (v0.3.0) — `3b_install_codex.sh`, model catalog,
  custom `litellm_proxy` provider with `wire_api = "responses"` (HTTP SSE).

### Fixed

- `set -e` traps in install/validate scripts — command substitutions could
  trigger `set -e` before error handlers, causing silent script death.
- Key rotation warning now shows even when validation fails.
- Grafana datasource UID mismatch, subquery syntax, dashboard variable
  filters (v0.2.0).
- Codex CLI WebSocket transport avoided — LiteLLM v1.89.3 WebSocket bug
  workaround with HTTP SSE (v0.3.0).

### Known Limitations

- **Linux only** — no macOS or Windows support.
- **Requires Docker + Docker Compose v2** — not bundled.
- **Requires a Huawei MaaS API key** (ap-southeast-1 region).
- **Inference smoke test requires a valid MaaS key**.
