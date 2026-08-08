package fishconfig

import (
	"net/http"
	"testing"
)

// uc 自测：status/scan/poll(token_scan)/thread/clean。
func TestUCActions(t *testing.T) {
	m := newMock()
	m.onJSON("/cas/ajax/getTokenForQrcodeLogin", `{"status":2000000,"data":{"members":{"token":"ucToken1"}}}`, 200)
	m.onJSON("/cas/ajax/getQrcodeLogin", `{"status":2000000,"data":{"qrcode":"UC_QR_1","qr_sign":"S1"}}`, 200)
	var pollN int
	m.on("/cas/ajax/loginByQrcode", func(w http.ResponseWriter, r *http.Request) {
		pollN++
		if pollN <= 1 {
			w.Write([]byte(`{"status":2000000,"data":{"status":0}}`))
			return
		}
		w.Write([]byte(`{"status":2000000,"data":{"status":1,"cookie":"UC_TOKEN=x; uc_cookie=1","nickname":"UC用户"}}`))
	})
	m.onJSON("/account/info", `{"status":2000000,"data":{"nickname":"UC用户","avatar":""}}`, 200)

	base := m.start(t)
	setStr(t, &ucCASBase, base+"/cas/ajax")
	setStr(t, &ucDriveBase, base)
	gw := NewGateway()
	gw.HTTP = DefaultHTTPFor(NetUC)

	// status 未登录
	r := gwDispatch(t, gw, "uc_status", "")
	assertOK(t, r)
	if st, _ := r.Data.(*StatusResult); st == nil || st.LoggedIn {
		t.Fatalf("uc status empty: %+v", r.Data)
	}
	// status 已登录
	r = gwDispatch(t, gw, "uc_status", `{"netdisk":"uc","cookie":"UC_TOKEN=x"}`)
	assertOK(t, r)
	if st, _ := r.Data.(*StatusResult); st == nil || !st.LoggedIn || st.Account.Name != "UC用户" {
		t.Fatalf("uc status: %+v", r.Data)
	}
	// scan
	r = gwDispatch(t, gw, "uc_scan", "")
	assertOK(t, r)
	if sc, _ := r.Data.(*ScanResult); sc == nil || sc.Session["qrcode"] != "UC_QR_1" {
		t.Fatalf("uc scan: %+v", r.Data)
	}
	// poll via uc_scan + session（Android 无独立 uc_login）
	r = gwDispatch(t, gw, "uc_scan", `{"session":{"qrcode":"UC_QR_1","qr_sign":"S1"}}`)
	assertOK(t, r)
	ls, _ := r.Data.(*LoginStage)
	lr := (*LoginResult)(nil)
	if ls != nil {
		lr = ls.Login
	}
	if lr == nil || !lr.Success || lr.Credential.Cookie == "" {
		t.Fatalf("uc login: %+v", r.Data)
	}
	// uc_token_scan：粘贴 cookie
	r = gwDispatch(t, gw, "uc_token_scan", `{"input":"UC_TOKEN=x"}`)
	assertOK(t, r)
	ls, _ = r.Data.(*LoginStage)
	if ls == nil || ls.Login == nil || !ls.Login.Success {
		t.Fatalf("uc token scan: %+v", r.Data)
	}
	// thread / clean
	r = gwDispatch(t, gw, "uc_thread", `{"value":2}`)
	assertOK(t, r)
	r = gwDispatch(t, gw, "uc_clean", "")
	assertOK(t, r)
	recordEvidence(t, "uc", r, "status/scan/poll/token_scan/thread/clean (mock CAS)")
}
