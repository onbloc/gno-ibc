package scenario

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/gno"
	"github.com/onbloc/gno-ibc/e2e/union/internal/voyager"
)

const (
	relayerFundingWei = "1000000000000000000"
)

type relayerPacket struct {
	SendTx, PacketHash string
	FromBlock          uint64
	GnoEvents          gno.PacketEvents
}

func (r *Runner) runRelayerInsufficientBalanceFailover(ctx context.Context) error {
	return r.withPrimaryEVMKey(ctx, r.cfg.RelayerEmptyPrivateKey, func(rendered []byte) error {
		address, err := r.requireEmptyRelayer(ctx, r.cfg.RelayerEmptyPrivateKey)
		if err != nil {
			return err
		}
		r.progressf("scenario relayer-insufficient-balance-failover: primary signer=%s balance_wei=0", address)
		packet, err := r.submitRelayerPacket(ctx)
		if err != nil {
			return err
		}
		if packet.GnoEvents, err = r.gno.WaitPacket(ctx, packet.PacketHash); err != nil {
			return err
		}
		stats, err := r.voyager.WaitActiveQueue(ctx)
		if err != nil {
			return err
		}
		r.progressf("scenario relayer-insufficient-balance-failover: acknowledgement pending active_queue=%d; starting secondary", stats.Total)
		return r.withSecondary(ctx, rendered, func(secondary *voyager.Runtime) error {
			ackTx, err := r.finishRelayerPacket(ctx, secondary, packet)
			if err != nil {
				return err
			}
			secondarySigner, err := r.requireRelayerSigner(ctx, ackTx, r.cfg.EVMPrivateKey)
			if err != nil {
				return err
			}
			r.progressf("scenario relayer-insufficient-balance-failover: secondary acknowledged packet=%s tx=%s", packet.PacketHash, ackTx)
			return r.writeEvidence("relayer-insufficient-balance-failover.json", map[string]any{
				"primary_signer": address, "primary_balance_wei": "0",
				"secondary_signer": secondarySigner,
				"active_queue":     stats, "packet_hash": packet.PacketHash,
				"transactions":        map[string]string{"send": packet.SendTx, "gno_receive": packet.GnoEvents.ReceiveTx, "evm_ack": ackTx},
				"secondary_completed": true,
			})
		})
	})
}

func (r *Runner) runRelayerOfflineFailover(ctx context.Context) error {
	return r.withPrimaryEVMKey(ctx, r.cfg.RelayerOfflinePrivateKey, func(rendered []byte) error {
		address, err := r.requireEmptyRelayer(ctx, r.cfg.RelayerOfflinePrivateKey)
		if err != nil {
			return err
		}
		r.progressf("scenario relayer-offline-failover: stopping primary signer=%s", address)
		if err := r.voyager.Close(ctx); err != nil {
			return err
		}
		packet, err := r.submitRelayerPacket(ctx)
		if err != nil {
			return err
		}
		return r.withSecondary(ctx, rendered, func(secondary *voyager.Runtime) error {
			if packet.GnoEvents, err = r.gno.WaitPacket(ctx, packet.PacketHash); err != nil {
				return err
			}
			ackTx, err := r.finishRelayerPacket(ctx, secondary, packet)
			if err != nil {
				return err
			}
			secondarySigner, err := r.requireRelayerSigner(ctx, ackTx, r.cfg.EVMPrivateKey)
			if err != nil {
				return err
			}
			r.progressf("scenario relayer-offline-failover: secondary relayed packet=%s tx=%s", packet.PacketHash, ackTx)
			return r.writeEvidence("relayer-offline-failover.json", map[string]any{
				"stopped_primary_signer": address, "secondary_signer": secondarySigner,
				"packet_hash":         packet.PacketHash,
				"transactions":        map[string]string{"send": packet.SendTx, "gno_receive": packet.GnoEvents.ReceiveTx, "evm_ack": ackTx},
				"secondary_completed": true,
			})
		})
	})
}

