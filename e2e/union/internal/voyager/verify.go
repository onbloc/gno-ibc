package voyager

import (
	"context"
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

// VerifyConnection checks one open connection edge.
func (r *Runtime) VerifyConnection(ctx context.Context, want ConnectionExpectation) error {
	return r.untilVisible(ctx, fmt.Sprintf("%s connection %d", want.Chain, want.ID), func(ctx context.Context) error {
		return r.verifyConnection(ctx, want)
	})
}

func (r *Runtime) verifyConnection(ctx context.Context, want ConnectionExpectation) error {
	got, err := r.connectionState(ctx, want.Chain, want.ID)
	if err != nil {
		return fmt.Errorf("verify %s connection %d: %w", want.Chain, want.ID, err)
	}
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

// VerifyChannel checks one open channel edge.
func (r *Runtime) VerifyChannel(ctx context.Context, want ChannelExpectation) error {
	return r.untilVisible(ctx, fmt.Sprintf("%s channel %d", want.Chain, want.ID), func(ctx context.Context) error {
		return r.verifyChannel(ctx, want)
	})
}

func (r *Runtime) verifyChannel(ctx context.Context, want ChannelExpectation) error {
	got, err := r.channelState(ctx, want.Chain, want.ID)
	if err != nil {
		return fmt.Errorf("verify %s channel %d: %w", want.Chain, want.ID, err)
	}
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
