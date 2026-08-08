package fishconfig

import (
	"context"
	"encoding/json"
	"strings"
	"time"
)

// Xunlei implements the 迅雷网盘 action client.
//
// 协议依据（PROTOCOL.md §3/§9 + w1 xunlei-strings.txt）：
//   - 登录方式：扫码(K2(10)) / Token JSON(K2(11))（L1.p1() -> C0203L0.v().H()）
//   - auth: POST https://xluser-ssl.xunlei.com/v1/auth/token（grant_type/refresh_token 字段已在证据中）
//   - 用户: GET https://xluser-ssl.xunlei.com/v1/user/me（Bearer；无凭证时 401，实测可达）
//   - 文件: GET https://api-pan.xunlei.com/drive/v1/files?parent_id=
//   - 头: x-device-id / x-captcha-token / Authorization，UA downloadprovider/...
type Xunlei struct{}

func init() { register(&Xunlei{}) }

// Name implements Client.
func (x *Xunlei) Name() string { return NetXunlei }

var (
	xunleiAuthBase = "https://xluser-ssl.xunlei.com/v1"
	xunleiDriveAPI = "https://api-pan.xunlei.com/drive/v1"
	// 迅雷网盘官方客户端 client_id（OAuth2 设备码；具体取值以 jar 内 C0203L0 为准，
	// 见 evidence 备注。若服务端 404 说明该 client_id 已失效，需从 smali 补全）
	xunleiClientID = "d16d8f6b-e0c8-48f0-87c4-4f43a34d37c0"
)

