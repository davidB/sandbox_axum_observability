use axum::extract::{Path, Query};
use axum::http::Method;
use axum::Extension;
use axum::{response::IntoResponse, routing::get, Router};
use axum_tracing_opentelemetry::{
    find_current_trace_id, init_tracer, make_resource, opentelemetry_tracing_layer, CollectorKind,
};
use clap::{ArgEnum, Parser};
use rand::prelude::*;
use reqwest_middleware::ClientBuilder;
use reqwest_tracing::TracingMiddleware;
use serde::Deserialize;
use serde_json::json;
use std::net::SocketAddr;
use std::time::Duration;
use tower_http::cors::{Any, CorsLayer};
use tracing::{error, info, trace, warn};

#[derive(Parser, Debug)]
#[clap(
    version, author = env!("CARGO_PKG_HOMEPAGE"), about,
)]
pub struct Settings {
    /// Listening port of http server
    #[clap(long, env("APP_PORT"), default_value("8080"))]
    pub port: u16,
    /// Listening host of http server
    #[clap(long, env("APP_HOST"), default_value("0.0.0.0"))]
    pub host: String,
    /// Minimal log level (same syntax than RUST_LOG)
    #[clap(long, env("APP_LOG_LEVEL"), default_value("info"))]
    pub log_level: String,
    #[clap(long, env("APP_REMOTE_URL"))]
    pub remote_url: Option<String>,
    // #[clap(long, env("APP_TRACING_COLLECTOR_URL"))]
    // pub tracing_collector_url: Option<String>,
    #[clap(
        long,
        env("APP_TRACING_COLLECTOR_KIND"),
        default_value("otlp"),
        arg_enum
    )]
    pub tracing_collector_kind: MyCollectorKind,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, ArgEnum)]
pub enum MyCollectorKind {
    Otlp,
    Jaeger,
    // Stdout,
}

impl From<MyCollectorKind> for CollectorKind {
    fn from(v: MyCollectorKind) -> Self {
        match v {
            MyCollectorKind::Otlp => Self::Otlp,
            MyCollectorKind::Jaeger => Self::Jaeger,
        }
    }
}

fn init_tracing(log_level: String, _tracing_collector_kind: CollectorKind) {
    use tracing_subscriber::filter::EnvFilter;
    // use tracing_subscriber::fmt::format::FmtSpan;
    use tracing_subscriber::layer::SubscriberExt;

    // std::env::set_var("RUST_LOG", "info,kube=trace");
    std::env::set_var("RUST_LOG", std::env::var("RUST_LOG").unwrap_or(log_level));

    // let otel_tracer = init_tracer(tracing_collector_kind).expect("setup of Tracer");
    let otel_tracer = init_tracer(
        CollectorKind::Otlp,
        make_resource(env!("CARGO_PKG_NAME"), env!("CARGO_PKG_VERSION")),
    )
    .expect("setup of Tracer");
    let otel_layer = tracing_opentelemetry::layer().with_tracer(otel_tracer);

    let fmt_layer = tracing_subscriber::fmt::layer()
        .json()
        .with_timer(tracing_subscriber::fmt::time::uptime())
        //.with_span_events(FmtSpan::NEW | FmtSpan::CLOSE)
        // .with_filter(EnvFilter::from_default_env())
        ;

    // Build a subscriber that combines the access log and stdout log
    // layers.
    let subscriber = tracing_subscriber::registry()
        .with(fmt_layer)
        // .with(access_log)
        .with(EnvFilter::from_default_env())
        .with(otel_layer);
    tracing::subscriber::set_global_default(subscriber).unwrap();
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let settings = Settings::parse();
    init_tracing(settings.log_level, settings.tracing_collector_kind.into());
    let remote_url = settings
        .remote_url
        .unwrap_or_else(|| format!("http://{}:{}/", settings.host, settings.port));
    let app = app(&remote_url);
    // run it
    let addr = format!("{}:{}", settings.host, settings.port).parse::<SocketAddr>()?;
    tracing::warn!("listening on {}", addr);
    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    Ok(())
}

fn app(remote_url: &str) -> Router {
    let simulation_settings = SimulationSettings {
        remote_url: remote_url.to_string(),
    };
    // build our application with a route
    Router::new()
        .route("/depth/:depth", get(simulation_depth))
        .route("/", get(simulation))
        .layer(Extension(simulation_settings))
        .layer(
            // see https://docs.rs/tower-http/latest/tower_http/cors/index.html
            // for more details
            CorsLayer::new()
                .allow_methods(vec![Method::GET, Method::POST])
                // allow requests from any origin
                .allow_origin(Any),
        )
        .layer(opentelemetry_tracing_layer())
        // route below are not managed/monitored
        .route("/health", get(health))
}

