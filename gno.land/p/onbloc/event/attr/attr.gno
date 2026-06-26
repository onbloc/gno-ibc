package attr

import "strconv"

// Columns splits an encoded event attribute value into indexed columns. A
// non-positive maxValueLen leaves the value unsplit.
func Columns(key string, value string, maxValueLen int) []string {
	if maxValueLen <= 0 {
		return []string{key, value}
	}

	if len(value) == 0 {
		return []string{key + "[0]", ""}
	}

	parts := (len(value) + maxValueLen - 1) / maxValueLen
	attrs := make([]string, 0, parts*2)
	for index := 0; index < parts; index++ {
		start := index * maxValueLen
		end := start + maxValueLen
		if end > len(value) {
			end = len(value)
		}
		attrs = append(attrs, key+"["+strconv.Itoa(index)+"]", value[start:end])
	}

	return attrs
}
