#!/usr/bin/env python3
"""Capture Grafana dashboard screenshots for visual verification.

Invoked by scripts/07_dashboard_shots.sh. All configuration arrives via
environment variables so no secret ever appears in a process argument:

  GRAFANA_SHOTS_URL        Grafana base URL (default http://127.0.0.1:3000)
  GRAFANA_SHOTS_UID        Dashboard UID to capture (required)
  GRAFANA_SHOTS_OUT        Output directory for the PNGs (required)
  GRAFANA_ADMIN_PASSWORD   Grafana admin password, from .env (required)

Two Grafana quirks this works around:
  1. Cookie auth: Grafana 302-redirects browsers to /login instead of
     issuing a 401 challenge, so HTTP basic-auth credentials never
     engage. We login via the API and inject the grafana_session cookie.
  2. Inner scroll container: the dashboard scrolls inside a nested div,
     so body.scrollHeight is just the viewport. We measure the tallest
     element, resize the viewport to the full dashboard height (which
     also triggers lazy panel rendering), then capture.

Output: full.png (entire dashboard) plus band-NN.png (1100px vertical
bands sized for vision-model inspection) in GRAFANA_SHOTS_OUT. The
directory is forced to 0700 and every PNG to 0600 — the images replicate
the authenticated dashboard (spend, usage, error detail). Exits non-zero
with a debug.png if the dashboard fails to render.
"""
import http.cookiejar
import json
import os
import pathlib
import urllib.error
import urllib.request

from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeoutError

BASE = os.environ.get("GRAFANA_SHOTS_URL", "http://127.0.0.1:3000").rstrip("/")
UID = os.environ.get("GRAFANA_SHOTS_UID", "")
OUT_RAW = os.environ.get("GRAFANA_SHOTS_OUT", "")
PASSWORD = os.environ.get("GRAFANA_ADMIN_PASSWORD", "")

if not UID:
    raise SystemExit("GRAFANA_SHOTS_UID not set")
if not OUT_RAW:
    # Guard the raw env var: pathlib.Path("") resolves to ".", which is
    # truthy and would make the cleanup below delete PNGs in the CWD.
    raise SystemExit("GRAFANA_SHOTS_OUT not set")
if not PASSWORD:
    raise SystemExit("GRAFANA_ADMIN_PASSWORD not set (load .env first)")

OUT = pathlib.Path(OUT_RAW)
if OUT.exists() and not OUT.is_dir():
    raise SystemExit(
        f"refusing to write: {OUT} is a regular file — "
        "pass a directory path in GRAFANA_SHOTS_OUT"
    )
OUT.mkdir(parents=True, exist_ok=True)
# The PNGs replicate the authenticated dashboard (spend, usage, error
# detail) — protect them like 06_backup.sh protects its DB dumps. On a
# sticky /tmp another user can pre-create the output dir and read every
# capture, so verify ownership before writing anything.
if OUT.stat().st_uid != os.geteuid():
    raise SystemExit(
        f"refusing to write: {OUT} is owned by another user — "
        "they could read the captures; pick a different --out directory"
    )
# mkdir's mode argument is umask-masked and ignored when the directory
# already exists, so set the owner-only mode explicitly.
os.chmod(OUT, 0o700)
# Clean only this tool's own artifacts — never every PNG in the directory.
for pattern in ("full.png", "debug.png", "band-*.png"):
    for old in OUT.glob(pattern):
        old.unlink()


def save_shot(page, path, **kwargs):
    """Capture a screenshot, then lock the file to owner-only (0600)."""
    page.screenshot(path=str(path), **kwargs)
    os.chmod(path, 0o600)

DASH = f"{BASE}/d/{UID}/{UID}?kiosk"

# 1) Login via API to obtain the session cookie.
jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
req = urllib.request.Request(
    f"{BASE}/login",
    data=json.dumps({"user": "admin", "password": PASSWORD}).encode(),
    headers={"Content-Type": "application/json"},
)
try:
    with opener.open(req, timeout=15) as resp:
        print("login:", resp.read().decode()[:80])
