package scenario

import "context"

type scenarioCase struct {
	name    string
	enabled func(Options) bool
	run     func(*Runner, context.Context) error
}

// Slice order is execution order.
var scenarioCases = []scenarioCase{
	{"forged-proof-rejection", func(o Options) bool { return o.ForgedProofRejection }, (*Runner).runForgedProofRejection},
	{"erc20-to-gno", func(o Options) bool { return o.ERC20ToGno }, (*Runner).runERC20ToGnoScenario},
	{"amount-boundaries", func(o Options) bool { return o.AmountBoundaries }, (*Runner).runAmountBoundaries},
	{"gno-to-evm", func(o Options) bool { return o.GnoToEVM }, (*Runner).runGnoToEVMScenarios},
	{"relayer-insufficient-balance-failover", func(o Options) bool { return o.RelayerInsufficientBalanceFailover }, (*Runner).runRelayerInsufficientBalanceFailover},
	{"relayer-offline-failover", func(o Options) bool { return o.RelayerOfflineFailover }, (*Runner).runRelayerOfflineFailover},
	{"relayer-balance-recovery", func(o Options) bool { return o.RelayerBalanceRecovery }, (*Runner).runRelayerBalanceRecovery},
	{"evm-to-gno-timeout-refund", func(o Options) bool { return o.EVMToGnoTimeoutRefund }, (*Runner).runEVMToGnoTimeoutRefund},
	{"gno-to-evm-timeout-refund", func(o Options) bool { return o.GnoToEVMTimeoutRefund }, (*Runner).runGnoToEVMTimeoutRefund},
}
