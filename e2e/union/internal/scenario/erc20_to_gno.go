package scenario

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
)

// runERC20ToGnoScenario executes one disposable packet attempt.
func (r *Runner) runERC20ToGnoScenario(ctx context.Context) error {
	if err := r.mintERC20(ctx); err != nil {
		return err
	}
	if err := r.approveERC20(ctx); err != nil {
		return err
	}
	if err := r.sendTokenOrder(ctx); err != nil {
		return err
	}
	result, err := r.observePacket(ctx)
	if err != nil {
		return err
	}
	return r.finishPacket(result)
}

func (r *Runner) mintERC20(ctx context.Context) error {
	if r.packet != nil || r.current.Channels == nil || r.current.FailedWork.Final == nil {
		return fmt.Errorf("ERC20 packet requires a verified complete connection/channel state")
	}
	plan, err := r.evm.Prepare(ctx, r.current.Channels.Gno)
	if err != nil {
		return err
	}
	r.progressf("scenario erc20-to-gno: transfer token=%s amount=%s (18 decimals) sender=%s recipient=%s voucher=%s",
		strings.ToLower(r.cfg.EVMTestERC20), r.cfg.EVMTestAmount, plan.Sender,
		r.cfg.GnoRecipient, plan.Voucher)
	r.packet = &state.Packet{
		Token: strings.ToLower(r.cfg.EVMTestERC20), Sender: plan.Sender,
		Recipient: r.cfg.GnoRecipient, Amount: r.cfg.EVMTestAmount,
		Voucher: plan.Voucher, Salt: plan.Salt, Tag: plan.Tag,
		FailedWorkBaseline: *r.current.FailedWork.Final,
	}
	tx, err := r.evm.Mint(ctx, plan.Sender)
	if err != nil {
		return err
	}
	r.packet.MintTx = tx
	r.progressf("scenario erc20-to-gno: minted token (tx=%s)", tx)
	return nil
}

func (r *Runner) approveERC20(ctx context.Context) error {
	tx, err := r.evm.Approve(ctx)
	if err != nil {
		return err
	}
	r.packet.ApproveTx = tx
	r.progressf("scenario erc20-to-gno: approved ZKGM transfer (tx=%s)", tx)
	return nil
}

func (r *Runner) sendTokenOrder(ctx context.Context) error {
	packet := r.packet
	snapshot, err := r.evm.Snapshot(ctx, packet.Sender)
	if err != nil {
		return err
	}
	recipient, err := r.gno.VoucherBalance(ctx, packet.Voucher, packet.Recipient)
	if err != nil {
		return err
	}
	packet.BalancesBefore = &state.Balances{
		Sender: snapshot.Sender, Escrow: snapshot.Escrow,
		Recipient: strconv.FormatInt(recipient, 10),
	}
	packet.EVMFromBlock = &snapshot.Block
	result, err := r.evm.Send(
		ctx, r.current.Channels.EVM, packet.Sender, packet.Recipient,
		packet.Voucher, packet.Salt, packet.Tag,
	)
	if err != nil {
		return err
	}
	packet.SendTx, packet.PacketHash = result.Tx, result.PacketHash
	r.progressf("scenario erc20-to-gno: packet submitted hash=%s (tx=%s); waiting for Gno receive",
		result.PacketHash, result.Tx)
	return nil
}
