#!/usr/bin/env bash
# models.sh — Shared model catalog
#
# Single source of truth for the Huawei MaaS model list. Sourced by
# 02_litellm.sh (config generation) and 04_validate.sh (validation).
#
# To add/remove a model: edit this file, then update config.yaml.template,
# opencode.json.template, and model_catalog.json. Update slim.json.template
# only if agents should be assigned the new model.
#
# Format: model_name:tpm:rpm:max_tokens:max_input:max_output:input_cost:output_cost:cache_read_cost:cache_creation_cost
# cache_read_cost: cost per token for cache hit (0 if no cache support)
# cache_creation_cost: cost per token for cache write (0 if no cache support)

MODELS=(
  "glm-5.2:1000000:100:1000000:1000000:128000:0.0000014:0.0000044:0.00000026:0"
  "glm-5.3:1000000:100:1000000:1000000:128000:0.0000014:0.0000044:0.00000026:0"
  "glm-5.1:1000000:100:198000:192000:128000:0.000001078:0.000003774:0.00000027:0"
  "deepseek-v4-pro:30000:3:1000000:1000000:128000:0.000001617:0.000003235:0:0"
  "deepseek-v4-flash:30000:3:1000000:1000000:384000:0.000000135:0.00000027:0:0"
)

MODEL_COUNT=${#MODELS[@]}

# Off-peak pricing (Huawei MaaS Period 2: 21:00-07:59 GMT+8 = 13:00-00:00 UTC, 70% of peak)
# Format: model_name|hours_utc|input_cost|output_cost|cache_read_cost
# Only models with off-peak pricing are listed. Rates are absolute values.
OFF_PEAK_PRICING=(
  "glm-5.2|13:00-00:00|0.00000098|0.00000308|0.000000182"
  "glm-5.1|13:00-00:00|0.000000755|0.000002642|0.000000189"
)
# Total deployments = keys × models × 2 formats (OpenAI + Anthropic)

# Off-peak pricing (Huawei MaaS Period 2: 21:00-07:59 GMT+8 = 13:00-00:00 UTC, 70% of peak)
# Format: model_name|hours_utc|input_cost|output_cost|cache_read_cost
# Only models with off-peak pricing are listed. Rates are absolute values.
OFF_PEAK_PRICING=(
  "glm-5.2|13:00-00:00|0.00000098|0.00000308|0.000000182"
  "glm-5.1|13:00-00:00|0.000000755|0.000002642|0.000000189"
)

# Off-peak pricing (Huawei MaaS Period 2: 21:00-07:59 GMT+8 = 13:00-00:00 UTC, 70% of peak)
# Format: model_name|hours_utc|input_cost|output_cost|cache_read_cost
# Only models with off-peak pricing are listed. Rates are absolute values.
# off_peak_pricing goes in model_info (NOT litellm_params) per LiteLLM docs.
OFF_PEAK_PRICING=(
  "glm-5.2|13:00-00:00|0.00000098|0.00000308|0.000000182"
  "glm-5.1|13:00-00:00|0.000000755|0.000002642|0.000000189"
)
