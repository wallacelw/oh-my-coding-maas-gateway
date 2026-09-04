#!/usr/bin/env bash
# models.sh — Shared model catalog
#
# Single source of truth for the Huawei MaaS model list. Sourced by
# 02_litellm.sh (config generation) and 04_validate.sh (validation).
#
# To add/remove a model: edit this file, then update config.yaml.template,
# opencode.json.template, model_catalog.json, and slim.json.template.
#
# Format: model_name:tpm:rpm:max_tokens:max_input:max_output:input_cost:output_cost:cache_read_cost:cache_creation_cost
# cache_read_cost: cost per token for cache hit (0 if no cache support)
# cache_creation_cost: cost per token for cache write (0 if no cache support)

MODELS=(
  "glm-5.2:1000000:100:198000:192000:128000:0.0000014:0.0000044:0.00000026:0"
  "glm-5.1:1000000:100:198000:192000:128000:0.000001078:0.000003774:0.00000027:0"
  "deepseek-v4-pro:30000:3:1000000:1000000:128000:0.000001617:0.000003235:0:0"
  "deepseek-v4-flash:60000:15:1000000:1000000:128000:0.000000135:0.00000027:0:0"
)

MODEL_COUNT=${#MODELS[@]}
# Total deployments = keys × models × 2 formats (OpenAI + Anthropic)
