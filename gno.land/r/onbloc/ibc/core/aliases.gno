package core

// Domain types and commitment/path helpers live in the pure package
// gno.land/p/onbloc/ibc/types (the single source of truth). core re-exports
// them as aliases so existing core.* references keep working without touching
// ~1900 call sites, while the definitions remain state-free and reusable.
//
// Constructors (NewPacket, NewMsg*, ...) are crossing functions — gno requires
// them to live in a realm package, so they are defined in core directly
// (constructors.gno, msg.gno), not aliased here.
//
// Per ROLES.md: the pure types package is the domain model; core owns state
// and orchestration. core remains a thin facade over these names.

import (
	"gno.land/p/onbloc/ibc/app"
	"gno.land/p/onbloc/ibc/host"
	"gno.land/p/onbloc/ibc/types"
)

// --- interface contracts (defined in pure host/app packages) ---
type (
	ILightClient      = host.ILightClient
	IForceLightClient = host.IForceLightClient
	IApp              = app.IApp
	IIntentApp        = app.IIntentApp
)

// --- identifier / scalar types ---
type (
	ClientId     = types.ClientId
	ConnectionId = types.ConnectionId
	ChannelId    = types.ChannelId
	Timestamp    = types.Timestamp
	Height       = types.Height
	Bytes        = types.Bytes
	H256         = types.H256
	ClientType   = types.ClientType
)

// --- enums ---
type (
	Status          = types.Status
	ConnectionState = types.ConnectionState
	ChannelState    = types.ChannelState
	PacketStatus    = types.PacketStatus
)

const (
	StatusUnknown = types.StatusUnknown
	StatusActive  = types.StatusActive
	StatusExpired = types.StatusExpired
	StatusFrozen  = types.StatusFrozen

	ConnectionStateUnknown = types.ConnectionStateUnknown
	ConnectionStateInit    = types.ConnectionStateInit
	ConnectionStateTryOpen = types.ConnectionStateTryOpen
	ConnectionStateOpen    = types.ConnectionStateOpen

	ChannelStateUnknown = types.ChannelStateUnknown
	ChannelStateInit    = types.ChannelStateInit
	ChannelStateTryOpen = types.ChannelStateTryOpen
	ChannelStateOpen    = types.ChannelStateOpen
	ChannelStateClosed  = types.ChannelStateClosed

	PacketStatusUnknown = types.PacketStatusUnknown
	PacketStatusSuccess = types.PacketStatusSuccess
	PacketStatusFailure = types.PacketStatusFailure
	PacketStatusAsync   = types.PacketStatusAsync
)

// --- domain structs ---
type (
	Packet               = types.Packet
	Channel              = types.Channel
	Connection           = types.Connection
	RecvPacketResult     = types.RecvPacketResult
	ConsensusStateUpdate = types.ConsensusStateUpdate
)

// --- commitment magic values ---
var (
	COMMITMENT_MAGIC     = types.COMMITMENT_MAGIC
	COMMITMENT_MAGIC_ACK = types.COMMITMENT_MAGIC_ACK
)

// --- commitment / path helpers (pure, no realm boundary) ---
var (
	CommitPacket  = types.CommitPacket
	CommitPackets = types.CommitPackets
	CommitAcks    = types.CommitAcks

	ClientStatePath           = types.ClientStatePath
	ConsensusStatePath        = types.ConsensusStatePath
	ConnectionPath            = types.ConnectionPath
	ChannelPath               = types.ChannelPath
	PacketCommitmentPath      = types.PacketCommitmentPath
	PacketAcknowledgementPath = types.PacketAcknowledgementPath
	BatchPacketsPath          = types.BatchPacketsPath
	BatchReceiptsPath         = types.BatchReceiptsPath
)
