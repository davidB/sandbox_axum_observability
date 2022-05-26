use opentelemetry::global;
use opentelemetry::sdk::propagation::TraceContextPropagator;
use opentelemetry::sdk::trace as sdktrace;
use opentelemetry::{sdk::Resource, trace::TraceError};
use opentelemetry_lib as opentelemetry;

#[derive(Clone, Copy, Debug, PartialEq, Eq, clap::ArgEnum)]
pub enum CollectorKind {
    Otlp,
    Jaeger,
    // Stdout,
}

pub fn init_tracer(kind: CollectorKind) -> Result<sdktrace::Tracer, TraceError> {
    // use opentelemetry_otlp::WithExportConfig;
    use opentelemetry_semantic_conventions as semcov;
    let resource = Resource::new(vec![
        semcov::resource::SERVICE_NAME.string(env!("CARGO_PKG_NAME")), //TODO Replace with the name of your application
        semcov::resource::SERVICE_VERSION.string(env!("CARGO_PKG_VERSION")), //TODO Replace with the version of your application
    ]);

    match kind {
        CollectorKind::Otlp => {
            // if let Some(url) = std::env::var_os("OTEL_COLLECTOR_URL")
            // "http://localhost:14499/otlp/v1/traces"
            // let collector_url = url.to_str().ok_or(TraceError::Other(
            //     anyhow!("failed to parse OTEL_COLLECTOR_URL").into(),
            // ))?;
            init_tracer_otlp(resource)
        }
        CollectorKind::Jaeger => {
            // Or "OTEL_EXPORTER_JAEGER_ENDPOINT"
            // or now variable
            init_tracer_jaeger(resource)
        } // _ => {
          //     //sdktrace::stdout::new_pipeline().install_simple()
          //     Err(TraceError::Other(anyhow!("no config found").into()))
          // }
    }
}

pub fn init_tracer_otlp(resource: Resource) -> Result<sdktrace::Tracer, TraceError> {
    global::set_text_map_propagator(TraceContextPropagator::new());

    // resource = resource.merge(&read_dt_metadata());

    opentelemetry_otlp::new_pipeline()
        .tracing()
        //endpoint (default = 0.0.0.0:4317 for grpc protocol, 0.0.0.0:4318 http protocol):
        .with_exporter(
            opentelemetry_otlp::new_exporter().tonic(), //.http().with_endpoint(collector_url),
        )
        .with_trace_config(
            sdktrace::config()
                .with_resource(resource)
                .with_sampler(sdktrace::Sampler::AlwaysOn),
        )
        .install_batch(opentelemetry::runtime::Tokio)
}

// https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/sdk-environment-variables.md#jaeger-exporter
pub fn init_tracer_jaeger(resource: Resource) -> Result<sdktrace::Tracer, TraceError> {
    opentelemetry::global::set_text_map_propagator(
        opentelemetry::sdk::propagation::TraceContextPropagator::new(),
    );

    opentelemetry_jaeger::new_pipeline()
        .with_service_name(env!("CARGO_PKG_NAME"))
        .with_trace_config(
            sdktrace::config()
                .with_resource(resource)
                .with_sampler(sdktrace::Sampler::AlwaysOn),
        )
        .install_batch(opentelemetry::runtime::Tokio)
}

pub fn find_trace_id() -> Option<String> {
    use opentelemetry::trace::TraceContextExt;
    use tracing_opentelemetry::OpenTelemetrySpanExt;
    // let context = opentelemetry::Context::current();
    // OpenTelemetry Context is propagation inside code is done via tracing crate
    let context = tracing::Span::current().context();
    let span = context.span();
    let span_context = span.span_context();
    span_context
        .is_valid()
        .then(|| span_context.trace_id().to_string())
}

// #[cfg(test)]
// mod tests {
//     use opentelemetry::{
//         trace::{FutureExt, Span, SpanBuilder, TraceContextExt, TraceId, Tracer},
//         Context,
//     };

//     use super::*;

//     #[tokio::test]
//     async fn try_to_create_context_with_trace_id() {
//         // let parent_context = opentelemetry::global::get_text_map_propagator(|propagator| {
//         //     //propagator.extract(&HeaderCarrier::new(req.headers_mut()))
//         //     propagator.
//         // });
//         // // // let conn_info = req.connection_info();
//         // let uri = req.uri();
//         // let mut builder = self
//         //     .tracer
//         //     .span_builder(uri.path().to_string())
//         //     .with_kind(SpanKind::Server);
//         let _ = init_tracer(CollectorKind::Otlp);
//         // use opentelemetry_semantic_conventions as semcov;
//         // let resource = Resource::new(vec![
//         //     // semcov::resource::SERVICE_NAME.string(env!("CARGO_PKG_NAME")), //TODO Replace with the name of your application
//         //     // semcov::resource::SERVICE_VERSION.string(env!("CARGO_PKG_VERSION")), //TODO Replace with the version of your application
//         // ]);
//         // let _ = init_tracer_otlp(resource);

//         let tracer = global::tracer("");
//         tracer.in_span("operation", |cx| {
//             dbg!(cx.span().span_context().trace_id());
//         });
//         let cx = Context::new(); //.with_value(ValueA("a"));
//                                  //tracer.with_context(cx);
//                                  //let cx = Context::current();
//         let span = tracer.build_with_context(SpanBuilder::from_name("hello"), &cx);
//         // Values can be queried by type
//         // assert_eq!(cx.get::<String>(), Some("hello".to_string()));
//         dbg!(cx.get::<TraceId>());
//         dbg!(cx.span().span_context().trace_id());
//         dbg!(span.span_context().trace_id());
//         // dbg!(span
//         //     .span_context()
//         //     .context()
//         //     .span()
//         //     .span_context()
//         //     .trace_id());
//         assert_eq!(true, true);
//     }
// }
