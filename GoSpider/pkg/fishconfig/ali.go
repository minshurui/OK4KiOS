package fishconfig

import (
	"context"
	"encoding/json"
	"net/url"
	"strings"
	"time"
)

// Ali implements the 阿里云盘 action client.
//
// 协议依据（PROTOCOL.md §3/§9 + w1 ali-strings.txt）：
//   - OAuth 授权 https://open.aliyundrive.com/oauth/users/authorize?client_id=10e184c407cb4d8087f9d3b8f1fd2c23&redirect_uri=https://opentoken.xiaoya.pro/callback&scope=user:base,file:all:read,file:all:write&state=
//   - Token  https://auth.aliyundrive.com/v2/account/token（grant_type=authorization_code / refresh_token）
//   - 刷新   https://auth.xiaoya.pro/api/ali_open/refresh
//   - 用户   POST https://api.aliyundrive.com/v2/databox/get_personal_info（Bearer）
//   - 文件   POST https://api.aliyundrive.com/adrive/v1.0/openFile/list
//   - 登录方式：Token 输入（L1.G0() -> Z0(...,"Token",...)）
type Ali struct{}

func init() { register(&Ali{}) }

// Name implements Client.
func (a *Ali) Name() string { return NetAli }

var (
	aliAPIBase     = "https://api.aliyundrive.com"
	aliAuthBase    = "https://auth.aliyundrive.com/v2/account/token"
	aliRefreshBase = "https://auth.xiaoya.pro/api/ali_open/refresh"
	aliClientID    = "10e184c407cb4d8087f9d3b8f1fd2c23"
	aliRedirect    = "https://opentoken.xiaoya.pro/callback"
	aliScope       = "user:base,file:all:read,file:all:write"
)

