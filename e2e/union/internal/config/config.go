package config

import (
	"crypto/sha1"
	"encoding/hex"
	"errors"
	"fmt"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const (
	VoyagerRevision = "9024777562dcaa01613017cd0b958569b85e243e"
	ChannelVersion  = "ucs03-zkgm-0"
)

var (
	addressPattern    = regexp.MustCompile(`^0x[0-9a-fA-F]{40}$`)
	privateKeyPattern = regexp.MustCompile(`^0x[0-9a-fA-F]{64}$`)
	gnoAddressPattern = regexp.MustCompile(`^g1[0-9a-z]{38}$`)
	gnoRealmPattern   = regexp.MustCompile(`^gno\.land/r/[A-Za-z0-9_./-]+$`)
	revisionPattern   = regexp.MustCompile(`^[0-9a-f]{40}$`)
)

// Config is the validated private environment contract for the live runner.
type Config struct {
	ScriptDir              string
	UnionChainID           string
	EVMChainID             string
	GnoChainID             string
	UnionVoyagerDir        string
	UnionVoyagerRevision   string
	UnionIBCHostContract   string
	EVMIBCHandler          string
	EVMMulticall           string
	EVMCometBLSClientImpl  string
	EVMProofLensClientImpl string
	GnoIBCCoreRealm        string
	GnoZKGMPort            string
	EVMZKGMContract        string
	GaloisProverEndpoint   string
	UnionRPCURL            string
	EVMRPCURL              string
	GnoRPCURL              string
	GnoTxIndexerRPCURL     string
	VoyagerDatabaseURL     string
	TrustedMPTPrivateKey   string
	UnionPrivateKey        string
	EVMPrivateKey          string
	GnoPrivateKey          string
	EVMTestERC20           string
	GnoRecipient           string
	EVMTestAmount          string
	EVMPacketRPCURL        string
	GnoPacketRPCURL        string
	GnoPacketIndexerRPCURL string
	ArtifactDir            string
	StateFile              string
	VoyagerImage           string
	VoyagerRustLog         string
	CommandTimeout         time.Duration
	ScenarioTimeout        time.Duration
	PollInterval           time.Duration
	EVMRefreshInterval     time.Duration
	VoyagerStopTimeout     time.Duration
	CleanupTimeout         time.Duration
}

// Load reads, defaults, and validates the environment without external I/O.
func Load(scriptDir string, lookup func(string) (string, bool), packet bool) (Config, error) {
	get := func(name string) string {
		value, _ := lookup(name)
		return value
	}
	cfg := Config{
		ScriptDir:              scriptDir,
		UnionChainID:           get("UNION_CHAIN_ID"),
		EVMChainID:             get("EVM_CHAIN_ID"),
		GnoChainID:             get("GNO_CHAIN_ID"),
		UnionVoyagerDir:        get("UNION_VOYAGER_DIR"),
		UnionVoyagerRevision:   get("UNION_VOYAGER_REVISION"),
		UnionIBCHostContract:   get("UNION_IBC_HOST_CONTRACT"),
		EVMIBCHandler:          get("EVM_IBC_HANDLER"),
		EVMMulticall:           get("EVM_MULTICALL"),
		EVMCometBLSClientImpl:  get("EVM_COMETBLS_CLIENT_IMPL"),
		EVMProofLensClientImpl: get("EVM_PROOF_LENS_CLIENT_IMPL"),
		GnoIBCCoreRealm:        get("GNO_IBC_CORE_REALM"),
		GnoZKGMPort:            get("GNO_ZKGM_PORT"),
		EVMZKGMContract:        get("EVM_ZKGM_CONTRACT"),
		GaloisProverEndpoint:   get("GALOIS_PROVER_ENDPOINT"),
		UnionRPCURL:            get("UNION_RPC_URL"),
		EVMRPCURL:              get("EVM_RPC_URL"),
		GnoRPCURL:              get("GNO_RPC_URL"),
		GnoTxIndexerRPCURL:     get("GNO_TX_INDEXER_RPC_URL"),
		VoyagerDatabaseURL:     get("VOYAGER_DATABASE_URL"),
		TrustedMPTPrivateKey:   get("TRUSTED_MPT_PRIVATE_KEY"),
		UnionPrivateKey:        get("UNION_PRIVATE_KEY"),
		EVMPrivateKey:          get("EVM_PRIVATE_KEY"),
		GnoPrivateKey:          get("GNO_PRIVATE_KEY"),
		EVMTestERC20:           get("EVM_TEST_ERC20"),
		GnoRecipient:           get("GNO_RECIPIENT"),
		EVMTestAmount:          get("EVM_TEST_AMOUNT"),
		EVMPacketRPCURL:        get("EVM_PACKET_RPC_URL"),
		GnoPacketRPCURL:        get("GNO_PACKET_RPC_URL"),
		GnoPacketIndexerRPCURL: get("GNO_PACKET_INDEXER_RPC_URL"),
		ArtifactDir:            get("E2E_ARTIFACT_DIR"),
		StateFile:              get("E2E_STATE_FILE"),
	}

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

	if cfg.EVMPacketRPCURL == "" {
		cfg.EVMPacketRPCURL = cfg.EVMRPCURL
	}

	if cfg.GnoPacketRPCURL == "" {
		cfg.GnoPacketRPCURL = cfg.GnoRPCURL
	}

	if cfg.GnoPacketIndexerRPCURL == "" {
		cfg.GnoPacketIndexerRPCURL = cfg.GnoTxIndexerRPCURL
	}

	cfg.VoyagerImage = get("VOYAGER_IMAGE")
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

	var err error
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

// TopologyFingerprint preserves the fixed-point git blob hash.
func (c Config) TopologyFingerprint() string {
	var payload strings.Builder
	for _, value := range []string{
		c.EVMIBCHandler, c.EVMMulticall, c.EVMZKGMContract,
		c.EVMCometBLSClientImpl, c.EVMProofLensClientImpl,
	} {
		payload.WriteString(strings.ToLower(value))
		payload.WriteByte(0)
	}
	body := payload.String()
	sum := sha1.Sum(fmt.Appendf([]byte{}, "blob %d\x00%s", len(body), body))
	return hex.EncodeToString(sum[:])
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
