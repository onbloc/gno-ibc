package storage

import "testing"

func TestDecodeProofBincode(t *testing.T) {
	// Mirrors ethereum_light_client_types::StorageProof:
	// https://github.com/unionlabs/union/blob/main/lib/ethereum-light-client-types/src/storage_proof.rs
	//
	// U256 uses fixed-int little-endian bincode encoding in Union's primitive
	// wrapper, so DecodeProof normalizes Key/Value back to 32-byte big-endian
	// EVM words.
	bz := mustHex(
		"0200000000000000000000000000000000000000000000000000000000000000" + // key U256(2), little endian
			"efbeadde00000000000000000000000000000000000000000000000000000000" + // value U256(0xdeadbeef), little endian
			"0200000000000000" + // proof length
			"0300000000000000" + // proof[0] length
			"aabbcc" +
			"0000000000000000", // proof[1] length
	)

	proof, err := DecodeProof(bz)
	if err != nil {
		t.Fatalf("DecodeProof: %v", err)
	}
	assertHex(t, "key", proof.Key, "0000000000000000000000000000000000000000000000000000000000000002")
	assertHex(t, "value", proof.Value, "00000000000000000000000000000000000000000000000000000000deadbeef")
	if len(proof.Proof) != 2 {
		t.Fatalf("proof length: got %d want 2", len(proof.Proof))
	}
	assertHex(t, "proof[0]", proof.Proof[0], "aabbcc")
	assertHex(t, "proof[1]", proof.Proof[1], "")

	assertHex(t, "EncodeProof", EncodeProof(proof), "0200000000000000000000000000000000000000000000000000000000000000"+
		"efbeadde00000000000000000000000000000000000000000000000000000000"+
		"0200000000000000"+
		"0300000000000000"+
		"aabbcc"+
		"0000000000000000")
}

func TestDecodeProofRejectsTrailingBytes(t *testing.T) {
	_, err := DecodeProof(mustHex(
		"0200000000000000000000000000000000000000000000000000000000000000" +
			"efbeadde00000000000000000000000000000000000000000000000000000000" +
			"0000000000000000" +
			"ff",
	))
	if err != ErrTrailingProofBytes {
		t.Fatalf("DecodeProof trailing: got %v want %v", err, ErrTrailingProofBytes)
	}
}
