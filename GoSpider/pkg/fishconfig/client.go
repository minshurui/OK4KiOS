package fishconfig

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// User-Agent presets extracted from the smali evidence (w1 strings files).
const (
	UAQuark  = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 quark-cloud-drive/3.0.1 Chrome/100.0.4896.160 Electron/18.3.5.12-a038f7b798 Safari/537.36 Channel/pckk_other_ch"
	UAUC     = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) uc-cloud-drive/1.8.7 Chrome/100.0.4896.160 Electron/18.3.5.16-b62cf9c50d Safari/537.36 Channel/ucpan_other_ch"
	UAWeb    = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
	UAXunlei = "downloadprovider/8.31.0.9726 netWorkType/5G appid/40 deviceName/Xiaomi_M2004j7ac deviceModel/M2004J7AC OSVersion/12 protocolVersion/301 platformVersion/10 sdkVersion/512000 Oauth2Client/0.9 (Linux 4_14_186-perf-gddfs8vbb238b) (JAVA 0)"
)

// EvidenceEntry records one HTTP interaction for the self-test evidence files.
type EvidenceEntry struct {
	Netdisk string            `json:"netdisk"`
	Action  string            `json:"action"`
	Method  string            `json:"method"`
	URL     string            `json:"url"`
	Headers map[string]string `json:"headers,omitempty"`
	Body    string            `json:"body,omitempty"`
	Status  int               `json:"status"`
	Resp    string            `json:"response,omitempty"`
	Result  any               `json:"result,omitempty"`
	Note    string            `json:"note,omitempty"`
}

// EvidenceDir is where self-tests write evidence JSON (committed).
var EvidenceDir = ""

func init() {
	// 测试工作目录可能是包目录或仓库根目录；向上找 go.mod 定位仓库根。
	if d := os.Getenv("OK4K_EVIDENCE_DIR"); d != "" {
		EvidenceDir = d
		return
	}
	dir, err := os.Getwd()
	if err != nil {
		return
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil {
			// 根目录本身是 GoSpider（module ok4kspider）
			if b, _ := os.ReadFile(filepath.Join(dir, "go.mod")); strings.Contains(string(b), "module ok4kspider") {
				EvidenceDir = filepath.Join(dir, "pkg", "fishconfig", "evidence")
				return
			}
			EvidenceDir = filepath.Join(dir, "pkg", "fishconfig", "evidence")
			return
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return
		}
		dir = parent
	}
}

// RecordEvidence appends one entry to evidence/<netdisk>.json (best effort).
func RecordEvidence(e EvidenceEntry) {
	if e.Netdisk == "" {
		e.Netdisk = "gateway"
	}
	if EvidenceDir == "" {
		return
	}
	if err := os.MkdirAll(EvidenceDir, 0o755); err != nil {
		return
	}
	path := filepath.Join(EvidenceDir, e.Netdisk+".json")
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer f.Close()
	if b, err := json.Marshal(e); err == nil {
		f.Write(b)
		f.WriteString("\n")
	}
}

// HTTP is a shared helper wrapping http.Client with per-netdisk defaults and
// an optional evidence hook.
type HTTP struct {
	Client       *http.Client
	UserAgent    string
	Base         string
	ExtraHeaders map[string]string
	Evidence     *EvidenceEntry // if set, every Do() fills it and records
	Timeout      time.Duration
}

// NewHTTP builds a client helper with a UA preset and 20s dial timeout.
func NewHTTP(ua string) *HTTP {
	return &HTTP{
		Client:    &http.Client{Timeout: 30 * time.Second},
		UserAgent: ua,
	}
}

// header sets a default header unless already provided in req.
func (h *HTTP) header(req *http.Request, k, v string) {
	if req.Header.Get(k) == "" {
		req.Header.Set(k, v)
	}
}

