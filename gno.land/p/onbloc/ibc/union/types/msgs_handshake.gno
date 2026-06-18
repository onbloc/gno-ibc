package types

// Handshake datagrams: client lifecycle (create / update / force-update),
// connection handshake (4-way), and channel handshake (4-way + close).
// Mirroring the packet datagrams in msgs.gno, proof heights are plain block
// numbers (u64) and constructors are pure (no realm boundary).

// --- client lifecycle ---

type MsgCreateClient struct {
	ClientType          ClientType
	ClientStateBytes    []byte
	ConsensusStateBytes []byte
}

func NewMsgCreateClient(clientType ClientType, clientStateBytes, consensusStateBytes []byte) MsgCreateClient {
	return MsgCreateClient{ClientType: clientType, ClientStateBytes: clientStateBytes, ConsensusStateBytes: consensusStateBytes}
}

type MsgUpdateClient struct {
	ClientId      ClientId
	ClientMessage []byte
}

func NewMsgUpdateClient(clientId ClientId, clientMessage []byte) MsgUpdateClient {
	return MsgUpdateClient{ClientId: clientId, ClientMessage: clientMessage}
}

type MsgForceUpdateClient struct {
	ClientId            ClientId
	ClientStateBytes    []byte
	ConsensusStateBytes []byte
}

func NewMsgForceUpdateClient(clientId ClientId, clientStateBytes, consensusStateBytes []byte) MsgForceUpdateClient {
	return MsgForceUpdateClient{ClientId: clientId, ClientStateBytes: clientStateBytes, ConsensusStateBytes: consensusStateBytes}
}

// --- connection handshake ---

type MsgConnectionOpenInit struct {
	ClientId             ClientId
	CounterpartyClientId ClientId
}

func NewMsgConnectionOpenInit(clientId, counterpartyClientId ClientId) MsgConnectionOpenInit {
	return MsgConnectionOpenInit{ClientId: clientId, CounterpartyClientId: counterpartyClientId}
}

type MsgConnectionOpenTry struct {
	ClientId                 ClientId
	CounterpartyClientId     ClientId
	CounterpartyConnectionId ConnectionId
	ProofInit                []byte
	ProofHeight              uint64
}

func NewMsgConnectionOpenTry(clientId, counterpartyClientId ClientId, counterpartyConnectionId ConnectionId, proofInit []byte, proofHeight uint64) MsgConnectionOpenTry {
	return MsgConnectionOpenTry{ClientId: clientId, CounterpartyClientId: counterpartyClientId, CounterpartyConnectionId: counterpartyConnectionId, ProofInit: proofInit, ProofHeight: proofHeight}
}

type MsgConnectionOpenAck struct {
	ConnectionId             ConnectionId
	CounterpartyConnectionId ConnectionId
	ProofTry                 []byte
	ProofHeight              uint64
}

func NewMsgConnectionOpenAck(connectionId, counterpartyConnectionId ConnectionId, proofTry []byte, proofHeight uint64) MsgConnectionOpenAck {
	return MsgConnectionOpenAck{ConnectionId: connectionId, CounterpartyConnectionId: counterpartyConnectionId, ProofTry: proofTry, ProofHeight: proofHeight}
}

type MsgConnectionOpenConfirm struct {
	ConnectionId ConnectionId
	ProofAck     []byte
	ProofHeight  uint64
}

func NewMsgConnectionOpenConfirm(connectionId ConnectionId, proofAck []byte, proofHeight uint64) MsgConnectionOpenConfirm {
	return MsgConnectionOpenConfirm{ConnectionId: connectionId, ProofAck: proofAck, ProofHeight: proofHeight}
}

// --- channel handshake ---

type MsgChannelOpenInit struct {
	PortId             []byte
	CounterpartyPortId []byte
	ConnectionId       ConnectionId
	Version            string
}

func NewMsgChannelOpenInit(portId, counterpartyPortId []byte, connectionId ConnectionId, version string) MsgChannelOpenInit {
	return MsgChannelOpenInit{PortId: portId, CounterpartyPortId: counterpartyPortId, ConnectionId: connectionId, Version: version}
}

type MsgChannelOpenTry struct {
	PortId              []byte
	Channel             Channel
	CounterpartyVersion string
	ProofInit           []byte
	ProofHeight         uint64
}

func NewMsgChannelOpenTry(portId []byte, channel Channel, counterpartyVersion string, proofInit []byte, proofHeight uint64) MsgChannelOpenTry {
	return MsgChannelOpenTry{PortId: portId, Channel: channel, CounterpartyVersion: counterpartyVersion, ProofInit: proofInit, ProofHeight: proofHeight}
}

type MsgChannelOpenAck struct {
	ChannelId             ChannelId
	CounterpartyVersion   string
	CounterpartyChannelId ChannelId
	ProofTry              []byte
	ProofHeight           uint64
}

func NewMsgChannelOpenAck(channelId ChannelId, counterpartyVersion string, counterpartyChannelId ChannelId, proofTry []byte, proofHeight uint64) MsgChannelOpenAck {
	return MsgChannelOpenAck{ChannelId: channelId, CounterpartyVersion: counterpartyVersion, CounterpartyChannelId: counterpartyChannelId, ProofTry: proofTry, ProofHeight: proofHeight}
}

type MsgChannelOpenConfirm struct {
	ChannelId   ChannelId
	ProofAck    []byte
	ProofHeight uint64
}

func NewMsgChannelOpenConfirm(channelId ChannelId, proofAck []byte, proofHeight uint64) MsgChannelOpenConfirm {
	return MsgChannelOpenConfirm{ChannelId: channelId, ProofAck: proofAck, ProofHeight: proofHeight}
}

type MsgChannelCloseInit struct{}

func NewMsgChannelCloseInit() MsgChannelCloseInit {
	return MsgChannelCloseInit{}
}

type MsgChannelCloseConfirm struct{}

func NewMsgChannelCloseConfirm() MsgChannelCloseConfirm {
	return MsgChannelCloseConfirm{}
}
