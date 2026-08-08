package fishconfig

import (
	"net/http"
	"testing"
)

// guangya 自测：status/scan(设备码)/login(轮询+token)/magnet_switch/clean。
// 与 iOS GuangyaAuthService 语义一致（PROTOCOL.md §4）。
func TestGuangyaActions(t *testing.T) {
	m := newMock()
	m.onJSON("/v1/auth/device/code", `{"data":{"device_code":"DC_GY","verification_uri_complete":"https://account.guangyapan.com/verify?dc=DC_GY"}}`, 200)
	var pollN int
	m.on("/v1/auth/token", func(w http.ResponseWriter, r *http.Request) {
		pollN++
		if pollN <= 1 {
			w.Write([]byte(`{"error":"authorization_pending"}`))
			return
		}
		w.Write([]byte(`{"data":{"access_token":"GY_ACCESS","refresh_token":"GY_REFRESH","token_type":"Bearer","sub":"sub1","name":"光鸭用户","picture":"","phone":"138..."}}`))
	})
	m.onJSON("/v1/user/me", `{"data":{"sub":"sub1","name":"光鸭用户","picture":"https://p.png","phone":"13800000000","kaiser_folder":"/光鸭"}}`, 200)

	base := m.start(t)
	setStr(t, &guangyaAccount, base)
	gw := NewGateway()
	gw.HTTP = DefaultHTTPFor(NetGuangya)

	// status 已登录
	r := gwDispatch(t, gw, "guangya_status", `{"netdisk":"guangya","token":"GY_ACCESS"}`)
	assertOK(t, r)
	if st, _ := r.Data.(*StatusResult); st == nil || !st.LoggedIn || st.Account.Name != "光鸭用户" {
		t.Fatalf("guangya status: %+v", r.Data)
	}
	// scan
	r = gwDispatch(t, gw, "guangya_login", "")
	assertOK(t, r)
	ls, _ := r.Data.(*LoginStage)
	sc := (*ScanResult)(nil)
	if ls != nil {
		sc = ls.Scan
	}
	if sc == nil || sc.Kind != "device_code" || sc.Session["device_code"] != "DC_GY" {
		t.Fatalf("guangya scan: %+v", r.Data)
	}
	// login 轮询
	r = gwDispatch(t, gw, "guangya_login", `{"session":{"device_code":"DC_GY"}}`)
	assertOK(t, r)
	ls, _ = r.Data.(*LoginStage)
	lr := (*LoginResult)(nil)
	if ls != nil {
		lr = ls.Login
	}
	if lr == nil || !lr.Success || lr.Credential.Token != "GY_ACCESS" {
		t.Fatalf("guangya login: %+v", r.Data)
	}
	// magnet switch
	r = gwDispatch(t, gw, "guangya_magnet_switch", `{"on":true}`)
	assertOK(t, r)
	// clean
	r = gwDispatch(t, gw, "guangya_clean", "")
	assertOK(t, r)
	recordEvidence(t, "guangya", r, "status/scan/login(device-code poll)/magnet_switch/clean (mock)")
}
