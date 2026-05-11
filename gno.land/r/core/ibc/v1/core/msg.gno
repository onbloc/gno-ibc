package core

type MsgCreateClient struct {
	ClientType          ClientType
	ClientStateBytes    Bytes
	ConsensusStateBytes Bytes
	Relayer             address
}

type MsgUpdateClient struct {
	ClientId      ClientId
	ClientMessage Bytes
	Relayer       address
}

type MsgMisbehaviour struct {
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
	PortId             address
	CounterpartyPortId address
	ConnectionId       ConnectionId
	Version            string
	Relayer            address
}

type MsgChannelOpenTry struct {
	PortId              address
	Channel             Channel
	CounterpartyVersion string
	ProofInit           Bytes
	ProofHeight         Height
	Relayer             address
}

type MsgChannelOpenAck struct {
	ChannelId             ChannelId
	CounterpartyVersion   string
	CounterpartyChannelId ChannelId
	ProofTry              Bytes
	ProofHeight           Height
	Relayer               address
}

type MsgChannelOpenConfirm struct {
	ChannelId   ChannelId
	ProofAck    Bytes
	ProofHeight Height
	Relayer     address
}

type MsgChannelCloseInit struct {
	ChannelId ChannelId
	Relayer   address
}

type MsgChannelCloseConfirm struct {
	ChannelId   ChannelId
	ProofClose  Bytes
	ProofHeight Height
	Relayer     address
}

type MsgPacketSend struct {
	SourceChannelId  ChannelId
	TimeoutTimestamp Timestamp
	Data             Bytes
}

type MsgPacketRecv struct {
	Packets     []Packet
	RelayerMsgs []Bytes
	Proof       Bytes
	ProofHeight Height
	Relayer     address
}

type MsgPacketAcknowledgement struct {
	Packets          []Packet
	Acknowledgements []Bytes
	Proof            Bytes
	ProofHeight      Height
	Relayer          address
}

type MsgPacketTimeout struct {
	Packet      Packet
	Proof       Bytes
	ProofHeight Height
	Relayer     address
}
