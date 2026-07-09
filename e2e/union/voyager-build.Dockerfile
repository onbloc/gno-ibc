# Build union-voyager in Linux environment
# Build context should be the union-voyager directory
# Rust 1.90 stable avoids nightly-only regressions in transitive crates.
FROM rust:1.90-bookworm AS builder
ENV RUSTC_BOOTSTRAP=1

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    clang \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

# Copy source (build context is union-voyager root)
COPY . .

# Build only binaries used by e2e/union/voyager-config.gno-union.jsonc.
RUN cargo build --release -j1 \
    -p voyager \
    -p voyager-state-module-cosmwasm \
    -p voyager-state-module-gno \
    -p voyager-proof-module-cosmwasm \
    -p voyager-proof-module-gno \
    -p voyager-finality-module-cometbls \
    -p voyager-finality-module-gno \
    -p voyager-client-module-cometbls \
    -p voyager-client-module-gno \
    -p voyager-client-bootstrap-module-cometbls \
    -p voyager-client-bootstrap-module-gno \
    -p voyager-event-source-plugin-cosmwasm \
    -p voyager-event-source-plugin-gno \
    -p voyager-transaction-plugin-cosmos \
    -p voyager-transaction-plugin-gno \
    -p voyager-plugin-transaction-batch \
    -p voyager-client-update-plugin-cometbls \
    -p voyager-client-update-plugin-gno \
    -p voyager-plugin-packet-timeout

# Output stage - use debian for glibc compatibility
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /output/modules /output/plugins

COPY --from=builder /build/target/release/voyager /output/voyager
COPY --from=builder /build/target/release/voyager-state-module-* /output/modules/
COPY --from=builder /build/target/release/voyager-proof-module-* /output/modules/
COPY --from=builder /build/target/release/voyager-finality-module-* /output/modules/
COPY --from=builder /build/target/release/voyager-client-module-* /output/modules/
COPY --from=builder /build/target/release/voyager-client-bootstrap-module-* /output/modules/
COPY --from=builder /build/target/release/voyager-event-source-plugin-* /output/plugins/
COPY --from=builder /build/target/release/voyager-transaction-plugin-* /output/plugins/
COPY --from=builder /build/target/release/voyager-client-update-plugin-* /output/plugins/
COPY --from=builder /build/target/release/voyager-plugin-* /output/plugins/
# Create release directory with symlinks for voyager
RUN mkdir -p /output/release && \
    for f in /output/modules/* /output/plugins/*; do \
        ln -sf "../$(basename "$f")" /output/release/; \
    done
