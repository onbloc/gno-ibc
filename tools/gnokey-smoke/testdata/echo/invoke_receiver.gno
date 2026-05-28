package main

import (
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	echo "gno.land/r/gnoswap/ibc/examples/echo"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

func main(cur realm) {
	r := zkgm.GetReceiver(echo.PkgPath)
	if r == nil {
		panic("echo receiver not registered")
	}
	println("registered true")

	env := z.CallEnv{
		Caller:             "g1relayer",
		ProxyAccount:       "zkgm1example",
		Path:               u256.NewUint(1),
		SourceChannel:      "27",
		DestinationChannel: "1",
		Sender:             []byte("alice"),
		Calldata:           []byte("hello"),
		Relayer:            []byte("g1relayer"),
		RelayerMsg:         []byte(""),
	}

	if err := r.OnZkgm(cross(cur), env); err != nil {
		panic(err.Error())
	}

	println("calls", echo.Calls())
	println("last_calldata", echo.LastCalldata())
}
