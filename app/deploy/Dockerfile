# This dockerfile build executable from source code before create the final image
# - use cargo-chef to cache build of dependencies into docker's layer
# - using this dockerfile into ci, do NOT require to provide the executable
#   (steps could be remove, but more time will be needed)
#
# build with `docker build -t my-app -f Dockerfile .`
# run with `docker run -p 8080:80 -it --rm --env APP_HOST=0.0.0.0 my-app`
# call with `curl -i http://127.0.0.1:8080/health`

FROM lukemathwalker/cargo-chef:latest-rust-1.59.0 AS chef
WORKDIR /workspace

FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS build
COPY --from=planner /workspace/recipe.json recipe.json
# Build dependencies - this is the caching Docker layer!
RUN cargo chef cook --release --recipe-path recipe.json
# Build application
COPY . .
RUN cargo build --release

# We do not need the Rust toolchain to run the binary!

# To have the digest (instead of tag):
# - docker pull gcr.io/distroless/cc:nonroot | grep digest
# - or go to https://console.cloud.google.com/gcr/images/distroless/global/cc and filter by tags
FROM gcr.io/distroless/cc:nonroot AS runtime
WORKDIR /workspace
COPY --from=build /workspace/target/release/example-opentelemetry /app

ENV APP_PORT=8080
EXPOSE $APP_PORT

ENTRYPOINT ["/app"]
