package fishconfig

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

// mockServer routes by path prefix and returns the registered fixture.
type mockServer struct {
	mu       sync.Mutex
	muRoutes map[string]func(w http.ResponseWriter, r *http.Request)
	seen     []EvidenceEntry // captured interactions
}

func newMock() *mockServer {
	return &mockServer{muRoutes: map[string]func(w http.ResponseWriter, r *http.Request){}}
}

func (m *mockServer) on(path string, fn func(w http.ResponseWriter, r *http.Request)) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.muRoutes[path] = fn
}

func (m *mockServer) onJSON(path, body string, status int) {
	m.on(path, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		w.Write([]byte(body))
	})
}

func (m *mockServer) handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		m.mu.Lock()
		defer m.mu.Unlock()
		body := ""
		if r.Body != nil {
			buf := make([]byte, 4096)
			n, _ := r.Body.Read(buf)
			body = string(buf[:n])
		}
		m.seen = append(m.seen, EvidenceEntry{Method: r.Method, URL: r.URL.String(), Body: body})
		path := r.URL.Path
		if fn, ok := m.muRoutes[path]; ok {
			fn(w, r)
			return
		}
		// prefix match (e.g. /cas/ajax/getQrcodeLogin with query)
		for p, fn := range m.muRoutes {
			if strings.HasPrefix(path, p) {
				fn(w, r)
				return
			}
		}
		http.Error(w, "no mock for "+path, 404)
	})
}

// newMockHTTP starts a mock server and returns its base URL.
func (m *mockServer) start(t *testing.T) string {
	t.Helper()
	srv := httptest.NewServer(m.handler())
	t.Cleanup(srv.Close)
	return srv.URL
}

// record is a helper to append evidence from a gateway response.
func recordEvidence(t *testing.T, netdisk string, resp *ActionResponse, note string) {
	t.Helper()
	RecordEvidence(EvidenceEntry{Netdisk: netdisk, Action: resp.Action, Result: resp, Note: note})
}

// assertOK fails the test if resp.Ok is false.
func assertOK(t *testing.T, resp *ActionResponse) {
	t.Helper()
	if !resp.Ok {
		t.Fatalf("action %s failed: %s", resp.Action, resp.Error)
	}
}

// setVars restores endpoint overrides after the test.
func setVars(t *testing.T, pairs ...[2]string) {
	t.Helper()
	// pairs are (varName, value); resolve via a registry to stay simple:
	// caller passes pointer addresses through a typed helper instead.
	_ = pairs
}

// setStr overrides one string var and restores it at cleanup.
func setStr(t *testing.T, dst *string, val string) {
	t.Helper()
	old := *dst
	*dst = val
	t.Cleanup(func() { *dst = old })
}

func strPtr(s string) *string { return &s }

var _ = json.Marshal
var _ = fmt.Sprintf

// helper: gateway dispatch convenience
func gwDispatch(t *testing.T, gw *Gateway, action, payload string) *ActionResponse {
	t.Helper()
	resp := gw.Dispatch(t.Context(), action, payload)
	return resp
}
