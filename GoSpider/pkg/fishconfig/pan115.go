package fishconfig

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"strings"
	"time"
)

// Pan115 implements the 115网盘 action client.
//
// 协议依据（PROTOCOL.md §9 115 + w1 pan115-strings.txt）：
//   - 扫码 https://passportapi.115.com/app/1.0/alipaymini/1.0/login/qrcode/
//     （实测可达但需正确 query 参数，ac=alipaymini&u=0&time_stamp=；参数细节以 smali 为准）
//   - 轮询 https://qrcodeapi.115.com/api/1.0/alipaymini/1.0/token/?ac=..&uid=..&time_stamp=..
//     或 https://qrcodeapi.115.com/get/status/（实测返回 key invalid -> 需 key 参数）
//   - 存储 https://115.com/index.php?ct=ajax&ac=get_storage_info（Cookie）
//   - 登录方式：Cookie 输入（L1.W0() -> Z0(...,"Cookie",...)）
type Pan115 struct{}

func init() { register(&Pan115{}) }

// Name implements Client.
func (p *Pan115) Name() string { return NetPan115 }

var (
	pan115QRAPI     = "https://passportapi.115.com/app/1.0/alipaymini/1.0/login/qrcode/"
	pan115TokenAPI  = "https://qrcodeapi.115.com/api/1.0/alipaymini/1.0/token/"
	pan115StatusAPI = "https://115.com/index.php"
)

// Status checks the saved cookie against the storage info endpoint.
func (p *Pan115) Status(ctx context.Context, cred Credential, h *HTTP) (*StatusResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "pan115_status"
		h.Evidence.Note = "GET 115.com/index.php?ct=ajax&ac=get_storage_info with cookie"
	}
	req, err := newRequest(ctx, "GET", pan115StatusAPI+"?ct=ajax&ac=get_storage_info", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Cookie", cred.Cookie)
	_, body, err := h.Do(ctx, req)
	if err != nil {
		return nil, errf("pan115 status: %w", err)
	}
	var resp struct {
		State int `json:"state"`
		Data  struct {
			UserName string `json:"user_name"`
			UserID   string `json:"user_id"`
			UseSize  int64  `json:"use_size"`
			Size     int64  `json:"size"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, errf("pan115 status: bad json: %w", err)
	}
	if resp.State != 0 || resp.Data.UserName == "" {
		return &StatusResult{LoggedIn: false, Hint: "115Cookie无效（state=" + itoa(resp.State) + "）"}, nil
	}
	acc := &AccountInfo{Name: resp.Data.UserName, UserID: resp.Data.UserID}
	return &StatusResult{LoggedIn: true, Account: acc,
		Usage: &UsageInfo{Used: resp.Data.UseSize, Total: resp.Data.Size},
		Hint:  "115网盘已登录"}, nil
}

// Scan starts the 115 QR login.
func (p *Pan115) Scan(ctx context.Context, h *HTTP) (*ScanResult, error) {
	if h.Evidence != nil {
		h.Evidence.Action = "pan115_scan"
		h.Evidence.Note = "GET /app/1.0/alipaymini/1.0/login/qrcode/ (query params 需 smali 补齐)"
	}
	ts := fmt.Sprintf("%d", time.Now().Unix())
	u := pan115QRAPI + "?ac=alipaymini&u=0&time_stamp=" + ts
	_, body, err := h.Get(ctx, u)
	if err != nil {
		return nil, errf("pan115 scan: %w", err)
	}
	var resp struct {
		State int `json:"state"`
		Data  struct {
			Qrcode    string `json:"qrcode"`
			UID       string `json:"uid"`
			AppID     string `json:"app_id"`
			TimeStamp string `json:"time_stamp"`
			Sign      string `json:"sign"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, errf("pan115 scan: bad json: %w", err)
	}
	if resp.State != 0 || resp.Data.Qrcode == "" {
		return nil, errf("pan115 scan: state=%d msg=%s（query 参数需从 smali 补齐）", resp.State, string(body))
	}
	qr := resp.Data.Qrcode
	if !strings.Contains(qr, "://") {
		// qrcode 是内容 ID；二维码图片由 115 前端从 cdnassets 渲染
		qr = "https://115.com/?ct=login&ac=qrcode&qrcode=" + url.QueryEscape(qr)
	}
	return &ScanResult{
		Kind:      "qrcode",
		QRContent: qr,
		Session: map[string]any{
			"qrcode": resp.Data.Qrcode, "uid": resp.Data.UID, "app_id": resp.Data.AppID,
			"time_stamp": resp.Data.TimeStamp, "sign": resp.Data.Sign,
		},
		Interval: 3,
		Timeout:  180,
		Hint:     "使用115App扫码",
	}, nil
}

// Login polls the QR session or verifies a pasted cookie.
func (p *Pan115) Login(ctx context.Context, req LoginRequest, h *HTTP) (*LoginResult, error) {
	if req.Input != "" {
		return p.loginWithCookie(ctx, req.Input, h)
	}
	if len(req.Session) == 0 {
		return nil, errf("pan115 login: need session from pan115_scan or pasted cookie")
	}
	if h.Evidence != nil {
		h.Evidence.Action = "pan115_login"
		h.Evidence.Note = "poll /api/1.0/alipaymini/1.0/token/ until data.status=ok"
	}
	uid, _ := req.Session["uid"].(string)
	appID, _ := req.Session["app_id"].(string)
	ts, _ := req.Session["time_stamp"].(string)
	code, _ := req.Session["qrcode"].(string)
	for i := 0; i < 60; i++ {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}
		q := url.Values{"ac": {appID}, "uid": {uid}, "time_stamp": {ts}, "qrcode": {code}}
		_, body, err := h.Get(ctx, pan115TokenAPI+"?"+q.Encode())
		if err != nil {
			return nil, errf("pan115 poll: %w", err)
		}
		var poll struct {
			State int `json:"state"`
			Data  struct {
				Status   string `json:"status"` // wait / ok / cancel
				Token    string `json:"token"`
				UserID   string `json:"user_id"`
				UserName string `json:"user_name"`
			} `json:"data"`
		}
		_ = json.Unmarshal(body, &poll)
		switch poll.Data.Status {
		case "ok":
			cookie := "UID=" + poll.Data.UserID + "; CID=" + poll.Data.UserID + "; SEID=" + poll.Data.Token
			return &LoginResult{
				Success:    true,
				Credential: Credential{Netdisk: NetPan115, Cookie: cookie},
				Account:    &AccountInfo{Name: poll.Data.UserName, UserID: poll.Data.UserID},
				Hint:       "115网盘登录成功",
			}, nil
		case "cancel", "expired":
			return &LoginResult{Success: false, Hint: "115扫码已取消或过期"}, nil
		}
		if !sleepCtx(ctx, 3) {
			return nil, ctx.Err()
		}
	}
	return &LoginResult{Success: false, Hint: "115扫码超时（180s）"}, nil
}

func (p *Pan115) loginWithCookie(ctx context.Context, input string, h *HTTP) (*LoginResult, error) {
	st, err := p.Status(ctx, Credential{Netdisk: NetPan115, Cookie: input}, h)
	if err != nil {
		return nil, errf("pan115 cookie verify: %w", err)
	}
	if st.LoggedIn {
		return &LoginResult{Success: true, Credential: Credential{Netdisk: NetPan115, Cookie: input},
			Account: st.Account, Hint: "115Cookie有效"}, nil
	}
	return &LoginResult{Success: false, Hint: "115Cookie无效"}, nil
}

var _ = time.Now