except urllib.error.HTTPError as e:
    raise SystemExit(
        f"Grafana login failed (HTTP {e.code}) — check GRAFANA_ADMIN_PASSWORD in .env"
    )
except urllib.error.URLError as e:
    raise SystemExit(
        f"Grafana not reachable at {BASE} — is the stack running? ({e.reason})"
    )
# Plain dicts are accepted by add_cookies at runtime; the TypedDict
# export name differs across playwright versions, so no typed import.
cookies = [{"name": c.name, "value": c.value, "url": BASE} for c in jar]
if not any(c["name"] == "grafana_session" for c in cookies):
    raise SystemExit("login did not yield grafana_session cookie")

# Tallest element wins: finds the dashboard's inner scroll container
# regardless of Grafana's version-specific class names.
MEASURE_HEIGHT = """() => {
    let h = document.body.scrollHeight;
    for (const el of document.querySelectorAll('*')) {
        if (el.scrollHeight > h) h = el.scrollHeight;
    }
    return h;
}"""

# Coupled to the current dashboard's size: the 44-panel layout renders
# ~4,400px tall, far above this gate, while a blank or login page stays
# near the 1050px viewport. A future compact redesign under 2000px would
# fail this gate despite a healthy dashboard — lower the constant
# alongside such a redesign.
MIN_RENDERED_HEIGHT = 2000

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    # close() must run on every exit path — the debug.png SystemExit below
    # and any mid-capture exception would otherwise leak the chromium process.
    try:
        ctx = browser.new_context(viewport={"width": 1680, "height": 1050})
        ctx.add_cookies(cookies)  # type: ignore
        page = ctx.new_page()
        failed = []
        page.on("requestfailed", lambda r: failed.append(f"{r.failure} {r.url[:120]}"))
        errors = []
        page.on(
            "console",
            lambda m: errors.append(m.text[:150]) if m.type == "error" else None,
        )

        rendered = False
        for attempt in (1, 2):
            failed.clear()
            errors.clear()
            try:
                page.goto(DASH, wait_until="domcontentloaded", timeout=60000)
            except PlaywrightTimeoutError:
                # A timed-out load consumes the retry like a bad load does;
                # only a timeout on the final attempt aborts the capture.
                if attempt == 2:
                    raise SystemExit(
                        f"page load timed out after 60000ms — Grafana dashboard at "
                        f"{DASH} did not finish loading; is the stack healthy?"
                    )
                print("  page load timed out — retrying...")
                continue
            page.wait_for_timeout(8000)
            height = page.evaluate(MEASURE_HEIGHT)
            on_login = "/login" in page.url
            print(
                f"attempt {attempt}: url={page.url} "
                f"height={height} failed_reqs={len(failed)}"
            )
            if not on_login and height > MIN_RENDERED_HEIGHT:
                rendered = True
                break
            print("  retrying after a bad load...")

        if not rendered:
            print("PANEL CONTENT MISSING - dumping failed requests and console errors")
            for f in failed[:15]:
                print("  req:", f)
            for e in errors[:15]:
                print("  console:", e)
            save_shot(page, OUT / "debug.png")
            raise SystemExit("dashboard did not render panel content")

        # 2) Tall viewport so every panel is in view (lazy render), then settle.
        full_height = height + 40
        if full_height > 12000:
            print("note: render height clamped at the 12000px cap — capture is truncated")
        height = min(full_height, 12000)
        page.set_viewport_size({"width": 1680, "height": height})
        page.wait_for_timeout(12000)

        # 3) Capture: full image plus fixed-height bands for detailed inspection.
        save_shot(page, OUT / "full.png")
        band = 1100
        y = 0
        i = 1
        while y < height:
            save_shot(
                page,
                OUT / f"band-{i:02d}.png",
                clip={"x": 0, "y": y, "width": 1680, "height": min(band, height - y)},
            )
            y += band
            i += 1
        print(f"SAVED: full.png ({height}px tall) + {i - 1} bands in {OUT}")
        if failed:
            print(f"note: {len(failed)} failed requests during capture (first 5):")
            for f in failed[:5]:
                print("  ", f)
    finally:
        browser.close()
