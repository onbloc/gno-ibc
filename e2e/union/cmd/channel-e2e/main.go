package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/scenario"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	options := scenario.Options{}
	configPath := flag.String("config", "runner.json", "runner configuration JSON")
	flag.BoolVar(&options.Apply, "apply", false, "allow broadcasts")
	flag.BoolVar(&options.Resume, "resume", false, "resume from saved state")
	flag.BoolVar(&options.ForgedProofRejection, "forged-proof-rejection", false, "reject a mutated live EVM membership proof")
	flag.BoolVar(&options.ERC20ToGno, "erc20-to-gno", false, "run the ERC20 EVM-to-Gno scenario")
	flag.BoolVar(&options.AmountBoundaries, "amount-boundaries", false, "run EVM-to-Gno amount boundary scenarios (includes --erc20-to-gno)")
	flag.BoolVar(&options.GnoToEVM, "gno-to-evm", false, "run Gno-to-EVM lifecycle and refund scenarios (includes --erc20-to-gno)")
	flag.Usage = func() {
		fmt.Fprintf(flag.CommandLine.Output(), "usage: %s [--config path] [--resume] [--apply] [--forged-proof-rejection] [--erc20-to-gno] [--amount-boundaries] [--gno-to-evm]\n", os.Args[0])
	}
	flag.Parse()
	if flag.NArg() != 0 {
		flag.Usage()
		os.Exit(2)
	}
	options.Normalize()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	scriptDir, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("cannot determine working directory")
	}
	cfg, err := config.Load(*configPath, scriptDir, os.LookupEnv, options.ERC20ToGno)
	if err != nil {
		return err
	}
	runner, err := scenario.New(cfg, options)
	if err != nil {
		return err
	}
	if err := runner.Run(ctx); err != nil {
		return err
	}
	fmt.Println("Voyager config render and preflight passed")
	if !options.Apply && !options.Resume {
		fmt.Println("dry preflight only; broadcasting requires --apply")
		return nil
	}
	return nil
}
