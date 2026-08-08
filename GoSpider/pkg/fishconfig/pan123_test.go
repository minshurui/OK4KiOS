package fishconfig

import (
	"net/http"
	"testing"
)

// pan123 自测：status/scan(litepan OAuth)/login(轮询+Open Token+账号密码)/community_cookie/thread/clean。
func TestPan123Actions(t *testing.T) {
	m := newMock()
	m.onJSON("/api/oauth/start", `{"success":true,"data":{"session_id":"SID_123","oauth_url":"https://yun.123pan.com/auth?client_id=c&state=SID_123","expires_in":600}}`, 200)
	var pollN int
	m.on("/api/oauth/status/", func(w http.ResponseWriter, r *http.Request) {
		pollN++
		if pollN <= 1 {
			w.Write([]byte(`{"success":true,"data":{"status":"pending","token_data":null}}`))
			return
		}
		w.Write([]byte(`{"success":true,"data":{"status":"success","token_data":{"access_token":"P123_ACCESS","refresh_token":"P123_REFRESH","expires_in":7200}}}`))
	})
	m.onJSON("/api/v1/user/info", `{"code":0,"data":{"username":"123用户","userId":12345}}`, 200)
	m.onJSON("/api/restful/goapi/v1/oauth2/user/login", `{"code":0,"data":{"access_token":"P123_PW","refresh_token":"P123_PW_RT","expires_in":7200}}`, 200)

	base := m.start(t)
	setStr(t, &pan123LiteBase, base+"/api/oauth")
	setStr(t, &pan123APIBase, base+"/api")
	setStr(t, &pan123GoAPI, base+"/api/restful/goapi/v1/oauth2/user/login")
	gw := NewGateway()
	gw.HTTP = DefaultHTTPFor(NetPan123)

	// status 已配置 token
	r := gwDispatch(t, gw, "pan123_status", `{"netdisk":"pan123","token":"P123_ACCESS"}`)
	assertOK(t, r)
	if st, _ := r.Data.(*StatusResult); st == nil || !st.LoggedIn || st.Account.Name != "123用户" {
		t.Fatalf("pan123 status: %+v", r.Data)
	}
	// scan
	r = gwDispatch(t, gw, "pan123_login", "")
	assertOK(t, r)
	ls, _ := r.Data.(*LoginStage)
	sc := (*ScanResult)(nil)
	if ls != nil {
		sc = ls.Scan
	}
	if sc == nil || sc.Session["session_id"] != "SID_123" {
		t.Fatalf("pan123 scan: %+v", r.Data)
	}
	// login 轮询
	r = gwDispatch(t, gw, "pan123_login", `{"session":{"session_id":"SID_123","expires_in":30}}`)
	assertOK(t, r)
	ls, _ = r.Data.(*LoginStage)
	lr := (*LoginResult)(nil)
	if ls != nil {
		lr = ls.Login
	}
	if lr == nil || !lr.Success || lr.Credential.Token != "P123_ACCESS" {
		t.Fatalf("pan123 login: %+v", r.Data)
	}
	// login Open Token JSON
	r = gwDispatch(t, gw, "pan123_login", `{"input":"{\"access_token\":\"P123_ACCESS\",\"refresh_token\":\"R\"}"}`)
	assertOK(t, r)
	ls, _ = r.Data.(*LoginStage)
	if ls == nil || ls.Login == nil || !ls.Login.Success {
		t.Fatalf("pan123 token json: %+v", r.Data)
	}
	// login 账号密码
	r = gwDispatch(t, gw, "pan123_login", `{"account":"u@x.com","password":"pw"}`)
	assertOK(t, r)
	ls, _ = r.Data.(*LoginStage)
	if ls == nil || ls.Login == nil || !ls.Login.Success {
		t.Fatalf("pan123 pw: %+v", r.Data)
	}
	// community cookie（粘贴 123 社区 Cookie -> 校验走 status 语义）
	r = gwDispatch(t, gw, "pan123_community_cookie", `{"input":"{\"access_token\":\"P123_ACCESS\"}"}`)
	assertOK(t, r)
	// thread / clean
	r = gwDispatch(t, gw, "pan123_thread", `{"value":8}`)
	assertOK(t, r)
	r = gwDispatch(t, gw, "pan123_clean", "")
	assertOK(t, r)
	recordEvidence(t, "pan123", r, "status/scan/login(oauth poll+token+pw)/community_cookie/thread/clean (mock)")
}
