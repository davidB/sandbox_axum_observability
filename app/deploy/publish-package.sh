#! /usr/bin/env bash
# require
# - `docker` or `nerdctl`
# - `git`
# shellcheck shell=bash

set -euo pipefail
# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"

# input
APP_NAME=${1:-$(basename "${PROJECT_DIR}")}
IMAGE_TAG=${2:-$(git describe --always --dirty)}
IMAGE_REPOSITORY="${APP_NAME}"
IMAGE_FULL_TAG="k8s.io/${IMAGE_REPOSITORY}:${IMAGE_TAG}"

find_image_builder() {
  if [ -x "$(command -v nerdctl)" ]; then
    command -v nerdctl
  elif [ -x "$(command -v docker)" ]; then
    command -v docker
  else
    echo "builder not found: docker or nerdctl"
    exit 1
  fi
}

build_local_image() {
  # Since we want to use the K8s cluster to build and manage images,
  # be sure to use the K8s cluster namespace to store the images by specifying
  # the k8s.io namespace. This is done by providing the providing these args
  # in nerdctl: -n k8s.io
  echo "'${IMAGE_FULL_TAG}' build"
  export DOCKER_BUILDKIT=1
  CMD_BUILDER=$(find_image_builder)
  "$CMD_BUILDER" \
    --namespace k8s.io \
    build \
    --progress=plain \
    --target runtime \
    -t "${IMAGE_FULL_TAG}" \
    -f "${PROJECT_DIR}/deploy/Dockerfile" \
    "${PROJECT_DIR}"
}

show_publication() {
  CMD_BUILDER=$(find_image_builder)
  ("$CMD_BUILDER" --namespace k8s.io images | grep "${IMAGE_REPOSITORY}") ||
    (echo "failed to find image repository" && exit 1)
}

update_values_image() {
  if [ -d "${SCRIPT_DIR}/chart" ]; then
    cat >"${SCRIPT_DIR}/chart/values_image.yaml" <<-EOF
image:
  repository: "${IMAGE_REPOSITORY}"
  tag: "${IMAGE_TAG}"
EOF
  fi
}

output_info_for_github() {
  echo "::set-output name=image_repository::${IMAGE_REPOSITORY}"
  echo "::set-output name=image_tag::${IMAGE_TAG}"
}

build_local_image
show_publication
update_values_image
output_info_for_github
