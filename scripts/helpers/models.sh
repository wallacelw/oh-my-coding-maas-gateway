#!/usr/bin/env bash
# models.sh — Shared model catalog
#
# Single source of truth for the Huawei MaaS model list. Sourced by
# 02_litellm.sh (config generation) and 04_validate.sh (validation).
#
# To add/remove a model: edit this file only.
#
# Format: model_name:tpm:rpm:max_tokens:max_input:max_output:input_cost:output_cost

MODELS=(
  "glm-5.2:198000:100:198000:192000:128000:0.0000014:0.0000044"
  "glm-5.1:500000:30:198000:192000:128000:0.000001078:0.000003774"
  "glm-5:500000:30:198000:192000:64000:0.000000809:0.000002965"
  "deepseek-v4-pro:30000:3:1000000:1000000:128000:0.000001617:0.000003235"
  "deepseek-v4-flash:30000:3:1000000:1000000:128000:0.000000135:0.00000027"
  "deepseek-v3.2:500000:700:160000:128000:32000:0.00000027:0.000000404"
)

MODEL_COUNT=${#MODELS[@]}
# Total deployments = keys × models × 2 formats (OpenAI + Anthropic)
