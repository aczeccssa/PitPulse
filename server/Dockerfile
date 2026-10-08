FROM rust:1.94-slim AS build
WORKDIR /src
RUN apt-get update \
 && apt-get install -y --no-install-recommends pkg-config libssl-dev \
 && rm -rf /var/lib/apt/lists/*
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY tests ./tests
RUN cargo build --release

FROM debian:trixie-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --uid 10001 pitpulse
COPY --from=build /src/target/release/pitpulse-server /usr/local/bin/pitpulse-server
USER pitpulse
WORKDIR /var/lib/pitpulse
EXPOSE 38701
ENTRYPOINT ["/usr/local/bin/pitpulse-server"]
ENV F1_COMPANION_BIND=0.0.0.0:38701
ENV F1_COMPANION_DATABASE_PATH=/var/lib/pitpulse/pitpulse.sqlite
