package attr

import "strconv"

const maxValueLen = 1024

// Columns splits an encoded event attribute value into indexed columns.
func Columns(key string, value string) []string {
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

// MaxValueLen returns the maximum event attribute value length.
func MaxValueLen() int {
	return maxValueLen
}
