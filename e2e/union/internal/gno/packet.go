package gno

import (
	"context"
	"fmt"
	"regexp"
	"strconv"
	"time"
)

var packetHashPattern = regexp.MustCompile(`^0x[0-9a-fA-F]{64}$`)

// PacketEvents identifies the matching receive and acknowledgement.
type PacketEvents struct {
	ReceiveTx, WriteAckTx, Acknowledgement string
}

// PacketSend identifies one Gno-origin packet.
type PacketSend struct {
	Tx, PacketHash string
	Height         int64
}

// PacketAck identifies one source-side acknowledgement.
type PacketAck struct {
	Tx, Value string
}

// WaitPacket requires exactly one PacketRecv and WriteAck in the same Gno transaction.
func (c *Client) WaitPacket(ctx context.Context, packetHash string) (PacketEvents, error) {
	waitCtx, cancel := context.WithTimeout(ctx, c.cfg.ScenarioTimeout)
	defer cancel()
	for {
		events, err := c.queryEvents(
			waitCtx, []string{"PacketRecv", "WriteAck"},
			map[string]string{"packet_hash": packetHash},
		)
		if err != nil {
			return PacketEvents{}, err
		}
		var receive, writeAck []packetEvent
		for _, event := range events {
			switch event.Type {
			case "PacketRecv":
				receive = append(receive, event)
			case "WriteAck":
				writeAck = append(writeAck, event)
			}
		}
		if len(receive) > 1 {
			return PacketEvents{}, fmt.Errorf("Gno PacketRecv count=%d, want exactly one", len(receive))
		}
		if len(writeAck) > 1 {
			return PacketEvents{}, fmt.Errorf("Gno WriteAck count=%d, want exactly one", len(writeAck))
		}
		if len(receive) == 0 || len(writeAck) == 0 {
			if err := pause(waitCtx, c.cfg.PollInterval); err != nil {
				return PacketEvents{}, fmt.Errorf("Gno packet events were not visible: %w", err)
			}
			continue
		}
		if receive[0].TxHash != writeAck[0].TxHash {
			return PacketEvents{}, fmt.Errorf("Gno PacketRecv and WriteAck transactions differ")
		}
		acknowledgement, err := parseAcknowledgement(writeAck[0].Attrs)
		if err != nil {
			return PacketEvents{}, err
		}
		return PacketEvents{
			ReceiveTx: receive[0].TxHash, WriteAckTx: writeAck[0].TxHash,
			Acknowledgement: acknowledgement,
		}, nil
	}
}

// WaitAcknowledgement returns exactly one source-side PacketAck.
func (c *Client) WaitAcknowledgement(ctx context.Context, packetHash string) (PacketAck, error) {
	waitCtx, cancel := context.WithTimeout(ctx, c.cfg.ScenarioTimeout)
	defer cancel()
	for {
		events, err := c.queryEvents(
			waitCtx, []string{"PacketAck"}, map[string]string{"packet_hash": packetHash},
		)
		if err != nil {
			return PacketAck{}, err
		}
		switch len(events) {
		case 0:
			if err := pause(waitCtx, c.cfg.PollInterval); err != nil {
				return PacketAck{}, fmt.Errorf("Gno PacketAck was not visible: %w", err)
			}
		case 1:
			acknowledgement, err := parseAcknowledgement(events[0].Attrs)
			if err != nil {
				return PacketAck{}, err
			}
			return PacketAck{Tx: events[0].TxHash, Value: acknowledgement}, nil
		default:
			return PacketAck{}, fmt.Errorf("Gno PacketAck count=%d, want exactly one", len(events))
		}
	}
}

// WaitPacketSend returns the one new send after the captured block.
func (c *Client) WaitPacketSend(ctx context.Context, channel, after int64) (PacketSend, error) {
	waitCtx, cancel := context.WithTimeout(ctx, c.cfg.ScenarioTimeout)
	defer cancel()
	for {
		events, err := c.queryEvents(
			waitCtx, []string{"PacketSend"},
			map[string]string{"source_channel_id": strconv.FormatInt(channel, 10)},
		)
		if err != nil {
			return PacketSend{}, err
		}
		var matches []packetEvent
		for _, event := range events {
			if event.BlockHeight > after {
				matches = append(matches, event)
			}
		}
		if len(matches) > 1 {
			return PacketSend{}, fmt.Errorf("new Gno PacketSend count=%d, want exactly one", len(matches))
		}
		if len(matches) == 0 {
			if err := pause(waitCtx, c.cfg.PollInterval); err != nil {
				return PacketSend{}, fmt.Errorf("Gno PacketSend was not visible: %w", err)
			}
			continue
		}
		packetHash := attributeValue(matches[0].Attrs, "packet_hash")
		if !packetHashPattern.MatchString(packetHash) || matches[0].BlockHeight <= 0 {
			return PacketSend{}, fmt.Errorf("malformed Gno PacketSend hash")
		}
		return PacketSend{
			Tx: matches[0].TxHash, PacketHash: packetHash, Height: matches[0].BlockHeight,
		}, nil
	}
}

func pause(ctx context.Context, interval time.Duration) error {
	if interval <= 0 {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			return nil
		}
	}
	timer := time.NewTimer(interval)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}
