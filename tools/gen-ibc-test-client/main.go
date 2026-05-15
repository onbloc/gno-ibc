// gen-ibc-test-client prints deterministic values used by
// gno.land/r/core/ibc/v1/core/gnokey_tx_queries.md.
//
// Usage:
//
//	cd tools/gen-ibc-test-client && go run .
package main

import (
	"bytes"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"strings"

	"golang.org/x/crypto/sha3"
)

const (
	realmPath = "gno.land/r/core/ibc/v1/core"

	devnetChainID     = "union-devnet-1337"
	devnetHeight      = uint64(3405691582)
	devnetTimeSeconds = uint64(1732205251)
	devnetTimeNanos   = uint64(998131342)
	proofHeight       = devnetHeight - 1

	clientID                 = uint32(1)
	counterpartyClientID     = uint32(99)
	connectionID             = uint32(1)
	counterpartyConnectionID = uint32(77)
	channelID                = uint32(1)
	counterpartyChannelID    = uint32(2)
	portID                   = "g1TODO_PORT"
	counterpartyPortID       = "g1TODO_PORT"
	version                  = "ucs03-zkgm-0"

	clientType                = "cometbls"
	trustingPeriod            = 10 * 365 * 24 * 3600 * 1_000_000_000
	updatedTrustPeriod        = trustingPeriod
	maxClockDrift             = 10 * 1_000_000_000
	frozenHeight       uint64 = 0
)

var (
	devnetAppHash         = mustHex("EE7E3E58F98AC95D63CE93B270981DF3EE54CA367F8D521ED1F444717595CD36")
	devnetValidatorsHash  = mustHex("20DDFE7A0F75C65D876316091ECCD494A54A2BB324C872015F73E528D53CB9C4")
	contractAddress       = mustHex("0cf2ffe8f45a20514018173d3007644817a9767dc0fbdb246696fd9c261ce3bc")
	z35Root               = mustHex("e86ffd094be9dde9459f6c88333e663785f4f88adc7f3f91a55e166a3cfa89d1")
	z35ConnectionTryProof = mustHex("0add010ada010a2005f3c8eef62e74b10b7ee910fcc73c8358000f692d9ce2341a989e008e45b35d1220ff4fb67348c16e70c898c7cf43c460a684bc900d2b41e5a24ef6dcb2945860341a0d08011000180120012a03000202222b08011204020402201a212075fa5fd43f02dfcbcb0d9d1091ef50e8878f62e295bc58e670579fff822312c7222b08011204040802201a21208d76df01234dbce513db8913f231e2ad27b505ea2641f38079cd7d4e79136417222b08011204061002201a212023a5b9a52805603bebfa4b8d9153918f6bb74d8c190a95fb17651f3c228e15070a360a340a0369626312203b0e2fd01a894dc222e13ce7f5cfb397176764abe6376a7b7e63b2dfb9952a981a0b08011000180120012a0100")
	z35ChannelTryProof    = mustHex("0ad9010ad6010a2088601476d11616a71c5be67555bd1dff4b1cbf21533d2669b768b61518cfe1c31220fa3c11d224a164cd0beca2b6756128dc1531714a75813e9c2b5840bd8f2a83471a0d08011000180120012a0300020222290801122502040220fc911eec9c73d4884020ebb7d0173bfb0739579e4e64c63585a1e61466f11fc120222908011225040802209581d4d357f7e8f0d772870c181754178423903f17e5a481ecf11eb2688ff79e20222b08011204061002201a212023a5b9a52805603bebfa4b8d9153918f6bb74d8c190a95fb17651f3c228e15070a360a340a0369626312203b0e2fd01a894dc222e13ce7f5cfb397176764abe6376a7b7e63b2dfb9952a981a0b08011000180120012a0100")
	devnetZKP             = mustHex("03CF56142A1E03D2445A82100FEAF70C1CD95A731ED85792AFFF5792EC0BDD2108991BB56F9043A269F88903DE616A9AB99A3C5AB778E566744B060456C5616C06BCE7F1930421768C2CBD79F88D08EC3A52D7C9A867064E973064385E9C945E02951190DD7CE1662546733DD540188C96E608CA750FEF36B39E2577833634C70AE6F1A6D00DC6C21446AAF285EF35D944E8782B131300574F9A889C7E708A2325E9A78013BBE869D38B19C602DAF69644C77D177E99ED76398BCEE13C61FDBF2E178A5BA028A36033E54D1D9A0071E82E04079A5305347EBAC6D66F6EBFA48B1DA1BF9DC5A51EFA292E1DC7B85D26F18422EB386C48CA75434039764448BB96268DDC2CF683DDCA4BD83DF21C5631CF784375EEBE77EABC2DE77886BF1D48392C9C52E063B4A7131EAB9ABBA12A9F26888BC37366D41AC7D4BAC0BF6755ACB009BF9F36F380B6D0EEAABF066503A1B6E01DCC965D968D7694E01B1755E6BDD21C7A80B41682748F9B7151714BE34AA79AAD48BBB2A84525F6CDF812658C6E4F")
)

