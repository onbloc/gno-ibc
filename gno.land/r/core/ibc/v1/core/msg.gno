package core

type MsgCreateClient struct {
	ClientType          ClientType
	ClientStateBytes    []byte
	ConsensusStateBytes []byte
}

func NewMsgCreateClient(_ realm, clientType ClientType, clientStateBytes, consensusStateBytes []byte) MsgCreateClient {
	return MsgCreateClient{ClientType: clientType, ClientStateBytes: clientStateBytes, ConsensusStateBytes: consensusStateBytes}
}

type MsgUpdateClient struct {
	ClientId      ClientId
	ClientMessage []byte
}

func NewMsgUpdateClient(_ realm, clientId ClientId, clientMessage []byte) MsgUpdateClient {
	return MsgUpdateClient{ClientId: clientId, ClientMessage: clientMessage}
}

type MsgConnectionOpenInit struct {
	ClientId             ClientId
	CounterpartyClientId ClientId
}

func NewMsgConnectionOpenInit(_ realm, clientId, counterpartyClientId ClientId) MsgConnectionOpenInit {
	return MsgConnectionOpenInit{ClientId: clientId, CounterpartyClientId: counterpartyClientId}
}

type MsgConnectionOpenTry struct {
	ClientId                 ClientId
	CounterpartyClientId     ClientId
	CounterpartyConnectionId ConnectionId
	ProofInit                []byte
	ProofHeight              Height
}

func NewMsgConnectionOpenTry(_ realm, clientId, counterpartyClientId ClientId, counterpartyConnectionId ConnectionId, proofInit []byte, proofHeight Height) MsgConnectionOpenTry {
	return MsgConnectionOpenTry{ClientId: clientId, CounterpartyClientId: counterpartyClientId, CounterpartyConnectionId: counterpartyConnectionId, ProofInit: proofInit, ProofHeight: proofHeight}
}

type MsgConnectionOpenAck struct {
	ConnectionId             ConnectionId
	CounterpartyConnectionId ConnectionId
	ProofTry                 []byte
	ProofHeight              Height
}

func NewMsgConnectionOpenAck(_ realm, connectionId, counterpartyConnectionId ConnectionId, proofTry []byte, proofHeight Height) MsgConnectionOpenAck {
	return MsgConnectionOpenAck{ConnectionId: connectionId, CounterpartyConnectionId: counterpartyConnectionId, ProofTry: proofTry, ProofHeight: proofHeight}
}

type MsgConnectionOpenConfirm struct {
	ConnectionId ConnectionId
	ProofAck     []byte
	ProofHeight  Height
}

func NewMsgConnectionOpenConfirm(_ realm, connectionId ConnectionId, proofAck []byte, proofHeight Height) MsgConnectionOpenConfirm {
	return MsgConnectionOpenConfirm{ConnectionId: connectionId, ProofAck: proofAck, ProofHeight: proofHeight}
}

type MsgChannelOpenInit struct {
	PortId             []byte
	CounterpartyPortId []byte
	ConnectionId       ConnectionId
	Version            string
}

func NewMsgChannelOpenInit(_ realm, portId, counterpartyPortId []byte, connectionId ConnectionId, version string) MsgChannelOpenInit {
	return MsgChannelOpenInit{PortId: portId, CounterpartyPortId: counterpartyPortId, ConnectionId: connectionId, Version: version}
}

type MsgChannelOpenTry struct {
	PortId              []byte
	Channel             Channel
	CounterpartyVersion string
	ProofInit           []byte
	ProofHeight         Height
}

type MsgChannelOpenAck struct {
	ChannelId             ChannelId
	CounterpartyVersion   string
	CounterpartyChannelId ChannelId
	ProofTry              []byte
	ProofHeight           Height
}

func NewMsgChannelOpenAck(_ realm, channelId ChannelId, counterpartyVersion string, counterpartyChannelId ChannelId, proofTry []byte, proofHeight Height) MsgChannelOpenAck {
	return MsgChannelOpenAck{ChannelId: channelId, CounterpartyVersion: counterpartyVersion, CounterpartyChannelId: counterpartyChannelId, ProofTry: proofTry, ProofHeight: proofHeight}
}

type MsgChannelOpenConfirm struct {
	ChannelId   ChannelId
	ProofAck    []byte
	ProofHeight Height
}

type MsgChannelCloseInit struct{}

type MsgChannelCloseConfirm struct{}

type MsgPacketRecv struct {
	Packets     []Packet
	RelayerMsgs [][]byte
	Proof       []byte
	ProofHeight Height
}

func NewMsgPacketRecv(_ realm, packets []Packet, relayerMsgs [][]byte, proof []byte, proofHeight Height) MsgPacketRecv {
	return MsgPacketRecv{Packets: packets, RelayerMsgs: relayerMsgs, Proof: proof, ProofHeight: proofHeight}
}

type MsgPacketAcknowledgement struct {
	Packets          []Packet
	Acknowledgements [][]byte
	Proof            []byte
	ProofHeight      Height
}

func NewMsgPacketAcknowledgement(_ realm, packets []Packet, acknowledgements [][]byte, proof []byte, proofHeight Height) MsgPacketAcknowledgement {
	return MsgPacketAcknowledgement{Packets: packets, Acknowledgements: acknowledgements, Proof: proof, ProofHeight: proofHeight}
}

type MsgPacketTimeout struct {
	Packet      Packet
	Proof       []byte
	ProofHeight Height
}

func NewMsgPacketTimeout(_ realm, packet Packet, proof []byte, proofHeight Height) MsgPacketTimeout {
	return MsgPacketTimeout{Packet: packet, Proof: proof, ProofHeight: proofHeight}
}

type MsgIntentPacketRecv struct {
	Packets             []Packet
	MarketMakerMessages [][]byte
}

type MsgBatchSend struct {
	Packets []Packet
}

func NewMsgBatchSend(_ realm, packets []Packet) MsgBatchSend {
	return MsgBatchSend{Packets: packets}
}

type MsgBatchAcks struct {
	Packets []Packet
	Acks    [][]byte
}

type MsgWriteAcknowledgement struct {
	Packet          Packet
	Acknowledgement []byte
}

func NewMsgWriteAcknowledgement(_ realm, packet Packet, acknowledgement []byte) MsgWriteAcknowledgement {
	return MsgWriteAcknowledgement{Packet: packet, Acknowledgement: acknowledgement}
}
