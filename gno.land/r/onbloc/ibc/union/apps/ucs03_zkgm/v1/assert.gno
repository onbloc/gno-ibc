package v1

func assertIsRlmCurrent(_ int, rlm realm) {
	if !rlm.IsCurrent() {
		panic(errSpoofedRealm)
	}
}
