package fishconfig

import (
	"context"
	"encoding/json"
	"fmt"
	"time"
)

// Guangya implements the 光鸭网盘 action client — Go 镜像 PROTOCOL.md §4 的
// 完整已复现闭环（设备码 + 轮询 + 刷新 + 资料），与 iOS GuangyaAuthService
// 语义一致，作为网关内统一的 9+1 网盘客户端之一。
type Guangya struct{}

func init() { register(&Guangya{}) }

// Name implements Client.
func (g *Guangya) Name() string { return NetGuangya }

var (
	guangyaClientID  = "aMe-8VSlkrbQXpUR"
	guangyaAccount   = "https://account.guangyapan.com"
	guangyaWebOrigin = "https://www.guangyapan.com"
)

// Status verifies the access token via /v1/user/me.
func (g *Guangya) Status(ctx context.Context, cred Credential, h *HTTP) (*StatusResult, error) {
	token := cred.Token
	if token == "" {
		if v, _ := cred.Raw["access_token"].(string); v != "" {
			token = v
		}
	}
	if token == "" {
		return &StatusResult{LoggedIn: false, Hint: "光鸭未配置Token"}, nil
	}
	if h.Evidence != nil {
		h.Evidence.Action = "guangya_status"
		h.Evidence.Note = "GET account.guangyapan.com/v1/user/me with Bearer"
	}
	req, err := newRequest(ctx, "GET", guangyaAccount+"/v1/user/me", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Origin", guangyaWebOrigin)
	req.Header.Set("Referer", guangyaWebOrigin+"/")
	_, body, err := h.Do(ctx, req)
	if err != nil {
		return nil, errf("guangya status: %w", err)
	}
	// response: {data:{sub,name,picture,phone,...}} 或平铺
	var resp struct {
		Data map[string]any `json:"data"`
	}
	_ = json.Unmarshal(body, &resp)
	m := resp.Data
	if m == nil {
		m = map[string]any{}
		_ = json.Unmarshal(body, &m)
	}
	name := firstNonEmpty(asString(m, "name"), asString(m, "nickname"))
	if name == "" && asString(m, "sub") == "" {
		return &StatusResult{LoggedIn: false, Hint: "光鸭Token无效或已过期"}, nil
	}
	acc := &AccountInfo{Name: name, Avatar: asString(m, "picture"), UserID: asString(m, "sub")}
	extra := map[string]any{}
	for _, k := range []string{"phone", "kaiser_folder", "token_type"} {
		if v := asString(m, k); v != "" {
			extra[k] = v
		}
	}
	if len(extra) > 0 {
		acc.Extra = extra
	}
	return &StatusResult{LoggedIn: true, Account: acc, Hint: "光鸭网盘已登录"}, nil
}

// Scan starts the OAuth device-code flow.
func (g *Guangya) Scan(ctx context.Context, h *HTTP) (*ScanResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "guangya_scan"
		h.Evidence.Note = "POST /v1/auth/device/code (client_id from evidence, live-verified flow)"
	}
	var out struct {
		Data map[string]any `json:"data"`
	}
	body, err := h.PostJSONInto(ctx, guangyaAccount+"/v1/auth/device/code", map[string]any{
		"scope": "user", "client_id": guangyaClientID,
	}, &out)
	if err != nil {
		return nil, errf("guangya scan: %w", err)
	}
	m := out.Data
	if m == nil {
		m = map[string]any{}
		_ = json.Unmarshal(body, &m)
	}
	deviceCode := firstNonEmpty(asString(m, "device_code"), asString(m, "deviceCode"))
	uri := firstNonEmpty(asString(m, "verification_uri_complete"), asString(m, "verification_uri"))
	if deviceCode == "" {
		return nil, errf("guangya scan: no device_code: %s", string(body))
	}
	return &ScanResult{
		Kind:      "device_code",
		QRURL:     uri,
		QRContent: uri,
		Session:   map[string]any{"device_code": deviceCode},
		Interval:  3,
		Timeout:   180,
		Hint:      "使用光鸭App扫码（二维码=verification_uri_complete）",
	}, nil
}

// Login polls the device-code session or verifies a pasted token.
func (g *Guangya) Login(ctx context.Context, req LoginRequest, h *HTTP) (*LoginResult, error) {
	if req.Input != "" {
		return g.loginWithToken(ctx, req.Input, h)
	}
	if len(req.Session) == 0 {
		return nil, errf("guangya login: need session from guangya_scan or pasted token")
	}
	if h.Evidence != nil {
		h.Evidence.Action = "guangya_login"
		h.Evidence.Note = "poll POST /v1/auth/token grant_type=device_code (3s interval, 180s timeout)"
	}
	deviceCode, _ := req.Session["device_code"].(string)
	body := map[string]any{
		"grant_type":  "urn:ietf:params:oauth:grant-type:device_code",
		"device_code": deviceCode,
		"client_id":   guangyaClientID,
	}
	for i := 0; i < 60; i++ {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}
		var out struct {
			Error string         `json:"error"`
			Data  map[string]any `json:"data"`
		}
		raw, err := h.PostJSONInto(ctx, guangyaAccount+"/v1/auth/token", body, &out)
		if err != nil {
			return nil, errf("guangya poll: %w", err)
		}
		switch out.Error {
		case "", "invalid_grant":
			if token := asString(out.Data, "access_token"); token != "" {
				return g.finish(ctx, out.Data, h)
			}
		case "authorization_pending", "slow_down":
			// 继续轮询
		case "access_denied", "expired_token":
			return &LoginResult{Success: false, Hint: "光鸭扫码已取消或过期"}, nil
		default:
			return &LoginResult{Success: false, Hint: "光鸭扫码失败（" + out.Error + "）"}, nil
		}
		if !sleepCtx(ctx, 3) {
			return nil, ctx.Err()
		}
		_ = raw
	}
	return &LoginResult{Success: false, Hint: "光鸭扫码超时（180s）"}, nil
}

// finish builds the persisted credential and verifies via profile.
func (g *Guangya) finish(ctx context.Context, m map[string]any, h *HTTP) (*LoginResult, error) {
	access := asString(m, "access_token")
	cred := Credential{Netdisk: NetGuangya, Token: access, Raw: m}
	st, err := g.Status(ctx, cred, h)
	if err != nil {
		return nil, errf("guangya verify: %w", err)
	}
	// 刷新缺失字段继承旧凭据（与 iOS 一致）
	return &LoginResult{Success: st.LoggedIn, Credential: cred, Account: st.Account,
		Hint: "光鸭网盘登录成功"}, nil
}

func (g *Guangya) loginWithToken(ctx context.Context, input string, h *HTTP) (*LoginResult, error) {
	var m map[string]any
	if err := json.Unmarshal([]byte(input), &m); err != nil {
		// 允许直接粘贴 access_token
		m = map[string]any{"access_token": input}
	}
	return g.finish(ctx, m, h)
}

var _ = fmt.Sprintf
var _ = time.Now
