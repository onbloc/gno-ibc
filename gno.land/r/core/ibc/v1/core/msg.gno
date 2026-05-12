package core

type MsgCreateClient struct {
	ClientType          ClientType
	ClientStateBytes    Bytes
	ConsensusStateBytes Bytes
}

type MsgUpdateClient struct {
	ClientId      ClientId
	ClientMessage Bytes
}

type MsgConnectionOpenInit struct {
	ClientId             ClientId
	CounterpartyClientId ClientId
}

type MsgConnectionOpenTry struct {
	ClientId                 ClientId
	CounterpartyClientId     ClientId
	CounterpartyConnectionId ConnectionId
	ProofInit                Bytes
	ProofHeight              Height
}

type MsgConnectionOpenAck struct {
	ConnectionId             ConnectionId
	CounterpartyConnectionId ConnectionId
	ProofTry                 Bytes
	ProofHeight              Height
}

type MsgConnectionOpenConfirm struct {
	ConnectionId ConnectionId
	ProofAck     Bytes
	ProofHeight  Height
}

type MsgChannelOpenInit struct {
	PortId             Bytes
	CounterpartyPortId Bytes
	ConnectionId       ConnectionId
	Version            string
}

type MsgChannelOpenTry struct {
	PortId              Bytes
	Channel             Channel
	CounterpartyVersion string
	ProofInit           Bytes
	ProofHeight         Height
}

type MsgChannelOpenAck struct {
	ChannelId             ChannelId
	CounterpartyVersion   string
	CounterpartyChannelId ChannelId
	ProofTry              Bytes
	ProofHeight           Height
}

type MsgChannelOpenConfirm struct {
	ChannelId   ChannelId
	ProofAck    Bytes
	ProofHeight Height
}

type MsgChannelCloseInit struct{}

type MsgChannelCloseConfirm struct{}

type MsgPacketRecv struct {
	Packets     []Packet
	RelayerMsgs []Bytes
	Proof       Bytes
	ProofHeight Height
}

type MsgPacketAcknowledgement struct {
	Packets          []Packet
	Acknowledgements []Bytes
	Proof            Bytes
	ProofHeight      Height
}

type MsgPacketTimeout struct {
	Packet      Packet
	Proof       Bytes
	ProofHeight Height
}

type MsgIntentPacketRecv struct {
	Packets             []Packet
	MarketMakerMessages []Bytes
}

type MsgBatchSend struct {
	Packets []Packet
}

type MsgBatchAcks struct {
	Packets []Packet
	Acks    []Bytes
}

type MsgCommitMembershipProof struct {
	ClientId    ClientId
	ProofHeight Height
	Proof       Bytes
	Path        Bytes
	Value       Bytes
}

type MsgCommitNonMembershipProof struct {
	ClientId    ClientId
	ProofHeight Height
	Proof       Bytes
	Path        Bytes
}

type MsgCommitPacketTimeout struct {
	Packet      Packet
	ProofHeight Height
	Proof       Bytes
}
