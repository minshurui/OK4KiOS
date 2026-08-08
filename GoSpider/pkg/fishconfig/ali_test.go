package fishconfig

import (
	"testing"
)

// ali 自测：status/scan(OAuth URL)/token 输入+刷新/thread/clean。
func TestAliActions(t *testing.T) {
	m := newMock()
	m.onJSON("/v2/databox/get_personal_info", `{"name":"阿里用户","avatar":"https://a.png","domain_id":"1"}`, 200)
	m.onJSON("/api/ali_open/refresh", `{"access_token":"NEW_TOKEN","refresh_token":"NEW_RT","expires_in":7200}`, 200)
	m.onJSON("/v2/account/token", `{"access_token":"CODE_TOKEN","refresh_token":"CODE_RT","expires_in":7200,"token_type":"Bearer"}`, 200)

	base := m.start(t)
	setStr(t, &aliAPIBase, base)
	setStr(t, &aliRefreshBase, base+"/api/ali_open/refresh")
	setStr(t, &aliAuthBase, base+"/v2/account/token")
	gw := NewGateway()
	gw.HTTP = DefaultHTTPFor(NetAli)

	// status 未配置 token
	r := gwDispatch(t, gw, "ali_status", "")
	assertOK(t, r)
	if st, _ := r.Data.(*StatusResult); st == nil || st.LoggedIn {
		t.Fatalf("ali status empty: %+v", r.Data)
	}
	// status 已配置
	r = gwDispatch(t, gw, "ali_status", `{"netdisk":"ali","token":"GOOD_TOKEN"}`)
	assertOK(t, r)
	if st, _ := r.Data.(*StatusResult); st == nil || !st.LoggedIn || st.Account.Name != "阿里用户" {
		t.Fatalf("ali status: %+v", r.Data)
	}
	// scan -> OAuth URL
	r = gwDispatch(t, gw, "ali_scan", "")
	assertOK(t, r)
	sc, _ := r.Data.(*ScanResult)
	if sc == nil || sc.Kind != "oauth_url" || sc.QRURL == "" {
		t.Fatalf("ali scan: %+v", r.Data)
	}
	// ali_token 输入 Open Token JSON
	r = gwDispatch(t, gw, "ali_token", `{"input":"{\"access_token\":\"GOOD_TOKEN\",\"refresh_token\":\"RT\"}"}`)
	assertOK(t, r)
	ls, _ := r.Data.(*LoginStage)
	lr := (*LoginResult)(nil)
	if ls != nil {
		lr = ls.Login
	}
	if lr == nil || !lr.Success || lr.Credential.Token != "GOOD_TOKEN" {
		t.Fatalf("ali token: %+v", r.Data)
	}
	// token 无效 -> 刷新重试（xiaoya proxy）
	r = gwDispatch(t, gw, "ali_token", `{"input":"{\"access_token\":\"BAD_TOKEN\",\"refresh_token\":\"RT\"}"}`)
	assertOK(t, r)
	ls, _ = r.Data.(*LoginStage)
	if ls == nil || ls.Login == nil || !ls.Login.Success {
		t.Fatalf("ali token refresh: %+v", r.Data)
	}
	// 授权码换取
	r = gwDispatch(t, gw, "ali_token", `{"input":"AUTH_CODE_1"}`)
	assertOK(t, r)
	// thread / clean
	r = gwDispatch(t, gw, "ali_thread", `{"value":4}`)
	assertOK(t, r)
	r = gwDispatch(t, gw, "ali_clean", "")
	assertOK(t, r)
	recordEvidence(t, "ali", r, "status/scan/token(refresh+code)/thread/clean (mock)")
}
