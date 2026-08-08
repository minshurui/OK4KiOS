package fishconfig

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

// Pan123 implements the 123云盘 action client.
//
// 协议依据（PROTOCOL.md §3/§9 + w1 pan123-strings.txt + 实测闭环）：
//   - litepan 中转: POST https://oauth.litepan.top/api/oauth/start
//     {driver_type:"123云盘", callback_url:"https://oauth.litepan.top/callback-popup"}
//     -> {success:true, data:{session_id, oauth_url, expires_in}}（实测可达）
//     轮询 GET /api/oauth/status/{session_id} -> status pending/success/error + token_data
//     刷新 POST /api/oauth/refresh {driver_type, refresh_token}
//   - 登录方式：扫码授权(F2(18))/账号密码(F2(19))/Open Token(F2(20))
//   - 账号密码: POST https://api.123278.com/api/restful/goapi/v1/oauth2/user/login
//   - 用户: GET https://api.123pan.com/api/v1/user/info
//     Headers: Platform: open_platform, Authorization: Bearer {access_token}
type Pan123 struct{}

func init() { register(&Pan123{}) }

// Name implements Client.
func (p *Pan123) Name() string { return NetPan123 }

var (
	pan123LiteBase = "https://oauth.litepan.top/api/oauth"
	pan123APIBase  = "https://api.123pan.com/api"
	pan123GoAPI    = "https://api.123278.com/api/restful/goapi/v1/oauth2/user/login"
	pan123Driver   = "123云盘"
	pan123Callback = "https://oauth.litepan.top/callback-popup"
)

