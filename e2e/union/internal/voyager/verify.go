package voyager

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

// ClientExpectation describes one persisted client relation.
type ClientExpectation struct {
	Chain, Counterparty, ClientType, IBCInterface string
	ID                                            int64
}

// LensExpectation describes one persisted Lens relation.
type LensExpectation struct {
	Chain, L2Chain string
	ID, L1, L2     int64
}

// ConnectionExpectation describes one side of an open connection.
type ConnectionExpectation struct {
	Chain                                          string
	ID, Client, CounterpartyClient, CounterpartyID int64
}

// ChannelExpectation describes one side of an open channel.
type ChannelExpectation struct {
	Chain, CounterpartyPort, Version string
	ID, Connection, CounterpartyID   int64
}

// VerifyClient checks the immutable identity and counterparty of a client.
func (r *Runtime) VerifyClient(ctx context.Context, want ClientExpectation) error {
	refreshes := 0
	nextRefresh := time.Now().Add(r.cfg.EVMRefreshInterval)
	return r.untilVisible(ctx, fmt.Sprintf("%s client %d", want.Chain, want.ID), func(ctx context.Context) error {
		err := r.verifyClient(ctx, want)
		if !errors.Is(err, ErrNotFound) || want.Chain != r.cfg.EVMChainID ||
			refreshes == 3 || time.Now().Before(nextRefresh) {
			return err
		}
		if err := r.restart(ctx); err != nil {
			return err
		}
		refreshes++
		nextRefresh = time.Now().Add(r.cfg.EVMRefreshInterval)
		return ErrNotFound
	})
}

func (r *Runtime) verifyClient(ctx context.Context, want ClientExpectation) error {
	info, err := r.clientInfo(ctx, want.Chain, want.ID)
	if err != nil {
		return fmt.Errorf("verify %s client %d: %w", want.Chain, want.ID, err)
	}
	if info.ClientType != want.ClientType || info.IBCInterface != want.IBCInterface {
		return fmt.Errorf("client relation mismatch for %s client %d", want.Chain, want.ID)
	}
	meta, err := r.clientMeta(ctx, want.Chain, want.ID)
	if err != nil {
		return fmt.Errorf("verify %s client %d metadata: %w", want.Chain, want.ID, err)
	}
	if meta.CounterpartyChainID != want.Counterparty {
		return fmt.Errorf("client counterparty mismatch for %s client %d", want.Chain, want.ID)
	}
	status, err := r.clientStatus(ctx, want.Chain, want.ID)
	if err != nil {
		return fmt.Errorf("verify %s client %d status: %w", want.Chain, want.ID, err)
	}
	if status != "active" {
		return fmt.Errorf("%s client %d is %s", want.Chain, want.ID, status)
	}
	return nil
}

// VerifyLens checks both saved client edges in decoded Lens state.
func (r *Runtime) VerifyLens(ctx context.Context, want LensExpectation) error {
	return r.untilVisible(ctx, fmt.Sprintf("%s Lens client %d", want.Chain, want.ID), func(ctx context.Context) error {
		return r.verifyLens(ctx, want)
	})
}

func (r *Runtime) verifyLens(ctx context.Context, want LensExpectation) error {
	got, err := r.lensState(ctx, want.Chain, want.ID)
	if err != nil {
		return fmt.Errorf("verify %s Lens client %d: %w", want.Chain, want.ID, err)
	}
	if got.L1.value != want.L1 || got.L2.value != want.L2 || got.L2Chain != want.L2Chain {
		return fmt.Errorf("Lens relation mismatch for %s client %d", want.Chain, want.ID)
	}
	return nil
}

// ConnectionEvidence verifies and returns one sanitized observed connection.
func (r *Runtime) ConnectionEvidence(ctx context.Context, want ConnectionExpectation) (json.RawMessage, error) {
	var got connectionState
	err := r.untilVisible(ctx, fmt.Sprintf("%s connection %d", want.Chain, want.ID), func(ctx context.Context) error {
		var err error
		got, err = r.connectionState(ctx, want.Chain, want.ID)
		if err != nil {
			return fmt.Errorf("verify %s connection %d: %w", want.Chain, want.ID, err)
		}
		return checkConnection(got, want)
	})
	if err != nil {
		return nil, err
	}
	data, err := json.Marshal(struct {
		State                    string `json:"state"`
		ClientID                 int64  `json:"client_id"`
		CounterpartyClientID     int64  `json:"counterparty_client_id"`
		CounterpartyConnectionID int64  `json:"counterparty_connection_id"`
	}{
		State: got.Status, ClientID: got.Client.value,
		CounterpartyClientID:     got.CounterpartyClient.value,
		CounterpartyConnectionID: got.Counterparty.value,
	})
	return data, err
}

func checkConnection(got connectionState, want ConnectionExpectation) error {
	if got.Client.value != want.Client || got.CounterpartyClient.value != want.CounterpartyClient {
		return fmt.Errorf("connection relation mismatch for %s connection %d", want.Chain, want.ID)
	}
	if !strings.EqualFold(got.Status, "open") {
		return ErrNotFound
	}
	if !got.Counterparty.valid || got.Counterparty.value != want.CounterpartyID {
		return fmt.Errorf("connection relation mismatch for %s connection %d", want.Chain, want.ID)
	}
	return nil
}

// ChannelEvidence verifies and returns one sanitized observed channel.
func (r *Runtime) ChannelEvidence(ctx context.Context, want ChannelExpectation) (json.RawMessage, error) {
	var got channelState
	err := r.untilVisible(ctx, fmt.Sprintf("%s channel %d", want.Chain, want.ID), func(ctx context.Context) error {
		var err error
		got, err = r.channelState(ctx, want.Chain, want.ID)
		if err != nil {
			return fmt.Errorf("verify %s channel %d: %w", want.Chain, want.ID, err)
		}
		return checkChannel(got, want)
	})
	if err != nil {
		return nil, err
	}
	data, err := json.Marshal(struct {
		State                 string `json:"state"`
		ConnectionID          int64  `json:"connection_id"`
		CounterpartyChannelID int64  `json:"counterparty_channel_id"`
		CounterpartyPortID    string `json:"counterparty_port_id"`
		Version               string `json:"version"`
	}{
		State: got.Status, ConnectionID: got.Connection.value,
		CounterpartyChannelID: got.Counterparty.value,
		CounterpartyPortID:    got.Port, Version: got.Version,
	})
	return data, err
}

func checkChannel(got channelState, want ChannelExpectation) error {
	if got.Connection.value != want.Connection ||
		!strings.EqualFold(got.Port, want.CounterpartyPort) || got.Version != want.Version {
		return fmt.Errorf("channel relation mismatch for %s channel %d", want.Chain, want.ID)
	}
	if !strings.EqualFold(got.Status, "open") {
		return ErrNotFound
	}
	if !got.Counterparty.valid || got.Counterparty.value != want.CounterpartyID {
		return fmt.Errorf("channel relation mismatch for %s channel %d", want.Chain, want.ID)
	}
	return nil
}

func (r *Runtime) untilVisible(ctx context.Context, label string, check func(context.Context) error) error {
	waitCtx, cancel := context.WithTimeout(ctx, r.cfg.ScenarioTimeout)
	defer cancel()
	for {
		err := check(waitCtx)
		if err == nil {
			return nil
		}
		if !errors.Is(err, ErrNotFound) {
			return err
		}
		if err := pause(waitCtx, r.cfg.PollInterval); err != nil {
			return fmt.Errorf("%w: %s was not visible", classifyContext(waitCtx, err), label)
		}
	}
}
