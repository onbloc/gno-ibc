package ics20zkgm_adapter

// assertIsRlmCurrent guards every Store setter, mirroring
// apps/ucs03_zkgm/assert.gno: it rejects a stale/spoofed rlm token that no
// longer corresponds to the actual current call frame.
func assertIsRlmCurrent(_ int, rlm realm) {
	if !rlm.IsCurrent() {
		panic("ics20zkgm_adapter: spoofed realm")
	}
}
