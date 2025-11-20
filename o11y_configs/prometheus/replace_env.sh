#!/bin/sh
# Environment variable substitution script for Prometheus config
# Usage: ./replace_env.sh input.yml output.yml
#
# NOTE: Prometheus does NOT support environment variable interpolation natively.
# This script performs substitution before Prometheus starts, replacing ${VAR_NAME}
# placeholders with actual environment variable values from docker-compose.
#
# For Kubernetes: Use an init container with envsubst, or better yet, use
# Kubernetes service discovery instead of static targets.
#
# Replaces ${VAR_NAME} with environment variable values
# Works without envsubst dependency

INPUT_FILE="$1"
OUTPUT_FILE="$2"

cp "$INPUT_FILE" "$OUTPUT_FILE"

for var in $(grep -o '\${[A-Za-z0-9_]\+}' "$OUTPUT_FILE" | tr -d '${}' | sort -u); do
  value=$(printenv "$var")
  if [ -n "$value" ]; then
    sed -i "s|\${$var}|$value|g" "$OUTPUT_FILE"
  fi
done
