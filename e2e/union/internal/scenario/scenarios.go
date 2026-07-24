package scenario

import "context"

type scenarioCase struct {
	name    string
	enabled func(Options) bool
	run     func(*Runner, context.Context) error
}

// Slice order is execution order.
var scenarioCases = []scenarioCase{
	{"erc20-to-gno", func(o Options) bool { return o.ERC20ToGno }, (*Runner).runERC20ToGnoScenario},
	{"amount-boundaries", func(o Options) bool { return o.AmountBoundaries }, (*Runner).runAmountBoundaries},
	{"gno-to-evm", func(o Options) bool { return o.GnoToEVM }, (*Runner).runGnoToEVMScenarios},
}
