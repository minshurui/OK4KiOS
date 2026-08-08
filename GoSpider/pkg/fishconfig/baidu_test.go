package fishconfig

import (
	"net/http"
	"testing"
)

// baidu 自测：status/scan(二维码)/login(轮询+BDUSS)/thread/clean。
func TestBaiduActions(t *testing.T) {
	m := newMock()
	m.onJSON("/v2/api/getqrcode", `{"errno":0,"data":{"img":"data:image/png;base64,xx","sign":"BD_SIGN_1"}}`, 200)
	var pollN int
	m.on("/v2/api/qrcode/", func(w http.ResponseWriter, r *http.Request) {
		pollN++
		if pollN <= 1 {
			w.Write([]byte(`{"errno":0,"data":{"status":0}}`))
			return
		}
		w.Write([]byte(`{"errno":0,"data":{"status":2}}`))
	})
	// v3 login -> 302 + Set-Cookie BDUSS
	m.on("/v3/api/login", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Location", "https://pan.baidu.com/disk/home")
		w.Header().Add("Set-Cookie", "BDUSS=bdussvalue; Path=/; Domain=.baidu.com")
		w.Header().Add("Set-Cookie", "PSTM=123; Path=/; Domain=.baidu.com")
		w.WriteHeader(302)
	})
	m.onJSON("/api/user/getinfo", `{"errno":0,"baidu_name":"百度用户","netdisk_name":"百度用户","avatar_url":"https://a.png"}`, 200)

	base := m.start(t)
	setStr(t, &baiduPassport, base)
	setStr(t, &baiduPanAPI, base)
	gw := NewGateway()
	gw.HTTP = DefaultHTTPFor(NetBaidu)

	// status 已登录
	r := gwDispatch(t, gw, "baidu_status", `{"netdisk":"baidu","cookie":"BDUSS=bdussvalue"}`)
	assertOK(t, r)
	if st, _ := r.Data.(*StatusResult); st == nil || !st.LoggedIn || st.Account.Name != "百度用户" {
		t.Fatalf("baidu status: %+v", r.Data)
	}
	// scan
	r = gwDispatch(t, gw, "baidu_scan", "")
	assertOK(t, r)
	sc, _ := r.Data.(*ScanResult)
	if sc == nil || sc.Session["sign"] != "BD_SIGN_1" {
		t.Fatalf("baidu scan: %+v", r.Data)
	}
	// login 轮询（baidu_scan + session）
	r = gwDispatch(t, gw, "baidu_scan", `{"session":{"sign":"BD_SIGN_1"}}`)
	assertOK(t, r)
	ls, _ := r.Data.(*LoginStage)
	lr := (*LoginResult)(nil)
	if ls != nil {
		lr = ls.Login
	}
	if lr == nil || !lr.Success || lr.Credential.Cookie == "" {
		t.Fatalf("baidu login: %+v", r.Data)
	}
	// login 手动 cookie
	r = gwDispatch(t, gw, "baidu_scan", `{"input":"BDUSS=bdussvalue"}`)
	assertOK(t, r)
	ls, _ = r.Data.(*LoginStage)
	if ls == nil || ls.Login == nil || !ls.Login.Success {
		t.Fatalf("baidu cookie: %+v", r.Data)
	}
	// thread / clean
	r = gwDispatch(t, gw, "baidu_thread", `{"value":16}`)
	assertOK(t, r)
	r = gwDispatch(t, gw, "baidu_clean", "")
	assertOK(t, r)
	recordEvidence(t, "baidu", r, "status/scan/login(poll+BDUSS+cookie)/thread/clean (mock)")
}
