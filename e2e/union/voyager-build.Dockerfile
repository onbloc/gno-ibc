# syntax=docker/dockerfile:1.7
FROM rust:1.90-bookworm@sha256:3914072ca0c3b8aad871db9169a651ccfce30cf58303e5d6f2db16d1d8a7e58f AS builder

ENV RUSTC_BOOTSTRAP=1
ARG UNION_COMMIT
LABEL org.opencontainers.image.revision=$UNION_COMMIT

WORKDIR /build
RUN apt-get update && apt-get install -y \
    clang \
    libssl-dev \
    pkg-config \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

COPY . .
RUN test -n "$UNION_COMMIT"

# Build only the binaries referenced by config.jsonc.template.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/build/target \
    cargo build -j1 \
    -p voyager \
    -p voyager-state-module-cosmwasm \
    -p voyager-state-module-gno \
    -p voyager-state-module-evm \
    -p voyager-proof-module-cosmwasm \
    -p voyager-proof-module-gno \
    -p voyager-proof-module-evm-mpt \
    -p voyager-finality-module-cometbls \
    -p voyager-finality-module-gno \
    -p voyager-finality-module-trusted-evm \
    -p voyager-client-module-cometbls \
    -p voyager-client-module-gno \
    -p voyager-client-module-proof-lens \
    -p voyager-client-module-trusted-mpt \
    -p voyager-client-module-state-lens-ics23-mpt \
    -p voyager-client-bootstrap-module-cometbls \
    -p voyager-client-bootstrap-module-gno \
    -p voyager-client-bootstrap-module-proof-lens \
    -p voyager-client-bootstrap-module-trusted-mpt \
    -p voyager-client-bootstrap-module-state-lens-ics23-mpt \
    -p voyager-event-source-plugin-cosmwasm \
    -p voyager-event-source-plugin-gno \
    -p voyager-event-source-plugin-evm \
    -p voyager-transaction-plugin-cosmos \
    -p voyager-transaction-plugin-gno \
    -p voyager-transaction-plugin-evm \
    -p voyager-plugin-transaction-batch \
    -p voyager-plugin-transaction-batch-proof-lens \
    -p voyager-client-update-plugin-cometbls \
    -p voyager-client-update-plugin-gno \
    -p voyager-client-update-plugin-proof-lens \
    -p voyager-client-update-plugin-trusted-mpt \
    -p voyager-client-update-plugin-state-lens && \
    mkdir -p /build/out/modules /build/out/plugins && \
    cp /build/target/debug/voyager /build/out/voyager && \
    cp /build/target/debug/voyager-state-module-* /build/out/modules/ && \
    cp /build/target/debug/voyager-proof-module-* /build/out/modules/ && \
    cp /build/target/debug/voyager-finality-module-* /build/out/modules/ && \
    cp /build/target/debug/voyager-client-module-* /build/out/modules/ && \
    cp /build/target/debug/voyager-client-bootstrap-module-* /build/out/modules/ && \
    cp /build/target/debug/voyager-event-source-plugin-* /build/out/plugins/ && \
    cp /build/target/debug/voyager-transaction-plugin-* /build/out/plugins/ && \
    cp /build/target/debug/voyager-client-update-plugin-* /build/out/plugins/ && \
    cp /build/target/debug/voyager-plugin-* /build/out/plugins/

FROM debian:bookworm-slim@sha256:7b140f374b289a7c2befc338f42ebe6441b7ea838a042bbd5acbfca6ec875818

ARG UNION_COMMIT
LABEL org.opencontainers.image.revision=$UNION_COMMIT
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /output/release

COPY --from=builder /build/out/voyager /output/voyager
COPY --from=builder /build/out/modules/ /output/modules/
COPY --from=builder /build/out/plugins/ /output/plugins/
RUN for file in /output/modules/* /output/plugins/*; do \
      ln -s "$file" "/output/release/$(basename "$file")"; \
    done

ENTRYPOINT ["/output/voyager"]
