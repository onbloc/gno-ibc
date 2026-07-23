package main

import (
	"context"
	"flag"
	"log"

	"github.com/onbloc/gno-ibc/e2e/union/internal/scenario"
)

func main() {
	erc20ToGno := flag.Bool("erc20-to-gno", false, "run the ERC20 EVM-to-Gno scenario")
	flag.Parse()

	ctx := context.Background()
	runner := new(scenario.Runner)
	if err := runner.RunChannel(ctx); err != nil {
		log.Fatal(err)
	}
	if *erc20ToGno {
		if err := runner.RunERC20ToGno(ctx); err != nil {
			log.Fatal(err)
		}
	}
}