func main() {
	printHeader()
	printCreateClient()
	printUpdateClient()
	printConnectionOpenInit()
	printConnectionOpenTry()
	printConnectionOpenAck()
	printConnectionOpenConfirm()
	printChannelOpenInit()
	printChannelOpenTry()
	printChannelOpenAck()
	printChannelOpenConfirm()
}

func printHeader() {
	fmt.Printf("CORE_PATH=%s\n", realmPath)
	fmt.Printf("PROOF_HEIGHT=%d\n", proofHeight)
	fmt.Printf("PORT_ID=%q\n", portID)
	fmt.Printf("COUNTERPARTY_PORT_ID=%q\n", counterpartyPortID)
	fmt.Printf("VERSION=%q\n\n", version)
}

func printCreateClient() {
	clientStateHex, consensusStateHex := createClientArgs()
	printSection("1", "CreateClient", "createClientArgs, clientStatePath, consensusStatePath")
	fmt.Printf("CLIENT_TYPE=%s\n", clientType)
	fmt.Printf("CLIENT_STATE_HEX=%s\n", clientStateHex)
	fmt.Printf("CONSENSUS_STATE_HEX=%s\n", consensusStateHex)
	printCreateClientRunScript(clientStateHex, consensusStateHex)
	printCommit("client state", clientStatePath(clientID), keccak256(mustHex(clientStateHex)))
	printCommit("consensus state", consensusStatePath(clientID, proofHeight), keccak256(mustHex(consensusStateHex)))
}

func printCreateClientRunScript(clientStateHex, consensusStateHex string) {
	fmt.Printf("RUN_SCRIPT=cat >/tmp/create_client.gno <<'EOF'\n")
	fmt.Printf("package main\n\n")
	fmt.Printf("import (\n")
	fmt.Printf("\t\"encoding/hex\"\n\n")
	fmt.Printf("\tcore \"gno.land/r/core/ibc/v1/core\"\n")
	fmt.Printf("\tcometbls \"gno.land/r/core/ibc/v1/lightclients/cometbls\"\n")
	fmt.Printf(")\n\n")
	fmt.Printf("func main() {\n")
	fmt.Printf("\tclientState, err := hex.DecodeString(\"%s\")\n", clientStateHex)
	fmt.Printf("\tif err != nil {\n")
	fmt.Printf("\t\tpanic(err)\n")
	fmt.Printf("\t}\n\n")
	fmt.Printf("\tconsensusState, err := hex.DecodeString(\"%s\")\n", consensusStateHex)
	fmt.Printf("\tif err != nil {\n")
	fmt.Printf("\t\tpanic(err)\n")
	fmt.Printf("\t}\n\n")
	fmt.Printf("\tclientID := core.CreateClient(cross, core.MsgCreateClient{\n")
	fmt.Printf("\t\tClientType:          cometbls.ClientType,\n")
	fmt.Printf("\t\tClientStateBytes:    clientState,\n")
	fmt.Printf("\t\tConsensusStateBytes: consensusState,\n")
	fmt.Printf("\t})\n")
	fmt.Printf("\tprintln(\"CreateClient\", clientID.String())\n")
	fmt.Printf("}\n")
	fmt.Printf("EOF\n")
	fmt.Printf("gnokey maketx run -gas-fee 1000000ugnot -gas-wanted 50000000 -broadcast -chainid dev -remote tcp://127.0.0.1:26657 test1 /tmp/create_client.gno\n")
}

