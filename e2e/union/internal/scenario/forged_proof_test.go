package scenario

import (
	"encoding/binary"
	"testing"
)

func TestMutateStorageProofFlipsProofNodeOnly(t *testing.T) {
	proof := make([]byte, 0, 92)
	proof = append(proof, make([]byte, 64)...)
	proof = binary.LittleEndian.AppendUint64(proof, 2)
	proof = binary.LittleEndian.AppendUint64(proof, 0)
	proof = binary.LittleEndian.AppendUint64(proof, 4)
	proof = append(proof, 0xde, 0xad, 0xbe, 0xef)

	mutated, err := mutateStorageProof(proof)
	if err != nil {
		t.Fatal(err)
	}
	nodeByte := len(proof) - 1
	if mutated[nodeByte] != 0xee {
		t.Fatalf("mutated node byte = %x, want ee", mutated[nodeByte])
	}
	for i := range proof {
		if i != nodeByte && proof[i] != mutated[i] {
			t.Fatalf("framing byte %d changed", i)
		}
	}
	if proof[nodeByte] != 0xef {
		t.Fatal("valid control proof was modified")
	}
}

func TestMutateStorageProofRejectsMissingNodeData(t *testing.T) {
	if _, err := mutateStorageProof(make([]byte, 72)); err == nil {
		t.Fatal("proof without an MPT node unexpectedly mutated")
	}
}
