#!/usr/bin/env bash
# models.sh — Shared model catalog
#
# Single source of truth for the Huawei MaaS model list. Sourced by
# 02_litellm.sh (config generation) and 04_validate.sh (validation).
#
# To add/remove a model: edit this file, then update config.yaml.template,
# opencode.json.template, and model_catalog.json. If the model surfaces
# reasoning (reasoning_effort pass-through or thinking mode), add it to
# REASONING_MODELS. If it has off-peak pricing, add it to OFF_PEAK_PRICING.
# If it accepts image input (multimodal), add it to VISION_MODELS and set
# "attachment": true on its opencode.json.template entries. Update
# slim.json.template only if agents should be assigned the new model.
#
# Format: model_name:tpm:rpm:max_tokens:max_input:max_output:input_cost:output_cost:cache_read_cost:cache_creation_cost
# cache_read_cost: cost per token for cache hit (0 if no cache support)
# cache_creation_cost: cost per token for cache write (0 if no cache support)

MODELS=(
  "glm-5.2:1000000:100:1000000:1000000:128000:0.0000014:0.0000044:0.00000026:0"
  "glm-5.3:1000000:100:1000000:1000000:128000:0.0000014:0.0000044:0.00000026:0"
  "glm-5.1:1000000:100:198000:192000:128000:0.000001078:0.000003774:0.00000027:0"
  "deepseek-v4.1-flash:1000000:100:1000000:1000000:384000:0.0000003:0.0000012:0.00000003:0"
)

MODEL_COUNT=${#MODELS[@]}
# Total deployments = keys × models × 2 formats (OpenAI + Anthropic)

# Off-peak pricing (Huawei MaaS Period 2: 21:00-07:59 GMT+8 = 13:00-00:00 UTC;
# 70% of peak for glm models, 50% for deepseek-v4.1-flash)
# Format: model_name|hours_utc|input_cost|output_cost|cache_read_cost
# Only models with off-peak pricing are listed. Rates are absolute values.
# off_peak_pricing goes in model_info (NOT litellm_params) per LiteLLM docs.
OFF_PEAK_PRICING=(
  "glm-5.2|13:00-00:00|0.00000098|0.00000308|0.000000182"
  "glm-5.1|13:00-00:00|0.000000755|0.000002642|0.000000189"
  "deepseek-v4.1-flash|13:00-00:00|0.00000015|0.0000006|0.000000015"
)

# Models that surface reasoning — via reasoning_effort pass-through
# (glm-5.3, glm-5.2) or thinking mode (deepseek-v4.1-flash)
# (glm-5.3: high/low, always thinks; glm-5.2: max/xhigh/high/medium/low/minimal/none;
#  glm-5.1: not supported; deepseek-v4.1-flash: thinking mode, 96K max reasoning len)
REASONING_MODELS=(
  "glm-5.3"
  "glm-5.2"
  "deepseek-v4.1-flash"
)

# Models that accept image input (multimodal)
VISION_MODELS=(
  "deepseek-v4.1-flash"
)

# ── Catalog validation ──
# Verifies cross-array consistency. Call before config generation or validation.
# Returns 0 if valid, 1 with error message on stderr if not.
validate_catalog() {
  local errors=0
  local model_names=()
  for entry in "${MODELS[@]}"; do
    local name="${entry%%:*}"
    model_names+=("$name")
    # Verify 10 fields
    local field_count
    field_count=$(echo "$entry" | tr ':' '\n' | wc -l)
    if [ "$field_count" -ne 10 ]; then
      echo "validate_catalog: $name has $field_count fields (expected 10)" >&2
      errors=$((errors + 1))
    fi
  done

  # Verify OFF_PEAK_PRICING names ⊆ MODELS names and 5-field format
  for entry in "${OFF_PEAK_PRICING[@]}"; do
    local name="${entry%%|*}"
    if ! printf '%s\n' "${model_names[@]}" | grep -qxF "$name"; then
      echo "validate_catalog: OFF_PEAK_PRICING model '$name' not in MODELS" >&2
      errors=$((errors + 1))
    fi
    local op_field_count
    op_field_count=$(echo "$entry" | tr '|' '\n' | wc -l)
    if [ "$op_field_count" -ne 5 ]; then
      echo "validate_catalog: OFF_PEAK_PRICING '$name' has $op_field_count fields (expected 5: name|hours|input|output|cache)" >&2
      errors=$((errors + 1))
    fi
  done

  # Verify REASONING_MODELS names ⊆ MODELS names
  for name in "${REASONING_MODELS[@]}"; do
    if ! printf '%s\n' "${model_names[@]}" | grep -qxF "$name"; then
      echo "validate_catalog: REASONING_MODELS model '$name' not in MODELS" >&2
      errors=$((errors + 1))
    fi
  done

  # Verify VISION_MODELS names ⊆ MODELS names
  for name in "${VISION_MODELS[@]}"; do
    if ! printf '%s\n' "${model_names[@]}" | grep -qxF "$name"; then
      echo "validate_catalog: VISION_MODELS model '$name' not in MODELS" >&2
      errors=$((errors + 1))
    fi
  done

  [ "$errors" -eq 0 ]
}
