# Build union-voyager in Linux environment
# Build context should be the union-voyager directory
FROM rust:1.83-bookworm AS builder

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

# Build voyager binary
RUN cargo build --release --bin voyager

# Output stage - copy binary to output directory
FROM alpine:3.21
RUN mkdir -p /output
COPY --from=builder /build/target/release/voyager /output/voyager
# Also copy modules/plugins for convenience
RUN mkdir -p /output/modules && mkdir -p /output/plugins
COPY --from=builder /build/target/debug/voyager-state-module-* /output/modules/
COPY --from=builder /build/target/debug/voyager-proof-module-* /output/modules/
COPY --from=builder /build/target/debug/voyager-finality-module-* /output/modules/
COPY --from=builder /build/target/debug/voyager-client-module-* /output/modules/
COPY --from=builder /build/target/debug/voyager-client-bootstrap-module-* /output/modules/
COPY --from=builder /build/target/debug/voyager-event-source-plugin-* /output/plugins/
COPY --from=builder /build/target/debug/voyager-transaction-plugin-* /output/plugins/
COPY --from=builder /build/target/debug/voyager-client-update-plugin-* /output/plugins/
COPY --from=builder /build/target/debug/voyager-plugin-* /output/plugins/
