package fishconfig

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
)

// Baidu implements the 百度网盘 action client.
//
// 协议依据（PROTOCOL.md §3/§9 + 公开 passport 扫码协议）：
//   - 登录方式：扫码(K2(17)) / 手动Cookie（L1.H0() -> T0(...,"baidu",...)）
//   - 扫码 GET https://passport.baidu.com/v2/api/getqrcode?lp=pc&apiver=v3 -> {data:{img,sign}}
//   - 轮询 GET https://passport.baidu.com/v2/api/qrcode/{sign}?lp=pc&apiver=v3
//     status: 0 未扫 / 1 已扫待确认 / 2 已确认 / 3 过期
//   - 登录 GET https://passport.baidu.com/v3/api/login?sign=..&u=http://pan.baidu.com/disk/home
//     （重定向链写入 BDUSS）
//   - 账号 GET https://pan.baidu.com/api/user/getinfo（Cookie）-> {baidu_name, netdisk_name}
type Baidu struct{}

func init() { register(&Baidu{}) }

// Name implements Client.
func (b *Baidu) Name() string { return NetBaidu }

var (
	baiduPassport = "https://passport.baidu.com"
	baiduPanAPI   = "https://pan.baidu.com"
)

// Status checks the saved cookie against the pan user info endpoint.
func (b *Baidu) Status(ctx context.Context, cred Credential, h *HTTP) (*StatusResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "baidu_status"
		h.Evidence.Note = "GET pan.baidu.com/api/user/getinfo with cookie"
	}
	req, err := newRequest(ctx, "GET", baiduPanAPI+"/api/user/getinfo", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Cookie", cred.Cookie)
	req.Header.Set("Referer", "https://pan.baidu.com/")
	_, body, err := h.Do(ctx, req)
	if err != nil {
		return nil, errf("baidu status: %w", err)
	}
	var resp struct {
		Errno       int    `json:"errno"`
		BaiduName   string `json:"baidu_name"`
		NetdiskName string `json:"netdisk_name"`
		AvatarURL   string `json:"avatar_url"`
		ErrMsg      string `json:"errmsg"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, errf("baidu status: bad json: %w", err)
	}
	if resp.Errno != 0 {
		return &StatusResult{LoggedIn: false, Hint: "百度网盘Cookie无效（errno=" + itoa(resp.Errno) + " " + resp.ErrMsg + "）"}, nil
	}
	name := firstNonEmpty(resp.NetdiskName, resp.BaiduName)
	acc := &AccountInfo{Name: name, Avatar: resp.AvatarURL}
	return &StatusResult{LoggedIn: name != "", Account: acc, Hint: "百度网盘已登录"}, nil
}

// Scan starts the Baidu passport QR login.
func (b *Baidu) Scan(ctx context.Context, h *HTTP) (*ScanResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "baidu_scan"
		h.Evidence.Note = "GET passport.baidu.com/v2/api/getqrcode"
	}
	_, body, err := h.Get(ctx, baiduPassport+"/v2/api/getqrcode?lp=pc&apiver=v3")
	if err != nil {
		return nil, errf("baidu scan: %w", err)
	}
	var resp struct {
		Errno int `json:"errno"`
		Data  struct {
			Img  string `json:"img"` // data:image URL
			Sign string `json:"sign"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, errf("baidu scan: bad json: %w", err)
	}
	if resp.Errno != 0 || resp.Data.Sign == "" {
		return nil, errf("baidu scan: getqrcode failed errno=%d", resp.Errno)
	}
	return &ScanResult{
		Kind:     "qrcode",
		QRImage:  resp.Data.Img,
		Session:  map[string]any{"sign": resp.Data.Sign},
		Interval: 3,
		Timeout:  180,
		Hint:     "使用百度网盘App扫码",
	}, nil
}

// Login polls the QR session, or verifies a pasted cookie.
func (b *Baidu) Login(ctx context.Context, req LoginRequest, h *HTTP) (*LoginResult, error) {
	if req.Input != "" {
		return b.loginWithCookie(ctx, req.Input, h)
	}
	if len(req.Session) == 0 {
		return nil, errf("baidu login: need session from baidu_scan or pasted cookie")
	}
	if h.Evidence != nil {
		h.Evidence.Action = "baidu_login"
		h.Evidence.Note = "poll /v2/api/qrcode/{sign} until confirmed, then /v3/api/login for BDUSS"
	}
	sign, _ := req.Session["sign"].(string)
	if sign == "" {
		return nil, errf("baidu login: session missing sign")
	}
	for i := 0; i < 60; i++ {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}
		_, body, err := h.Get(ctx, baiduPassport+"/v2/api/qrcode/"+sign+"?lp=pc&apiver=v3")
		if err != nil {
			return nil, errf("baidu poll: %w", err)
		}
		var poll struct {
			Errno int `json:"errno"`
			Data  struct {
				Status int `json:"status"`
			} `json:"data"`
		}
		_ = json.Unmarshal(body, &poll)
		switch poll.Data.Status {
		case 2: // confirmed -> login to grab BDUSS cookie
			return b.finishQR(ctx, sign, h)
		case 3:
			return &LoginResult{Success: false, Hint: "百度二维码已过期，请重新扫码"}, nil
		}
		if !sleepCtx(ctx, 3) {
			return nil, ctx.Err()
		}
	}
	return &LoginResult{Success: false, Hint: "百度扫码超时（180s）"}, nil
}

// finishQR hits the v3 login URL (no redirect follow) and captures Set-Cookie.
func (b *Baidu) finishQR(ctx context.Context, sign string, h *HTTP) (*LoginResult, error) {
	u := baiduPassport + "/v3/api/login?sign=" + sign + "&u=" + "http%3A%2F%2Fpan.baidu.com%2Fdisk%2Fhome" + "&apiver=v3&lp=pc"
	req, err := newRequest(ctx, "GET", u, nil)
	if err != nil {
		return nil, err
	}
	// do not follow redirects; collect Set-Cookie from the 302 chain
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
		return nil, errf("baidu finish: %w", err)
	}
	for _, c := range resp.Header.Values("Set-Cookie") {
		jar.set(c)
	}
	cookie := jar.String()
	if !strings.Contains(cookie, "BDUSS") && !strings.Contains(cookie, "BDUSS=") {
		return &LoginResult{Success: false, Hint: "百度扫码确认但未取到 BDUSS Cookie"}, nil
	}
	st, err := b.Status(ctx, Credential{Netdisk: NetBaidu, Cookie: cookie}, h)
	if err != nil {
		return nil, errf("baidu verify: %w", err)
	}
	return &LoginResult{Success: st.LoggedIn, Credential: Credential{Netdisk: NetBaidu, Cookie: cookie},
		Account: st.Account, Hint: "百度网盘登录成功"}, nil
}

func (b *Baidu) loginWithCookie(ctx context.Context, input string, h *HTTP) (*LoginResult, error) {
	st, err := b.Status(ctx, Credential{Netdisk: NetBaidu, Cookie: input}, h)
	if err != nil {
		return nil, errf("baidu cookie verify: %w", err)
	}
	if st.LoggedIn {
		return &LoginResult{Success: true, Credential: Credential{Netdisk: NetBaidu, Cookie: input},
			Account: st.Account, Hint: "百度网盘Cookie有效"}, nil
	}
	return &LoginResult{Success: false, Hint: "百度网盘Cookie无效"}, nil
}