func (r *Runner) runRelayerBalanceRecovery(ctx context.Context) error {
	return r.withPrimaryEVMKey(ctx, r.cfg.RelayerRecoveryPrivateKey, func(_ []byte) error {
		address, err := r.requireEmptyRelayer(ctx, r.cfg.RelayerRecoveryPrivateKey)
		if err != nil {
			return err
		}
		packet, err := r.submitRelayerPacket(ctx)
		if err != nil {
			return err
		}
		if packet.GnoEvents, err = r.gno.WaitPacket(ctx, packet.PacketHash); err != nil {
			return err
		}
		pendingDuration := 2 * r.cfg.EVMRefreshInterval
		if err := r.requireAcknowledgementPending(ctx, packet, pendingDuration); err != nil {
			return err
		}
		stats, err := r.voyager.WaitActiveQueue(ctx)
		if err != nil {
			return err
		}
		r.progressf("scenario relayer-balance-recovery: acknowledgement remained pending for %s active_queue=%d; funding signer=%s amount_wei=%s", pendingDuration, stats.Total, address, relayerFundingWei)
		if err := r.verifyRelayerFailedWork(ctx, r.voyager); err != nil {
			return err
		}
		fundTx, err := r.evm.FundNative(ctx, address, relayerFundingWei)
		if err != nil {
			return err
		}
		ackTx, err := r.finishRelayerPacket(ctx, r.voyager, packet)
		if err != nil {
			return err
		}
		if _, err := r.requireRelayerSigner(ctx, ackTx, r.cfg.RelayerRecoveryPrivateKey); err != nil {
			return err
		}
		balance, err := r.evm.NativeBalance(ctx, address)
		if err != nil {
			return err
		}
		if balance.Sign() <= 0 {
			return fmt.Errorf("funded relayer has no remaining balance")
		}
		r.progressf("scenario relayer-balance-recovery: active retry completed after funding signer=%s tx=%s", address, ackTx)
		return r.writeEvidence("relayer-balance-recovery.json", map[string]any{
			"primary_signer": address, "balance_before_wei": "0", "balance_after_wei": balance.String(),
			"active_queue_before_funding": stats, "packet_hash": packet.PacketHash,
			"transactions":           map[string]string{"send": packet.SendTx, "gno_receive": packet.GnoEvents.ReceiveTx, "fund": fundTx, "evm_ack": ackTx},
			"active_retry_completed": true,
		})
	})
}

func (r *Runner) requireAcknowledgementPending(ctx context.Context, packet relayerPacket, duration time.Duration) error {
	waitCtx, cancel := context.WithTimeout(ctx, duration)
	defer cancel()
	_, err := r.evm.WaitAcknowledgement(waitCtx, packet.FromBlock, r.current.Channels.EVM, packet.PacketHash)
	if err == nil {
		return fmt.Errorf("zero-balance relayer unexpectedly acknowledged packet")
	}
	if !errors.Is(err, context.DeadlineExceeded) {
		return err
	}
	return nil
}

func (r *Runner) withSecondary(ctx context.Context, rendered []byte, run func(*voyager.Runtime) error) (runErr error) {
	secondary := voyager.New(r.cfg, r.progress)
	defer func() {
		cleanupCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), r.cfg.CleanupTimeout)
		defer cancel()
		runErr = errors.Join(runErr, secondary.Close(cleanupCtx))
	}()
	if err := secondary.Start(ctx, rendered); err != nil {
		return err
	}
	r.progressf("relayer scenario: secondary Voyager ready")
	return run(secondary)
}

func (r *Runner) withPrimaryEVMKey(ctx context.Context, privateKey string, run func([]byte) error) (runErr error) {
	base, err := r.renderVoyagerForConfig(r.cfg)
	if err != nil {
		return err
	}
	primaryCfg := r.cfg
	primaryCfg.EVMPrivateKey = privateKey
	primary, err := r.renderVoyagerForConfig(primaryCfg)
	if err != nil {
		return err
	}
	if err := r.voyager.Restart(ctx, primary); err != nil {
		return err
	}
	defer func() {
		restoreCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), r.cfg.ScenarioTimeout+r.cfg.CleanupTimeout)
		defer cancel()
		runErr = errors.Join(runErr, r.voyager.Restart(restoreCtx, base))
	}()
	return run(base)
}

