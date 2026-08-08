package fishconfig

import (
	"net/http"
	"testing"
)

// xunlei 自测：status/scan(设备码)/login(轮询+Token JSON)/thread/clean。
func TestXunleiActions(t *testing.T) {
	m := newMock()
	m.onJSON("/v1/auth/device/code", `{"device_code":"DC1","user_code":"1234","verification_uri":"https://pan.xunlei.com/","verification_uri_complete":"https://pan.xunlei.com/verify/DC1","interval":3,"expires_in":300}`, 200)
	var pollN int
	m.on("/v1/auth/token", func(w http.ResponseWriter, r *http.Request) {
		pollN++
		if pollN <= 1 {
			w.Write([]byte(`{"error":"authorization_pending"}`))
			return
		}
		w.Write([]byte(`{"access_token":"XL_ACCESS","refresh_token":"XL_REFRESH","expires_in":7200}`))
	})
	m.onJSON("/v1/user/me", `{"user_id":"u1","name":"迅雷用户","nickname":"迅雷用户","avatar_url":""}`, 200)

	base := m.start(t)
	setStr(t, &xunleiAuthBase, base+"/v1")
	gw := NewGateway()
	gw.HTTP = DefaultHTTPFor(NetXunlei)

	// status 已配置 token
	r := gwDispatch(t, gw, "xunlei_status", `{"netdisk":"xunlei","token":"XL_ACCESS"}`)
	assertOK(t, r)
	if st, _ := r.Data.(*StatusResult); st == nil || !st.LoggedIn || st.Account.Name != "迅雷用户" {
		t.Fatalf("xunlei status: %+v", r.Data)
	}
	// scan
	r = gwDispatch(t, gw, "xunlei_login", "")
	assertOK(t, r)
	ls, _ := r.Data.(*LoginStage)
	sc := (*ScanResult)(nil)
	if ls != nil {
		sc = ls.Scan
	}
	if sc == nil || sc.Kind != "device_code" || sc.Session["device_code"] != "DC1" {
		t.Fatalf("xunlei scan: %+v", r.Data)
	}
	// login 轮询
	r = gwDispatch(t, gw, "xunlei_login", `{"session":{"device_code":"DC1","client_id":"cid","interval":1,"expires_in":30}}`)
	assertOK(t, r)
	ls, _ = r.Data.(*LoginStage)
	lr := (*LoginResult)(nil)
	if ls != nil {
		lr = ls.Login
	}
	if lr == nil || !lr.Success || lr.Credential.Token != "XL_ACCESS" {
		t.Fatalf("xunlei login: %+v", r.Data)
	}
	// login Token JSON
	r = gwDispatch(t, gw, "xunlei_login", `{"input":"{\"access_token\":\"XL_ACCESS\",\"refresh_token\":\"XL_REFRESH\"}"}`)
	assertOK(t, r)
	ls, _ = r.Data.(*LoginStage)
	if ls == nil || ls.Login == nil || !ls.Login.Success {
		t.Fatalf("xunlei token json: %+v", r.Data)
	}
	// thread / clean
	r = gwDispatch(t, gw, "xunlei_thread", `{"value":4}`)
	assertOK(t, r)
	r = gwDispatch(t, gw, "xunlei_clean", "")
	assertOK(t, r)
	recordEvidence(t, "xunlei", r, "status/scan/login(device-code poll+Token JSON)/thread/clean (mock)")
}