// Status verifies an access token against the user info endpoint.
func (p *Pan123) Status(ctx context.Context, cred Credential, h *HTTP) (*StatusResult, error) {
	token := cred.Token
	if token == "" {
		if v, _ := cred.Raw["access_token"].(string); v != "" {
			token = v
		}
	}
	if token == "" {
		return &StatusResult{LoggedIn: false, Hint: "123云盘未配置Token"}, nil
	}
	if h.Evidence != nil {
		h.Evidence.Action = "pan123_status"
		h.Evidence.Note = "GET api.123pan.com/api/v1/user/info (Platform: open_platform)"
	}
	req, err := newRequest(ctx, "GET", pan123APIBase+"/v1/user/info", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Platform", "open_platform")
	req.Header.Set("Authorization", "Bearer "+token)
	_, body, err := h.Do(ctx, req)
	if err != nil {
		return nil, errf("pan123 status: %w", err)
	}
	var resp struct {
		Code int `json:"code"`
		Data struct {
			Username string `json:"username"`
			UserID   int64  `json:"userId"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, errf("pan123 status: bad json: %w", err)
	}
	if resp.Code != 0 || resp.Data.Username == "" {
		return &StatusResult{LoggedIn: false, Hint: "123云盘Token无效（code=" + itoa(resp.Code) + "）"}, nil
	}
	return &StatusResult{LoggedIn: true,
		Account: &AccountInfo{Name: resp.Data.Username, UserID: fmt.Sprintf("%d", resp.Data.UserID)},
		Hint:    "123云盘已登录"}, nil
}

// Scan starts the litepan OAuth flow (123云盘App扫码授权).
func (p *Pan123) Scan(ctx context.Context, h *HTTP) (*ScanResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "pan123_scan"
		h.Evidence.Note = "POST oauth.litepan.top/api/oauth/start driver_type=123云盘 (live-verified)"
	}
	var out struct {
		Success bool `json:"success"`
		Data    struct {
			SessionID string `json:"session_id"`
			OAuthURL  string `json:"oauth_url"`
			ExpiresIn int    `json:"expires_in"`
		} `json:"data"`
	}
	body, err := h.PostJSONInto(ctx, pan123LiteBase+"/start", map[string]any{
		"driver_type": pan123Driver, "callback_url": pan123Callback,
	}, &out)
	if err != nil {
		return nil, errf("pan123 scan: %w", err)
	}
	if !out.Success || out.Data.SessionID == "" {
		return nil, errf("pan123 scan: start failed: %s", string(body))
	}
	return &ScanResult{
		Kind:      "oauth_url",
		QRURL:     out.Data.OAuthURL,
		QRContent: out.Data.OAuthURL,
		Session:   map[string]any{"session_id": out.Data.SessionID},
		Interval:  3,
		Timeout:   out.Data.ExpiresIn,
		Hint:      "手机扫码授权123云盘（或浏览器打开链接）",
	}, nil
}

// Login supports: session poll (litepan status), pasted Open Token JSON,
// or account+password via the goapi login endpoint.
func (p *Pan123) Login(ctx context.Context, req LoginRequest, h *HTTP) (*LoginResult, error) {
	switch {
	case req.Account != "" && req.Password != "":
		return p.loginWithPassword(ctx, req, h)
	case req.Input != "":
		return p.loginWithTokenJSON(ctx, req.Input, h)
	case len(req.Session) > 0:
		return p.pollSession(ctx, req, h)
	}
	return nil, errf("pan123 login: need session / account+password / pasted Open Token")
}

func (p *Pan123) pollSession(ctx context.Context, req LoginRequest, h *HTTP) (*LoginResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "pan123_login"
		h.Evidence.Note = "poll /api/oauth/status/{session_id} until success"
	}
	sid, _ := req.Session["session_id"].(string)
	expires := 600
	if v, _ := req.Session["expires_in"].(float64); v > 0 {
		expires = int(v)
	}
	for i := 0; i < expires/3; i++ {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}
		var out struct {
			Success bool `json:"success"`
			Data    struct {
				Status    string         `json:"status"` // pending / success / error
				TokenData map[string]any `json:"token_data"`
				Error     any            `json:"error"`
			} `json:"data"`
		}
		body, err := h.GetJSON(ctx, pan123LiteBase+"/status/"+sid, &out)
		_ = body
		if err != nil {
			return nil, errf("pan123 poll: %w", err)
		}
		switch out.Data.Status {
		case "success":
			return p.finishWithTokenData(ctx, out.Data.TokenData, h)
		case "error":
			msg := fmt.Sprintf("%v", out.Data.Error)
			return &LoginResult{Success: false, Hint: "123云盘授权失败（" + msg + "）"}, nil
		}
		if !sleepCtx(ctx, 3) {
			return nil, ctx.Err()
		}
	}
	return &LoginResult{Success: false, Hint: "123云盘授权超时"}, nil
}

func (p *Pan123) finishWithTokenData(ctx context.Context, td map[string]any, h *HTTP) (*LoginResult, error) {
	access := asString(td, "access_token", "accessToken")
	if access == "" {
		return nil, errf("pan123: token_data missing access_token")
	}
	cred := Credential{Netdisk: NetPan123, Token: access, Raw: td}
	st, err := p.Status(ctx, cred, h)
	if err != nil {
		return nil, errf("pan123 verify: %w", err)
	}
	return &LoginResult{Success: st.LoggedIn, Credential: cred, Account: st.Account,
		Hint: "123云盘授权成功"}, nil
}

func (p *Pan123) loginWithTokenJSON(ctx context.Context, input string, h *HTTP) (*LoginResult, error) {
	var m map[string]any
	if err := json.Unmarshal([]byte(input), &m); err != nil {
		return nil, errf("pan123 login: Open Token JSON parse: %w", err)
	}
	return p.finishWithTokenData(ctx, m, h)
}

func (p *Pan123) loginWithPassword(ctx context.Context, req LoginRequest, h *HTTP) (*LoginResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "pan123_login"
		h.Evidence.Note = "POST api.123278.com/api/restful/goapi/v1/oauth2/user/login"
	}
	var out struct {
		Code int            `json:"code"`
		Data map[string]any `json:"data"`
	}
	body, err := h.PostJSONInto(ctx, pan123GoAPI, map[string]any{
		"username": req.Account, "password": req.Password,
	}, &out)
	if err != nil {
		return nil, errf("pan123 password login: %w", err)
	}
	if out.Code != 0 {
		return &LoginResult{Success: false, Hint: "123云盘账号密码登录失败（code=" + itoa(out.Code) + "）"}, nil
	}
	_ = body
	return p.finishWithTokenData(ctx, out.Data, h)
}

// CommunityCookie is handled by gateway as a login-style op (paste 123社区 cookie).
var _ = http.MethodGet
var _ = strings.TrimSpace
var _ = time.Now
