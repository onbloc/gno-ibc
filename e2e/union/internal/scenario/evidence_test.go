package scenario

import (
	"os"
	"strings"
	"testing"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
)

func TestEvidenceSecretsPreventCompleteCheckpoint(t *testing.T) {
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
			runner := Runner{cfg: cfg, current: completedState(cfg, 7)}
			runner.current.Ports.Gno = tc.secret(&runner.cfg)

			err := runner.saveChannelEvidence()
			if err == nil || !strings.Contains(err.Error(), "secret") {
				t.Fatalf("error = %v, want secret scan failure", err)
			}
			if _, err := os.Stat(cfg.StateFile); !os.IsNotExist(err) {
				t.Fatalf("complete checkpoint exists after evidence rejection: %v", err)
			}
		})
	}
}
