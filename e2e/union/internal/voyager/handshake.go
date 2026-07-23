package voyager

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
)

// NextConnectionID returns the first unallocated connection ID.
func (r *Runtime) NextConnectionID(ctx context.Context, chain string) (int64, error) {
	return r.nextIBCID(ctx, chain, "connection")
}

// NextChannelID returns the first unallocated channel ID.
func (r *Runtime) NextChannelID(ctx context.Context, chain string) (int64, error) {
	return r.nextIBCID(ctx, chain, "channel")
}

func (r *Runtime) nextIBCID(ctx context.Context, chain, kind string) (int64, error) {
	for id := int64(1); ; id++ {
		var err error
		if kind == "connection" {
			_, err = r.connectionState(ctx, chain, id)
		} else {
			_, err = r.channelState(ctx, chain, id)
		}
		if errors.Is(err, ErrNotFound) {
			return id, nil
		}
		if err != nil {
			return 0, err
		}
	}
}

// ConnectionOperation returns the pinned Voyager connection_open_init payload.
func ConnectionOperation(chain string, client, counterpartyClient int64) json.RawMessage {
	return operation(chain, "connection_open_init", map[string]any{
		"client_id": client, "counterparty_client_id": counterpartyClient,
	})
}

// ChannelOperation returns the pinned Voyager channel_open_init payload.
func ChannelOperation(chain, port, counterpartyPort string, connection int64) json.RawMessage {
	return operation(chain, "channel_open_init", map[string]any{
		"port_id": port, "counterparty_port_id": counterpartyPort,
		"connection_id": connection, "version": config.ChannelVersion,
	})
}

func operation(chain, datagramType string, value map[string]any) json.RawMessage {
	data, _ := json.Marshal(map[string]any{
		"@type": "call",
		"@value": map[string]any{
			"@type": "submit_tx",
			"@value": map[string]any{
				"chain_id": chain,
				"datagrams": []any{map[string]any{
					"ibc_spec_id": "ibc-union",
					"datagram": map[string]any{
						"@type":  datagramType,
						"@value": value,
					},
				}},
			},
		},
	})
	return data
}

// SubmitConnection broadcasts one prepared connection operation.
func (r *Runtime) SubmitConnection(ctx context.Context, operation json.RawMessage) error {
	_, err := r.retryWrite(ctx, "q", "e", string(operation))
	return err
}

// SubmitChannel broadcasts one prepared channel operation.
func (r *Runtime) SubmitChannel(ctx context.Context, operation json.RawMessage) error {
	_, err := r.retryWrite(ctx, "q", "e", string(operation))
	return err
}

// ConnectionPresent resolves an ambiguous submission without another write.
func (r *Runtime) ConnectionPresent(
	ctx context.Context,
	chain string,
	id, client, counterpartyClient int64,
) (bool, error) {
	got, err := r.connectionState(ctx, chain, id)
	if errors.Is(err, ErrNotFound) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if got.Client.value != client || got.CounterpartyClient.value != counterpartyClient {
		return false, fmt.Errorf("connection allocation race: unexpected %s connection %d", chain, id)
	}
	return true, nil
}

// ChannelPresent resolves an ambiguous submission without another write.
func (r *Runtime) ChannelPresent(
	ctx context.Context,
	chain string,
	id, connection int64,
	counterpartyPort, version string,
) (bool, error) {
	got, err := r.channelState(ctx, chain, id)
	if errors.Is(err, ErrNotFound) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if got.Connection.value != connection ||
		!strings.EqualFold(got.Port, counterpartyPort) || got.Version != version {
		return false, fmt.Errorf("channel allocation race: unexpected %s channel %d", chain, id)
	}
	return true, nil
}
