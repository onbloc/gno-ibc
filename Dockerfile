# Stage 1: Build gnoland binary
FROM golang:1.24-alpine AS builder

ARG GNO_COMMIT=e16676eec5f75ab563d4ade83e17d4a96ea04aee

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

EXPOSE 26656 26657 26660

ENTRYPOINT ["gnoland"]
