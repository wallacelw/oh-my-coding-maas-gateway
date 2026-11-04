# Vendored: drawio skill

This directory vendors the official draw.io agent skill from the
[jgraph/drawio-mcp](https://github.com/jgraph/drawio-mcp) repository so the
installer can drop it into each coding agent without a network fetch at
install time.

## Provenance

- **Source repository:** `jgraph/drawio-mcp` (https://github.com/jgraph/drawio-mcp)
- **Vendored date:** 2026-11-03
- **drawio-mcp era:** the `@drawio/mcp` npm package pinned by this repo is
  `1.10.1`; these files were taken from the matching upstream tree.
- **License:** Apache-2.0 (the `@drawio/mcp` npm package declares
  `"license": "Apache-2.0"`; the upstream `jgraph/drawio-mcp` repo is
  Apache-2.0). The vendored skill files themselves carry no separate license
  header — they fall under the upstream repo's Apache-2.0 license.

## Files vendored

| File | Upstream path | Notes |
|------|---------------|-------|
| `SKILL.md` | `skills/drawio/SKILL.md` | Byte-identical copy. |
| `scripts/find-shapes.js` | `skills/drawio/scripts/find-shapes.js` | Byte-identical copy. |

Both files are copied **unmodified**. Do not edit them here; re-vendor instead.

## Egress audit — `scripts/find-shapes.js`

The vendored shape-lookup helper talks to exactly **three** endpoints:

1. `https://app.diagrams.net/` — base URL used only to rewrite relative
   `image=img/lib/...` style references into absolute URLs inside generated
   diagram styles. No user data is sent.
2. `https://cdn.jsdelivr.net/gh/jgraph/drawio-mcp@main/shape-search/search-index.json`
   — **inbound** download of the shape-search index. No user data is sent.
3. `https://icons.diagrams.net/api/icons/search?p=0&c=3&q=` — an **outbound**
   icon-name query. Only the shape/icon **query terms** are sent (no user data,
   no document content). This call is avoidable by not using shape search.

No diagram content, file contents, project data, or credentials are ever
transmitted by this skill. Everything the skill produces stays local; the only
network traffic is the read-only lookups above.

## Updating

To refresh the vendored copy:

1. Pull the matching files from the upstream `jgraph/drawio-mcp` repo at the
   version that lines up with `DRAWIO_MCP_VERSION` (in
   `scripts/helpers/versions.sh`).
2. Replace `skills/drawio/SKILL.md` and `skills/drawio/scripts/find-shapes.js`
   with the upstream copies, **keeping them unmodified**.
3. Re-run the egress audit above and update this file if the endpoint set
   changes.
4. Commit the refreshed files.
