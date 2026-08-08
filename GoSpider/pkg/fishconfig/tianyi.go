package fishconfig

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"strconv"
	"strings"
)

// Tianyi implements the 天翼云盘 action client.
//
// 协议依据（PROTOCOL.md §3/§9 + w1 tianyi-strings.txt）：
//   - 基址 https://api.cloud.189.cn
//   - 扫码: GET /open/user/getQrCode.action?appId=8027001086180899&clientType=TELEPC&version=6.2&channelId=web_cloud.189.cn
//     -> {result:0, qrCode, sessionKey, shortToken}
//     轮询 POST /open/user/qrCodeLogin.action (form appId/sessionKey/shortToken)
//     -> {result:0, token, redirectUrl}
//   - 账号密码: POST /open/user/unifyLoginByAccount.action（userName + RSA password）
//   - 短信: GET /open/user/getSmsCode.action + POST /open/user/verifySmsCode.action
//   - 用户: GET /api/portal/v2/getUserBriefInfo.action（Cookie）
//   - 持久化: COOKIE_SESSION_ID（登录后由 redirectUrl 建会话）+ SessionKey
type Tianyi struct{}

func init() { register(&Tianyi{}) }

// Name implements Client.
func (t *Tianyi) Name() string { return NetTianyi }

var (
	tianyiBase    = "https://api.cloud.189.cn"
	tianyiAppID   = "8027001086180899"
	tianyiChannel = "web_cloud.189.cn"
)

// Status checks the saved session against the user brief info endpoint.
func (t *Tianyi) Status(ctx context.Context, cred Credential, h *HTTP) (*StatusResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "tianyi_status"
		h.Evidence.Note = "GET /api/portal/v2/getUserBriefInfo.action with cookie"
	}
	req, err := newRequest(ctx, "GET", tianyiBase+"/api/portal/v2/getUserBriefInfo.action", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Cookie", cred.Cookie)
	if sk := asString(cred.Raw, "session_key", "sessionKey"); sk != "" {
		req.Header.Set("SessionKey", sk)
	}
	_, body, err := h.Do(ctx, req)
	if err != nil {
		return nil, errf("tianyi status: %w", err)
	}
	var resp struct {
		Result        int    `json:"result"`
		ErrorCode     string `json:"errorCode"`
		UserBriefInfo struct {
			Name     string `json:"name"`
			Nickname string `json:"nickname"`
			Avatar   string `json:"avatar"`
			UserID   string `json:"userInfoId"`
		} `json:"userBriefInfo"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, errf("tianyi status: bad json: %w", err)
	}
	if resp.Result != 0 {
		return &StatusResult{LoggedIn: false, Hint: "天翼云盘凭证无效（result=" + itoa(resp.Result) + "）"}, nil
	}
	name := firstNonEmpty(resp.UserBriefInfo.Nickname, resp.UserBriefInfo.Name)
	acc := &AccountInfo{Name: name, Avatar: resp.UserBriefInfo.Avatar, UserID: resp.UserBriefInfo.UserID}
	return &StatusResult{LoggedIn: name != "", Account: acc, Hint: "天翼云盘已登录"}, nil
}

// Scan starts the tianyi QR login.
func (t *Tianyi) Scan(ctx context.Context, h *HTTP) (*ScanResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "tianyi_scan"
		h.Evidence.Note = "GET /open/user/getQrCode.action"
	}
	u := tianyiBase + "/open/user/getQrCode.action?appId=" + tianyiAppID +
		"&clientType=TELEPC&version=6.2&channelId=" + tianyiChannel
	_, body, err := h.Get(ctx, u)
	if err != nil {
		return nil, errf("tianyi scan: %w", err)
	}
	var resp struct {
		Result     int    `json:"result"`
		QrCode     string `json:"qrCode"`
		SessionKey string `json:"sessionKey"`
		ShortToken string `json:"shortToken"`
		Msg        string `json:"msg"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, errf("tianyi scan: bad json: %w", err)
	}
	if resp.Result != 0 || resp.QrCode == "" {
		return nil, errf("tianyi scan: getQrCode failed result=%d msg=%s", resp.Result, resp.Msg)
	}
	return &ScanResult{
		Kind:      "qrcode",
		QRContent: resp.QrCode,
		Session: map[string]any{
			"session_key": resp.SessionKey, "short_token": resp.ShortToken, "app_id": tianyiAppID,
		},
		Interval: 3,
		Timeout:  180,
		Hint:     "使用天翼云盘App扫码",
	}, nil
}

