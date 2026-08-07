package engine

import (
	"fmt"
	"time"

	"github.com/dop251/goja"
)

// JSSignature runs a Spider signature script that returns a string.
// The script receives (url, params, headers, ts) and must return the
// signature/parameter string. A timeout guards against infinite loops.
func JSSignature(script, urlStr string, params map[string]string) (string, error) {
	vm := goja.New()
	vm.SetFieldNameMapper(goja.UncapFieldNameMapper())
	// Minimal browser-like helpers often used by Spider scripts.
	_ = vm.Set("Date", map[string]any{"now": func() int64 { return time.Now().UnixMilli() }})
	_ = vm.Set("now", time.Now().UnixMilli())
	_ = vm.Set("params", params)
	_ = vm.Set("url", urlStr)
	done := make(chan struct{})
	var result goja.Value
	var err error
	go func() {
		defer close(done)
		result, err = vm.RunString(script)
	}()
	select {
	case <-done:
		if err != nil {
			return "", err
		}
		if result == nil || goja.IsUndefined(result) || goja.IsNull(result) {
			return "", fmt.Errorf("script returned nothing")
		}
		return result.String(), nil
	case <-time.After(10 * time.Second):
		vm.Interrupt("timeout")
		return "", fmt.Errorf("script timeout")
	}
}
