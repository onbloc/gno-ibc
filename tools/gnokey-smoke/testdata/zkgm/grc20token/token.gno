package smoketoken

import (
	"gno.land/p/demo/tokens/grc20"
	"gno.land/r/demo/defi/grc20reg"
)

var (
	Token         *grc20.Token
	privateLedger *grc20.PrivateLedger
	userTeller    grc20.Teller
)

func init(cur realm) {
	Token, privateLedger = grc20.NewToken(0, cur, "SmokeToken", "SMOKE", 6)
	userTeller = Token.CallerTeller()
	grc20reg.Register(cross(cur), Token, "")
}

func Faucet(cur realm, amount int64) {
	if err := privateLedger.Mint(cur.Previous().Address(), amount); err != nil {
		panic(err.Error())
	}
}

func Approve(cur realm, spender address, amount int64) {
	if err := userTeller.Approve(0, cur, spender, amount); err != nil {
		panic(err.Error())
	}
}

func BalanceOf(owner address) int64 {
	return userTeller.BalanceOf(owner)
}

func Allowance(owner address, spender address) int64 {
	return userTeller.Allowance(owner, spender)
}
