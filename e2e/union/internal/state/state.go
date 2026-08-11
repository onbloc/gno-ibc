// Package state owns runtime topology and evidence values.
package state

// PacketOutcome records the matching cross-chain acknowledgement result.
type PacketOutcome string

const (
	PacketOutcomeSuccess PacketOutcome = "success"
	PacketOutcomeFailure PacketOutcome = "failure"
)

// State tracks the current client, connection, and channel topology.
type State struct {
	FailedWork  FailedWork
	Clients     Clients
	Allowlists  Allowlists
	Connections *HandshakeIDs
	Channels    *HandshakeIDs
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
	Plain     []int64
	ProofLens []int64
}

type HandshakeIDs struct {
	Gno int64 `json:"gno"`
	EVM int64 `json:"evm"`
}

type Packet struct {
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