// Status verifies a Bearer token against the personal info endpoint.
func (a *Ali) Status(ctx context.Context, cred Credential, h *HTTP) (*StatusResult, error) {
	token := cred.Token
	if token == "" {
		if v, _ := cred.Raw["access_token"].(string); v != "" {
			token = v
		} else if v, _ := cred.Raw["token"].(string); v != "" {
			token = v
		}
	}
	if token == "" {
		return &StatusResult{LoggedIn: false, Hint: "阿里云盘未配置Token"}, nil
	}
	if h.Evidence != nil {
		h.Evidence.Action = "ali_status"
		h.Evidence.Note = "POST /v2/databox/get_personal_info with Bearer"
	}
	req, err := newRequest(ctx, "POST", aliAPIBase+"/v2/databox/get_personal_info", []byte(`{}`))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	_, body, err := h.Do(ctx, req)
	if err != nil {
		return nil, errf("ali status: %w", err)
	}
	var resp struct {
		Name   string `json:"name"`
		Avatar string `json:"avatar"`
		Code   string `json:"code"`
		Msg    string `json:"message"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, errf("ali status: bad json: %w", err)
	}
	if resp.Code != "" {
		return &StatusResult{LoggedIn: false, Hint: "阿里云盘Token无效（" + resp.Code + "）"}, nil
	}
	acc := &AccountInfo{Name: resp.Name, Avatar: resp.Avatar}
	return &StatusResult{LoggedIn: resp.Name != "", Account: acc, Hint: "阿里云盘已登录"}, nil
}

// Scan returns the OAuth authorize URL (user authorizes in browser, pastes the
// returned Open Token via ali_token).
func (a *Ali) Scan(ctx context.Context, h *HTTP) (*ScanResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "ali_scan"
		h.Evidence.Note = "generate OAuth authorize URL (client_id from evidence)"
	}
	state := "ok4k-" + itoa(int(time.Now().UnixNano()%1000000))
	q := url.Values{
		"client_id":    {aliClientID},
		"redirect_uri": {aliRedirect},
		"scope":        {aliScope},
		"state":        {state},
	}
	authURL := "https://open.aliyundrive.com/oauth/users/authorize?" + q.Encode()
	return &ScanResult{
		Kind:     "oauth_url",
		QRURL:    authURL,
		Session:  map[string]any{"state": state},
		Interval: 0,
		Timeout:  300,
		Hint:     "浏览器打开授权链接，同意后把回调中的 Token JSON 粘贴到“Token”输入框",
	}, nil
}

// Login handles pasted Open Token JSON (input) or an authorization code.
func (a *Ali) Login(ctx context.Context, req LoginRequest, h *HTTP) (*LoginResult, error) {
	input := strings.TrimSpace(req.Input)
	if input == "" {
		return nil, errf("ali login: need pasted Token JSON")
	}
	// authorization code -> exchange
	if !strings.HasPrefix(input, "{") && !strings.Contains(input, "access_token") {
		return a.exchangeCode(ctx, input, h)
	}
	var m map[string]any
	if err := json.Unmarshal([]byte(input), &m); err != nil {
		return nil, errf("ali login: Token JSON parse: %w", err)
	}
	token := firstNonEmpty(asString(m, "access_token"), asString(m, "token"))
	if token == "" {
		return nil, errf("ali login: Token JSON missing access_token")
	}
	cred := Credential{Netdisk: NetAli, Token: token, Raw: m}
	st, err := a.Status(ctx, cred, h)
	if err != nil {
		return nil, errf("ali login verify: %w", err)
	}
	if st.LoggedIn {
		return &LoginResult{Success: true, Credential: cred, Account: st.Account,
			Hint: "阿里云盘Token有效"}, nil
	}
	// try refresh once via xiaoya proxy (evidence endpoint)
	if rt := asString(m, "refresh_token"); rt != "" {
		if h.Evidence != nil {
			h.Evidence.Note = "ali login: refresh via auth.xiaoya.pro then re-verify"
		}
		var rb struct {
			AccessToken  string `json:"access_token"`
			RefreshToken string `json:"refresh_token"`
		}
		body, err := h.PostJSONInto(ctx, aliRefreshBase, map[string]any{
			"grant_type": "refresh_token", "refresh_token": rt, "client_id": aliClientID,
		}, &rb)
		if err == nil && rb.AccessToken != "" {
			m2 := map[string]any{}
			for k, v := range m {
				m2[k] = v
			}
			m2["access_token"] = rb.AccessToken
			if rb.RefreshToken != "" {
				m2["refresh_token"] = rb.RefreshToken
			}
			cred = Credential{Netdisk: NetAli, Token: rb.AccessToken, Raw: m2}
			st2, err2 := a.Status(ctx, cred, h)
			if err2 == nil && st2.LoggedIn {
				return &LoginResult{Success: true, Credential: cred, Account: st2.Account,
					Hint: "阿里云盘Token已刷新并验证"}, nil
			}
			_ = body
		}
	}
	return &LoginResult{Success: false, Hint: "阿里云盘Token无效或已过期"}, nil
}

// exchangeCode swaps an OAuth authorization code for a token.
func (a *Ali) exchangeCode(ctx context.Context, code string, h *HTTP) (*LoginResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "ali_token"
		h.Evidence.Note = "POST auth.aliyundrive.com/v2/account/token grant_type=authorization_code"
	}
	var out struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
		ExpiresIn    int    `json:"expires_in"`
	}
	body, err := h.PostJSONInto(ctx, aliAuthBase, map[string]any{
		"grant_type": "authorization_code", "code": code, "client_id": aliClientID,
	}, &out)
	if err != nil {
		return nil, errf("ali code exchange: %w", err)
	}
	if out.AccessToken == "" {
		return &LoginResult{Success: false, Hint: "阿里授权码换取Token失败（" + string(body) + "）"}, nil
	}
	cred := Credential{Netdisk: NetAli, Token: out.AccessToken, Raw: map[string]any{
		"access_token": out.AccessToken, "refresh_token": out.RefreshToken, "expires_in": out.ExpiresIn,
	}}
	st, err := a.Status(ctx, cred, h)
	if err != nil {
		return nil, errf("ali code verify: %w", err)
	}
	return &LoginResult{Success: st.LoggedIn, Credential: cred, Account: st.Account,
		Hint: "阿里云盘授权成功"}, nil
}
