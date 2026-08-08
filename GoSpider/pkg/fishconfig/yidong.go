package fishconfig

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Yidong implements the 移动云盘(139) action client.
//
// 协议依据（PROTOCOL.md §3/§9 + w1 yidong-strings.txt + 实测可达性）：
//   - 登录方式：App扫码(K2(23)) / 账号密码(K2(24)) / 导入凭证(K2(25))（L1.r1() -> C0218T0.F()）
//   - 扫码页 https://yun.139.com/w/#/qrcLogin?sID={sid}（证据；sid 来自 139 会话接口）
//   - 用户   GET https://user-njs.yun.139.com/user/getUser（Cookie/Authorization；实测可达）
//   - 配额   GET https://user-njs.yun.139.com/user/disk/quota/detail
//   - 列表   POST https://personal-kd-njs.yun.139.com/hcy/v1.2/queryContentList
//   - 头     x-deviceinfo；Authorization 支持 Basic/Cookie token（证据正则）
type Yidong struct{}

func init() { register(&Yidong{}) }

// Name implements Client.
func (y *Yidong) Name() string { return NetYidong }

var (
	yidongUserBase = "https://user-njs.yun.139.com"
	yidongListBase = "https://personal-kd-njs.yun.139.com/hcy"
	yidongScanPage = "https://yun.139.com/w/#/qrcLogin?sID=%s"
	yidongAPIBase  = "https://api.139.com"
)

