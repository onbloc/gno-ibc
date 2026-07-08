FROM golang:1.26.0-alpine AS builder

ARG GNO_REPO
ARG GNO_COMMIT

RUN apk add --no-cache git make
RUN git clone --filter=blob:none "$GNO_REPO" /src/gno
WORKDIR /src/gno
RUN git checkout "$GNO_COMMIT"
RUN cd contribs/gnodev && go build -o /usr/local/bin/gnodev .
RUN cd gno.land/cmd/gnokey && go build -o /usr/local/bin/gnokey .
RUN cd gnovm/cmd/gno && go build -o /usr/local/bin/gno .

FROM alpine:3.21

RUN apk add --no-cache bash curl

COPY --from=builder /usr/local/bin/gnodev /usr/local/bin/gnodev
COPY --from=builder /usr/local/bin/gnokey /usr/local/bin/gnokey
COPY --from=builder /usr/local/bin/gno /usr/local/bin/gno
COPY --from=builder /src/gno /gnoroot

COPY gno.land /gno-ibc/gno.land
COPY e2e/union/gno/entrypoint.sh /entrypoint.sh

ENV GNOROOT=/gnoroot

RUN chmod +x /entrypoint.sh

EXPOSE 26657 8888

ENTRYPOINT ["/entrypoint.sh"]
