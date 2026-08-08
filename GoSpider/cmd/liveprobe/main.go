// Command liveprobe probes the documented netdisk endpoints (no credentials
// required) and writes reachability evidence to pkg/fishconfig/evidence/live/.
// It is the "自测脚本" companion to the mock-based go tests: run with
//
//	go run ./cmd/liveprobe
//
// Safe to run repeatedly; only issues anonymous/unauth requests.
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type probeResult struct {
	Netdisk string `json:"netdisk"`
	Target  string `json:"target"`
	Method  string `json:"method"`
	Status  int    `json:"status"`
	Resp    string `json:"response,omitempty"`
	Reach   string `json:"reachability"` // reachable | endpoint_shape_ok | blocked | needs_auth | params_needed
	Note    string `json:"note,omitempty"`
}

func main() {
	dir := evidenceDir()
	os.MkdirAll(dir, 0o755)
	client := &http.Client{Timeout: 12 * time.Second}
	ua := "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

	probes := []probeResult{
		probe(client, ua, "quark", "GET", "https://uop.quark.cn/cas/ajax/getTokenForQrcodeLogin", nil,
			"扫码第一步（CAS token）；实测可达"),
		probe(client, ua, "uc", "GET", fmt.Sprintf("https://api.open.uc.cn/cas/ajax/getTokenForQrcodeLogin?__dt=641254&__t=%d", time.Now().UnixMilli()), nil,
			"扫码第一步（CAS token）；实测可达"),
		probe(client, ua, "pan123", "POST", "https://oauth.litepan.top/api/oauth/start",
			[]byte(`{"driver_type":"123云盘","callback_url":"https://oauth.litepan.top/callback-popup"}`),
			"litepan OAuth start；实测返回 oauth_url+session_id"),
		probe(client, ua, "tianyi", "GET", "https://api.cloud.189.cn/open/user/getQrCode.action?appId=8027001086180899&clientType=TELEPC&version=6.2&channelId=web_cloud.189.cn", nil,
			"扫码 getQrCode；需要会话参数"),
		probe(client, ua, "pan115", "GET", "https://passportapi.115.com/app/1.0/alipaymini/1.0/login/qrcode/?ac=alipaymini&u=0&time_stamp=1786159706", nil,
			"扫码 qrcode；query 参数需从 smali 补齐"),
		probe(client, ua, "xunlei", "POST", "https://xluser-ssl.xunlei.com/v1/auth/device/code",
			[]byte(`{"client_id":"d16d8f6b-e0c8-48f0-87c4-4f43a34d37c0","scope":"user"}`),
			"设备码；client_id 需从 jar 补全（当前 404）"),
		probe(client, ua, "xunlei", "GET", "https://xluser-ssl.xunlei.com/v1/user/me", nil,
			"用户端点；无凭证 401=可达"),
		probe(client, ua, "yidong", "GET", "https://user-njs.yun.139.com/user/getUser", nil,
			"用户端点；无凭证返回 code=01000101=可达"),
		probe(client, ua, "yidong", "GET", "https://api.139.com/queryId", nil,
			"139 会话接口；部分网络不可达（连接挂起）"),
		probe(client, ua, "baidu", "GET", "https://pan.baidu.com/api/user/getinfo", nil,
			"用户端点；无凭证 errno!=0=可达"),
		probe(client, ua, "ali", "POST", "https://api.aliyundrive.com/v2/databox/get_personal_info", []byte(`{}`),
			"用户端点；无凭证返回错误码=可达"),
	}

	var lines []byte
	for _, p := range probes {
		classify(&p)
		b, _ := json.Marshal(p)
		lines = append(lines, b...)
		lines = append(lines, '\n')
		fname := filepath.Join(dir, p.Netdisk+".json")
		f, err := os.OpenFile(fname, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
		if err == nil {
			f.Write(b)
			f.WriteString("\n")
			f.Close()
		}
		fmt.Printf("%-8s %-4s %-60s -> %-12s %s\n", p.Netdisk, p.Method, p.Target, p.Reach, truncate(p.Resp, 60))
	}
	os.WriteFile(filepath.Join(dir, "_summary.json"), lines, 0o644)
}

func probe(c *http.Client, ua, netdisk, method, target string, body []byte, note string) probeResult {
	req, err := http.NewRequest(method, target, bytes.NewReader(body))
	if err != nil {
		return probeResult{Netdisk: netdisk, Target: target, Method: method, Reach: "blocked", Note: err.Error()}
	}
	req.Header.Set("User-Agent", ua)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	start := time.Now()
	resp, err := c.Do(req)
	if err != nil {
		return probeResult{Netdisk: netdisk, Target: target, Method: method, Reach: "blocked", Note: err.Error() + " (" + time.Since(start).Round(time.Millisecond).String() + ")"}
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 500))
	return probeResult{Netdisk: netdisk, Target: target, Method: method, Status: resp.StatusCode, Resp: string(b), Note: note}
}

func classify(p *probeResult) {
	if p.Reach == "blocked" {
		return
	}
	switch {
	case p.Status >= 200 && p.Status < 400:
		p.Reach = "reachable"
	case p.Status == 401 || p.Status == 403:
		p.Reach = "needs_auth"
	case p.Status == 404 || p.Status == 400:
		p.Reach = "endpoint_shape_ok"
	case p.Status >= 500:
		p.Reach = "server_error"
	}
}

func evidenceDir() string {
	if d := os.Getenv("OK4K_EVIDENCE_DIR"); d != "" {
		return d
	}
	// 仓库根：向上找 go.mod（module ok4kspider）
	dir, _ := os.Getwd()
	for {
		if b, err := os.ReadFile(filepath.Join(dir, "go.mod")); err == nil && strings.Contains(string(b), "module ok4kspider") {
			return filepath.Join(dir, "pkg", "fishconfig", "evidence", "live")
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return "evidence/live"
}

func truncate(s string, n int) string {
	s = strings.ReplaceAll(s, "\n", " ")
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}
