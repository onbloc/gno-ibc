package config

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const (
	ChannelVersion = "ucs03-zkgm-0"
)

var (
	addressPattern    = regexp.MustCompile(`^0x[0-9a-fA-F]{40}$`)
	privateKeyPattern = regexp.MustCompile(`^0x[0-9a-fA-F]{64}$`)
	gnoAddressPattern = regexp.MustCompile(`^g1[0-9a-z]{38}$`)
	gnoRealmPattern   = regexp.MustCompile(`^gno\.land/r/[A-Za-z0-9_./-]+$`)
	revisionPattern   = regexp.MustCompile(`^[0-9a-f]{40}$`)
)

// Config is the validated private configuration for the live runner.
type Config struct {
	ScriptDir                 string        `json:"-"`
	UnionChainID              string        `json:"UNION_CHAIN_ID"`
	EVMChainID                string        `json:"EVM_CHAIN_ID"`
	GnoChainID                string        `json:"GNO_CHAIN_ID"`
	UnionVoyagerRevision      string        `json:"UNION_VOYAGER_REVISION"`
	UnionIBCHostContract      string        `json:"UNION_IBC_HOST_CONTRACT"`
	EVMIBCHandler             string        `json:"EVM_IBC_HANDLER"`
	EVMMulticall              string        `json:"EVM_MULTICALL"`
	EVMCometBLSClientImpl     string        `json:"EVM_COMETBLS_CLIENT_IMPL"`
	EVMProofLensClientImpl    string        `json:"EVM_PROOF_LENS_CLIENT_IMPL"`
	GnoIBCCoreRealm           string        `json:"GNO_IBC_CORE_REALM"`
	GnoZKGMPort               string        `json:"GNO_ZKGM_PORT"`
	EVMZKGMContract           string        `json:"EVM_ZKGM_CONTRACT"`
	GaloisProverEndpoint      string        `json:"GALOIS_PROVER_ENDPOINT"`
	UnionRPCURL               string        `json:"UNION_RPC_URL"`
	EVMRPCURL                 string        `json:"EVM_RPC_URL"`
	GnoRPCURL                 string        `json:"GNO_RPC_URL"`
	GnoTxIndexerRPCURL        string        `json:"GNO_TX_INDEXER_RPC_URL"`
	VoyagerDatabaseURL        string        `json:"VOYAGER_DATABASE_URL"`
	TrustedMPTPrivateKey      string        `json:"TRUSTED_MPT_PRIVATE_KEY"`
	UnionPrivateKey           string        `json:"UNION_PRIVATE_KEY"`
	EVMPrivateKey             string        `json:"EVM_PRIVATE_KEY"`
	RelayerEmptyPrivateKey    string        `json:"RELAYER_EMPTY_PRIVATE_KEY"`
	RelayerOfflinePrivateKey  string        `json:"RELAYER_OFFLINE_PRIVATE_KEY"`
	RelayerRecoveryPrivateKey string        `json:"RELAYER_RECOVERY_PRIVATE_KEY"`
	GnoPrivateKey             string        `json:"GNO_PRIVATE_KEY"`
	EVMTestERC20              string        `json:"EVM_TEST_ERC20"`
	GnoRecipient              string        `json:"GNO_RECIPIENT"`
	EVMTestAmount             string        `json:"EVM_TEST_AMOUNT"`
	UnionPacketRPCURL         string        `json:"UNION_PACKET_RPC_URL"`
	EVMPacketRPCURL           string        `json:"EVM_PACKET_RPC_URL"`
	GnoPacketRPCURL           string        `json:"GNO_PACKET_RPC_URL"`
	GnoPacketIndexerRPCURL    string        `json:"GNO_PACKET_INDEXER_RPC_URL"`
	ArtifactDir               string        `json:"E2E_ARTIFACT_DIR"`
	StateFile                 string        `json:"E2E_STATE_FILE"`
	VoyagerImage              string        `json:"VOYAGER_IMAGE"`
	VoyagerRustLog            string        `json:"-"`
	CommandTimeout            time.Duration `json:"-"`
	ScenarioTimeout           time.Duration `json:"-"`
	PollInterval              time.Duration `json:"-"`
	EVMRefreshInterval        time.Duration `json:"-"`
	VoyagerStopTimeout        time.Duration `json:"-"`
	CleanupTimeout            time.Duration `json:"-"`
}

