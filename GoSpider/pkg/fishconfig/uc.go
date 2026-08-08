package fishconfig

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// UC implements the UC网盘 action client (同源 UC-family CAS 扫码协议).
//
// 协议依据（PROTOCOL.md §9 UC + w1 uc-strings.txt）：
//   - 基址 https://pc-api.uc.cn/1/clouddrive/
//   - 扫码 https://api.open.uc.cn/cas/ajax/getTokenForQrcodeLogin?__dt=641254&__t={ts}
//   - 账号 https://drive.uc.cn/account/info?fr=pc&platform=pc（Cookie）
//   - 文件 https://pc-api.uc.cn/1/clouddrive/file/sort?pr=UCBrowser&fr=pc&...（Cookie）
//   - UA: uc-cloud-drive/1.8.7 ... Channel/ucpan_other_ch
type UC struct{}

func init() { register(&UC{}) }

// Name implements Client.
func (u *UC) Name() string { return NetUC }

var (
	ucCASBase   = "https://api.open.uc.cn/cas/ajax"
	ucDriveBase = "https://drive.uc.cn"
	ucAPIFile   = "https://pc-api.uc.cn/1/clouddrive"
)

// Status checks the saved cookie against the UC account endpoint.
func (u *UC) Status(ctx context.Context, cred Credential, h *HTTP) (*StatusResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "uc_status"
		h.Evidence.Note = "GET drive.uc.cn/account/info with saved cookie"
	}
	req, err := newRequest(ctx, "GET", ucDriveBase+"/account/info?fr=pc&platform=pc", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Cookie", cred.Cookie)
	req.Header.Set("Origin", ucDriveBase)
	_, body, err := h.Do(ctx, req)
	if err != nil {
		return nil, errf("uc status: %w", err)
	}
	var resp struct {
		Status int `json:"status"`
		Data   struct {
			Nickname string `json:"nickname"`
			Avatar   string `json:"avatar"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, errf("uc status: bad json: %w", err)
	}
	if resp.Status != 2000000 && resp.Status != 0 {
		return &StatusResult{LoggedIn: false, Hint: "UC凭证无效（status=" + itoa(resp.Status) + "）"}, nil
	}
	acc := &AccountInfo{Name: resp.Data.Nickname, Avatar: resp.Data.Avatar}
	return &StatusResult{LoggedIn: acc.Name != "", Account: acc, Hint: "UC网盘已登录"}, nil
}

// Scan starts the UC-family QR login.
func (u *UC) Scan(ctx context.Context, h *HTTP) (*ScanResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "uc_scan"
		h.Evidence.Note = "CAS getTokenForQrcodeLogin?__dt=641254&__t={ts} (live-reachable)"
	}
	ts := fmt.Sprintf("%d", time.Now().UnixMilli())
	_, body, err := h.Get(ctx, ucCASBase+"/getTokenForQrcodeLogin?__dt=641254&__t="+ts)
	if err != nil {
		return nil, errf("uc scan: %w", err)
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
		return nil, errf("uc scan: bad json: %w", err)
	}
	token := firstNonEmpty(tok.Data.Token, tok.Data.Members.Token)
	if token == "" {
		return nil, errf("uc scan: no token in response")
	}
	_, qb, err := h.Get(ctx, ucCASBase+"/getQrcodeLogin?token="+token)
	if err != nil {
		return nil, errf("uc scan: %w", err)
	}
	var qr struct {
		Data struct {
			Qrcode   string `json:"qrcode"`
			QrSign   string `json:"qr_sign"`
			LoginURL string `json:"login_url"`
		} `json:"data"`
	}
	_ = json.Unmarshal(qb, &qr)
	code := firstNonEmpty(qr.Data.Qrcode, qr.Data.LoginURL)
	if code == "" {
		return nil, errf("uc scan: qrcode missing (server returned %d bytes)", len(qb))
	}
	return &ScanResult{
		Kind:      "qrcode",
		QRContent: code,
		Session:   map[string]any{"token": token, "qrcode": code, "qr_sign": qr.Data.QrSign},
		Interval:  3,
		Timeout:   180,
		Hint:      "使用UC网盘App扫码",
	}, nil
}

// Login polls the scan session or verifies a pasted credential.
func (u *UC) Login(ctx context.Context, req LoginRequest, h *HTTP) (*LoginResult, error) {
	if req.Input != "" {
		return u.loginWithCredential(ctx, req.Input, h)
	}
	if len(req.Session) == 0 {
		return nil, errf("uc login: need session from uc_scan or pasted cookie/token")
	}
	if h.Evidence != nil {
		h.Evidence.Action = "uc_login"
		h.Evidence.Note = "poll CAS loginByQrcode until status ok"
	}
	qrcode, _ := req.Session["qrcode"].(string)
	sign, _ := req.Session["qr_sign"].(string)
	if qrcode == "" {
		return nil, errf("uc login: session missing qrcode")
	}
	for i := 0; i < 60; i++ {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}
		_, body, err := h.Get(ctx, ucCASBase+"/loginByQrcode?qrcode="+qrcode+"&qr_sign="+sign)
		if err != nil {
			return nil, errf("uc login poll: %w", err)
		}
		var poll struct {
			Status int `json:"status"`
			Data   struct {
				Status   int    `json:"status"`
				Cookie   string `json:"cookie"`
				Nickname string `json:"nickname"`
			} `json:"data"`
		}
		_ = json.Unmarshal(body, &poll)
		st := poll.Data.Status
		if st == 1 {
			return &LoginResult{
				Success:    true,
				Credential: Credential{Netdisk: NetUC, Cookie: poll.Data.Cookie},
				Account:    &AccountInfo{Name: poll.Data.Nickname},
				Hint:       "UC网盘登录成功",
			}, nil
		}
		if st != 0 && st != 2000001 && st != 2000002 {
			return &LoginResult{Success: false, Hint: "UC扫码失败或已取消（status=" + itoa(st) + "）"}, nil
		}
		if !sleepCtx(ctx, 3) {
			return nil, ctx.Err()
		}
	}
	return &LoginResult{Success: false, Hint: "UC扫码超时（180s）"}, nil
}

func (u *UC) loginWithCredential(ctx context.Context, input string, h *HTTP) (*LoginResult, error) {
	cookie := input
	if !strings.Contains(input, "=") {
		var m map[string]any
		if err := json.Unmarshal([]byte(input), &m); err == nil {
			cookie = firstNonEmpty(asString(m, "cookie"), asString(m, "token"))
		}
	}
	st, err := u.Status(ctx, Credential{Netdisk: NetUC, Cookie: cookie}, h)
	if err != nil {
		return nil, errf("uc login verify: %w", err)
	}
	if st.LoggedIn {
		return &LoginResult{Success: true, Credential: Credential{Netdisk: NetUC, Cookie: cookie},
			Account: st.Account, Hint: "UC凭证有效"}, nil
	}
	return &LoginResult{Success: false, Hint: "UC凭证无效"}, nil
}