// applyDefaults fills UA/extra headers on a request.
func (h *HTTP) applyDefaults(req *http.Request) {
	if h.UserAgent != "" {
		h.header(req, "User-Agent", h.UserAgent)
	}
	if h.Base != "" {
		req.Header.Set("Referer", h.Base)
	}
	for k, v := range h.ExtraHeaders {
		h.header(req, k, v)
	}
}

// Do executes a request, records evidence when configured, and returns the
// response with the body fully read and closed.
func (h *HTTP) Do(ctx context.Context, req *http.Request) (*http.Response, []byte, error) {
	h.applyDefaults(req)
	resp, err := h.Client.Do(req.WithContext(ctx))
	if err != nil {
		return nil, nil, err
	}
	body, err := io.ReadAll(resp.Body)
	resp.Body.Close()
	if err != nil {
		return resp, body, err
	}
	if h.Evidence != nil {
		h.Evidence.Method = req.Method
		h.Evidence.URL = req.URL.String()
		h.Evidence.Headers = map[string]string{}
		for k := range req.Header {
			if strings.EqualFold(k, "Cookie") || strings.EqualFold(k, "Authorization") {
				continue // never leak credentials into evidence
			}
			h.Evidence.Headers[k] = req.Header.Get(k)
		}
		h.Evidence.Status = resp.StatusCode
		if len(body) < 4000 {
			h.Evidence.Resp = string(body)
		} else {
			h.Evidence.Resp = string(body[:4000])
		}
	}
	return resp, body, nil
}

// Get performs a GET and returns status + body.
func (h *HTTP) Get(ctx context.Context, rawURL string) (int, []byte, error) {
	req, err := http.NewRequest(http.MethodGet, rawURL, nil)
	if err != nil {
		return 0, nil, err
	}
	resp, body, err := h.Do(ctx, req)
	if err != nil {
		return 0, nil, err
	}
	return resp.StatusCode, body, nil
}

// PostJSON performs a POST with a JSON body.
func (h *HTTP) PostJSON(ctx context.Context, rawURL string, payload any) (int, []byte, error) {
	b, err := json.Marshal(payload)
	if err != nil {
		return 0, nil, err
	}
	req, err := http.NewRequest(http.MethodPost, rawURL, bytes.NewReader(b))
	if err != nil {
		return 0, nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, body, err := h.Do(ctx, req)
	if err != nil {
		return 0, nil, err
	}
	return resp.StatusCode, body, nil
}

// PostForm performs a POST with form-encoded body.
func (h *HTTP) PostForm(ctx context.Context, rawURL string, form url.Values) (int, []byte, error) {
	req, err := http.NewRequest(http.MethodPost, rawURL, strings.NewReader(form.Encode()))
	if err != nil {
		return 0, nil, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, body, err := h.Do(ctx, req)
	if err != nil {
		return 0, nil, err
	}
	return resp.StatusCode, body, nil
}

// GetJSON decodes a GET JSON response into out and returns the raw body.
func (h *HTTP) GetJSON(ctx context.Context, rawURL string, out any) ([]byte, error) {
	_, body, err := h.Get(ctx, rawURL)
	if err != nil {
		return nil, err
	}
	return body, json.Unmarshal(body, out)
}

// PostJSONInto decodes a POST JSON response into out and returns the raw body.
func (h *HTTP) PostJSONInto(ctx context.Context, rawURL string, payload, out any) ([]byte, error) {
	_, body, err := h.PostJSON(ctx, rawURL, payload)
	if err != nil {
		return nil, err
	}
	return body, json.Unmarshal(body, out)
}

// errf formats an error.
func errf(format string, a ...any) error { return fmt.Errorf(format, a...) }

// respString decodes a nested JSON object field with fallback extraction used
// by several netdisks (e.g. {"data":{...}} vs {...}).
func nested(data []byte) map[string]any {
	m := map[string]any{}
	if err := json.Unmarshal(data, &m); err != nil {
		return nil
	}
	return m
}

// poll loop helpers
func sleepCtx(ctx context.Context, d time.Duration) bool {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-t.C:
		return true
	}
}
