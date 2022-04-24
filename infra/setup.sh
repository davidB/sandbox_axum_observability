#!/bin/bash

set -euo pipefail
# set -x
DIR="$(cd "$(dirname "$0")" && pwd)"
SUB_CMD="${1:-install}"

function install_raw() {
  local CLUSTER_NAME=$1
  local FOLDER_NAME=$2
  kubectl apply -f "${DIR}/${FOLDER_NAME}"
}

function uninstall_raw() {
  local CLUSTER_NAME=$1
  local FOLDER_NAME=$2
  kubectl delete -f "${DIR}/${FOLDER_NAME}"
}

function install_kustomize() {
  local CLUSTER_NAME=$1
  local FOLDER_NAME=$2
  # kustomize build "${DIR}/${FOLDER_NAME}/overlays/${CLUSTER_NAME}"
  kubectl kustomize --reorder='none' "${DIR}/${FOLDER_NAME}/overlays/${CLUSTER_NAME}" | kubectl apply -f -
  # kubectl apply -k "${DIR}/${FOLDER_NAME}/overlays/${CLUSTER_NAME}"
}

function uninstall_kustomize() {
  local CLUSTER_NAME=$1
  local FOLDER_NAME=$2
  kubectl delete -k "${DIR}/${FOLDER_NAME}/overlays/${CLUSTER_NAME}"
}

function install_chart() {
  local CLUSTER_NAME=$1
  local CHART_NAME=$2
  local CHART_NAMESPACE=${3:-}
  local CHART_INSTALL_NAME="${4:-${CHART_NAME}}"
  local HELM_OPTS=""
  # local CLUSTER_BASENAME
  # CLUSTER_BASENAME=$(cut -d'-' -f1 <<<"$CLUSTER_NAME")
  pushd "${DIR}/${CHART_NAME}" >/dev/null
  if [ -n "${CHART_NAMESPACE}" ]; then
    HELM_OPTS=("--namespace" "${CHART_NAMESPACE}" "--create-namespace")
  fi
  helm dependency update .
  helm upgrade --install "${HELM_OPTS[@]}" --cleanup-on-fail -f "values.yaml" -f "values_${CLUSTER_NAME}.yaml" "${CHART_INSTALL_NAME}" .
  # helm install ${HELM_OPTS} --dependency-update -f "values_${CLUSTER_BASENAME}.yaml" -f "values_${CLUSTER_NAME}.yaml" "${CHART_INSTALL_NAME}" .
  # helm template ${HELM_OPTS} --debug -f "values_${CLUSTER_NAME}.yaml" "${CHART_INSTALL_NAME}" .
  popd >/dev/null
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
  # --kube-context "admin@${CLUSTER_NAME}"
  local CMD=("helm" "uninstall" "${CHART_INSTALL_NAME}" "${HELM_OPTS[@]}")
  echo "${CMD[@]}"
  "${CMD[@]}"
}

CURRENT_CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[].name}')
CURRENT_CLUSTER_NAME=$(basename "$CURRENT_CLUSTER_NAME")
if [ "$CURRENT_CLUSTER_NAME" = "rancher-desktop" ]; then
  CURRENT_CLUSTER_NAME="local"
fi

if [ "$SUB_CMD" != "uninstall" ]; then
  SUB_CMD="install"
fi

helm repo add grafana https://grafana.github.io/helm-charts
# helm search repo grafana/ # to list all version available

"${SUB_CMD}_chart" "${CURRENT_CLUSTER_NAME}" "minio" "minio"
"${SUB_CMD}_chart" "${CURRENT_CLUSTER_NAME}" "grafana" "grafana"
"${SUB_CMD}_chart" "${CURRENT_CLUSTER_NAME}" "tempo" "tempo"
# "${SUB_CMD}_chart" "${CURRENT_CLUSTER_NAME}" "linkerd" "linkerd"
# "${SUB_CMD}_chart" "${CURRENT_CLUSTER_NAME}" "linkerd-viz" "linkerd-viz"
# "${SUB_CMD}_chart" "${CURRENT_CLUSTER_NAME}" "linkerd-jaeger" "linkerd-jaeger"
