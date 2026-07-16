FROM golang:1.26.0-alpine AS builder

RUN apk add --no-cache git make
COPY .gno-version /tmp/gno-version
RUN set -eu; . /tmp/gno-version; \
    test -n "$GNO_REPO"; test -n "$GNO_COMMIT"; \
    git clone --filter=blob:none "$GNO_REPO" /src/gno; \
    git -C /src/gno checkout "$GNO_COMMIT"
WORKDIR /src/gno
RUN cd contribs/gnodev && go build -o /usr/local/bin/gnodev .
RUN cd gno.land/cmd/gnokey && go build -o /usr/local/bin/gnokey .
RUN cd gnovm/cmd/gno && go build -o /usr/local/bin/gno .
COPY e2e/union/gno/testdata/raw-key-address/main.go /tmp/raw-key-address.go
RUN go build -o /usr/local/bin/raw-key-address /tmp/raw-key-address.go
RUN rm -rf /src/gno/.git

FROM alpine:3.21

RUN apk add --no-cache bash curl

COPY --from=builder /usr/local/bin/gnodev /usr/local/bin/gnodev
COPY --from=builder /usr/local/bin/gnokey /usr/local/bin/gnokey
COPY --from=builder /usr/local/bin/gno /usr/local/bin/gno
COPY --from=builder /usr/local/bin/raw-key-address /usr/local/bin/raw-key-address
COPY --from=builder /src/gno /gnoroot

COPY gno.land /gno-ibc/gno.land
COPY e2e/union/gno/entrypoint.sh /entrypoint.sh

ENV GNOROOT=/gnoroot

RUN chmod +x /entrypoint.sh

EXPOSE 26657 8888

ENTRYPOINT ["/entrypoint.sh"]
