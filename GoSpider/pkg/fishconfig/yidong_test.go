package fishconfig

import (
	"net/http"
	"testing"
)

// yidong 自测：status/scan(扫码页)/login(凭证+账号密码+轮询)/clean。
func TestYidongActions(t *testing.T) {
	m := newMock()
	m.onJSON("/user/getUser", `{"success":true,"code":"0000","data":{"user":{"name":"移动用户","userId":"139-1"}}}`, 200)
	m.onJSON("/queryId", `{"data":{"sid":"SID_139","serverTime":1}}`, 200)
	m.onJSON("/queryLoginResult", `{"data":{"status":"ok","jclk_token":"JCLK_1"}}`, 200)
	m.onJSON("/login", `{"data":{"jclk_token":"JCLK_1","msg":"ok"}}`, 200)
	// jclk_token 换会话
	m.on("/orchestration/auth/login", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Add("Set-Cookie", "YUNLOGIN=ses1; Path=/")
		w.WriteHeader(302)
	})

	base := m.start(t)
	setStr(t, &yidongUserBase, base)
	setStr(t, &yidongAPIBase, base)
	gw := NewGateway()
	gw.HTTP = DefaultHTTPFor(NetYidong)

	// status 已登录（cookie）
	r := gwDispatch(t, gw, "yidong_status", `{"netdisk":"yidong","cookie":"YUNLOGIN=ses1"}`)
	assertOK(t, r)
	if st, _ := r.Data.(*StatusResult); st == nil || !st.LoggedIn || st.Account.Name != "移动用户" {
		t.Fatalf("yidong status: %+v", r.Data)
	}
	// status 未登录
	r = gwDispatch(t, gw, "yidong_status", "")
	assertOK(t, r)
	// scan（扫码页；queryId 不可达时降级本地 sid）——yidong 无独立 *_scan，空载荷 *_login 即扫码入口
	r = gwDispatch(t, gw, "yidong_login", "")
	assertOK(t, r)
	ls, _ := r.Data.(*LoginStage)
	if ls == nil || ls.Stage != "start" || ls.Scan == nil || ls.Scan.Kind != "web" {
		t.Fatalf("yidong scan: %+v", r.Data)
	}
	// login 凭证导入
	r = gwDispatch(t, gw, "yidong_login", `{"input":"YUNLOGIN=ses1"}`)
	assertOK(t, r)
	ls, _ = r.Data.(*LoginStage)
	if ls == nil || ls.Login == nil || !ls.Login.Success {
		t.Fatalf("yidong cookie: %+v", r.Data)
	}
	// login 账号密码
	r = gwDispatch(t, gw, "yidong_login", `{"account":"13800000000","password":"pw"}`)
	assertOK(t, r)
	// login 扫码轮询
	r = gwDispatch(t, gw, "yidong_login", `{"session":{"sid":"SID_139"}}`)
	assertOK(t, r)
	// clean
	r = gwDispatch(t, gw, "yidong_clean", "")
	assertOK(t, r)
	recordEvidence(t, "yidong", r, "status/scan/login(credential/pw/poll)/clean (mock)")
}
