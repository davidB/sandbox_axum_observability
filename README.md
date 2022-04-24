# sandbox_axum_observability

!!! WIP !!!

Sandbox I used to experiment [axum] and observability (for target platform), observability via infra (as most as possible). The stack and framework selected:

- [ ] [tokio-rs/axum: Ergonomic and modular web framework built with Tokio, Tower, and Hyper](https://github.com/tokio-rs/axum) as rust web framework.
- [ ] [tokio-rs/tracing: Application level tracing for Rust.](https://github.com/tokio-rs/tracing) (and also for log)
- [ ] [OpenTelemetry](https://opentelemetry.io/)
- [x] [Grafana | Grafana Labs](https://grafana.com/oss/grafana/) for dashboard and integration of log, trace, metrics
- [x] [Grafana Tempo | Grafana Labs](https://grafana.com/oss/tempo/) to store trace
- [ ] [Grafana Loki | Grafana Labs](https://grafana.com/oss/loki/) to store log
- [ ] [Prometheus - Monitoring system & time series database](https://prometheus.io/) to store metrics
- [ ] [Linkerd](https://linkerd.io/) a service-mesh but used for its observability feature
- [ ] [Rancher Desktop](https://rancherdesktop.io/) as kubernetes cluster for local test, but I hope the code to easily portable for kind, minikube, k3d, k3s,...

## Infra

- Try to be more like a target / live environment, so use distributed solution and a S3 backend (minio) And use more resources on local than using "local dev approach"
- Setup of grafana and tempo is based on [tempo/example/helm at main · grafana/tempo](https://github.com/grafana/tempo/tree/main/example/helm), in distributed mode (consume more resources, aka several pods) and setup to use minio as S3 store. To be more like a target environment
- no ingress or api gateway setup, access will be via port forward

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