func printUpdateClient() {
	headerHex := updateClientArgs()
	updatedClientState := encodeClientState(devnetChainID, updatedTrustPeriod, maxClockDrift, frozenHeight, devnetHeight)
	updatedConsensusState := encodeConsensusState(devnetTimeSeconds*1_000_000_000+devnetTimeNanos, devnetAppHash, devnetValidatorsHash)

	printSection("2", "UpdateClient", "updateClientArgs, encodeHeader, encodeClientState, encodeConsensusState")
	fmt.Printf("CLIENT_ID=%d\n", clientID)
	fmt.Printf("CLIENT_MESSAGE_HEX=%s\n", headerHex)
	printCommit("updated client state", clientStatePath(clientID), keccak256(updatedClientState))
	printCommit("updated consensus state", consensusStatePath(clientID, devnetHeight), keccak256(updatedConsensusState))
}

func printConnectionOpenInit() {
	printSection("3", "ConnectionOpenInit", "connectionOpenInitArgs, encodeConnection, connectionPath")
	c := connection{State: 1, ClientID: clientID, CounterpartyClientID: counterpartyClientID}
	fmt.Printf("CLIENT_ID=%d\n", clientID)
	fmt.Printf("COUNTERPARTY_CLIENT_ID=%d\n", counterpartyClientID)
	printCommit("connection init", connectionPath(connectionID), keccak256(encodeConnection(c)))
}

func printConnectionOpenTry() {
	printSection("4", "ConnectionOpenTry", "connectionOpenTryArgs, z35ConnectionTryProofHex, encodeConnection, connectionPath")
	args := connectionOpenTryArgs()
	fmt.Printf("CLIENT_ID=%d\n", args.ClientID)
	fmt.Printf("COUNTERPARTY_CLIENT_ID=%d\n", args.CounterpartyClientID)
	fmt.Printf("COUNTERPARTY_CONNECTION_ID=%d\n", args.CounterpartyConnectionID)
	fmt.Printf("PROOF_INIT_HEX=%s\n", args.ProofHex)
	fmt.Printf("PROOF_HEIGHT=%d\n", args.ProofHeight)
	c := connection{State: 2, ClientID: clientID, CounterpartyClientID: counterpartyClientID, CounterpartyConnectionID: args.CounterpartyConnectionID}
	printCommit("connection try", connectionPath(2), keccak256(encodeConnection(c)))
}

func printConnectionOpenAck() {
	printSection("5", "ConnectionOpenAck", "connectionOpenAckArgs, z35ConnectionTryProofHex, encodeConnection, connectionPath")
	args := connectionOpenAckArgs()
	fmt.Printf("CONNECTION_ID=%d\n", args.ConnectionID)
	fmt.Printf("COUNTERPARTY_CONNECTION_ID=%d\n", args.CounterpartyConnectionID)
	fmt.Printf("PROOF_TRY_HEX=%s\n", args.ProofHex)
	fmt.Printf("PROOF_HEIGHT=%d\n", args.ProofHeight)
	c := connection{State: 3, ClientID: clientID, CounterpartyClientID: counterpartyClientID, CounterpartyConnectionID: args.CounterpartyConnectionID}
	printCommit("connection open", connectionPath(connectionID), keccak256(encodeConnection(c)))
}

func printConnectionOpenConfirm() {
	printSection("6", "ConnectionOpenConfirm", "connectionOpenConfirmArgs, encodeConnection, connectionPath")
	args := connectionOpenConfirmArgs()
	fmt.Printf("CONNECTION_ID=%d\n", args.ConnectionID)
	fmt.Printf("PROOF_ACK_HEX=%s\n", args.ProofHex)
	fmt.Printf("PROOF_HEIGHT=%d\n", args.ProofHeight)
	c := connection{State: 3, ClientID: clientID, CounterpartyClientID: counterpartyClientID, CounterpartyConnectionID: connectionID}
	printCommit("connection confirm/open", connectionPath(2), keccak256(encodeConnection(c)))
}

func printChannelOpenInit() {
	printSection("7", "ChannelOpenInit", "channelOpenInitArgs, encodeChannel, channelPath")
	args := channelOpenInitArgs()
	fmt.Printf("PORT_ID=%s\n", args.PortID)
	fmt.Printf("COUNTERPARTY_PORT_ID=%s\n", args.CounterpartyPortID)
	fmt.Printf("CONNECTION_ID=%d\n", args.ConnectionID)
	fmt.Printf("VERSION=%s\n", args.Version)
	ch := channel{State: 1, ConnectionID: args.ConnectionID, CounterpartyPortID: []byte(args.CounterpartyPortID), Version: args.Version}
	printCommit("channel init", channelPath(channelID), keccak256(encodeChannel(ch)))
}

