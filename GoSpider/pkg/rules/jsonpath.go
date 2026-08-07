package rules

import (
	"fmt"
	"strconv"
	"strings"
)

// JSONPath implements a minimal JSONPath subset:
//
//	$.list[0].vod_name
//	$.data.items[*].title
//	$["list"][0]["vod_name"]
func JSONPath(data any, path string) (any, bool) {
	p := strings.TrimSpace(path)
	if !strings.HasPrefix(p, "$") {
		return nil, false
	}
	cur := data
	rest := p[1:]
	for rest != "" {
		rest = strings.TrimLeft(rest, ".")
		if rest == "" {
			break
		}
		switch {
		case strings.HasPrefix(rest, "["):
			end := strings.Index(rest, "]")
			if end < 0 {
				return nil, false
			}
			key := strings.TrimSpace(rest[1:end])
			rest = rest[end+1:]
			if key == "*" {
				arr, ok := cur.([]any)
				if !ok {
					return nil, false
				}
				// Apply the remaining path to every element and collect.
				if rest != "" {
					var out []any
					for _, item := range arr {
						if v, ok := JSONPath(item, "$"+rest); ok {
							out = append(out, v)
						}
					}
					return out, true
				}
				cur = arr
				continue
			}
			idx, err := strconv.Atoi(strings.Trim(key, "'\""))
			if err != nil {
				return nil, false
			}
			arr, ok := cur.([]any)
			if !ok || idx < 0 || idx >= len(arr) {
				return nil, false
			}
			cur = arr[idx]
		default:
			key := rest
			if i := strings.IndexAny(rest, ".["); i >= 0 {
				key = rest[:i]
				rest = rest[i:]
			} else {
				rest = ""
			}
			key = strings.Trim(key, "'\"")
			m, ok := cur.(map[string]any)
			if !ok {
				return nil, false
			}
			v, ok := m[key]
			if !ok {
				return nil, false
			}
			cur = v
		}
	}
	return cur, true
}

// JSONPathString returns the string form of the JSONPath result.
func JSONPathString(data any, path string) string {
	v, ok := JSONPath(data, path)
	if !ok {
		return ""
	}
	switch t := v.(type) {
	case string:
		return t
	case float64:
		return strconv.FormatFloat(t, 'f', -1, 64)
	case bool:
		return fmt.Sprintf("%v", t)
	case nil:
		return ""
	default:
		return fmt.Sprintf("%v", t)
	}
}