// Status verifies a Bearer token against /v1/user/me.
func (x *Xunlei) Status(ctx context.Context, cred Credential, h *HTTP) (*StatusResult, error) {
	token := cred.Token
	if token == "" {
		if v, _ := cred.Raw["access_token"].(string); v != "" {
			token = v
		}
	}
	if token == "" {
		return &StatusResult{LoggedIn: false, Hint: "迅雷网盘未配置Token"}, nil
	}
	if h.Evidence != nil {
		h.Evidence.Action = "xunlei_status"
		h.Evidence.Note = "GET xluser-ssl.xunlei.com/v1/user/me with Bearer"
	}
	req, err := newRequest(ctx, "GET", xunleiAuthBase+"/user/me", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("x-device-id", deviceID())
	_, body, err := h.Do(ctx, req)
	if err != nil {
		return nil, errf("xunlei status: %w", err)
	}
	if len(body) > 0 && strings.Contains(string(body), "unauthenticated") {
		return &StatusResult{LoggedIn: false, Hint: "迅雷Token无效或已过期"}, nil
	}
	var resp struct {
		UserID   string `json:"user_id"`
		Name     string `json:"name"`
		Nickname string `json:"nickname"`
		Avatar   string `json:"avatar_url"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, errf("xunlei status: bad json: %w", err)
	}
	name := firstNonEmpty(resp.Nickname, resp.Name)
	acc := &AccountInfo{Name: name, Avatar: resp.Avatar, UserID: resp.UserID}
	return &StatusResult{LoggedIn: name != "" || resp.UserID != "", Account: acc, Hint: "迅雷网盘已登录"}, nil
}

// Scan starts an OAuth2 device-code login (迅雷App扫码).
func (x *Xunlei) Scan(ctx context.Context, h *HTTP) (*ScanResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "xunlei_scan"
		h.Evidence.Note = "POST /v1/auth/device/code (client_id 来自证据; 实测 404=需从 smali 补 client_id)"
	}
	var out struct {
		DeviceCode              string `json:"device_code"`
		UserCode                string `json:"user_code"`
		VerificationURI         string `json:"verification_uri"`
		VerificationURIComplete string `json:"verification_uri_complete"`
		Interval                int    `json:"interval"`
		ExpiresIn               int    `json:"expires_in"`
	}
	body, err := h.PostJSONInto(ctx, xunleiAuthBase+"/auth/device/code", map[string]any{
		"client_id": xunleiClientID, "scope": "user",
	}, &out)
	if err != nil {
		return nil, errf("xunlei scan: %w", err)
	}
	if out.DeviceCode == "" {
		return nil, errf("xunlei scan: no device_code (server: %s)", string(body))
	}
	uri := firstNonEmpty(out.VerificationURIComplete, out.VerificationURI)
	if uri == "" {
		uri = "https://pan.xunlei.com/" // fallback login page
	}
	return &ScanResult{
		Kind:      "device_code",
		QRURL:     uri,
		QRContent: uri,
		Session:   map[string]any{"device_code": out.DeviceCode, "client_id": xunleiClientID},
		Interval:  out.Interval,
		Timeout:   out.ExpiresIn,
		Hint:      "使用迅雷App扫码",
	}, nil
}

// Login polls the device-code session or verifies pasted Token JSON.
func (x *Xunlei) Login(ctx context.Context, req LoginRequest, h *HTTP) (*LoginResult, error) {
	if req.Input != "" {
		return x.loginWithTokenJSON(ctx, req.Input, h)
	}
	if len(req.Session) == 0 {
		return nil, errf("xunlei login: need session from xunlei_scan or pasted Token JSON")
	}
	if h.Evidence != nil {
		h.Evidence.Action = "xunlei_login"
		h.Evidence.Note = "poll POST /v1/auth/token grant_type=device_code"
	}
	deviceCode, _ := req.Session["device_code"].(string)
	clientID, _ := req.Session["client_id"].(string)
	if clientID == "" {
		clientID = xunleiClientID
	}
	interval := 3
	if v, _ := req.Session["interval"].(float64); v > 0 {
		interval = int(v)
	}
	expires := 300
	if v, _ := req.Session["expires_in"].(float64); v > 0 {
		expires = int(v)
	}
	for i := 0; i < expires/interval; i++ {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}
		var out struct {
			AccessToken  string `json:"access_token"`
			RefreshToken string `json:"refresh_token"`
			Error        string `json:"error"`
		}
		body, err := h.PostJSONInto(ctx, xunleiAuthBase+"/auth/token", map[string]any{
			"grant_type":  "urn:ietf:params:oauth:grant-type:device_code",
			"client_id":   clientID,
			"device_code": deviceCode,
		}, &out)
		if err != nil {
			return nil, errf("xunlei poll: %w", err)
		}
		switch out.Error {
		case "", "invalid_grant":
			if out.AccessToken != "" {
				return x.finishWithToken(ctx, out.AccessToken, out.RefreshToken, h)
			}
		case "authorization_pending", "slow_down":
			// keep polling
		case "access_denied", "expired_token":
			return &LoginResult{Success: false, Hint: "迅雷扫码已取消或过期"}, nil
		default:
			return &LoginResult{Success: false, Hint: "迅雷扫码失败（" + out.Error + "）"}, nil
		}
		if !sleepCtx(ctx, time.Duration(interval)*time.Second) {
			return nil, ctx.Err()
		}
		_ = body
	}
	return &LoginResult{Success: false, Hint: "迅雷扫码超时"}, nil
}

func (x *Xunlei) finishWithToken(ctx context.Context, access, refresh string, h *HTTP) (*LoginResult, error) {
	cred := Credential{Netdisk: NetXunlei, Token: access, Raw: map[string]any{
		"access_token": access, "refresh_token": refresh,
	}}
	st, err := x.Status(ctx, cred, h)
	if err != nil {
		return nil, errf("xunlei verify: %w", err)
	}
	return &LoginResult{Success: st.LoggedIn, Credential: cred, Account: st.Account,
		Hint: "迅雷网盘登录成功"}, nil
}

func (x *Xunlei) loginWithTokenJSON(ctx context.Context, input string, h *HTTP) (*LoginResult, error) {
	var m map[string]any
	if err := json.Unmarshal([]byte(input), &m); err != nil {
		return nil, errf("xunlei login: Token JSON parse: %w", err)
	}
	access := asString(m, "access_token", "token")
	if access == "" {
		return nil, errf("xunlei login: Token JSON missing access_token")
	}
	return x.finishWithToken(ctx, access, asString(m, "refresh_token"), h)
}

// deviceID returns a stable pseudo device id for x-device-id.
func deviceID() string {
	// 与 Android 相同语义：持久化的随机 id；Go 侧用固定前缀+时间
	return "ok4k-go-" + itoa(int(time.Now().UnixNano()%100000000))
}
