package core

type MsgCreateClient struct {
    client_type ClientType
    client_state_bytes Bytes
    consensus_state_bytes Bytes
}

type MsgUpdateClient struct {
    client_id ClientId
    client_message Bytes
}

type MsgConnectionOpenInit struct {
    client_id ClientId
    counterparty_client_id ClientId
}

type MsgConnectionOpenTry struct {
    client_id ClientId
    counterparty_client_id ClientId
    counterparty_connection_id ConnectionId
    proof_init Bytes
    proof_height Height
}

type MsgConnectionOpenAck struct {
    connection_id ConnectionId
    counterparty_connection_id ConnectionId
    proof_try Bytes
    proof_height Height
}

type MsgConnectionOpenConfirm struct {
    connection_id ConnectionId
    proof_ack Bytes
    proof_height Height
}

type MsgChannelOpenInit struct {
    port_id Bytes
    counterparty_port_id Bytes
    connection_id ConnectionId
    version string
}

type MsgChannelOpenTry struct {
    port_id Bytes
    channel Channel
    counterparty_version string
    proof_init Bytes
    proof_height Height
}

type MsgChannelOpenAck struct {
    channel_id ChannelId
    counterparty_version string
    counterparty_channel_id ChannelId
    proof_try Bytes
    proof_height Height
}

type MsgChannelOpenConfirm struct {
    channel_id ChannelId
    proof_ack Bytes
    proof_height Height
}

type MsgChannelCloseInit struct {}

type MsgChannelCloseConfirm struct {}

type MsgPacketRecv struct {
    packets []Packet
    relayer_msgs []Bytes
    proof Bytes
    proof_height Height
}

type MsgPacketAcknowledgement struct {
    packets []Packet
    acknowledgements []Bytes
    proof Bytes
    proof_height Height
}

type MsgPacketTimeout struct {
    packet Packet
    /// TODO: Should this be proof_unreceived?
    proof Bytes
    proof_height Height
}

type MsgIntentPacketRecv struct {
    packets []Packet
    market_maker_messages []Bytes
}

type MsgBatchSend struct {
    // TODO: Ensure len >= 2
    packets []Packet
}

type MsgBatchAcks struct {
    // TODO: Ensure len >= 2
    packets []Packet
    // TODO: Ensure same length as packets somehow (maybe zip the lists into one field?)
    acks []Bytes
}

type MsgCommitMembershipProof struct {
    client_id ClientId
    proof_height Height
    proof Bytes
    path Bytes
    value Bytes
}

type MsgCommitNonMembershipProof struct {
    client_id ClientId
    proof_height Height
    proof Bytes
    path Bytes
}

type MsgCommitPacketTimeout struct {
    packet Packet
    proof_height Height
    proof Bytes
}
