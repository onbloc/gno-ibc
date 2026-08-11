package scenario

import (
	"encoding/json"
	"os"
	"strings"
	"testing"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/gno"
)

func TestMembershipProofOutputArtifactPreservesRawStreams(t *testing.T) {
	cfg := testConfig(t)
	if err := os.MkdirAll(cfg.ArtifactDir, 0o700); err != nil {
		t.Fatal(err)
	}
	runner := Runner{cfg: cfg}
	want := gno.MembershipProofTx{
		Classification: "proof verification rejected",
		Stdout:         "raw stdout\n",
		Stderr:         "raw stderr\n",
		CommandError:   "exit status 1",
	}
	if err := runner.writeEvidence("gnokey.json", want); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(cfg.ArtifactDir + "/gnokey.json")
	if err != nil {
		t.Fatal(err)
	}
	var got gno.MembershipProofTx
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatal(err)
	}
	if got != want {
		t.Fatalf("artifact = %#v, want %#v", got, want)
	}
}

func TestEvidenceRejectsSecrets(t *testing.T) {
	tests := []struct {
		name   string
		secret func(*config.Config) string
	}{
		{"private key", func(cfg *config.Config) string {
			cfg.EVMPrivateKey = "0x" + strings.Repeat("a", 64)
			return cfg.EVMPrivateKey
		}},
		{"credential URL", func(*config.Config) string {
			return "https://user:" + "password@example.com"
		}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			cfg := testConfig(t)
			if err := os.MkdirAll(cfg.ArtifactDir, 0o700); err != nil {
				t.Fatal(err)
			}
			runner := Runner{cfg: cfg}
			raw, err := json.Marshal(map[string]string{"value": tc.secret(&runner.cfg)})
			if err != nil {
				t.Fatal(err)
			}
			runner.gnoConnectionEvidence = raw

			err = runner.writeChannelEvidence()
			if err == nil || !strings.Contains(err.Error(), "secret") {
				t.Fatalf("error = %v, want secret scan failure", err)
			}
		})
	}
}
