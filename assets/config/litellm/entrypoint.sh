#!/usr/bin/env bash
set -e

# ─── LiteLLM entrypoint with OpenLit auto-instrumentation ───
#
# This script installs the OpenLit Python SDK and wraps LiteLLM's
# startup with `openlit-instrument` for zero-code auto-instrumentation.
#
# OpenLit SDK auto-instruments LiteLLM's internal calls and produces
# rich OTel traces with GenAI semantic conventions that the OpenLit
# dashboard needs: ITL, TTFT, TPOT, cost per token, etc.
#
# Without this, LiteLLM's built-in "otel" callback only produces
# generic OpenTelemetry spans that the OpenLit dashboard cannot render.

echo "[entrypoint] Installing OpenLit SDK for auto-instrumentation..."
pip install -q openlit 2>/dev/null || {
  echo "[entrypoint] WARNING: Failed to install openlit. Falling back to LiteLLM without auto-instrumentation."
  exec python -m litellm "$@"
}

echo "[entrypoint] OpenLit SDK installed. Starting LiteLLM with auto-instrumentation..."

# OpenLit SDK reads these env vars for configuration:
#   OTEL_EXPORTER_OTLP_ENDPOINT  — where to send traces (set in docker-compose.yml)
#   OTEL_SERVICE_NAME            — service name in traces
#   OTEL_DEPLOYMENT_ENVIRONMENT  — environment tag
export OTEL_SERVICE_NAME="${OTEL_SERVICE_NAME:-litellm-proxy}"
export OTEL_DEPLOYMENT_ENVIRONMENT="${OTEL_DEPLOYMENT_ENVIRONMENT:-production}"

# Start LiteLLM with OpenLit zero-code instrumentation
exec openlit-instrument python -m litellm "$@"
