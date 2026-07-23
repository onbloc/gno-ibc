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
	submit := false
	if r.current.Connections == nil {
		if !r.options.Apply {
			return fmt.Errorf("saved state has no connection IDs; verification-only resume will not broadcast")
		}
		gnoID, err := r.voyager.NextConnectionID(ctx, r.cfg.GnoChainID)
		if err != nil {
			return err
		}
		evmID, err := r.voyager.NextConnectionID(ctx, r.cfg.EVMChainID)
		if err != nil {
			return err
		}
		r.current.Connections = &state.HandshakeIDs{Gno: gnoID, EVM: evmID}
		r.current.Phase = state.PhaseConnectionSubmitting
		if err := state.Save(r.cfg.StateFile, r.current); err != nil {
			return err
		}
		if !r.options.Resume {
			if err := state.RemoveBootstrap(r.bootstrapFile()); err != nil {
				return err
			}
		}
		submit = true
	}

	operation := voyager.ConnectionOperation(
		r.cfg.EVMChainID, r.current.Clients.EVMGno, r.current.Clients.GnoEVM,
	)

	if r.current.Phase == state.PhaseConnectionSubmitting ||
		r.current.Phase == state.Phase("connection-prepared") {
		if submit {
			if err := r.voyager.SubmitConnection(ctx, operation); err != nil {
				return err
			}
		} else {
			gno, err := r.voyager.ConnectionPresent(
				ctx, r.cfg.GnoChainID, r.current.Connections.Gno,
				r.current.Clients.GnoEVM, r.current.Clients.EVMGno,
			)
			if err != nil {
				return err
			}
			evm, err := r.voyager.ConnectionPresent(
				ctx, r.cfg.EVMChainID, r.current.Connections.EVM,
				r.current.Clients.EVMGno, r.current.Clients.GnoEVM,
			)
			if err != nil {
				return err
			}
			if !gno && !evm {
				return fmt.Errorf("connection submission is ambiguous; refusing to enqueue it again")
			}
		}

		r.current.Phase = state.PhaseConnectionSubmitted
		if err := state.Save(r.cfg.StateFile, r.current); err != nil {
			return err
		}
	}
	return r.verifyOpenConnections(ctx)
}

func (r *Runner) establishChannel(ctx context.Context) error {
	submit := false
	if r.current.Channels == nil {
		if !r.options.Apply {
			return fmt.Errorf("saved state has no channel IDs; verification-only resume will not broadcast")
		}
		gnoID, err := r.voyager.NextChannelID(ctx, r.cfg.GnoChainID)
		if err != nil {
			return err
		}
		evmID, err := r.voyager.NextChannelID(ctx, r.cfg.EVMChainID)
		if err != nil {
			return err
		}
		r.current.Channels = &state.HandshakeIDs{Gno: gnoID, EVM: evmID}
		r.current.Phase = state.PhaseChannelSubmitting
		if err := state.Save(r.cfg.StateFile, r.current); err != nil {
			return err
		}
		submit = true
	}
	gnoPort := "0x" + hex.EncodeToString([]byte(r.cfg.GnoZKGMPort))
	operation := voyager.ChannelOperation(
		r.cfg.GnoChainID, gnoPort, strings.ToLower(r.cfg.EVMZKGMContract), r.current.Connections.Gno,
	)
	if r.current.Phase == state.PhaseChannelSubmitting ||
		r.current.Phase == state.Phase("channel-prepared") {
		if submit {
			if err := r.voyager.SubmitChannel(ctx, operation); err != nil {
				return err
			}
		} else {
			gno, err := r.voyager.ChannelPresent(
				ctx, r.cfg.GnoChainID, r.current.Channels.Gno, r.current.Connections.Gno,
				r.cfg.EVMZKGMContract, config.ChannelVersion,
			)
			if err != nil {
				return err
			}
			evm, err := r.voyager.ChannelPresent(
				ctx, r.cfg.EVMChainID, r.current.Channels.EVM, r.current.Connections.EVM,
				gnoPort, config.ChannelVersion,
			)
			if err != nil {
				return err
			}
			if !gno && !evm {
				return fmt.Errorf("channel submission is ambiguous; refusing to enqueue it again")
			}
		}
		r.current.Phase = state.PhaseChannelSubmitted
		if err := state.Save(r.cfg.StateFile, r.current); err != nil {
			return err
		}
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

	return nil
}
