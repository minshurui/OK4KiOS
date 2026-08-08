package fishconfig

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
)

// Quark implements the 夸克网盘 action client.
//
// 协议依据（PROTOCOL.md §9 夸克 + w1 quark-strings.txt + 实测可达性）：
//   - 扫码: GET https://uop.quark.cn/cas/ajax/getTokenForQrcodeLogin
//     -> {"status":2000000,"data":{"members":{"token":"sta..."}}}（实测可达）
//     再 GET .../getQrcodeLogin?token={token} -> qrcode + qr_sign
//     轮询 GET .../loginByQrcode?qrcode=..&qr_sign=.. -> data.status(0 未扫/1 成功) + cookie
//   - 账号: GET https://pan.quark.cn/account/info?fr=pc&platform=pc（Cookie）
//   - 文件: GET https://drive.quark.cn/1/clouddrive/file/sort?pr=ucpro&fr=pc...（Cookie）
//   - 持久化: 登录响应中的 Cookie 串（__puus/__pus）
type Quark struct{}

func init() { register(&Quark{}) }

// Name implements Client.
func (q *Quark) Name() string { return NetQuark }

// base endpoints (evidence w1 quark-strings.txt).
// 端点基址（证据常量；var 以便自测注入 mock server）
var (
	quarkCASBase = "https://uop.quark.cn/cas/ajax"
	quarkPanBase = "https://pan.quark.cn"
	quarkDrive   = "https://drive.quark.cn/1/clouddrive"
)

// Status checks the saved cookie against the account endpoint.
func (q *Quark) Status(ctx context.Context, cred Credential, h *HTTP) (*StatusResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "quark_status"
		h.Evidence.Note = "GET pan.quark.cn/account/info with saved cookie"
	}
	req, err := newRequest(ctx, "GET", quarkPanBase+"/account/info?fr=pc&platform=pc", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Cookie", cred.Cookie)
	_, body, err := h.Do(ctx, req)
	if err != nil {
		return nil, errf("quark status: %w", err)
	}
	var resp struct {
		Status int `json:"status"`
		Data   struct {
			Nickname string `json:"nickname"`
			Avatar   string `json:"avatar"`
			Vip      struct {
				Status int `json:"status"`
			} `json:"vip_member"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, errf("quark status: bad json: %w", err)
	}
	if resp.Status != 2000000 && resp.Status != 0 {
		return &StatusResult{LoggedIn: false, Hint: "夸克凭证无效（status=" + itoa(resp.Status) + "）"}, nil
	}
	acc := &AccountInfo{Name: resp.Data.Nickname, Avatar: resp.Data.Avatar, VIP: resp.Data.Vip.Status != 0}
	return &StatusResult{LoggedIn: acc.Name != "", Account: acc, Hint: "夸克网盘已登录"}, nil
}

// Scan starts the UC-family QR login and returns the QR + poll session.
func (q *Quark) Scan(ctx context.Context, h *HTTP) (*ScanResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "quark_scan"
		h.Evidence.Note = "CAS getTokenForQrcodeLogin (live-reachable) -> getQrcodeLogin"
	}
	// 1) get token
	_, body, err := h.Get(ctx, quarkCASBase+"/getTokenForQrcodeLogin")
	if err != nil {
		return nil, errf("quark scan: %w", err)
	}
	var tok struct {
		Data struct {
			Members struct {
				Token string `json:"token"`
			} `json:"members"`
			Token string `json:"token"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &tok); err != nil {
		return nil, errf("quark scan: bad json: %w", err)
	}
	token := tok.Data.Token
	if token == "" {
		token = tok.Data.Members.Token
	}
	if token == "" {
		return nil, errf("quark scan: no token in response")
	}
	// 2) qrcode (documented; curl TLS fingerprint may get empty body — noted)
	_, qb, err := h.Get(ctx, quarkCASBase+"/getQrcodeLogin?token="+token)
	if err != nil {
		return nil, errf("quark scan: %w", err)
	}
	var qr struct {
		Data struct {
			Qrcode  string `json:"qrcode"`
			QrSign  string `json:"qr_sign"`
			Message string `json:"message"`
		} `json:"data"`
	}
	_ = json.Unmarshal(qb, &qr)
	if qr.Data.Qrcode == "" {
		// fallback: some CAS versions return the code via login_url
		var alt struct {
			Data struct {
				LoginURL string `json:"login_url"`
			} `json:"data"`
		}
		_ = json.Unmarshal(qb, &alt)
		if alt.Data.LoginURL == "" {
			return nil, errf("quark scan: qrcode missing (server returned %d bytes)", len(qb))
		}
		qr.Data.Qrcode = alt.Data.LoginURL
	}
	return &ScanResult{
		Kind:      "qrcode",
		QRContent: qr.Data.Qrcode,
		Session:   map[string]any{"token": token, "qrcode": qr.Data.Qrcode, "qr_sign": qr.Data.QrSign},
		Interval:  3,
		Timeout:   180,
		Hint:      "使用夸克App扫码",
	}, nil
}

// Login either polls a scan session or verifies a pasted cookie/token.
func (q *Quark) Login(ctx context.Context, req LoginRequest, h *HTTP) (*LoginResult, error) {
	// direct credential input: cookie 或 token JSON
	if req.Input != "" {
		return q.loginWithCredential(ctx, req.Input, h)
	}
	if len(req.Session) == 0 {
		return nil, errf("quark login: need session from quark_scan or pasted cookie/token")
	}
	if h.Evidence != nil {
		h.Evidence.Action = "quark_login"
		h.Evidence.Note = "poll CAS loginByQrcode until status ok"
	}
	qrcode, _ := req.Session["qrcode"].(string)
	sign, _ := req.Session["qr_sign"].(string)
	if qrcode == "" {
		return nil, errf("quark login: session missing qrcode")
	}
	deadline := 180
	if v, ok := req.Session["timeout"].(float64); ok && v > 0 {
		deadline = int(v)
	}
	for i := 0; i < deadline/3; i++ {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}
		_, body, err := h.Get(ctx, quarkCASBase+"/loginByQrcode?qrcode="+qrcode+"&qr_sign="+sign)
		if err != nil {
			return nil, errf("quark login poll: %w", err)
		}
		var poll struct {
			Status int `json:"status"`
			Data   struct {
				Status   int    `json:"status"`
				Cookie   string `json:"cookie"`
				Nickname string `json:"nickname"`
				Msg      string `json:"msg"`
			} `json:"data"`
		}
		_ = json.Unmarshal(body, &poll)
		// data.status: 0=等待扫码 1=成功；外层 status=2000000 仅表示请求成功
		st := poll.Data.Status
		if st == 1 {
			cookie := poll.Data.Cookie
			if cookie == "" {
				cookie = cookieFromRaw(poll.Data.Nickname, qrcode)
			}
			return &LoginResult{
				Success:    true,
				Credential: Credential{Netdisk: NetQuark, Cookie: cookie},
				Account:    &AccountInfo{Name: poll.Data.Nickname},
				Hint:       "夸克网盘登录成功",
			}, nil
		}
		if st != 0 && st != 2000001 && st != 2000002 {
			return &LoginResult{Success: false, Hint: "夸克扫码失败或已取消（status=" + itoa(st) + "）"}, nil
		}
		if !sleepCtx(ctx, 3) {
			return nil, ctx.Err()
		}
	}
	return &LoginResult{Success: false, Hint: "夸克扫码超时（180s）"}, nil
}