func printChannelOpenTry() {
	printSection("8", "ChannelOpenTry", "channelOpenTryArgs, z35ChannelTryProofHex, encodeChannel, channelPath")
	args := channelOpenTryArgs()
	fmt.Printf("PORT_ID=%s\n", args.PortID)
	fmt.Printf("CONNECTION_ID=%d\n", args.ConnectionID)
	fmt.Printf("COUNTERPARTY_PORT_ID=%s\n", args.CounterpartyPortID)
	fmt.Printf("COUNTERPARTY_CHANNEL_ID=%d\n", args.CounterpartyChannelID)
	fmt.Printf("VERSION=%s\n", args.Version)
	fmt.Printf("COUNTERPARTY_VERSION=%s\n", args.CounterpartyVersion)
	fmt.Printf("PROOF_INIT_HEX=%s\n", args.ProofHex)
	fmt.Printf("PROOF_HEIGHT=%d\n", args.ProofHeight)
	ch := channel{State: 2, ConnectionID: args.ConnectionID, CounterpartyChannelID: args.CounterpartyChannelID, CounterpartyPortID: []byte(args.CounterpartyPortID), Version: args.Version}
	printCommit("channel try", channelPath(2), keccak256(encodeChannel(ch)))
}

func printChannelOpenAck() {
	printSection("9", "ChannelOpenAck", "channelOpenAckArgs, z35ChannelTryProofHex, encodeChannel, channelPath")
	args := channelOpenAckArgs()
	fmt.Printf("CHANNEL_ID=%d\n", args.ChannelID)
	fmt.Printf("COUNTERPARTY_VERSION=%s\n", args.CounterpartyVersion)
	fmt.Printf("COUNTERPARTY_CHANNEL_ID=%d\n", args.CounterpartyChannelID)
	fmt.Printf("PROOF_TRY_HEX=%s\n", args.ProofHex)
	fmt.Printf("PROOF_HEIGHT=%d\n", args.ProofHeight)
	ch := channel{State: 3, ConnectionID: connectionID, CounterpartyChannelID: args.CounterpartyChannelID, CounterpartyPortID: []byte(counterpartyPortID), Version: args.CounterpartyVersion}
	printCommit("channel open", channelPath(channelID), keccak256(encodeChannel(ch)))
}

func printChannelOpenConfirm() {
	printSection("10", "ChannelOpenConfirm", "channelOpenConfirmArgs, encodeChannel, channelPath")
	args := channelOpenConfirmArgs()
	fmt.Printf("CHANNEL_ID=%d\n", args.ChannelID)
	fmt.Printf("PROOF_ACK_HEX=%s\n", args.ProofHex)
	fmt.Printf("PROOF_HEIGHT=%d\n", args.ProofHeight)
	ch := channel{State: 3, ConnectionID: connectionID, CounterpartyChannelID: channelID, CounterpartyPortID: []byte(counterpartyPortID), Version: version}
	printCommit("channel confirm/open", channelPath(2), keccak256(encodeChannel(ch)))
}

func printSection(n, name, source string) {
	fmt.Printf("\n[%s] %s\n", n, name)
	fmt.Printf("source=%s\n", source)
}

func printCommit(label string, key, value [32]byte) {
	paramsKey := fmt.Sprintf("vm:%s:%s", realmPath, hex.EncodeToString(key[:]))
	proofData := hex.EncodeToString([]byte("/pv/" + paramsKey))
	fmt.Printf("%s.params_key=%s\n", label, paramsKey)
	fmt.Printf("%s.proof_data=0x%s\n", label, strings.ToUpper(proofData))
	fmt.Printf("%s.expected_value=%s\n", label, hex.EncodeToString(value[:]))
	fmt.Printf("%s.abci_query=http://localhost:26657/abci_query?path=%%22.store/main/key%%22&data=0x%s&prove=true\n", label, strings.ToUpper(proofData))
}

func createClientArgs() (clientStateHex, consensusStateHex string) {
	clientState := encodeClientState(devnetChainID, trustingPeriod, maxClockDrift, frozenHeight, proofHeight)
	consensusState := encodeConsensusState((devnetTimeSeconds-1000)*1_000_000_000, devnetAppHash, devnetValidatorsHash)
	return hex.EncodeToString(clientState), hex.EncodeToString(consensusState)
}

