package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
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
	flag.BoolVar(&options.Apply, "apply", false, "allow broadcasts")
	flag.BoolVar(&options.Resume, "resume", false, "resume from saved state")
	flag.BoolVar(&options.ERC20ToGno, "erc20-to-gno", false, "run the ERC20 EVM-to-Gno scenario")
	flag.BoolVar(&options.AmountBoundaries, "amount-boundaries", false, "run EVM-to-Gno amount boundary scenarios")
	flag.Usage = func() {
		fmt.Fprintf(flag.CommandLine.Output(), "usage: %s [--resume] [--apply] [--erc20-to-gno] [--amount-boundaries]\n", os.Args[0])
	}
	flag.Parse()
	if flag.NArg() != 0 {
		flag.Usage()
		os.Exit(2)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	scriptDir, err := resolveScriptDir()
	if err != nil {
		return err
	}
	cfg, err := config.Load(scriptDir, os.LookupEnv, options.ERC20ToGno)
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

func resolveScriptDir() (string, error) {
	dir := os.Getenv("E2E_SCRIPT_DIR")
	if dir == "" {
		var err error
		dir, err = os.Getwd()
		if err != nil {
			return "", fmt.Errorf("cannot determine working directory")
		}
	}
	dir, err := filepath.Abs(dir)
	if err != nil {
		return "", fmt.Errorf("cannot resolve E2E script directory")
	}
	if info, err := os.Stat(filepath.Join(dir, "config.jsonc.template")); err != nil || !info.Mode().IsRegular() {
		return "", fmt.Errorf("E2E_SCRIPT_DIR has no config.jsonc.template: %s", dir)
	}
	return dir, nil
}
