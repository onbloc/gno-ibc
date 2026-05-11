package cometbls

import (
	"errors"

	"gno.land/p/aib/ics23"
)

// DecodeProofs decodes a protobuf-encoded MerkleProof (repeated CommitmentProof field 1).
func DecodeProofs(buf []byte) ([]ics23.CommitmentProof, error) {
	var out []ics23.CommitmentProof
	pos := 0
	for pos < len(buf) {
		fieldNum, wireType, newPos, err := pbDecodeTag(buf, pos)
		if err != nil {
			return nil, err
		}
		pos = newPos
		if wireType != 2 {
			pos, err = pbSkipField(buf, pos, wireType)
			if err != nil {
				return nil, err
			}
			continue
		}
		b, newPos, err := pbDecodeBytes(buf, pos)
		if err != nil {
			return nil, err
		}
		pos = newPos
		if fieldNum != 1 {
			continue
		}
		cp, err := pbDecodeCommitmentProof(b)
		if err != nil {
			return nil, err
		}
		out = append(out, cp)
	}
	return out, nil
}

func pbDecodeCommitmentProof(buf []byte) (ics23.CommitmentProof, error) {
	pos := 0
	for pos < len(buf) {
		fieldNum, wireType, newPos, err := pbDecodeTag(buf, pos)
		if err != nil {
			return nil, err
		}
		pos = newPos
		if wireType != 2 {
			pos, err = pbSkipField(buf, pos, wireType)
			if err != nil {
				return nil, err
			}
			continue
		}
		b, newPos, err := pbDecodeBytes(buf, pos)
		if err != nil {
			return nil, err
		}
		pos = newPos
		switch fieldNum {
		case 1:
			ep, err := pbDecodeExistenceProof(b)
			if err != nil {
				return nil, err
			}
			return ics23.CommitmentProof_Exist{Exist: ep}, nil
		case 2:
			nep, err := pbDecodeNonExistenceProof(b)
			if err != nil {
				return nil, err
			}
			return ics23.CommitmentProof_Nonexist{Nonexist: nep}, nil
		}
	}
	return nil, errors.New("cometbls: empty commitment proof")
}

func pbDecodeExistenceProof(buf []byte) (*ics23.ExistenceProof, error) {
	ep := &ics23.ExistenceProof{Path: make([]*ics23.InnerOp, 0, 32)}
	pos := 0
	for pos < len(buf) {
		fieldNum, wireType, newPos, err := pbDecodeTag(buf, pos)
		if err != nil {
			return nil, err
		}
		pos = newPos
		switch {
		case (fieldNum == 1 || fieldNum == 2) && wireType == 2:
			b, newPos, err := pbDecodeBytes(buf, pos)
			if err != nil {
				return nil, err
			}
			pos = newPos
			if fieldNum == 1 {
				ep.Key = b
			} else {
				ep.Value = b
			}
		case fieldNum == 3 && wireType == 2:
			b, newPos, err := pbDecodeBytes(buf, pos)
			if err != nil {
				return nil, err
			}
			pos = newPos
			ep.Leaf, err = pbDecodeLeafOp(b)
			if err != nil {
				return nil, err
			}
		case fieldNum == 4 && wireType == 2:
			b, newPos, err := pbDecodeBytes(buf, pos)
			if err != nil {
				return nil, err
			}
			pos = newPos
			inner, err := pbDecodeInnerOp(b)
			if err != nil {
				return nil, err
			}
			ep.Path = append(ep.Path, inner)
		default:
			pos, err = pbSkipField(buf, pos, wireType)
			if err != nil {
				return nil, err
			}
		}
	}
	return ep, nil
}

func pbDecodeLeafOp(buf []byte) (*ics23.LeafOp, error) {
	lop := &ics23.LeafOp{}
	pos := 0
	for pos < len(buf) {
		fieldNum, wireType, newPos, err := pbDecodeTag(buf, pos)
		if err != nil {
			return nil, err
		}
		pos = newPos
		switch {
		case fieldNum >= 1 && fieldNum <= 4 && wireType == 0:
			v, newPos, err := pbDecodeVarint(buf, pos)
			if err != nil {
				return nil, err
			}
			pos = newPos
			switch fieldNum {
			case 1:
				lop.Hash = ics23.HashOp(v)
			case 2:
				lop.PrehashKey = ics23.HashOp(v)
			case 3:
				lop.PrehashValue = ics23.HashOp(v)
			case 4:
				lop.Length = ics23.LengthOp(v)
			}
		case fieldNum == 5 && wireType == 2:
			b, newPos, err := pbDecodeBytes(buf, pos)
			if err != nil {
				return nil, err
			}
			pos = newPos
			lop.Prefix = b
		default:
			pos, err = pbSkipField(buf, pos, wireType)
			if err != nil {
				return nil, err
			}
		}
	}
	return lop, nil
}

func pbDecodeInnerOp(buf []byte) (*ics23.InnerOp, error) {
	iop := &ics23.InnerOp{}
	pos := 0
	for pos < len(buf) {
		fieldNum, wireType, newPos, err := pbDecodeTag(buf, pos)
		if err != nil {
			return nil, err
		}
		pos = newPos
		switch {
		case fieldNum == 1 && wireType == 0:
			v, newPos, err := pbDecodeVarint(buf, pos)
			if err != nil {
				return nil, err
			}
			pos = newPos
			iop.Hash = ics23.HashOp(v)
		case (fieldNum == 2 || fieldNum == 3) && wireType == 2:
			b, newPos, err := pbDecodeBytes(buf, pos)
			if err != nil {
				return nil, err
			}
			pos = newPos
			if fieldNum == 2 {
				iop.Prefix = b
			} else {
				iop.Suffix = b
			}
		default:
			pos, err = pbSkipField(buf, pos, wireType)
			if err != nil {
				return nil, err
			}
		}
	}
	return iop, nil
}

func pbDecodeNonExistenceProof(buf []byte) (*ics23.NonExistenceProof, error) {
	nep := &ics23.NonExistenceProof{}
	pos := 0
	for pos < len(buf) {
		fieldNum, wireType, newPos, err := pbDecodeTag(buf, pos)
		if err != nil {
			return nil, err
		}
		pos = newPos
		if wireType != 2 {
			pos, err = pbSkipField(buf, pos, wireType)
			if err != nil {
				return nil, err
			}
			continue
		}
		b, newPos, err := pbDecodeBytes(buf, pos)
		if err != nil {
			return nil, err
		}
		pos = newPos
		switch fieldNum {
		case 1:
			nep.Key = b
		case 2:
			ep, err := pbDecodeExistenceProof(b)
			if err != nil {
				return nil, err
			}
			nep.Left = ep
		case 3:
			ep, err := pbDecodeExistenceProof(b)
			if err != nil {
				return nil, err
			}
			nep.Right = ep
		}
	}
	return nep, nil
}