func updateClientArgs() string {
	return hex.EncodeToString(encodeHeader(header{
		Height:             devnetHeight,
		TimeSeconds:        devnetTimeSeconds,
		TimeNanos:          devnetTimeNanos,
		ValidatorsHash:     devnetValidatorsHash,
		NextValidatorsHash: devnetValidatorsHash,
		AppHash:            devnetAppHash,
		TrustedHeight:      proofHeight,
		ZKP:                devnetZKP,
	}))
}

type proofArgs struct {
	ClientID                 uint32
	CounterpartyClientID     uint32
	ConnectionID             uint32
	CounterpartyConnectionID uint32
	ChannelID                uint32
	CounterpartyChannelID    uint32
	PortID                   string
	CounterpartyPortID       string
	Version                  string
	CounterpartyVersion      string
	ProofHex                 string
	ProofHeight              uint64
}

func connectionOpenTryArgs() proofArgs {
	return proofArgs{
		ClientID:                 clientID,
		CounterpartyClientID:     counterpartyClientID,
		CounterpartyConnectionID: connectionID,
		ProofHex:                 z35ConnectionTryProofHex(),
		ProofHeight:              proofHeight,
	}
}

func connectionOpenAckArgs() proofArgs {
	return proofArgs{
		ConnectionID:             connectionID,
		CounterpartyConnectionID: counterpartyConnectionID,
		ProofHex:                 z35ConnectionTryProofHex(),
		ProofHeight:              proofHeight,
	}
}

func connectionOpenConfirmArgs() proofArgs {
	return proofArgs{
		ConnectionID: connectionID + 1,
		ProofHex:     "REPLACE_WITH_CONNECTION_OPEN_PROOF_HEX",
		ProofHeight:  proofHeight,
	}
}

func channelOpenInitArgs() proofArgs {
	return proofArgs{
		PortID:             portID,
		CounterpartyPortID: counterpartyPortID,
		ConnectionID:       connectionID,
		Version:            version,
	}
}

func channelOpenTryArgs() proofArgs {
	return proofArgs{
		PortID:                portID,
		ConnectionID:          connectionID,
		CounterpartyPortID:    counterpartyPortID,
		CounterpartyChannelID: counterpartyChannelID,
		Version:               version,
		CounterpartyVersion:   version,
		ProofHex:              z35ChannelTryProofHex(),
		ProofHeight:           proofHeight,
	}
}

func channelOpenAckArgs() proofArgs {
	return proofArgs{
		ChannelID:             channelID,
		CounterpartyVersion:   version,
		CounterpartyChannelID: counterpartyChannelID,
		ProofHex:              z35ChannelTryProofHex(),
		ProofHeight:           proofHeight,
	}
}

func channelOpenConfirmArgs() proofArgs {
	return proofArgs{
		ChannelID:   channelID + 1,
		ProofHex:    "REPLACE_WITH_CHANNEL_OPEN_PROOF_HEX",
		ProofHeight: proofHeight,
	}
}

func z35ConnectionTryProofHex() string {
	return hex.EncodeToString(z35ConnectionTryProof)
}

func z35ChannelTryProofHex() string {
	return hex.EncodeToString(z35ChannelTryProof)
}

func clientStatePath(clientId uint32) [32]byte {
	return keccak256(bytes.Join([][]byte{slot(0), u32ToH256(clientId)}, nil))
}

func consensusStatePath(clientId uint32, height uint64) [32]byte {
	return keccak256(bytes.Join([][]byte{slot(1), u32ToH256(clientId), u64ToH256(height)}, nil))
}

func connectionPath(connectionId uint32) [32]byte {
	return keccak256(bytes.Join([][]byte{slot(2), u32ToH256(connectionId)}, nil))
}

func channelPath(channelId uint32) [32]byte {
	return keccak256(bytes.Join([][]byte{slot(3), u32ToH256(channelId)}, nil))
}

func slot(n uint32) []byte {
	var out [32]byte
	binary.BigEndian.PutUint32(out[28:], n)
	return out[:]
}

func u32ToH256(n uint32) []byte {
	var out [32]byte
	binary.BigEndian.PutUint32(out[28:], n)
	return out[:]
}