// Login supports: session poll (QR), account+password, sms code, or pasted cookie.
func (t *Tianyi) Login(ctx context.Context, req LoginRequest, h *HTTP) (*LoginResult, error) {
	switch {
	case req.Input != "":
		// pasted cookie
		return t.loginWithCookie(ctx, req.Input, h)
	case req.Code != "" && req.Account != "":
		return t.loginWithSMS(ctx, req, h)
	case req.Account != "" && req.Password != "":
		return t.loginWithPassword(ctx, req, h)
	case len(req.Session) > 0:
		return t.pollQR(ctx, req, h)
	}
	return nil, errf("tianyi login: need session/account+sms/account+password/cookie")
}

func (t *Tianyi) pollQR(ctx context.Context, req LoginRequest, h *HTTP) (*LoginResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "tianyi_login"
		h.Evidence.Note = "POST /open/user/qrCodeLogin.action until result=0"
	}
	sk, _ := req.Session["session_key"].(string)
	st, _ := req.Session["short_token"].(string)
	appID, _ := req.Session["app_id"].(string)
	if appID == "" {
		appID = tianyiAppID
	}
	for i := 0; i < 60; i++ {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}
		form := url.Values{"appId": {appID}, "sessionKey": {sk}, "shortToken": {st}}
		_, body, err := h.PostForm(ctx, tianyiBase+"/open/user/qrCodeLogin.action", form)
		if err != nil {
			return nil, errf("tianyi poll: %w", err)
		}
		var resp struct {
			Result      int    `json:"result"`
			Token       string `json:"token"`
			RedirectURL string `json:"redirectUrl"`
			Msg         string `json:"msg"`
			ErrorDesc   string `json:"errorDesc"`
		}
		_ = json.Unmarshal(body, &resp)
		if resp.Result == 0 && resp.Token != "" {
			return t.finishLogin(ctx, h, resp.Token, map[string]any{"session_key": sk})
		}
		if resp.Result != 0 && resp.Result != 1 && resp.Result != 2 && resp.Result != 4 {
			return &LoginResult{Success: false, Hint: "天翼扫码失败（result=" + itoa(resp.Result) + " " + resp.Msg + "）"}, nil
		}
		if !sleepCtx(ctx, 3) {
			return nil, ctx.Err()
		}
	}
	return &LoginResult{Success: false, Hint: "天翼扫码超时（180s）"}, nil
}

// finishLogin exchanges the login token for a session cookie by fetching the
// user brief info endpoint (which sets COOKIE_SESSION_ID server-side).
func (t *Tianyi) finishLogin(ctx context.Context, h *HTTP, token string, extra map[string]any) (*LoginResult, error) {
	req, err := newRequest(ctx, "GET", tianyiBase+"/open/user/getUserBriefInfo.action?token="+url.QueryEscape(token), nil)
	if err != nil {
		return nil, err
	}
	// capture Set-Cookie from this call, then persist token + cookie
	resp, _, err := h.Do(ctx, req)
	if err != nil {
		return nil, errf("tianyi finish: %w", err)
	}
	jar := &cookieJar{}
	for _, c := range resp.Header.Values("Set-Cookie") {
		jar.set(c)
	}
	cookieStr := jar.String()
	cred := Credential{Netdisk: NetTianyi, Token: token, Raw: map[string]any{}}
	for k, v := range extra {
		cred.Raw[k] = v
	}
	if cookieStr != "" {
		cred.Cookie = cookieStr
	}
	// verify
	st, err := t.Status(ctx, cred, h)
	if err == nil && st.LoggedIn {
		cred.Cookie = firstNonEmpty(cookieStr, cred.Cookie)
	}
	return &LoginResult{Success: st != nil && st.LoggedIn, Credential: cred,
		Account: accountOrNil(st), Hint: "天翼云盘登录成功"}, nil
}