func (r *Runner) renderVoyagerForConfig(cfg config.Config) ([]byte, error) {
	template, err := os.ReadFile(filepath.Join(cfg.ScriptDir, "config.jsonc.template"))
	if err != nil {
		return nil, fmt.Errorf("missing Voyager config template")
	}
	plain, proof, err := r.current.Allowlists.IDs()
	if err != nil {
		return nil, err
	}
	return config.RenderVoyager(template, cfg, plain, proof)
}

func (r *Runner) requireEmptyRelayer(ctx context.Context, privateKey string) (string, error) {
	address, err := r.evm.Address(ctx, privateKey)
	if err != nil {
		return "", err
	}
	balance, err := r.evm.NativeBalance(ctx, address)
	if err != nil {
		return "", err
	}
	if balance.Sign() != 0 {
		return "", fmt.Errorf("relayer fixture %s must start with zero balance; use a fresh disposable EVM chain", address)
	}
	return address, nil
}

func (r *Runner) submitRelayerPacket(ctx context.Context) (relayerPacket, error) {
	plan, err := r.evm.Prepare(ctx, r.current.Channels.Gno)
	if err != nil {
		return relayerPacket{}, err
	}
	if _, err := r.evm.Mint(ctx, plan.Sender); err != nil {
		return relayerPacket{}, err
	}
	if _, err := r.evm.Approve(ctx); err != nil {
		return relayerPacket{}, err
	}
	snapshot, err := r.evm.Snapshot(ctx, plan.Sender)
	if err != nil {
		return relayerPacket{}, err
	}
	sent, err := r.evm.SendTokenOrder(ctx, r.current.Channels.EVM, plan, r.cfg.GnoRecipient, r.cfg.EVMTestAmount, 0)
	if err != nil {
		return relayerPacket{}, err
	}
	r.progressf("relayer scenario: packet submitted hash=%s tx=%s", sent.PacketHash, sent.Tx)
	return relayerPacket{SendTx: sent.Tx, PacketHash: sent.PacketHash, FromBlock: snapshot.Block}, nil
}

func (r *Runner) finishRelayerPacket(ctx context.Context, runtime *voyager.Runtime, packet relayerPacket) (string, error) {
	ack, err := r.evm.WaitAcknowledgement(ctx, packet.FromBlock, r.current.Channels.EVM, packet.PacketHash)
	if err != nil {
		return "", err
	}
	success, err := matchingAcknowledgementResult(packet.GnoEvents.Acknowledgement, ack.Value)
	if err != nil {
		return "", err
	}
	if !success {
		return "", fmt.Errorf("relayer packet acknowledgement was not successful")
	}
	if err := r.evm.VerifyCommitmentCleared(ctx, packet.PacketHash); err != nil {
		return "", err
	}
	if err := r.verifyRelayerFailedWork(ctx, runtime); err != nil {
		return "", err
	}
	return ack.Tx, nil
}

func (r *Runner) verifyRelayerFailedWork(ctx context.Context, runtime *voyager.Runtime) error {
	baseline := *r.current.FailedWork.Final
	latest, err := runtime.FailedWorkID(ctx, baseline, r.current.FailedWork.Repaired)
	if err != nil {
		return err
	}
	if latest != baseline {
		return fmt.Errorf("Voyager moved relayer work to the failed queue")
	}
	return nil
}

func (r *Runner) requireRelayerSigner(ctx context.Context, txHash, privateKey string) (string, error) {
	want, err := r.evm.Address(ctx, privateKey)
	if err != nil {
		return "", err
	}
	got, err := r.evm.TransactionSender(ctx, txHash)
	if err != nil {
		return "", err
	}
	if got != want {
		return "", fmt.Errorf("EVM acknowledgement signer=%s, want %s", got, want)
	}
	return got, nil
}
