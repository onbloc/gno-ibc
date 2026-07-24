// Package state owns the durable runner checkpoint schema.
package state

// Phase is a durable scenario transition.
type Phase string

const (
	PhaseBootstrap               Phase = "bootstrap-in-progress"
	PhaseConnectionSubmitting    Phase = "connection-submitting"
	PhaseConnectionSubmitted     Phase = "connection-submitted"
	PhaseConnectionPrepared      Phase = "connection-prepared"
	PhaseChannelSubmitting       Phase = "channel-submitting"
	PhaseChannelSubmitted        Phase = "channel-submitted"
	PhaseChannelPrepared         Phase = "channel-prepared"
	PhaseComplete                Phase = "complete"
	PhaseFailedWork              Phase = "failed-work"
	PhasePacketMintSubmitting    Phase = "packet-mint-submitting"
	PhasePacketMintSubmitted     Phase = "packet-mint-submitted"
	PhasePacketApproveSubmitting Phase = "packet-approve-submitting"
	PhasePacketApproveSubmitted  Phase = "packet-approve-submitted"
	PhasePacketSendSubmitting    Phase = "packet-send-submitting"
	PhasePacketSendSubmitted     Phase = "packet-send-submitted"
	PhasePacketComplete          Phase = "packet-complete"
)

// PacketOutcome records the matching cross-chain acknowledgement result.
type PacketOutcome string

const (
	PacketOutcomeSuccess PacketOutcome = "success"
	PacketOutcomeFailure PacketOutcome = "failure"
)

// State is compatible with the fixed-point shell checkpoint.
type State struct {
	Phase           Phase         `json:"phase"`
	VoyagerRevision string        `json:"voyager_revision"`
	Chains          Chains        `json:"chains"`
	EVMTopology     EVMTopology   `json:"evm_topology"`
	Ports           Ports         `json:"ports"`
	Version         string        `json:"version"`
	FailedWork      FailedWork    `json:"failed_work"`
	Clients         Clients       `json:"clients"`
	Allowlists      Allowlists    `json:"allowlists"`
	Connections     *HandshakeIDs `json:"connections,omitempty"`
	Channels        *HandshakeIDs `json:"channels,omitempty"`
	Packet          *Packet       `json:"packet,omitempty"`
}

type Chains struct {
	Union string `json:"union"`
	EVM   string `json:"evm"`
	Gno   string `json:"gno"`
}

type EVMTopology struct {
	ChainID            string `json:"chain_id"`
	AddressFingerprint string `json:"address_fingerprint"`
}

type Ports struct {
	Gno string `json:"gno"`
	EVM string `json:"evm"`
}

type FailedWork struct {
	Baseline int64   `json:"baseline"`
	Final    *int64  `json:"final"`
	Repaired []int64 `json:"repaired"`
}

type Clients struct {
	GnoUnion int64 `json:"gno_union"`
	UnionGno int64 `json:"union_gno"`
	UnionEVM int64 `json:"union_evm"`
	EVMUnion int64 `json:"evm_union"`
	GnoEVM   int64 `json:"gno_evm"`
	EVMGno   int64 `json:"evm_gno"`
}

type Allowlists struct {
	Plain     string `json:"plain"`
	ProofLens string `json:"proof_lens"`
}

type HandshakeIDs struct {
	Gno int64 `json:"gno"`
	EVM int64 `json:"evm"`
}

type Packet struct {
	Phase              Phase         `json:"phase"`
	Token              string        `json:"token"`
	Sender             string        `json:"sender"`
	Recipient          string        `json:"recipient"`
	Amount             string        `json:"amount"`
	Voucher            string        `json:"voucher"`
	Salt               string        `json:"salt"`
	Tag                string        `json:"tag"`
	FailedWorkBaseline int64         `json:"failed_work_baseline"`
	MintTx             string        `json:"mint_tx,omitempty"`
	ApproveTx          string        `json:"approve_tx,omitempty"`
	BalancesBefore     *Balances     `json:"balances_before,omitempty"`
	EVMFromBlock       *uint64       `json:"evm_from_block,omitempty"`
	SendTx             string        `json:"send_tx,omitempty"`
	PacketHash         string        `json:"packet_hash,omitempty"`
	GnoReceiveTx       string        `json:"gno_receive_tx,omitempty"`
	GnoWriteAckTx      string        `json:"gno_write_ack_tx,omitempty"`
	EVMAckTx           string        `json:"evm_ack_tx,omitempty"`
	Outcome            PacketOutcome `json:"outcome,omitempty"`
	CommitmentCleared  bool          `json:"commitment_cleared,omitempty"`
	BalanceDeltas      *Balances     `json:"balance_deltas,omitempty"`
	FailedWorkFinal    *int64        `json:"failed_work_final,omitempty"`
}

type Balances struct {
	Sender    string `json:"sender"`
	Escrow    string `json:"escrow"`
	Recipient string `json:"recipient"`
}

// Expected is the current environment identity used to validate a checkpoint.
type Expected struct {
	VoyagerRevision     string
	Chains              Chains
	EVMChainID          string
	TopologyFingerprint string
	GnoPort             string
	EVMPort             string
	Version             string
	PacketToken         string
	PacketRecipient     string
	PacketAmount        string
	PacketLedgerAmount  int64
}
