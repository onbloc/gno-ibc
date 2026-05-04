package zkgm

import (
	"errors"

	u256 "gno.land/p/gnoswap/uint256"
)

// ErrChannelPathFull is returned by UpdateChannelPath when the path can no
// longer hold another hop.
var ErrChannelPathFull = errors.New("zkgm: channel path is full")

const (
	channelIDMask  = uint64(0xFFFFFFFF)
	channelSlotBit = uint(32)
	maxHopIndex    = 7
)

// channelIDMaskU256 is shared across functions; bitwise ops here only read it.
var channelIDMaskU256 = u256.NewUint(channelIDMask)

// DequeueChannelFromPath pops the lowest 32-bit channel slot off the path and
// shifts the remainder right. Returns the truncated path and the popped
// channel ID. A channel ID of 0 means the path was empty.
//
// Mirrors `dequeue_channel_from_path` at
// union/cosmwasm/app/ucs03-zkgm/src/contract.rs:3333.
func DequeueChannelFromPath(path *u256.Uint) (*u256.Uint, uint32) {
	if path.IsZero() {
		return u256.Zero(), 0
	}
	newPath := new(u256.Uint).Rsh(path, channelSlotBit)
	low := new(u256.Uint).And(path, channelIDMaskU256)
	return newPath, uint32(low.Uint64())
}

// PopChannelFromPath extracts the highest non-zero 32-bit channel slot from
// the path, returning the path with that slot cleared and the popped channel
// ID. A channel ID of 0 means the path was empty.
//
// Mirrors `pop_channel_from_path` at contract.rs:3351.
func PopChannelFromPath(path *u256.Uint) (*u256.Uint, uint32) {
	if path.IsZero() {
		return u256.Zero(), 0
	}
	highestIndex := uint(path.BitLen()-1) / channelSlotBit
	channelID := GetChannelFromPath(path, int(highestIndex))

	slotMask := new(u256.Uint).Lsh(channelIDMaskU256, highestIndex*channelSlotBit)
	basePath := new(u256.Uint).AndNot(path, slotMask)
	return basePath, channelID
}

// UpdateChannelPath appends nextChannelID to the path at the next free
// 32-bit slot. Returns ErrChannelPathFull when the path can no longer hold
// another hop.
//
// Mirrors `update_channel_path` at contract.rs:3365.
func UpdateChannelPath(path *u256.Uint, nextChannelID uint32) (*u256.Uint, error) {
	if path.IsZero() {
		return u256.NewUint(uint64(nextChannelID)), nil
	}
	nextHopIndex := uint(path.BitLen())/channelSlotBit + 1
	if nextHopIndex > maxHopIndex {
		return nil, ErrChannelPathFull
	}
	slot := MakePathFromChannel(nextChannelID, int(nextHopIndex))
	return new(u256.Uint).Or(slot, path), nil
}

// GetChannelFromPath returns the channel ID stored at the given 32-bit slot
// (0-indexed from the LSB). Returns 0 if the slot is empty or out of range.
//
// Mirrors `get_channel_from_path` at contract.rs:3380.
func GetChannelFromPath(path *u256.Uint, index int) uint32 {
	if index < 0 {
		return 0
	}
	shifted := new(u256.Uint).Rsh(path, uint(index)*channelSlotBit)
	masked := new(u256.Uint).And(shifted, channelIDMaskU256)
	return uint32(masked.Uint64())
}

// MakePathFromChannel builds a path containing channelID at the given slot.
//
// Mirrors `make_path_from_channel` at contract.rs:3386.
func MakePathFromChannel(channelID uint32, index int) *u256.Uint {
	if index < 0 {
		return u256.Zero()
	}
	return new(u256.Uint).Lsh(u256.NewUint(uint64(channelID)), uint(index)*channelSlotBit)
}

// ReverseChannelPath returns a path with the same channel hops in reversed
// order. Empty channel slots are skipped. Returns ErrChannelPathFull when the
// reversed path would overflow.
//
// Mirrors `reverse_channel_path` at contract.rs:3390.
func ReverseChannelPath(path *u256.Uint) (*u256.Uint, error) {
	reversed := u256.Zero()
	cur := path
	for {
		tail, head := PopChannelFromPath(cur)
		if head != 0 {
			updated, err := UpdateChannelPath(reversed, head)
			if err != nil {
				return nil, err
			}
			reversed = updated
		}
		if tail.IsZero() {
			break
		}
		cur = tail
	}
	return reversed, nil
}
