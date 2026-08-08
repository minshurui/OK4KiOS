package fishconfig

import (
	"net/http"
	"testing"
)

// tianyi 自测：status/scan(二维码)/login(轮询+账号密码+短信+cookie)/thread/clean。
func TestTianyiActions(t *testing.T) {
	m := newMock()
	m.onJSON("/open/user/getQrCode.action", `{"result":0,"qrCode":"TIANYI_QR_1","sessionKey":"SK1","shortToken":"ST1","time":1}`, 200)
	var pollN int
	m.on("/open/user/qrCodeLogin.action", func(w http.ResponseWriter, r *http.Request) {
		pollN++
		if pollN <= 1 {
			w.Write([]byte(`{"result":1,"msg":"waiting"}`))
			return
		}
		w.Write([]byte(`{"result":0,"token":"LOGIN_TOKEN_1","redirectUrl":"http://mock/cb"}`))
	})
	// getUserBriefInfo.action?token=... 建立会话 + 返回用户信息
	m.onJSON("/open/user/getUserBriefInfo.action", `{"result":0,"userBriefInfo":{"name":"天翼用户","nickname":"天翼用户","avatar":"","userInfoId":"189-1"}}`, 200)
	// v2 状态端点（带 cookie）
	m.onJSON("/api/portal/v2/getUserBriefInfo.action", `{"result":0,"userBriefInfo":{"name":"天翼用户","nickname":"天翼用户","avatar":"","userInfoId":"189-1"}}`, 200)
	// 账号密码登录
	m.onJSON("/open/user/unifyLoginByAccount.action", `{"result":0,"token":"PW_TOKEN_1","redirectUrl":"http://mock/cb"}`, 200)
	// 短信
	m.onJSON("/open/user/getSmsCode.action", `{"result":0}`, 200)
	m.onJSON("/open/user/verifySmsCode.action", `{"result":0,"token":"SMS_TOKEN_1","sessionKey":"SK_SMS"}`, 200)

	base := m.start(t)
	setStr(t, &tianyiBase, base)
	gw := NewGateway()
	gw.HTTP = DefaultHTTPFor(NetTianyi)

	// status 未登录
	r := gwDispatch(t, gw, "tianyi_status", "")
	assertOK(t, r)
	// status 已登录（cookie）
	r = gwDispatch(t, gw, "tianyi_status", `{"netdisk":"tianyi","cookie":"COOKIE_SESSION_ID=abc"}`)
	assertOK(t, r)
	if st, _ := r.Data.(*StatusResult); st == nil || !st.LoggedIn || st.Account.Name != "天翼用户" {
		t.Fatalf("tianyi status: %+v", r.Data)
	}
	// scan
	r = gwDispatch(t, gw, "tianyi_login", "")
	assertOK(t, r)
	ls, _ := r.Data.(*LoginStage)
	sc := (*ScanResult)(nil)
	if ls != nil {
		sc = ls.Scan
	}
	if sc == nil || sc.QRContent != "TIANYI_QR_1" {
		t.Fatalf("tianyi scan: %+v", r.Data)
	}
	// login 轮询
	r = gwDispatch(t, gw, "tianyi_login", `{"session":{"session_key":"SK1","short_token":"ST1","app_id":"8027001086180899"}}`)
	assertOK(t, r)
	ls, _ = r.Data.(*LoginStage)
	if ls == nil || ls.Login == nil || !ls.Login.Success {
		t.Fatalf("tianyi login poll: %+v", r.Data)
	}
	// login 账号密码
	r = gwDispatch(t, gw, "tianyi_login", `{"account":"13800000000","password":"pwd"}`)
	assertOK(t, r)
	ls, _ = r.Data.(*LoginStage)
	if ls == nil || ls.Login == nil || !ls.Login.Success {
		t.Fatalf("tianyi login pw: %+v", r.Data)
	}
	// login 短信
	r = gwDispatch(t, gw, "tianyi_login", `{"account":"13800000000","code":"123456"}`)
	assertOK(t, r)
	ls, _ = r.Data.(*LoginStage)
	if ls == nil || ls.Login == nil || !ls.Login.Success {
		t.Fatalf("tianyi login sms: %+v", r.Data)
	}
	// login 手动 cookie
	r = gwDispatch(t, gw, "tianyi_login", `{"input":"COOKIE_SESSION_ID=abc"}`)
	assertOK(t, r)
	// thread / clean
	r = gwDispatch(t, gw, "tianyi_thread", `{"value":8}`)
	assertOK(t, r)
	r = gwDispatch(t, gw, "tianyi_clean", "")
	assertOK(t, r)
	recordEvidence(t, "tianyi", r, "status/scan/login(poll/pw/sms/cookie)/thread/clean (mock)")
}
