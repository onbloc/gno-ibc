package core

type MsgCreateClient struct {
	ClientType          ClientType
	ClientStateBytes    []byte
	ConsensusStateBytes []byte
}

type MsgUpdateClient struct {
	ClientId      ClientId
	ClientMessage []byte
}

type MsgConnectionOpenInit struct {
	ClientId             ClientId
	CounterpartyClientId ClientId
}

type MsgConnectionOpenTry struct {
	ClientId                 ClientId
	CounterpartyClientId     ClientId
	CounterpartyConnectionId ConnectionId
	ProofInit                []byte
	ProofHeight              Height
}

type MsgConnectionOpenAck struct {
	ConnectionId             ConnectionId
	CounterpartyConnectionId ConnectionId
	ProofTry                 []byte
	ProofHeight              Height
}

type MsgConnectionOpenConfirm struct {
	ConnectionId ConnectionId
	ProofAck     []byte
	ProofHeight  Height
}

type MsgChannelOpenInit struct {
	PortId             []byte
	CounterpartyPortId []byte
	ConnectionId       ConnectionId
	Version            string
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

type MsgPacketAcknowledgement struct {
	Packets          []Packet
	Acknowledgements [][]byte
	Proof            []byte
	ProofHeight      Height
}

type MsgPacketTimeout struct {
	Packet      Packet
	Proof       []byte
	ProofHeight Height
}

type MsgIntentPacketRecv struct {
	Packets             []Packet
	MarketMakerMessages [][]byte
}

type MsgBatchSend struct {
	Packets []Packet
}

type MsgBatchAcks struct {
	Packets []Packet
	Acks    [][]byte
}

type MsgCommitMembershipProof struct {
	ClientId    ClientId
	ProofHeight Height
	Proof       []byte
	Path        []byte
	Value       []byte
}

type MsgCommitNonMembershipProof struct {
	ClientId    ClientId
	ProofHeight Height
	Proof       []byte
	Path        []byte
}

type MsgCommitPacketTimeout struct {
	Packet      Packet
	ProofHeight Height
	Proof       []byte
}

type MsgWriteAcknowledgement struct {
	Packet          Packet
	Acknowledgement []byte
}
