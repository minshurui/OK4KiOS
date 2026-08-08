package fishconfig

import (
	"bytes"
	"context"
	"io"
	"net/http"
)

// newRequest builds an http.Request with an optional JSON body.
func newRequest(ctx context.Context, method, rawURL string, body []byte) (*http.Request, error) {
	var rd io.Reader
	if body != nil {
		rd = bytes.NewReader(body)
	}
	req, err := http.NewRequestWithContext(ctx, method, rawURL, rd)
	if err != nil {
		return nil, err
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	return req, nil
}

// pick first non-empty string (field aliases across netdisk responses).
func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}

// asString extracts a string from a JSON map with several candidate keys.
func asString(m map[string]any, keys ...string) string {
	for _, k := range keys {
		if v, ok := m[k].(string); ok {
			return v
		}
	}
	return ""
}

// asInt64 extracts an int64 from a JSON map with several candidate keys.
func asInt64(m map[string]any, keys ...string) int64 {
	for _, k := range keys {
		switch v := m[k].(type) {
		case float64:
			return int64(v)
		case string:
			var n int64
			for _, c := range v {
				if c < '0' || c > '9' {
					break
				}
				n = n*10 + int64(c-'0')
			}
			return n
		}
	}
	return 0
}
