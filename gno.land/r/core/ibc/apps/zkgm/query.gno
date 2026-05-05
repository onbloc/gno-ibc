package zkgm

import (
	tb "gno.land/p/gnoswap/tokenbucket"
	u256 "gno.land/p/gnoswap/uint256"
)

func GetConfig() Config {
	return Config{
		ImplPath:     implPath,
		AllowedImpls: cloneStrings(allowedImpls),
		Paused:       paused,
	}
}

func Render(path string) string {
	if impl == nil {
		return "zkgm: impl not set"
	}
	return impl.Render(gRealm.PkgPath(), path)
}

func PredictWrappedToken(channelID string, baseToken string) string {
	return "zkgm/" + channelID + "/" + baseToken
}

func GetChannelBalanceV2(key string) *u256.Uint {
	value, ok := channelBalanceV2.Get(key)
	if !ok {
		return nil
	}
	return value.(*u256.Uint)
}

func GetTokenBucket(denom string) *tb.TokenBucket {
	value, ok := tokenBucket.Get(denom)
	if !ok {
		return nil
	}
	return value.(*tb.TokenBucket)
}

func GetMinter() string {
	return gRealm.PkgPath()
}

func GetBurnAddress() string {
	return gRealm.PkgPath() + "/burn"
}