func u64ToH256(n uint64) []byte {
	var out [32]byte
	binary.BigEndian.PutUint64(out[24:], n)
	return out[:]
}

func keccak256(data []byte) [32]byte {
	h := sha3.NewLegacyKeccak256()
	h.Write(data)
	var out [32]byte
	copy(out[:], h.Sum(nil))
	return out
}

func encodeClientState(chainID string, trustingPeriod, maxClockDrift, frozenHeight, latestHeight uint64) []byte {
	var chainIDBytes [32]byte
	copy(chainIDBytes[:], []byte(chainID))
	return abiEncodeStatic(chainIDBytes[:], word(trustingPeriod), word(maxClockDrift), word(frozenHeight), word(latestHeight), bytes32(contractAddress))
}

func encodeConsensusState(timestamp uint64, appHash, nextValidatorsHash []byte) []byte {
	return abiEncodeStatic(word(timestamp), bytes32(appHash), bytes32(nextValidatorsHash))
}

type header struct {
	Height             uint64
	TimeSeconds        uint64
	TimeNanos          uint64
	ValidatorsHash     []byte
	NextValidatorsHash []byte
	AppHash            []byte
	TrustedHeight      uint64
	ZKP                []byte
}

func encodeHeader(h header) []byte {
	return abiEncode([]abiValue{
		staticValue(word(h.Height)),
		staticValue(word(h.TimeSeconds)),
		staticValue(word(h.TimeNanos)),
		staticValue(bytes32(h.ValidatorsHash)),
		staticValue(bytes32(h.NextValidatorsHash)),
		staticValue(bytes32(h.AppHash)),
		staticValue(word(h.TrustedHeight)),
		dynamicValue(abiBytes(h.ZKP)),
	})
}

type connection struct {
	State                    uint8
	ClientID                 uint32
	CounterpartyClientID     uint32
	CounterpartyConnectionID uint32
}

func encodeConnection(c connection) []byte {
	return abiEncodeStatic(word(uint64(c.State)), word(uint64(c.ClientID)), word(uint64(c.CounterpartyClientID)), word(uint64(c.CounterpartyConnectionID)))
}

type channel struct {
	State                 uint8
	ConnectionID          uint32
	CounterpartyChannelID uint32
	CounterpartyPortID    []byte
	Version               string
}

func encodeChannel(c channel) []byte {
	return abiEncode([]abiValue{
		staticValue(word(uint64(c.State))),
		staticValue(word(uint64(c.ConnectionID))),
		staticValue(word(uint64(c.CounterpartyChannelID))),
		dynamicValue(abiBytes(c.CounterpartyPortID)),
		dynamicValue(abiString(c.Version)),
	})
}

type abiValue struct {
	dynamic bool
	data    []byte
}

func staticValue(data []byte) abiValue {
	return abiValue{data: data}
}

func dynamicValue(data []byte) abiValue {
	return abiValue{dynamic: true, data: data}
}

func abiEncode(values []abiValue) []byte {
	head := make([]byte, 0, len(values)*32)
	tail := make([]byte, 0)
	headLen := len(values) * 32
	for _, v := range values {
		if v.dynamic {
			head = append(head, word(uint64(headLen+len(tail)))...)
			tail = append(tail, v.data...)
			continue
		}
		head = append(head, v.data...)
	}
	return append(head, tail...)
}

func abiEncodeStatic(words ...[]byte) []byte {
	return bytes.Join(words, nil)
}

func abiBytes(bz []byte) []byte {
	pad := (32 - len(bz)%32) % 32
	out := make([]byte, 0, 32+len(bz)+pad)
	out = append(out, word(uint64(len(bz)))...)
	out = append(out, bz...)
	if pad > 0 {
		out = append(out, make([]byte, pad)...)
	}
	return out
}

func abiString(s string) []byte {
	return abiBytes([]byte(s))
}

func word(n uint64) []byte {
	var out [32]byte
	binary.BigEndian.PutUint64(out[24:], n)
	return out[:]
}

func bytes32(bz []byte) []byte {
	if len(bz) != 32 {
		panic(fmt.Sprintf("expected 32 bytes, got %d", len(bz)))
	}
	out := make([]byte, 32)
	copy(out, bz)
	return out
}

func mustHex(s string) []byte {
	bz, err := hex.DecodeString(strings.ToLower(s))
	if err != nil {
		panic(err)
	}
	return bz
}
