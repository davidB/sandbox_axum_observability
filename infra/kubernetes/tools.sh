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
  local HELM_OPTS=()
  if [ -n "${CHART_NAMESPACE}" ]; then
    HELM_OPTS=("--namespace" "${CHART_NAMESPACE}" "--create-namespace")
  fi
  #shellcheck disable=SC2207
  IFS=" " VALUES=($(detect_values_chart "$CLUSTER_NAME" "$CHART_PATH"))
  # helm install ${HELM_OPTS} --dependency-update -f "values_${CLUSTER_BASENAME}.yaml" -f "values_${CLUSTER_NAME}.yaml" "${CHART_INSTALL_NAME}" .
  cmd helm dependency update "$CHART_PATH"
  cmd "helm" "upgrade" "$CHART_INSTALL_NAME" "$CHART_PATH" "--install" "--cleanup-on-fail" "${VALUES[@]}" "${HELM_OPTS[@]}"
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

  # helm repo add minio-legacy https://helm.min.io/
  # helm repo add grafana https://grafana.github.io/helm-charts
  # helm search repo grafana/ # to list all version available
  # helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

  "${SUB_CMD}_chart" "${CURRENT_CLUSTER_NAME}" "minio" "minio"
  # "${SUB_CMD}_chart" "${CURRENT_CLUSTER_NAME}" "minio-operator" "minio-operator"
  # "${SUB_CMD}_chart" "${CURRENT_CLUSTER_NAME}" "minio-tenant-1" "minio-tenant-1"
  "${SUB_CMD}_chart" "${CURRENT_CLUSTER_NAME}" "grafana" "grafana"
  "${SUB_CMD}_chart" "${CURRENT_CLUSTER_NAME}" "kube-prometheus-stack" "kube-prometheus-stack"
  "${SUB_CMD}_chart" "${CURRENT_CLUSTER_NAME}" "tempo-distributed" "tempo-distributed"
  "${SUB_CMD}_chart" "${CURRENT_CLUSTER_NAME}" "loki-distributed" "loki-distributed"
  "${SUB_CMD}_chart" "${CURRENT_CLUSTER_NAME}" "promtail" "promtail"
  "${SUB_CMD}_chart" "${CURRENT_CLUSTER_NAME}" "linkerd" "linkerd"
  "${SUB_CMD}_chart" "${CURRENT_CLUSTER_NAME}" "linkerd-viz" "linkerd-viz"

  # kubectl annotate namespace grafana "linkerd.io/inject=enabled" --overwrite
  # kubectl annotate namespace app "linkerd.io/inject=enabled" --overwrite
}

gen_certs() {
  CERT_DIR="${DIR}/linkerd/certs/"
  mkdir -p CERT_DIR || true
  pushd "$CERT_DIR"
  CERT_FILE="${CERT_DIR}/ca.crt"
  CMD=$(command -v step-cli || command -v step)
  if [ ! -f "${CERT_FILE}" ]; then
    echo "-- create tls config ca"
    "$CMD" certificate create root.linkerd.cluster.local ca.crt ca.key \
      --profile root-ca \
      --no-password \
      --not-after 43800h \
      --insecure
  fi
  # shellcheck disable=SC2086
  yq eval -i ".linkerd2.identityTrustAnchorsPEM = \"$(cat ${CERT_FILE})\"" "${DIR}/linkerd/values.yaml"

  CERT_FILE="${DIR}/issuer.crt"
  if [ ! -f "${CERT_FILE}" ]; then
    echo "-- create tls config issuer"
    "$CMD" certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
      --profile intermediate-ca \
      --not-after 8760h \
      --no-password \
      --insecure \
      --ca ca.crt --ca-key ca.key
  fi
  # shellcheck disable=SC2086
  yq eval -i ".linkerd2.identity.issuer.tls.crtPEM = \"$(cat ${CERT_DIR}/issuer.crt)\"" "${DIR}/linkerd/values.yaml"
  # shellcheck disable=SC2086
  yq eval -i ".linkerd2.identity.issuer.tls.keyPEM = \"$(cat ${CERT_DIR}/issuer.key)\"" "${DIR}/linkerd/values.yaml"
}

foo() {
  echo "call foo with args '$1' '$2'"
}

# ------------------------------------------------------------------------------
# -- main

DIR="$(cd "$(dirname "$0")" && pwd)"
"$@"
