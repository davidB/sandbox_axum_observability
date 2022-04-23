# sandbox_axum_observability

!!! WIP !!!

Sandbox I used to experiment [axum] and observability, observability via infra (as most as possible). The stack and framework selected:

- [ ] [tokio-rs/axum: Ergonomic and modular web framework built with Tokio, Tower, and Hyper](https://github.com/tokio-rs/axum) as rust web framework.
- [ ] [tokio-rs/tracing: Application level tracing for Rust.](https://github.com/tokio-rs/tracing) (and also for log)
- [ ] [OpenTelemetry](https://opentelemetry.io/)
- [ ] [Grafana | Grafana Labs](https://grafana.com/oss/grafana/) for dashboard and integration of log, trace, metrics
- [ ] [Grafana Tempo | Grafana Labs](https://grafana.com/oss/tempo/) to store trace
- [ ] [Grafana Loki | Grafana Labs](https://grafana.com/oss/loki/) to store log
- [ ] [Prometheus - Monitoring system & time series database](https://prometheus.io/) to store metrics
- [ ] [Linkerd](https://linkerd.io/) a service-mesh but used for its observability feature
- [ ] [Rancher Desktop](https://rancherdesktop.io/) as kubernetes cluster for local test, but I hope the code to easyly portable for kind, minikube, k3d, k3s,...
