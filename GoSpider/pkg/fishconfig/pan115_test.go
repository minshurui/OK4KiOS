package fishconfig

import (
	"net/http"
	"testing"
)

// pan115 自测：status/scan(二维码)/login(轮询+cookie)/magnet_switch/clean。
func TestPan115Actions(t *testing.T) {
	m := newMock()
	m.onJSON("/app/1.0/alipaymini/1.0/login/qrcode/", `{"state":0,"data":{"qrcode":"115_QR_1","uid":"115u","app_id":"alipaymini","time_stamp":"1786159706","sign":"s"}}`, 200)
	var pollN int
	m.on("/api/1.0/alipaymini/1.0/token/", func(w http.ResponseWriter, r *http.Request) {
		pollN++
		if pollN <= 1 {
			w.Write([]byte(`{"state":0,"data":{"status":"wait"}}`))
			return
		}
		w.Write([]byte(`{"state":0,"data":{"status":"ok","token":"SEID_TOKEN","user_id":"115u","user_name":"115用户"}}`))
	})
	m.onJSON("/index.php", `{"state":0,"data":{"user_name":"115用户","user_id":"115u","use_size":100,"size":1000}}`, 200)

	base := m.start(t)
	setStr(t, &pan115QRAPI, base+"/app/1.0/alipaymini/1.0/login/qrcode/")
	setStr(t, &pan115TokenAPI, base+"/api/1.0/alipaymini/1.0/token/")
	setStr(t, &pan115StatusAPI, base+"/index.php")
	gw := NewGateway()
	gw.HTTP = DefaultHTTPFor(NetPan115)

	// status 已登录
	r := gwDispatch(t, gw, "pan115_status", `{"netdisk":"pan115","cookie":"UID=115u; CID=115u; SEID=SEID_TOKEN"}`)
	assertOK(t, r)
	st, _ := r.Data.(*StatusResult)
	if st == nil || !st.LoggedIn || st.Account.Name != "115用户" || st.Usage == nil {
		t.Fatalf("pan115 status: %+v", r.Data)
	}
	// scan
	r = gwDispatch(t, gw, "pan115_login", "")
	assertOK(t, r)
	ls, _ := r.Data.(*LoginStage)
	sc := (*ScanResult)(nil)
	if ls != nil {
		sc = ls.Scan
	}
	if sc == nil || sc.Session["qrcode"] != "115_QR_1" {
		t.Fatalf("pan115 scan: %+v", r.Data)
	}
	// login 轮询
	r = gwDispatch(t, gw, "pan115_login", `{"session":{"qrcode":"115_QR_1","uid":"115u","app_id":"alipaymini","time_stamp":"1786159706"}}`)
	assertOK(t, r)
	ls, _ = r.Data.(*LoginStage)
	lr := (*LoginResult)(nil)
	if ls != nil {
		lr = ls.Login
	}
	if lr == nil || !lr.Success || lr.Credential.Cookie == "" {
		t.Fatalf("pan115 login: %+v", r.Data)
	}
	// magnet switch
	r = gwDispatch(t, gw, "pan115_magnet_switch", `{"on":true}`)
	assertOK(t, r)
	// clean
	r = gwDispatch(t, gw, "pan115_clean", "")
	assertOK(t, r)
	recordEvidence(t, "pan115", r, "status/scan/login/magnet_switch/clean (mock)")
}
