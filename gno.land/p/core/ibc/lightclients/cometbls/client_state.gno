package cometbls

// clientState field numbers mirror
// union.ibc.lightclients.cometbls.v1.ClientState.
//
// Field 3 is reserved for the historical unbonding_period field.
//
// Field 16 is a Gno extension for the wasmd contract address used in the
// store key prefix.
const (
	csFieldChainID         = 1
	csFieldTrustingPeriod  = 2
	csFieldMaxClockDrift   = 4
	csFieldFrozenHeight    = 5
	csFieldLatestHeight    = 6
	csFieldContractAddress = 16
)

func EncodeClientState(cs ClientState) []byte {
	buf := make([]byte, 0, 64+len(cs.ChainID))
	buf = pbAppendBytes(buf, csFieldChainID, []byte(cs.ChainID))
	buf = pbAppendUint64(buf, csFieldTrustingPeriod, cs.TrustingPeriod)
	buf = pbAppendUint64(buf, csFieldMaxClockDrift, cs.MaxClockDrift)
	buf = pbAppendMsg(buf, csFieldFrozenHeight, pbEncodeHeight(cs.FrozenHeight))
	buf = pbAppendMsg(buf, csFieldLatestHeight, pbEncodeHeight(cs.LatestHeight))
	buf = pbAppendBytes(buf, csFieldContractAddress, cs.ContractAddress[:])
	return buf
}

func DecodeClientState(buf []byte) (ClientState, error) {
	var cs ClientState
	pos := 0
	for pos < len(buf) {
		fieldNum, wireType, newPos, err := pbDecodeTag(buf, pos)
		pos = newPos
		if err != nil {
			return cs, err
		}
		switch fieldNum {
		case csFieldChainID:
			b, newPos, err := pbDecodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return cs, err
			}
			cs.ChainID = string(b)
		case csFieldTrustingPeriod:
			v, newPos, err := pbDecodeVarint(buf, pos)
			pos = newPos
			if err != nil {
				return cs, err
			}
			cs.TrustingPeriod = v
		case csFieldMaxClockDrift:
			v, newPos, err := pbDecodeVarint(buf, pos)
			pos = newPos
			if err != nil {
				return cs, err
			}
			cs.MaxClockDrift = v
		case csFieldFrozenHeight:
			b, newPos, err := pbDecodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return cs, err
			}
			cs.FrozenHeight, err = pbDecodeHeight(b)
			if err != nil {
				return cs, err
			}
		case csFieldLatestHeight:
			b, newPos, err := pbDecodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return cs, err
			}
			cs.LatestHeight, err = pbDecodeHeight(b)
			if err != nil {
				return cs, err
			}
		case csFieldContractAddress:
			b, newPos, err := pbDecodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return cs, err
			}
			addr, err := toBytes32(b, "contract address")
			if err != nil {
				return cs, err
			}
			cs.ContractAddress = H256(addr)
		default:
			newPos, err := pbSkipField(buf, pos, wireType)
			pos = newPos
			if err != nil {
				return cs, err
			}
		}
	}
	return cs, nil
}