// Load reads, defaults, and validates a runner config file.
func Load(path, scriptDir string, lookup func(string) (string, bool), packet bool) (Config, error) {
	get := func(name string) string {
		value, _ := lookup(name)
		return value
	}
	info, err := os.Lstat(path)
	if err != nil {
		return Config{}, fmt.Errorf("cannot inspect runner config: %w", err)
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return Config{}, errors.New("runner config must be a regular non-symlink file")
	}
	if info.Mode().Perm()&0o077 != 0 {
		return Config{}, errors.New("runner config must not be accessible by group or other users")
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return Config{}, fmt.Errorf("cannot read runner config: %w", err)
	}
	cfg := Config{ScriptDir: scriptDir}
	if err := json.Unmarshal(raw, &cfg); err != nil {
		return Config{}, fmt.Errorf("cannot parse runner config: %w", err)
	}
	var pinned struct {
		Runner Config `json:"runner"`
	}
	devnet, err := os.ReadFile(filepath.Join(scriptDir, "devnet.json"))
	if err != nil {
		return Config{}, fmt.Errorf("cannot read devnet config: %w", err)
	}
	if err := json.Unmarshal(devnet, &pinned); err != nil {
		return Config{}, fmt.Errorf("cannot parse devnet config: %w", err)
	}
	if cfg.UnionVoyagerRevision != pinned.Runner.UnionVoyagerRevision ||
		cfg.UnionChainID != pinned.Runner.UnionChainID ||
		cfg.EVMChainID != pinned.Runner.EVMChainID ||
		cfg.GnoChainID != pinned.Runner.GnoChainID {
		return Config{}, errors.New("runner config pinned values do not match devnet.json")
	}
	cfg.RelayerEmptyPrivateKey = pinned.Runner.RelayerEmptyPrivateKey
	cfg.RelayerOfflinePrivateKey = pinned.Runner.RelayerOfflinePrivateKey
	cfg.RelayerRecoveryPrivateKey = pinned.Runner.RelayerRecoveryPrivateKey

	if cfg.ArtifactDir == "" {
		cfg.ArtifactDir = filepath.Join(scriptDir, "channel-e2e-artifacts")
	} else if !filepath.IsAbs(cfg.ArtifactDir) {
		cfg.ArtifactDir = filepath.Join(scriptDir, cfg.ArtifactDir)
	}

	if cfg.StateFile == "" {
		cfg.StateFile = filepath.Join(cfg.ArtifactDir, "state.json")
	} else if !filepath.IsAbs(cfg.StateFile) {
		cfg.StateFile = filepath.Join(scriptDir, cfg.StateFile)
	}

	if cfg.UnionPacketRPCURL == "" {
		cfg.UnionPacketRPCURL = cfg.UnionRPCURL
	}

	if cfg.EVMPacketRPCURL == "" {
		cfg.EVMPacketRPCURL = cfg.EVMRPCURL
	}

	if cfg.GnoPacketRPCURL == "" {
		cfg.GnoPacketRPCURL = cfg.GnoRPCURL
	}

	if cfg.GnoPacketIndexerRPCURL == "" {
		cfg.GnoPacketIndexerRPCURL = cfg.GnoTxIndexerRPCURL
	}

	if cfg.VoyagerImage == "" {
		revision := cfg.UnionVoyagerRevision
		if len(revision) > 12 {
			revision = revision[:12]
		}
		cfg.VoyagerImage = "union-voyager-e2e:" + revision
	}

	cfg.VoyagerRustLog = get("VOYAGER_RUST_LOG")
	if cfg.VoyagerRustLog == "" {
		cfg.VoyagerRustLog = "warn"
	}

	if cfg.CommandTimeout, err = seconds(get("VOYAGER_COMMAND_TIMEOUT_SECONDS"), 120); err != nil {
		return Config{}, errors.New("VOYAGER_COMMAND_TIMEOUT_SECONDS must be a positive integer")
	}
	if cfg.ScenarioTimeout, err = seconds(get("E2E_TIMEOUT_SECONDS"), 900); err != nil {
		return Config{}, errors.New("E2E_TIMEOUT_SECONDS must be a positive integer")
	}
	if cfg.PollInterval, err = nonnegativeSeconds(get("E2E_POLL_SECONDS"), 2); err != nil {
		return Config{}, errors.New("E2E_POLL_SECONDS must be a non-negative integer")
	}
	if cfg.EVMRefreshInterval, err = nonnegativeSeconds(get("VOYAGER_EVM_REFRESH_SECONDS"), 60); err != nil {
		return Config{}, errors.New("VOYAGER_EVM_REFRESH_SECONDS must be a non-negative integer")
	}
	if cfg.VoyagerStopTimeout, err = seconds(get("VOYAGER_STOP_TIMEOUT_SECONDS"), 10); err != nil {
		return Config{}, errors.New("VOYAGER_STOP_TIMEOUT_SECONDS must be a positive integer")
	}
	if cfg.CleanupTimeout, err = seconds(get("E2E_CLEANUP_TIMEOUT_SECONDS"), 30); err != nil ||
		cfg.CleanupTimeout <= cfg.VoyagerStopTimeout {
		return Config{}, errors.New("E2E_CLEANUP_TIMEOUT_SECONDS must exceed VOYAGER_STOP_TIMEOUT_SECONDS")
	}
	if err := cfg.validate(packet); err != nil {
		return Config{}, err
	}
	return cfg, nil
}

func nonnegativeSeconds(raw string, fallback int64) (time.Duration, error) {
	if raw == "0" {
		return 0, nil
	}
	return seconds(raw, fallback)
}

func seconds(raw string, fallback int64) (time.Duration, error) {
	if raw == "" {
		return time.Duration(fallback) * time.Second, nil
	}
	if strings.Trim(raw, "0123456789") != "" {
		return 0, errors.New("invalid seconds")
	}
	duration, err := time.ParseDuration(raw + "s")
	if err != nil || duration <= 0 {
		return 0, errors.New("invalid seconds")
	}
	return duration, nil
}
