

default:
  just --list

k8s_create:
  # k3d cluster create "$CLUSTER_NAME" --agents 2
  kind create cluster --name "$CLUSTER_NAME" --config infra/kubernetes/config.yaml
  kubectl cluster-info --context kind-"$CLUSTER_NAME"

k8s_setup:
  # namespace should exits before behind instrumented by opentelemetry-operator
  kubectl create namespace "app"
  helmfile sync -f infra/kubernetes/helmfile.yaml

k8s_delete:
  # k3d cluster delete "$CLUSTER_NAME"
  kind delete cluster --name "$CLUSTER_NAME"

k8s_portforward_grafana:
  kubectl port-forward -n "grafana" service/"grafana" 8040:80

k8s_portforward_app:
  kubectl port-forward -n "app" service/"app" 8080:80

app_build_image:
  # cd app && pack build app \
  #   --buildpack docker.io/paketocommunity/rust \
  #   --builder paketobuildpacks/builder:full

  # --namespace k8s.io # to use with rancher-desktop
  docker buildx \
    build \
    --progress=plain \
    --target runtime \
    -t app:latest \
    -f "app/deploy/Dockerfile" \
    "app"
