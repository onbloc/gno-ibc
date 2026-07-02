# Stage 1: Build gnoland binary
FROM golang:1.25-alpine AS builder

ARG GNO_COMMIT=a929d44ee4169288d25b80b4e974ed7343050ac9

RUN apk add --no-cache git make gcc musl-dev

# Clone gno at pinned commit
RUN git clone https://github.com/gnolang/gno.git /gno && \
    cd /gno && \
    git checkout ${GNO_COMMIT}

# Build gnoland
WORKDIR /gno
RUN go build -o /usr/local/bin/gnoland ./gno.land/cmd/gnoland

# Stage 2: Runtime
FROM alpine:3.19

RUN apk add --no-cache ca-certificates bash

COPY --from=builder /usr/local/bin/gnoland /usr/local/bin/gnoland
COPY --from=builder /gno /gno
EXPOSE 26656 26657 26660

ENTRYPOINT ["gnoland"]
