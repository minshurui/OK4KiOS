package fishconfig

import (
	"net/http"
	"testing"
)

// quark 自测：status/scan/login/thread/clean，mock CAS + 账号端点。
func TestQuarkActions(t *testing.T) {
	m := newMock()
	// CAS getTokenForQrcodeLogin（实测响应形状）
	m.onJSON("/cas/ajax/getTokenForQrcodeLogin",
		`{"status":2000000,"message":"ok","data":{"members":{"token":"staTestToken"}}}`, 200)
	// getQrcodeLogin
	m.onJSON("/cas/ajax/getQrcodeLogin",
		`{"status":2000000,"message":"ok","data":{"qrcode":"QR_CONTENT_ABC","qr_sign":"SIGN123"}}`, 200)
	// loginByQrcode：先 pending 后 ok（带 cookie）
	var pollN int
	m.on("/cas/ajax/loginByQrcode", func(w http.ResponseWriter, r *http.Request) {
		pollN++
		if pollN <= 1 {
			w.Write([]byte(`{"status":2000000,"message":"ok","data":{"status":0,"msg":"wait"}}`))
			return
		}
		w.Write([]byte(`{"status":2000000,"message":"ok","data":{"status":1,"cookie":"__puus=tok1; __pus=tok1","nickname":"夸克用户"}}`))
	})
	// 账号端点
	m.onJSON("/account/info", `{"status":2000000,"message":"ok","data":{"nickname":"夸克用户","avatar":"https://a/x.png","vip_member":{"status":1}}}`, 200)

	base := m.start(t)
	setStr(t, &quarkCASBase, base+"/cas/ajax")
	setStr(t, &quarkPanBase, base)
	gw := NewGateway()
	gw.HTTP = DefaultHTTPFor(NetQuark)

	// status: 未登录
	r := gwDispatch(t, gw, "quark_status", "")
	assertOK(t, r)
	st, _ := r.Data.(*StatusResult)
	if st == nil || st.LoggedIn {
		t.Fatalf("status empty: %+v", r.Data)
	}
	// status: 已登录（带 cookie）
	payload := `{"netdisk":"quark","cookie":"__puus=tok1; __pus=tok1"}`
	r = gwDispatch(t, gw, "quark_status", payload)
	assertOK(t, r)
	st, _ = r.Data.(*StatusResult)
	if st == nil || !st.LoggedIn || st.Account.Name != "夸克用户" {
		t.Fatalf("status logged in: %+v", r.Data)
	}

	// scan
	r = gwDispatch(t, gw, "quark_scan", "")
	assertOK(t, r)
	sc, _ := r.Data.(*ScanResult)
	if sc == nil || sc.Session["qrcode"] != "QR_CONTENT_ABC" {
		t.Fatalf("scan: %+v", r.Data)
	}

	// login (poll) — Android 无独立 quark_login action，轮询复用 quark_scan + session
	sessJSON := `{"session":{"qrcode":"QR_CONTENT_ABC","qr_sign":"SIGN123","token":"staTestToken"}}`
	r = gwDispatch(t, gw, "quark_scan", sessJSON)
	assertOK(t, r)
	ls, _ := r.Data.(*LoginStage)
	lr := (*LoginResult)(nil)
	if ls != nil {
		lr = ls.Login
	}
	if lr == nil || !lr.Success || lr.Credential.Cookie == "" {
		t.Fatalf("login: %+v", r.Data)
	}

	// thread / clean
	r = gwDispatch(t, gw, "quark_thread", `{"value":8}`)
	assertOK(t, r)
	r = gwDispatch(t, gw, "quark_clean", "")
	assertOK(t, r)

	recordEvidence(t, "quark", r, "status/scan/login/thread/clean self-test (mock CAS)")
}
