package main

import "testing"

func TestPacketSendsExtractsCorePacketSend(t *testing.T) {
	tx := indexedTx{Hash: "0xabc", BlockHeight: 12}
	tx.Response.Events = append(tx.Response.Events,
		struct {
			Type    string      `json:"type"`
			PkgPath string      `json:"pkg_path"`
			Attrs   []eventAttr `json:"attrs"`
		}{Type: "PacketSend", PkgPath: "gno.land/r/other", Attrs: []eventAttr{{Key: "packet_hash", Value: "wrong"}}},
		struct {
			Type    string      `json:"type"`
			PkgPath string      `json:"pkg_path"`
			Attrs   []eventAttr `json:"attrs"`
		}{Type: packetSendEventType, PkgPath: corePkgPath, Attrs: []eventAttr{
			{Key: "packet_hash", Value: "0xhash"},
			{Key: "source_channel_id", Value: "1"},
			{Key: "destination_channel_id", Value: "31"},
			{Key: "packet_data[0]", Value: "0xda"},
			{Key: "packet_data[1]", Value: "ta"},
			{Key: "timeout_timestamp", Value: "99"},
		}},
	)

	packets := packetSends(tx)
	if len(packets) != 1 {
		t.Fatalf("packet count = %d, want 1", len(packets))
	}
	packet := packets[0]
	if packet.TxHash != "0xabc" || packet.BlockHeight != 12 || packet.PacketHash != "0xhash" || packet.SourceChannelID != "1" || packet.DestinationChannelID != "31" || packet.PacketData != "0xdata" || packet.TimeoutTimestamp != "99" {
		t.Fatalf("unexpected packet: %+v", packet)
	}
}
