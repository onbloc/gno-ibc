package rlp

// EncodeBytes returns the RLP string encoding of b.
func EncodeBytes(b []byte) []byte {
	out := make([]byte, 0, BytesSize(b))
	return AppendBytes(out, b)
}

// EncodeString returns the RLP string encoding of s.
func EncodeString(s string) []byte {
	return EncodeBytes([]byte(s))
}

// EncodeUint64 returns the canonical RLP encoding of x as an Ethereum integer.
func EncodeUint64(x uint64) []byte {
	out := make([]byte, 0, IntSize(x))
	return AppendUint64(out, x)
}

// EncodeList returns the RLP list encoding of already-encoded items.
func EncodeList(items ...[]byte) []byte {
	size := 0
	for _, item := range items {
		size += len(item)
	}
	out := make([]byte, 0, int(ListSize(uint64(size))))
	out = appendHeader(out, 0xC0, 0xF7, uint64(size))
	for _, item := range items {
		out = append(out, item...)
	}
	return out
}

// EncodeValue returns the RLP encoding of v.
func EncodeValue(v Value) []byte {
	switch v.Kind {
	case KindList:
		items := make([][]byte, len(v.List))
		for i, item := range v.List {
			items[i] = EncodeValue(item)
		}
		return EncodeList(items...)
	default:
		return EncodeBytes(v.Bytes)
	}
}

// AppendBytes appends the RLP string encoding of b to out.
func AppendBytes(out []byte, b []byte) []byte {
	if len(b) == 1 && b[0] <= 0x7f {
		return append(out, b[0])
	}
	out = appendHeader(out, 0x80, 0xB7, uint64(len(b)))
	return append(out, b...)
}

// AppendUint64 appends the canonical RLP encoding of x to out.
func AppendUint64(out []byte, x uint64) []byte {
	if x == 0 {
		return append(out, 0x80)
	}
	if x < 0x80 {
		return append(out, byte(x))
	}
	buf := make([]byte, 8)
	n := putUint(buf, x)
	out = append(out, byte(0x80+n))
	return append(out, buf[8-n:]...)
}

// StringSize returns the encoded size of s.
func StringSize(s string) uint64 {
	return BytesSize([]byte(s))
}

// BytesSize returns the encoded size of b.
func BytesSize(b []byte) uint64 {
	n := len(b)
	if n == 1 && b[0] <= 0x7f {
		return 1
	}
	return uint64(headerSize(uint64(n)) + n)
}

// ListSize returns the encoded size of a list with contentSize payload bytes.
func ListSize(contentSize uint64) uint64 {
	return uint64(headerSize(contentSize)) + contentSize
}

// IntSize returns the encoded size of x.
func IntSize(x uint64) int {
	if x < 0x80 {
		return 1
	}
	return 1 + intSize(x)
}

func appendHeader(out []byte, smallTag, largeTag byte, size uint64) []byte {
	if size < 56 {
		return append(out, smallTag+byte(size))
	}
	buf := make([]byte, 8)
	n := putUint(buf, size)
	out = append(out, largeTag+byte(n))
	return append(out, buf[8-n:]...)
}

func headerSize(size uint64) int {
	if size < 56 {
		return 1
	}
	return 1 + intSize(size)
}

func intSize(x uint64) int {
	switch {
	case x < 1<<8:
		return 1
	case x < 1<<16:
		return 2
	case x < 1<<24:
		return 3
	case x < 1<<32:
		return 4
	case x < 1<<40:
		return 5
	case x < 1<<48:
		return 6
	case x < 1<<56:
		return 7
	default:
		return 8
	}
}

func putUint(buf []byte, x uint64) int {
	n := intSize(x)
	for i := 0; i < n; i++ {
		shift := uint((n - i - 1) * 8)
		buf[8-n+i] = byte(x >> shift)
	}
	return n
}