func (t *Tianyi) loginWithPassword(ctx context.Context, req LoginRequest, h *HTTP) (*LoginResult, error) {
	// 账号密码登录（证据：L1.l1() -> K2(7) 账号密码登录，C0278x0.f().s()）
	// RSA 公钥来自 https://api.cloud.189.cn/open/user/getCaptchaCode.action 的 captchaToken，
	// 实际加密在 Android 端本地完成；Go 侧先走文档化 unifyLoginByAccount 流程。
	if h.Evidence != nil {
		h.Evidence.Action = "tianyi_login"
		h.Evidence.Note = "POST /open/user/unifyLoginByAccount.action"
	}
	form := url.Values{
		"version":     {"6.2"},
		"accountType": {"01"},
		"userName":    {req.Account},
		"password":    {req.Password},
		"appId":       {tianyiAppID},
	}
	_, body, err := h.PostForm(ctx, tianyiBase+"/open/user/unifyLoginByAccount.action", form)
	if err != nil {
		return nil, errf("tianyi password login: %w", err)
	}
	var resp struct {
		Result      int    `json:"result"`
		Token       string `json:"token"`
		RedirectURL string `json:"redirectUrl"`
		Msg         string `json:"msg"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, errf("tianyi password login: bad json: %w", err)
	}
	if resp.Result != 0 || resp.Token == "" {
		return &LoginResult{Success: false, Hint: "天翼账号密码登录失败（" + resp.Msg + "）"}, nil
	}
	return t.finishLogin(ctx, h, resp.Token, nil)
}

func (t *Tianyi) loginWithSMS(ctx context.Context, req LoginRequest, h *HTTP) (*LoginResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "tianyi_login"
		h.Evidence.Note = "POST /open/user/verifySmsCode.action"
	}
	// 发送短信
	form := url.Values{"mobile": {req.Account}, "appId": {tianyiAppID}}
	if _, _, err := h.PostForm(ctx, tianyiBase+"/open/user/getSmsCode.action", form); err != nil {
		return nil, errf("tianyi sms send: %w", err)
	}
	form2 := url.Values{
		"mobile": {req.Account}, "code": {req.Code}, "appId": {tianyiAppID},
	}
	_, body, err := h.PostForm(ctx, tianyiBase+"/open/user/verifySmsCode.action", form2)
	if err != nil {
		return nil, errf("tianyi sms verify: %w", err)
	}
	var resp struct {
		Result      int    `json:"result"`
		Token       string `json:"token"`
		SessionKey  string `json:"sessionKey"`
		RedirectURL string `json:"redirectUrl"`
		Msg         string `json:"msg"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, errf("tianyi sms verify: bad json: %w", err)
	}
	if resp.Result != 0 || resp.Token == "" {
		return &LoginResult{Success: false, Hint: "天翼短信验证失败（" + resp.Msg + "）"}, nil
	}
	return t.finishLogin(ctx, h, resp.Token, map[string]any{"session_key": resp.SessionKey})
}

func (t *Tianyi) loginWithCookie(ctx context.Context, input string, h *HTTP) (*LoginResult, error) {
	st, err := t.Status(ctx, Credential{Netdisk: NetTianyi, Cookie: input}, h)
	if err != nil {
		return nil, errf("tianyi cookie verify: %w", err)
	}
	if st.LoggedIn {
		return &LoginResult{Success: true, Credential: Credential{Netdisk: NetTianyi, Cookie: input},
			Account: st.Account, Hint: "天翼云盘Cookie有效"}, nil
	}
	return &LoginResult{Success: false, Hint: "天翼云盘Cookie无效"}, nil
}

// cookieJar is a minimal Set-Cookie collector (persisted as cookie string).
type cookieJar struct{ parts []string }

func (j *cookieJar) set(setCookie string) {
	name := strings.TrimSpace(strings.SplitN(setCookie, "=", 2)[0])
	if name == "" {
		return
	}
	val := ""
	if idx := strings.Index(setCookie, "="); idx >= 0 {
		if semi := strings.Index(setCookie[idx+1:], ";"); semi >= 0 {
			val = setCookie[idx+1 : idx+1+semi]
		} else {
			val = setCookie[idx+1:]
		}
	}
	val = strings.TrimSpace(val)
	// replace existing name
	for i, p := range j.parts {
		if strings.HasPrefix(p, name+"=") {
			j.parts[i] = name + "=" + val
			return
		}
	}
	j.parts = append(j.parts, name+"="+val)
}

func (j *cookieJar) String() string { return strings.Join(j.parts, "; ") }

func accountOrNil(st *StatusResult) *AccountInfo {
	if st == nil {
		return nil
	}
	return st.Account
}

var _ = strconv.Itoa
var _ = fmt.Sprintf
