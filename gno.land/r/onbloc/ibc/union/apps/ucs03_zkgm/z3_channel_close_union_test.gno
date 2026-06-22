package zkgm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// Converted from Union test_on_channel_close_init_impossible.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3643-L3670
func TestOnChannelCloseInitImpossible(cur realm, t *testing.T) {
	setupChannelGate()
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	uassert.AbortsContains(t, cur, "the show must go on", func() {
		AsIBCApp().OnChannelCloseInit(cross(cur), 2, address("g1relayer"))
	})
}

// Converted from Union test_on_channel_close_init_only_ibc.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3672-L3699
func TestOnChannelCloseInitOnlyCore(cur realm, t *testing.T) {
	setupChannelGate()
	testing.SetRealm(testing.NewCodeRealm(proxyPkgPath))

	uassert.AbortsContains(t, cur, "ibc host only", func() {
		AsIBCApp().OnChannelCloseInit(cross(cur), 2, address("g1relayer"))
	})
}

// Converted from Union test_on_channel_close_confirm_impossible.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3701-L3728
func TestOnChannelCloseConfirmImpossible(cur realm, t *testing.T) {
	setupChannelGate()
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	uassert.AbortsContains(t, cur, "the show must go on", func() {
		AsIBCApp().OnChannelCloseConfirm(cross(cur), 2, address("g1relayer"))
	})
}

// Converted from Union test_on_channel_close_confirm_only_ibc.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3730-L3757
func TestOnChannelCloseConfirmOnlyCore(cur realm, t *testing.T) {
	setupChannelGate()
	testing.SetRealm(testing.NewCodeRealm(proxyPkgPath))

	uassert.AbortsContains(t, cur, "only core can channel close confirm", func() {
		AsIBCApp().OnChannelCloseConfirm(cross(cur), 2, address("g1relayer"))
	})
}
