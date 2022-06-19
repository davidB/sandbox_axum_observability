# sandbox_axum_observability <!-- omit in toc -->

!!! WIP !!!

Sandbox I used to experiment [axum] and observability (for target platform), observability via infra (as most as possible). The stack and framework selected:

- [App (Rust http service)](#app-rust-http-service)
  - [Main components for the app](#main-components-for-the-app)
  - [Usage on local shell](#usage-on-local-shell)
  - [direct to Jaeger](#direct-to-jaeger)
- [Infra](#infra)
  - [Light infra docker-compose](#light-infra-docker-compose)
  - [Kubernetes](#kubernetes)
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
  - [x] Log include trace_id to easily link response, log and trace
    - [x] on first log of the span, when incoming request has trace_id
    - [x] on following log of the span, when incoming request has trace_id
    - [x] on first log of the span, when incoming request has NO trace_id (imply start an new one)
    - [x] on following log of the span, when incoming request has trace_id
- [x] To simulate a multi-level microservice architecture, the service can call `APP_REMOTE_URL` (to define as it-self in the infra)
- [ ] Provide a endpoint `GET /depth/{:depth}` that wait a `duration` then call endpoint defined by `APP_REMOTE_URL` with the path parameter `depth` equals to current `depth - 1`
  - [x] `depth`: value between 0 and 10, if undefined a random value will be used.
  - [x] `duration_level_max`: duration in seconds, if undefined a random between 0.0 and 2.0
  - [x] the response of `APP_REMOTE_URL` is returned as wrapped response
  - [x] if `depth` is 0, then it returns the `{ "trace_id": "...."}`
  - [ ] if failure, then it returns the `{ "err_trace_id": "...."}`
  - [x] call `GET /` is like calling `GET /depth/{:depth}` with a random depth between 0 and 10
- [ ] To simulate error
  - [ ] `GET /health` can failed randomly via configuration `APP_HEALTH_FAILURE_PROBABILITY` (value between `0.0` and `1.0`)
  - [ ] `GET /depth/{}` can failed randomly via query parameter `failure_probability` (value between `0.0` and `1.0`)
- [ ] add test to validate and to demo feature above

### Main components for the app

- [ ] [tokio-rs/axum: Ergonomic and modular web framework built with Tokio, Tower, and Hyper](https://github.com/tokio-rs/axum) as rust web framework.
- [ ] [tokio-rs/tracing: Application level tracing for Rust.](https://github.com/tokio-rs/tracing) (and also for log)
- [ ] [OpenTelemetry](https://opentelemetry.io/)

### Usage on local shell

Launch the server

```sh
cd app
cargo run
```

Send http request from a curl client

```sh
# without client trace
# FIXME the log on the server include an empty trace_id
❯ curl -i "http://localhost:8080/depth/0"
HTTP/1.1 200 OK
content-type: application/json
content-length: 67
access-control-allow-origin: *
vary: origin
vary: access-control-request-method
vary: access-control-request-headers
date: Sat, 21 May 2022 15:35:32 GMT

{"simulation":"DONE","trace_id":"522e44c536fec8020790c59f20560d1a"}⏎

# with client trace
# for traceparent see [Trace Context](https://www.w3.org/TR/trace-context/#trace-context-http-headers-format)
❯ curl -i "http://localhost:8080/depth/2" -H 'traceparent: 00-0af7651916cd43dd8448eb211c80319c-b9c7c989f97918e1-00'
HTTP/1.1 200 OK
content-type: application/json
content-length: 113
access-control-allow-origin: *
vary: origin
vary: access-control-request-method
vary: access-control-request-headers
date: Sat, 21 May 2022 15:33:54 GMT

{"depth":2,"response":{"depth":1,"response":{"simulation":"DONE","trace_id":"0af7651916cd43dd8448eb211c80319c"}}}⏎
```

on jaeger web ui,  service `example-opentelemetry` should be listed and trace should be like

![trace in jaeger](doc/images/20220521164336.png)

### direct to Jaeger

Launch a local jaeger

```sh
## docker cli can be used instead of nerdctl
## to start jaeger (and auto remove on stop)
nerdctl run --name jaeger --rm -d -p6831:6831/udp -p6832:6832/udp -p16686:16686 jaegertracing/all-in-one:latest

# open web ui
open http://localhost:16686/


# send trace via jaeger protocol to local jaeger (agent)
cargo run -- --tracing-collector-kind jaeger

# to stop jaeger
nerdctl stop jaeger
```

## Infra

### Light infra docker-compose

based on [tempo/example/docker-compose/otel-collector at main · grafana/tempo](https://github.com/grafana/tempo/tree/main/example/docker-compose/otel-collector)

The otel-collector is configured to allow to received oltp, jaeger, zipkin trace and to expose port on localhost

```sh
cd infra/docker-compose

# or docker-compose
nerdctl compose up
```

Launch the server

```sh
# `oltp` is the default collector kind, but should also work with `jaeger`
cargo run
```

Send some curl command

Open your browser to grafana explorer [http://localhost:3000/explore](http://localhost:3000/explore), select `Tempo` datasource (pre-configured),  copy/paste the trace_id from log into search field, click "Run Query"

![](doc/images/20220522173234.png)

### Kubernetes

The setup of the infrastructure (cluster) defined under `/infra`.

- Try to be more like a target / live environment, so use distributed solution and a S3 backend (minio). So require more resources on local than using "local dev approach"
- Setup of grafana and tempo is based on [tempo/example/helm at main · grafana/tempo](https://github.com/grafana/tempo/tree/main/example/helm), in distributed mode (consume more resources, aka several pods) and setup to use minio as S3 store. To be more like a target environment
- no ingress or api gateway setup, access will be via port forward

#### Main components for the infra

- [x] [Grafana | Grafana Labs](https://grafana.com/oss/grafana/) for dashboard and integration of log, trace, metrics
- [x] [Grafana Tempo | Grafana Labs](https://grafana.com/oss/tempo/) to store trace
- [ ] [Grafana Loki | Grafana Labs](https://grafana.com/oss/loki/) to store log
- [ ] [Prometheus - Monitoring system & time series database](https://prometheus.io/) to store metrics
- [ ] [Linkerd](https://linkerd.io/) a service-mesh but used for its observability feature
- [ ] [Rancher Desktop](https://rancherdesktop.io/) as kubernetes cluster for local test, but I hope the code to easily portable for kind, minikube, k3d, k3s,...

#### Infra setup

Require: `kubectl`, `helm` v3

```sh
# after launch of your local (or remote) cluster, configure kubectl to access it as current context
infra/kubernetes/tools.sh charts install
# use `infra/kubernetes/tools.sh charts uninstall` to uninstall stuff ;-)
```

Use port forward to access UI and service

```sh
# access grafana UI on http://127.0.0.1:8040
kubectl port-forward -n grafana service/grafana 8040:service

# access minio UI on http://127.0.0.1:8041
kubectl port-forward -n minio service/minio 8041:console
```
