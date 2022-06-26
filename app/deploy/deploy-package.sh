#! /usr/bin/env bash
# require
# - helm 3+
# shellcheck shell=bash

set -euo pipefail
# set -x
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"

APP_NAME=${1:-$(basename "${PROJECT_DIR}")}
NAMESPACE=${2:-"$APP_NAME"}
CHART_PATH=${PROJECT_DIR}/deploy/chart

# job
#kubectl config view --minify
helm upgrade --install \
  --wait \
  --create-namespace \
  --namespace "${NAMESPACE}" \
  --values "${CHART_PATH}/values.yaml" \
  --values "${CHART_PATH}/values_image.yaml" \
  "${APP_NAME}" \
  "${CHART_PATH}"