async fn health() -> impl IntoResponse {
    axum::Json(json!({ "status" : "UP" }))
}

async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c()
            .await
            .expect("failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("failed to install signal handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }

    tracing::warn!("signal received, starting graceful shutdown");
    opentelemetry::global::shutdown_tracer_provider();
}

#[derive(Debug, Deserialize, Clone)]
#[allow(dead_code)]
struct SimulationParams {
    duration_level_max: Option<f32>,
    depth: Option<u8>,
}

#[derive(Debug, Clone)]
struct SimulationSettings {
    remote_url: String,
}

//TODO handle error
async fn simulation(
    params: Option<Query<SimulationParams>>,
    settings: Extension<SimulationSettings>,
) -> impl IntoResponse {
    let mut rng: StdRng = SeedableRng::from_entropy();
    let depth = rng.gen_range(0..=10);
    simulation_depth(Path(depth), params, settings).await
}

async fn simulation_depth(
    Path(depth): Path<i32>,
    params: Option<Query<SimulationParams>>,
    settings: Extension<SimulationSettings>,
) -> impl IntoResponse {
    let duration_level_max = params
        .clone()
        .and_then(|o| o.duration_level_max)
        .unwrap_or(2.0_f32);
    let depth = depth.min(10).max(0);

    sample_log();
    fake_job(duration_level_max).await;

    let resp_body = if depth > 0 {
        let url = format!(
            "{}depth/{}?duration={}",
            settings.remote_url,
            depth - 1,
            duration_level_max,
        );
        let resp = call_remote_app(&url).await.expect("json response for get");
        json!({ "depth": depth, "response": resp })
    } else {
        let trace_id = find_current_trace_id();
        json!({ "simulation" :  "DONE", "trace_id": trace_id})
    };
    axum::Json(resp_body)
}

#[tracing::instrument]
async fn fake_job(duration_level_max: f32) {
    let mut rng: StdRng = SeedableRng::from_entropy();
    let duration = Duration::from_secs_f32(rng.gen_range(0.0_f32..=duration_level_max));
    info!(duration=?duration, "sample log (info) with a value line");
    tokio::time::sleep(duration).await
}

fn sample_log() {
    trace!(value = "foo", "sample log (trace) with a value line");
    info!(value = "bar", "sample log (info) with a value line");
    warn!(value = "toto", "sample log (warn) with a value line");
    error!(value = ":-(", "sample log (error) with a value line");
}

async fn call_remote_app(url: &str) -> Result<serde_json::Value, reqwest::Error> {
    // TracingMiddleware create a span on request
    let client = ClientBuilder::new(reqwest::Client::new())
        .with(TracingMiddleware)
        .build();

    let response = client.get(url).send().await.expect("to receive a response");
    response.json::<serde_json::Value>().await
}

#[cfg(test)]
mod tests {
    // see https://github.com/tokio-rs/axum/blob/main/examples/testing/src/main.rs
    use super::*;
    use assert2::{assert, check};
    use axum::{
        body::Body,
        http::{Request, StatusCode},
    };
    use serde_json::{json, Value};
    use std::net::{SocketAddr, TcpListener};
    use tower::ServiceExt; // for `app.oneshot()`

    #[tokio::test]
    async fn health() {
        let app = app("");

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/health")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        check!(response.status() == StatusCode::OK);

        let body = hyper::body::to_bytes(response.into_body()).await.unwrap();
        let body: Value = serde_json::from_slice(&body).unwrap();
        check!(body == json!({ "status": "UP" }));
    }

    #[tokio::test]
    async fn not_found() {
        let app = app("");

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/does-not-exist")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert!(response.status() == StatusCode::NOT_FOUND);
        let body = hyper::body::to_bytes(response.into_body()).await.unwrap();
        assert!(body.is_empty());
    }

    #[tokio::test]
    async fn simulation_with_duration() {
        let listener = TcpListener::bind("0.0.0.0:0".parse::<SocketAddr>().unwrap()).unwrap();
        let addr = listener.local_addr().unwrap();
        let remote_url = format!("http://{}", addr);
        dbg!(&remote_url);
        tokio::spawn(async move {
            axum::Server::from_tcp(listener)
                .unwrap()
                .serve(app(&remote_url).into_make_service())
                .await
                .unwrap();
        });

        let client = hyper::Client::new();

        let response = client
            .request(
                Request::builder()
                    .uri(format!("http://{}/depth/1?duration_level_max=0.01", &addr))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        check!(response.status() == StatusCode::OK);
        let body = hyper::body::to_bytes(response.into_body()).await.unwrap();
        let body: Value = serde_json::from_slice(&body).unwrap();
        check!(body == json!({ "depth": 1, "response": { "simulation": "DONE" }}));
    }
}
