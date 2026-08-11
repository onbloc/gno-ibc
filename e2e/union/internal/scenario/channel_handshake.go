package scenario

import (
	"context"
	"encoding/hex"
	"fmt"
	"strings"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
	"github.com/onbloc/gno-ibc/e2e/union/internal/voyager"
)

func (r *Runner) establishConnection(ctx context.Context) error {
	if r.current.Connections == nil {
		gnoID, err := r.voyager.NextConnectionID(ctx, r.cfg.GnoChainID)
		if err != nil {
			return err
		}
		evmID, err := r.voyager.NextConnectionID(ctx, r.cfg.EVMChainID)
		if err != nil {
			return err
		}
		r.current.Connections = &state.HandshakeIDs{Gno: gnoID, EVM: evmID}
		if err := r.voyager.SubmitConnection(ctx, voyager.ConnectionOperation(
			r.cfg.EVMChainID, r.current.Clients.EVMGno, r.current.Clients.GnoEVM,
		)); err != nil {
			return err
		}
		r.progressf("connection submitted; waiting for OPEN")
	}
	return r.verifyOpenConnections(ctx)
}

func (r *Runner) establishChannel(ctx context.Context) error {
	if r.current.Channels == nil {
		gnoID, err := r.voyager.NextChannelID(ctx, r.cfg.GnoChainID)
		if err != nil {
			return err
		}
		evmID, err := r.voyager.NextChannelID(ctx, r.cfg.EVMChainID)
		if err != nil {
			return err
		}
		r.current.Channels = &state.HandshakeIDs{Gno: gnoID, EVM: evmID}
		gnoPort := "0x" + hex.EncodeToString([]byte(r.cfg.GnoZKGMPort))
		if err := r.voyager.SubmitChannel(ctx, voyager.ChannelOperation(
			r.cfg.GnoChainID, gnoPort, strings.ToLower(r.cfg.EVMZKGMContract), r.current.Connections.Gno,
		)); err != nil {
			return err
		}
		r.progressf("channel submitted; waiting for OPEN")
	}
	return r.verifyOpenChannels(ctx)
}

func (r *Runner) verifyOpenHandshakes(ctx context.Context) error {
	if r.current.Connections == nil || r.current.Channels == nil {
		return fmt.Errorf("handshake verification requires complete state")
	}
	if err := r.verifyOpenConnections(ctx); err != nil {
		return err
	}
	return r.verifyOpenChannels(ctx)
}

func (r *Runner) verifyOpenConnections(ctx context.Context) error {
	s := &r.current
	if s.Connections == nil {
		return fmt.Errorf("connection verification requires saved IDs")
	}
	checks := []voyager.ConnectionExpectation{
		{Chain: r.cfg.GnoChainID, ID: s.Connections.Gno, Client: s.Clients.GnoEVM, CounterpartyClient: s.Clients.EVMGno, CounterpartyID: s.Connections.EVM},
		{Chain: r.cfg.EVMChainID, ID: s.Connections.EVM, Client: s.Clients.EVMGno, CounterpartyClient: s.Clients.GnoEVM, CounterpartyID: s.Connections.Gno},
	}

	for i, check := range checks {
		evidence, err := r.voyager.ConnectionEvidence(ctx, check)
		if err != nil {
			return err
		}
		if i == 0 {
			r.gnoConnectionEvidence = evidence
		} else {
			r.evmConnectionEvidence = evidence
		}
	}
	r.progressf("connection OPEN: %s/connection-%d/client-%d <-> %s/connection-%d/client-%d",
		r.cfg.GnoChainID, s.Connections.Gno, s.Clients.GnoEVM,
		r.cfg.EVMChainID, s.Connections.EVM, s.Clients.EVMGno)

	return nil
}

func (r *Runner) verifyOpenChannels(ctx context.Context) error {
	s := &r.current
	if s.Connections == nil || s.Channels == nil {
		return fmt.Errorf("channel verification requires saved IDs")
	}

	gnoPort := "0x" + hex.EncodeToString([]byte(r.cfg.GnoZKGMPort))
	checks := []voyager.ChannelExpectation{
		{Chain: r.cfg.GnoChainID, ID: s.Channels.Gno, Connection: s.Connections.Gno, CounterpartyID: s.Channels.EVM, CounterpartyPort: strings.ToLower(r.cfg.EVMZKGMContract), Version: config.ChannelVersion},
		{Chain: r.cfg.EVMChainID, ID: s.Channels.EVM, Connection: s.Connections.EVM, CounterpartyID: s.Channels.Gno, CounterpartyPort: gnoPort, Version: config.ChannelVersion},
	}

	for i, check := range checks {
		evidence, err := r.voyager.ChannelEvidence(ctx, check)
		if err != nil {
			return err
		}
		if i == 0 {
			r.gnoChannelEvidence = evidence
		} else {
			r.evmChannelEvidence = evidence
		}
	}
	r.progressf("channel OPEN: %s/channel-%d/connection-%d <-> %s/channel-%d/connection-%d (%s)",
		r.cfg.GnoChainID, s.Channels.Gno, s.Connections.Gno,
		r.cfg.EVMChainID, s.Channels.EVM, s.Connections.EVM, config.ChannelVersion)
	r.progressf("channel ports: %s/%s <-> %s/%s",
		r.cfg.GnoChainID, r.cfg.GnoZKGMPort,
		r.cfg.EVMChainID, strings.ToLower(r.cfg.EVMZKGMContract))

	return nil
}