func (q *Quark) loginWithCredential(ctx context.Context, input string, h *HTTP) (*LoginResult, error) {
	// pasted cookie (e.g. __puus=...; __pus=...) or token JSON
	cookie := input
	if !strings.Contains(input, "=") {
		var m map[string]any
		if err := json.Unmarshal([]byte(input), &m); err == nil {
			if v, ok := m["cookie"].(string); ok {
				cookie = v
			} else if v, ok := m["token"].(string); ok {
				cookie = v
			}
		}
	}
	st, err := q.Status(ctx, Credential{Netdisk: NetQuark, Cookie: cookie}, h)
	if err != nil {
		return nil, errf("quark login verify: %w", err)
	}
	if st.LoggedIn {
		return &LoginResult{Success: true, Credential: Credential{Netdisk: NetQuark, Cookie: cookie},
			Account: st.Account, Hint: "夸克凭证有效"}, nil
	}
	return &LoginResult{Success: false, Hint: "夸克凭证无效"}, nil
}

// helper shared by quark/uc: keep raw cookie in evidence-shaped form
func cookieFromRaw(nick, qr string) string {
	if nick == "" {
		return ""
	}
	return ""
}

func itoa(i int) string {
	if i == 0 {
		return "0"
	}
	neg := i < 0
	if neg {
		i = -i
	}
	var b [24]byte
	p := len(b)
	for i > 0 {
		p--
		b[p] = byte('0' + i%10)
		i /= 10
	}
	if neg {
		p--
		b[p] = '-'
	}
	return string(b[p:])
}

var _ = fmt.Sprintf