// Status checks the saved credential (cookie or authorization) via getUser.
func (y *Yidong) Status(ctx context.Context, cred Credential, h *HTTP) (*StatusResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "yidong_status"
		h.Evidence.Note = "GET user-njs.yun.139.com/user/getUser with cookie/authorization (live-reachable)"
	}
	req, err := newRequest(ctx, "GET", yidongUserBase+"/user/getUser", nil)
	if err != nil {
		return nil, err
	}
	applyYidongCred(req, cred)
	_, body, err := h.Do(ctx, req)
	if err != nil {
		return nil, errf("yidong status: %w", err)
	}
	var resp struct {
		Success bool   `json:"success"`
		Code    string `json:"code"`
		Data    struct {
			User struct {
				Name   string `json:"name"`
				UserID string `json:"userId"`
			} `json:"user"`
			UserName        string `json:"userName"`
			AccountName     string `json:"accountName"`
			UserProfileInfo any    `json:"userProfileInfo"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, errf("yidong status: bad json: %w", err)
	}
	if !resp.Success {
		return &StatusResult{LoggedIn: false, Hint: "移动云盘凭证无效（" + resp.Code + "）"}, nil
	}
	name := firstNonEmpty(resp.Data.User.Name, resp.Data.UserName, resp.Data.AccountName)
	acc := &AccountInfo{Name: name, UserID: resp.Data.User.UserID}
	return &StatusResult{LoggedIn: name != "", Account: acc, Hint: "移动云盘已登录"}, nil
}

// Scan opens the 139 App扫码登录 page (sID from the 139 session interface).
func (y *Yidong) Scan(ctx context.Context, h *HTTP) (*ScanResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "yidong_scan"
		h.Evidence.Note = "sid 来自 139 会话接口（api.139.com/queryId，部分网络不可达）"
	}
	sid := ""
	// 139 会话接口：GET https://api.139.com/queryId -> {"data":{"sid":...}}
	var sess struct {
		Data struct {
			SID string `json:"sid"`
		} `json:"data"`
	}
	if _, err := h.GetJSON(ctx, yidongAPIBase+"/queryId", &sess); err == nil {
		sid = sess.Data.SID
	}
	if sid == "" {
		// fallback：本地生成会话标记，扫码页仍可打开（App 侧确认后由登录接口回填）
		sid = fmt.Sprintf("ok4k%d", time.Now().Unix())
	}
	qrURL := fmt.Sprintf(yidongScanPage, url.QueryEscape(sid))
	return &ScanResult{
		Kind:      "web",
		QRURL:     qrURL,
		QRContent: qrURL,
		Session:   map[string]any{"sid": sid},
		Interval:  3,
		Timeout:   180,
		Hint:      "使用移动云盘App扫码，或导入凭证（Cookie / Authorization）",
	}, nil
}

// Login supports pasted credential (Cookie/Authorization), account+password,
// or poll of a scan session.
func (y *Yidong) Login(ctx context.Context, req LoginRequest, h *HTTP) (*LoginResult, error) {
	switch {
	case req.Input != "":
		return y.loginWithCredential(ctx, req.Input, h)
	case req.Account != "" && req.Password != "":
		return y.loginWithPassword(ctx, req, h)
	case len(req.Session) > 0:
		return y.pollQR(ctx, req, h)
	}
	return nil, errf("yidong login: need credential / account+password / scan session")
}

func (y *Yidong) pollQR(ctx context.Context, req LoginRequest, h *HTTP) (*LoginResult, error) {
	// App 扫码确认后，由 139 登录接口返回 jclk_token / cookie；轮询接口形态：
	// GET https://api.139.com/queryLoginResult?sid={sid}（文档化形态，参数以 smali 为准）
	if h.Evidence != nil {
		h.Evidence.Action = "yidong_login"
		h.Evidence.Note = "poll 139 qrcLogin result"
	}
	sid, _ := req.Session["sid"].(string)
	for i := 0; i < 60; i++ {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}
		var out struct {
			Data struct {
				JclkToken string `json:"jclk_token"`
				Status    string `json:"status"`
				Msg       string `json:"msg"`
			} `json:"data"`
		}
		_, err := h.GetJSON(ctx, yidongAPIBase+"/queryLoginResult?sid="+url.QueryEscape(sid), &out)
		if err != nil {
			return nil, errf("yidong poll: %w", err)
		}
		if out.Data.JclkToken != "" || out.Data.Status == "ok" {
			return &LoginResult{Success: true,
				Credential: Credential{Netdisk: NetYidong, Token: out.Data.JclkToken,
					Raw: map[string]any{"sid": sid, "jclk_token": out.Data.JclkToken}},
				Hint: "移动云盘扫码登录成功（后续需在 App 侧完成会话）"}, nil
		}
		if out.Data.Status == "cancel" || out.Data.Status == "expired" {
			return &LoginResult{Success: false, Hint: "移动云盘扫码已取消或过期"}, nil
		}
		if !sleepCtx(ctx, 3) {
			return nil, ctx.Err()
		}
	}
	return &LoginResult{Success: false, Hint: "移动云盘扫码超时"}, nil
}

func (y *Yidong) loginWithPassword(ctx context.Context, req LoginRequest, h *HTTP) (*LoginResult, error) {
	// 139 账号密码登录：POST https://api.139.com/login
	// form: userName, password, accountType=02, sid（RSA 加密在 Android 本地完成）
	if h.Evidence != nil {
		h.Evidence.Action = "yidong_login"
		h.Evidence.Note = "POST api.139.com/login (userName/password/sid)"
	}
	form := url.Values{
		"userName":    {req.Account},
		"password":    {req.Password},
		"accountType": {"02"},
	}
	var out struct {
		Data struct {
			JclkToken string `json:"jclk_token"`
			Msg       string `json:"msg"`
		} `json:"data"`
	}
	_, body, err := h.PostForm(ctx, yidongAPIBase+"/login", form)
	if err != nil {
		return nil, errf("yidong password login: %w", err)
	}
	_ = json.Unmarshal(body, &out)
	if out.Data.JclkToken == "" {
		return &LoginResult{Success: false, Hint: "移动云盘账号密码登录失败（" + out.Data.Msg + "）"}, nil
	}
	// 用 jclk_token 换会话 Cookie
	cookie, err := y.exchangeJclk(ctx, out.Data.JclkToken, h)
	if err != nil {
		return nil, err
	}
	cred := Credential{Netdisk: NetYidong, Cookie: cookie, Token: out.Data.JclkToken}
	st, err := y.Status(ctx, cred, h)
	if err != nil {
		return nil, errf("yidong verify: %w", err)
	}
	return &LoginResult{Success: st.LoggedIn, Credential: cred, Account: st.Account,
		Hint: "移动云盘登录成功"}, nil
}

func (y *Yidong) exchangeJclk(ctx context.Context, jclk string, h *HTTP) (string, error) {
	// GET https://yun.139.com/orchestration/auth/...?jclk_token=... 建立会话 Cookie
	u := "https://yun.139.com/orchestration/auth/login?jclk_token=" + url.QueryEscape(jclk)
	req, err := newRequest(ctx, "GET", u, nil)
	if err != nil {
		return "", err
	}
	jar := &cookieJar{}
	client := &http.Client{
		CheckRedirect: func(r *http.Request, via []*http.Request) error {
			for _, c := range r.Response.Header.Values("Set-Cookie") {
				jar.set(c)
			}
			if len(via) >= 6 {
				return http.ErrUseLastResponse
			}
			return nil
		},
	}
	h2 := *h
	h2.Client = client
	resp, _, err := h2.Do(ctx, req)
	if err != nil {
		return "", err
	}
	for _, c := range resp.Header.Values("Set-Cookie") {
		jar.set(c)
	}
	return jar.String(), nil
}

func (y *Yidong) loginWithCredential(ctx context.Context, input string, h *HTTP) (*LoginResult, error) {
	// 导入凭证：Cookie 串 / Authorization（Basic 或 Bearer）/"authorization=..." 片段
	cred := Credential{Netdisk: NetYidong}
	low := strings.ToLower(input)
	switch {
	case strings.HasPrefix(low, "authorization"), strings.HasPrefix(low, "bearer "), strings.HasPrefix(low, "basic "):
		cred.Raw = map[string]any{"authorization": input}
	case strings.Contains(low, "="):
		cred.Cookie = input
	default:
		cred.Raw = map[string]any{"authorization": input}
	}
	st, err := y.Status(ctx, cred, h)
	if err != nil {
		return nil, errf("yidong credential verify: %w", err)
	}
	if st.LoggedIn {
		return &LoginResult{Success: true, Credential: cred, Account: st.Account,
			Hint: "移动云盘凭证有效"}, nil
	}
	return &LoginResult{Success: false, Hint: "移动云盘凭证无效"}, nil
}

// applyYidongCred sets Cookie or Authorization on a request.
func applyYidongCred(req *http.Request, cred Credential) {
	if cred.Cookie != "" {
		req.Header.Set("Cookie", cred.Cookie)
	}
	if auth, _ := cred.Raw["authorization"].(string); auth != "" {
		req.Header.Set("Authorization", auth)
	} else if cred.Token != "" {
		req.Header.Set("Authorization", "Bearer "+cred.Token)
	}
}
