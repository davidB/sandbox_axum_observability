default:
  just --list

k8s_create:
  # k3d cluster create "$CLUSTER_NAME" --agents 2
  kind create cluster --name "$CLUSTER_NAME" --config infra/kubernetes/config.yaml
  kubectl cluster-info --context kind-"$CLUSTER_NAME"

k8s_setup:
  # namespace "app" should exits before behind instrumented by opentelemetry-operator
  kubectl create namespace "app" || true
  helmfile sync -f infra/kubernetes/helmfile.yaml

k8s_delete:
  # k3d cluster delete "$CLUSTER_NAME"
  kind delete cluster --name "$CLUSTER_NAME"

k8s_portforward_grafana:
  echo "access grafana on http://localhost:8040"
  kubectl port-forward -n "grafana" service/"grafana" 8040:80

k8s_portforward_app:
  echo "access app on http://localhost:8080"
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
    -t localhost:5001/app:latest \
    -f "app/deploy/Dockerfile" \
    "app"
  # docker push localhost:5001/app:latest
  kind load docker-image app:latest --name "$CLUSTER_NAME"

# required
# - app_build_image: to have an image into the registry
# - k8s_create + k8s_setup: to have a k8s cluster to deploy into
app_deploy:
  helm upgrade --install \
    --wait \
    --create-namespace \
    --namespace "app" \
    --values "app/deploy/chart/values.yaml" \
    --values "app/deploy/chart/values_image.yaml" \
    "app" \
    "app/deploy/chart"

app_call_load:
  # Ramp VUs from 0 to 30 over 10s, stay there for 60s, then 10s down to 0.
  k6 run  -u 0 -s 10s:30 -s 60s:30 -s 10s:0 "app/deploy/load.k6.js"

app_call_sample:
  curl -i "http://localhost:8080/depth/2"
