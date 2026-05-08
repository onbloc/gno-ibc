// gen-ibc-test-client generates ABI-encoded ClientState and ConsensusState bytes
// for testing CreateClient on the local gnodev node.
//
// Usage:
//
//	cd tools/gen-ibc-test-client && go run .
package main

import (
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"fmt"

	"golang.org/x/crypto/sha3"
)

const realmPath = "gno.land/r/core/ibc/v1/core"

func main() {
	cs := encodeClientState(
		"union-devnet-1337",
		14*24*3600*1_000_000_000, // trusting_period: 14 days in ns
		10*1_000_000_000,         // max_clock_drift: 10s in ns
		0,                        // frozen_height
		3405691581,               // latest_height (devnetHeight - 1)
	)

	// devnetAH as app_hash, devnetVH as next_validators_hash
	devnetAH, _ := hex.DecodeString("EE7E3E58F98AC95D63CE93B270981DF3EE54CA367F8D521ED1F444717595CD36")
	devnetVH, _ := hex.DecodeString("20DDFE7A0F75C65D876316091ECCD494A54A2BB324C872015F73E528D53CB9C4")
	consState := encodeConsensusState(
		uint64(1732205251-1000)*1_000_000_000, // timestamp: devnetTimeSeconds-1000 in ns
		devnetAH,
		devnetVH,
	)

	csHex := hex.EncodeToString(cs)
	consHex := hex.EncodeToString(consState)

	fmt.Printf("ClientState hex:    %s\n", csHex)
	fmt.Printf("ConsensusState hex: %s\n", consHex)
	fmt.Println()

	// CreateClientRaw takes plain hex strings (no 0x prefix).
	fmt.Println("=== gnokey command ===")
	fmt.Printf(
		"gnokey maketx call -pkgpath %s -func CreateClientRaw "+
			"-args 07-cometbls -args %s -args %s "+
			"-gas-fee 1000000ugnot -gas-wanted 50000000 "+
			"-broadcast -chainid dev test1\n",
		realmPath, csHex, consHex,
	)
	fmt.Println()

	// ABCI query key: ClientStatePath(clientId=1) = keccak(CLIENT_STATE[32] || u32ToH256(1))
	// Stored params key: vm:<realmPath>:<hexEncodedPathKey>
	// Stored value: keccak(clientStateBytes)
	clientId := uint32(1)
	pathKey := clientStatePath(clientId)
	hexKey := hex.EncodeToString(pathKey[:])
	paramsKey := fmt.Sprintf("vm:%s:%s", realmPath, hexKey)
	expectedValue := keccak256(cs)

	fmt.Println("=== ABCI query ===")
	fmt.Printf("params key:     %s\n", paramsKey)
	fmt.Printf("expected value: %s\n", hex.EncodeToString(expectedValue[:]))
	fmt.Println()
	fmt.Printf("curl 'http://localhost:26657/abci_query?path=\"params/%s\"'\n", paramsKey)
	fmt.Println()
	fmt.Println("=== verify (decode response Data field) ===")
	fmt.Printf("python3 -c \"import base64; print(base64.b64decode('%s').hex())\"\n", base64.StdEncoding.EncodeToString(expectedValue[:]))
}

func clientStatePath(clientId uint32) [32]byte {
	var clientStateSlot [32]byte // all zeros = slot 0
	var idBuf [32]byte
	binary.BigEndian.PutUint32(idBuf[28:], clientId)

	input := append(clientStateSlot[:], idBuf[:]...)
	return keccak256(input)
}

func keccak256(data []byte) [32]byte {
	h := sha3.NewLegacyKeccak256()
	h.Write(data)
	var out [32]byte
	copy(out[:], h.Sum(nil))
	return out
}

// encodeClientState ABI-encodes a ClientState (5 static fields → 5×32 = 160 bytes).
func encodeClientState(chainID string, trustingPeriod, maxClockDrift, frozenHeight, latestHeight uint64) []byte {
	var buf [160]byte
	copy(buf[0:32], chainID)
	binary.BigEndian.PutUint64(buf[56:64], trustingPeriod)
	binary.BigEndian.PutUint64(buf[88:96], maxClockDrift)
	binary.BigEndian.PutUint64(buf[120:128], frozenHeight)
	binary.BigEndian.PutUint64(buf[152:160], latestHeight)
	return buf[:]
}

// encodeConsensusState ABI-encodes a ConsensusState (3 static fields → 3×32 = 96 bytes).
func encodeConsensusState(timestamp uint64, appHash, nextValidatorsHash []byte) []byte {
	var buf [96]byte
	binary.BigEndian.PutUint64(buf[24:32], timestamp)
	copy(buf[32:64], appHash)
	copy(buf[64:96], nextValidatorsHash)
	return buf[:]
}
