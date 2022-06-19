#!/bin/bash

set -euo pipefail
# set -x # output command for debug

function cmd() {
  echo "$@"
  "$@"
}

function install_raw() {
  local CLUSTER_NAME=$1
  local FOLDER_NAME=$2
  cmd kubectl apply -f "${DIR}/${FOLDER_NAME}"
}

function uninstall_raw() {
  local CLUSTER_NAME=$1
  local FOLDER_NAME=$2
  cmd kubectl delete -f "${DIR}/${FOLDER_NAME}"
}

function install_kustomize() {
  local CLUSTER_NAME=$1
  local FOLDER_NAME=$2
  # kustomize build "${DIR}/${FOLDER_NAME}/overlays/${CLUSTER_NAME}"
  cmd kubectl kustomize --reorder='none' "${DIR}/${FOLDER_NAME}/overlays/${CLUSTER_NAME}" | kubectl apply -f -
  # kubectl apply -k "${DIR}/${FOLDER_NAME}/overlays/${CLUSTER_NAME}"
}

function uninstall_kustomize() {
  local CLUSTER_NAME=$1
  local FOLDER_NAME=$2
  cmd kubectl delete -k "${DIR}/${FOLDER_NAME}/overlays/${CLUSTER_NAME}"
}

function detect_values_chart() {
  local CLUSTER_NAME=$1
  local CHART_PATH=$2
  local CLUSTER_BASENAME
  CLUSTER_BASENAME=$(cut -d'-' -f1 <<<"$CLUSTER_NAME")
  local array=()
  for filename in "values" "values_${CLUSTER_BASENAME}" "values_${CLUSTER_NAME}"; do
    if [ -f "$CHART_PATH/$filename.yaml" ]; then
      array+=("-f")
      array+=("$CHART_PATH/$filename.yaml")
    fi
    if [ -f "$CHART_PATH/../$filename.yaml" ]; then
      array+=("-f")
      array+=("$CHART_PATH/../$filename.yaml")
    fi
  done
  echo "${array[@]}"
}

function install_chart() {
  local CLUSTER_NAME=$1
  local CHART_NAME=$2
  local CHART_NAMESPACE=${3:-}
  local CHART_INSTALL_NAME="${4:-${CHART_NAME}}"
  local CHART_PATH="${DIR}/${CHART_NAME}"
  local HELM_OPTS=""
  if [ -n "${CHART_NAMESPACE}" ]; then
    HELM_OPTS=("--namespace" "${CHART_NAMESPACE}" "--create-namespace")
  fi
  #shellcheck disable=SC2207
  IFS=" " VALUES=($(detect_values_chart "$CLUSTER_NAME" "$CHART_PATH"))
  # helm install ${HELM_OPTS} --dependency-update -f "values_${CLUSTER_BASENAME}.yaml" -f "values_${CLUSTER_NAME}.yaml" "${CHART_INSTALL_NAME}" .
  # helm dependency update .
  cmd "helm" "upgrade" "--install" "--cleanup-on-fail" "${HELM_OPTS[@]}" "${VALUES[@]}" "$CHART_INSTALL_NAME" "$CHART_PATH"
}

function uninstall_chart() {
  local CLUSTER_NAME=$1
  local CHART_NAME=$2
  local CHART_NAMESPACE=${3:-}
  local CHART_INSTALL_NAME="${CHART_NAME}"
  local HELM_OPTS
  if [ -n "${CHART_NAMESPACE}" ]; then
    HELM_OPTS=("--namespace" "${CHART_NAMESPACE}")
  fi
  cmd "helm" "uninstall" "${CHART_INSTALL_NAME}" "${HELM_OPTS[@]}"
}

function lint_chart() {
  local CLUSTER_NAME=$1
  local CHART_NAME=$2
  local CHART_NAMESPACE=${3:-}
  local CHART_INSTALL_NAME="${CHART_NAME}"
  local CHART_PATH="${DIR}/${CHART_NAME}"

  #shellcheck disable=SC2207
  IFS=" " VALUES=($(detect_values_chart "$CLUSTER_NAME" "$CHART_PATH"))
  cmd "helm" "lint" "$CHART_PATH" "--strict" "${VALUES[@]}"
}

function debug_chart() {
  local CLUSTER_NAME=$1
  local CHART_NAME=$2
  local CHART_NAMESPACE=${3:-}
  local CHART_INSTALL_NAME="${CHART_NAME}"
  local CHART_PATH="${DIR}/${CHART_NAME}"
  local CLUSTER_BASENAME
  CLUSTER_BASENAME=$(cut -d'-' -f1 <<<"$CLUSTER_NAME")
  local HELM_OPTS
  if [ -n "${CHART_NAMESPACE}" ]; then
    HELM_OPTS=("--namespace" "${CHART_NAMESPACE}")
  fi
  #shellcheck disable=SC2207
  IFS=" " VALUES=($(detect_values_chart "$CLUSTER_NAME" "$CHART_PATH"))
  cmd "helm" "template" "${CHART_INSTALL_NAME}" "$CHART_PATH" "${HELM_OPTS[@]}" --debug "${VALUES[@]}"
}

# ------------------------------------------------------------------------------
# -- specific section to this repo

charts() {
  SUB_CMD="${1:-lint}"

  CURRENT_CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[].name}')
  CURRENT_CLUSTER_NAME=$(basename "$CURRENT_CLUSTER_NAME")

  case "$SUB_CMD" in
  "uninstall") ;;
  "install") ;;
  "lint") ;;
  "debug") ;;
  *)
    SUB_CMD="lint"
    ;;
  esac

  # helm repo add grafana https://grafana.github.io/helm-charts
  # helm search repo grafana/ # to list all version available

  "${SUB_CMD}_chart" "${CURRENT_CLUSTER_NAME}" "minio" "minio"
  "${SUB_CMD}_chart" "${CURRENT_CLUSTER_NAME}" "grafana" "grafana"
  "${SUB_CMD}_chart" "${CURRENT_CLUSTER_NAME}" "tempo" "tempo"
}

foo() {
  echo "call foo with args '$1' '$2'"
}

# ------------------------------------------------------------------------------
# -- main

DIR="$(cd "$(dirname "$0")" && pwd)"
"$@"
