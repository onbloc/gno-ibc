package cometbls

import "errors"

func EncodeClientState(cs ClientState) []byte {
	var buf []byte
	buf = pbAppendBytes(buf, 1, []byte(cs.ChainID))
	buf = pbAppendUint64(buf, 2, cs.TrustingPeriod)
	// Field 3 is reserved by Union for the historical unbonding_period slot.
	buf = pbAppendUint64(buf, 4, cs.MaxClockDrift)
	buf = pbAppendMsg(buf, 5, pbEncodeHeight(cs.FrozenHeight))
	buf = pbAppendMsg(buf, 6, pbEncodeHeight(cs.LatestHeight))
	buf = pbAppendBytes(buf, 16, cs.ContractAddress[:])
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
		case 1:
			b, newPos, err := pbDecodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return cs, err
			}
			cs.ChainID = string(b)
		case 2:
			v, newPos, err := pbDecodeVarint(buf, pos)
			pos = newPos
			if err != nil {
				return cs, err
			}
			cs.TrustingPeriod = v
		case 4:
			v, newPos, err := pbDecodeVarint(buf, pos)
			pos = newPos
			if err != nil {
				return cs, err
			}
			cs.MaxClockDrift = v
		case 5:
			b, newPos, err := pbDecodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return cs, err
			}
			cs.FrozenHeight, err = pbDecodeHeight(b)
			if err != nil {
				return cs, err
			}
		case 6:
			b, newPos, err := pbDecodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return cs, err
			}
			cs.LatestHeight, err = pbDecodeHeight(b)
			if err != nil {
				return cs, err
			}
		case 16:
			b, newPos, err := pbDecodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return cs, err
			}
			if len(b) != 32 {
				return cs, errors.New("cometbls: contract address must be 32 bytes")
			}
			copy(cs.ContractAddress[:], b)
		default:
			var err error
			pos, err = pbSkipField(buf, pos, wireType)
			if err != nil {
				return cs, err
			}
		}
	}
	return cs, nil
}
