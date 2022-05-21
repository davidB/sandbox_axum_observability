# sandbox_axum_observability <!-- omit in toc -->

!!! WIP !!!

Sandbox I used to experiment [axum] and observability (for target platform), observability via infra (as most as possible). The stack and framework selected:

- [App (Rust http service)](#app-rust-http-service)
  - [Main components for the app](#main-components-for-the-app)
- [Infra](#infra)
  - [Main components for the infra](#main-components-for-the-infra)
  - [Infra setup](#infra-setup)

## App (Rust http service)

The setup of the app (microservice) defined under `/app`. The Goals of the app

- [ ] Use axum, async api,...
- [ ] Delegate collect of metrics, logs,... to the infra as much as possible (eg http status, rps, ...)
- [ ] Try to be a cloud native app, follow 12 factor app recommendation via:
  - [x] Configuration dependent of the platform / stack override via Environment variable (use clap)
  - [x] Health-check via a `GET /health` endpoint
  - [x] Log printed on std output, in json format
  - [ ] Log include trace_id to easily link response, log and trace
- [ ] To simulate a multi-level microservice architecture, the service can call `APP_REMOTE_URL` (to define as it-self in the infra)
- [ ] Provide a endpoint `GET /` that wait a `duration` then call endpoint defined by `APP_REMOTE_URL` with the query parameter `depth` equals to current `depth - 1`
  - [x] `depth`: value between 0 and 10, if undefined a random value will be used.
  - [x] `duration_level_max`: duration in seconds, if undefined a random between 0.0 and 2.0
  - [x] the response of `APP_REMOTE_URL` is returned as wrapped response
  - [x] if `depth` is 0, then it returns the `{ "trace_id": "...."}`
  - [ ] if failure, then it returns the `{ "err_trace_id": "...."}`
- [ ] To simulate error
  - [ ] `GET /health` can failed randomly via configuration `APP_HEALTH_FAILURE_PROBABILITY` (value between `0.0` and `1.0`)
  - [ ] `GET /` can failed randomly via query parameter `failure_probability` (value between `0.0` and `1.0`)

### Main components for the app

- [ ] [tokio-rs/axum: Ergonomic and modular web framework built with Tokio, Tower, and Hyper](https://github.com/tokio-rs/axum) as rust web framework.
- [ ] [tokio-rs/tracing: Application level tracing for Rust.](https://github.com/tokio-rs/tracing) (and also for log)
- [ ] [OpenTelemetry](https://opentelemetry.io/)

## Infra

The setup of the infrastructure (cluster) defined under `/infra`.

- Try to be more like a target / live environment, so use distributed solution and a S3 backend (minio). So require more resources on local than using "local dev approach"
- Setup of grafana and tempo is based on [tempo/example/helm at main · grafana/tempo](https://github.com/grafana/tempo/tree/main/example/helm), in distributed mode (consume more resources, aka several pods) and setup to use minio as S3 store. To be more like a target environment
- no ingress or api gateway setup, access will be via port forward

### Main components for the infra

- [x] [Grafana | Grafana Labs](https://grafana.com/oss/grafana/) for dashboard and integration of log, trace, metrics
- [x] [Grafana Tempo | Grafana Labs](https://grafana.com/oss/tempo/) to store trace
- [ ] [Grafana Loki | Grafana Labs](https://grafana.com/oss/loki/) to store log
- [ ] [Prometheus - Monitoring system & time series database](https://prometheus.io/) to store metrics
- [ ] [Linkerd](https://linkerd.io/) a service-mesh but used for its observability feature
- [ ] [Rancher Desktop](https://rancherdesktop.io/) as kubernetes cluster for local test, but I hope the code to easily portable for kind, minikube, k3d, k3s,...

### Infra setup

Require: `kubectl`, `helm` v3

```sh
# after launch of your local (or remote) cluster, configure kubectl to access it as current context
infra/setup.sh install
# use `infra/setup.sh uninstall` to uninstall stuff ;-)
```

Use port forward to access UI and service

```sh
# access grafana UI on http://127.0.0.1:8040
kubectl port-forward -n grafana service/grafana 8040:service

# access minio UI on http://127.0.0.1:8041
kubectl port-forward -n minio service/minio 8041:console
```
