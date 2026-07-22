# syntax=docker/dockerfile:1.7
# Build union-voyager in Linux environment
# Build context should be the union-voyager directory
# Rust 1.90 stable avoids nightly-only regressions in transitive crates.
FROM rust:1.90-bookworm@sha256:3914072ca0c3b8aad871db9169a651ccfce30cf58303e5d6f2db16d1d8a7e58f AS builder
ENV RUSTC_BOOTSTRAP=1
ARG UNION_COMMIT
LABEL org.opencontainers.image.revision=$UNION_COMMIT

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    clang \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

# Copy source from the union-voyager build context.
COPY --from=union-src . .
RUN test -n "$UNION_COMMIT"

# Client IDs are numeric in ibc-union events, while jaq object keys are strings.
# Patch the build copy so client-specific regular and Proof Lens batchers can coexist.
RUN for source in \
      voyager/plugins/transaction-batch/src/lib.rs \
      voyager/plugins/transaction-batch-proof-lens/src/lib.rs; do \
        sed -i 's/has(\$client_id)/has(\$client_id | tostring)/' "$source"; \
        grep -F 'has($client_id | tostring)' "$source"; \
    done

# Build only binaries used by e2e/union/voyager-config.gno-union.jsonc.
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
    -p voyager-client-module-state-lens-ics23-ics23 \
    -p voyager-client-module-state-lens-ics23-mpt \
    -p voyager-client-bootstrap-module-cometbls \
    -p voyager-client-bootstrap-module-gno \
    -p voyager-client-bootstrap-module-proof-lens \
    -p voyager-client-bootstrap-module-trusted-mpt \
    -p voyager-client-bootstrap-module-state-lens-ics23-ics23 \
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
    -p voyager-client-update-plugin-state-lens \
    -p voyager-plugin-packet-timeout && \
    mkdir -p /build/out/modules /build/out/plugins /build/out/release && \
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

# Output stage - use debian for glibc compatibility
FROM debian:bookworm-slim@sha256:7b140f374b289a7c2befc338f42ebe6441b7ea838a042bbd5acbfca6ec875818
ARG UNION_COMMIT
LABEL org.opencontainers.image.revision=$UNION_COMMIT
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /output/modules /output/plugins

COPY --from=builder /build/out/voyager /output/voyager
COPY --from=builder /build/out/modules/ /output/modules/
COPY --from=builder /build/out/plugins/ /output/plugins/
# Create release directory with symlinks for voyager
RUN mkdir -p /output/release && \
    for f in /output/modules/*; do \
        ln -sf "../modules/$(basename "$f")" /output/release/; \
    done && \
    for f in /output/plugins/*; do \
        ln -sf "../plugins/$(basename "$f")" /output/release/; \
    done
