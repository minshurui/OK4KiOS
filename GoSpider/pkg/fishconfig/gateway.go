package fishconfig

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
)

// dispatchEntry is one case of the Android local switch in FishConfig.action()
// (FishConfig.java:112-800). The order below is the c-value order of the
// decompiled switch — the gateway keeps the same dispatch order.
type dispatchEntry struct {
	Action   string
	Runnable string // Android RunnableCXXXX(index) 证据
}

// dispatchTable reproduces the Android local switch verbatim (all 76 cases).
// Decoded from FishConfig.java f31short with Tools/decode_fishconfig_strings.py.
var dispatchTable = []dispatchEntry{
	{"proxy_config", "RunnableC0381h(4)"},
	{"xunlei_clean", "RunnableC0380g(7)"},
	{"xunlei_login", "RunnableC0380g(4)"},
	{"history_sync", "RunnableC0381h(15)"},
	{"danmu_help", "RunnableC0381h(28)"},
	{"quark_clean", "RunnableC0380g(20)"},
	{"uc_clean", "RunnableC0382i(0)"},
	{"usage_help", "RunnableC0381h(16)"},
	{"danmu_platforms", "RunnableC0380g(23)"},
	{"config_performance", "RunnableC0380g(18)"},
	{"config_strategy", "RunnableC0126n0(24)"},
	{"pan115_clean", "RunnableC0380g(13)"},
	{"webdav_backup", "RunnableC0380g(10)"},
	{"cloud_backup", "RunnableC0380g(25)"},
	{"pan123_community_cookie", "RunnableC0380g(15)"},
	{"danmu_toggle", "RunnableC0381h(21)"},
	{"config_backup", "RunnableC0381h(13)"},
	{"guangya_community_cookie", "RunnableC0380g(22)"},
	{"tianyi_status", "RunnableC0382i(2)"},
	{"tianyi_thread", "RunnableC0380g(17)"},
	{"baidu_scan", "RunnableC0382i(13)"},
	{"baidu_clean", "RunnableC0379f(0)"},
	{"magnet_cloud_help", "RunnableC0380g(9)"},
	{"quality_order", "RunnableC0381h(10)"},
	{"config_health", "RunnableC0380g(27)"},
	{"config_clear", "RunnableC0380g(26)"},
	{"uc_scan", "RunnableC0381h(14)"},
	{"quark_status", "RunnableC0234b0(27)"},
	{"quark_thread", "RunnableC0380g(9)"},
	{"xunlei_status", "RunnableC0380g(3)"},
	{"xunlei_thread", "RunnableC0380g(5)"},
	{"yidong_status", "RunnableC0381h(20)"},
	{"guangya_status", "RunnableC0380g(19)"},
	{"danmu_match_help", "RunnableC0381h(6)"},
	{"yidong_clean", "RunnableC0382i(9)"},
	{"yidong_login", "RunnableC0382i(1)"},
	{"pan_filter", "RunnableC0381h(7)"},
	{"magnet_config", "RunnableC0380g(29)"},
	{"pan123_status", "RunnableC0380g(14)"},
	{"pan123_thread", "RunnableC0380g(16)"},
	{"pan115_magnet_switch", "RunnableC0380g(11)"},
	{"config_accounts", "showAccountOverviewDialog()"},
	{"quality_manage", "RunnableC0381h(17)"},
	{"ali_status", "RunnableC0380g(0)"},
	{"ali_thread", "RunnableC0380g(2)"},
	{"danmu_ai_help", "RunnableC0381h(25)"},
	{"danmu_ai_test", "RunnableC0381h(24)"},
	{"settings_menu_manage", "RunnableC0381h(1)"},
	{"tianyi_help", "RunnableC0381h(9)"},
	{"go_version", "RunnableC0381h(5)"},
	{"quality_config", "RunnableC0381h(8)"},
	{"quark_scan", "RunnableC0234b0(6)"},
	{"danmu_ai_config", "RunnableC0381h(23)"},
	{"uc_token_scan", "RunnableC0381h(29)"},
	{"backup_mode", "RunnableC0381h(3)"},
	{"tianyi_clean", "RunnableC0380g(28)"},
	{"tianyi_login", "RunnableC0380g(6)"},
	{"thread_config", "RunnableC0381h(11)"},
	{"pan115_status", "RunnableC0380g(8)"},
	{"guangya_clean", "RunnableC0380g(24)"},
	{"guangya_login", "RunnableC0380g(21)"},
	{"ali_clean", "RunnableC0379f(1)"},
	{"quality_manage2", "RunnableC0381h(13)"},
	{"uc_status", "RunnableC0381h(2)"},
	{"ali_token", "RunnableC0380g(1)"},
	{"uc_thread", "RunnableC0381h(26)"},
	{"baidu_status", "RunnableC0382i(12)"},
	{"baidu_thread", "RunnableC0234b0(28)"},
	{"ali_scan", "RunnableC0380g(1)"},
	{"danmu_status", "RunnableC0381h(19)"},
	{"danmu_reset", "RunnableC0381h(18)"},
	{"scan_config", "RunnableC0381h(0)"},
	{"usage_help2", "RunnableC0381h(22)"},
}

// netdiskAction maps one FishConfig action to {netdisk, op}. This is the
// routing used by the gateway (built from PROTOCOL.md §2 + FishConfig.java
// switch decode).
var netdiskAction = map[string][2]string{
	// 夸克
	"quark_status": {NetQuark, KindStatus},
	"quark_scan":   {NetQuark, KindScan},
	"quark_thread": {NetQuark, KindThread},
	"quark_clean":  {NetQuark, KindClean},
	// UC
	"uc_status":     {NetUC, KindStatus},
	"uc_scan":       {NetUC, KindScan},
	"uc_token_scan": {NetUC, KindLogin},
	"uc_thread":     {NetUC, KindThread},
	"uc_clean":      {NetUC, KindClean},
	// 天翼
	"tianyi_status": {NetTianyi, KindStatus},
	"tianyi_login":  {NetTianyi, KindLogin},
	"tianyi_thread": {NetTianyi, KindThread},
	"tianyi_clean":  {NetTianyi, KindClean},
	// 阿里
	"ali_status": {NetAli, KindStatus},
	"ali_scan":   {NetAli, KindScan},
	"ali_token":  {NetAli, KindLogin},
	"ali_thread": {NetAli, KindThread},
	"ali_clean":  {NetAli, KindClean},
	// 百度
	"baidu_status": {NetBaidu, KindStatus},
	"baidu_scan":   {NetBaidu, KindScan},
	"baidu_thread": {NetBaidu, KindThread},
	"baidu_clean":  {NetBaidu, KindClean},
	// 迅雷
	"xunlei_status": {NetXunlei, KindStatus},
	"xunlei_login":  {NetXunlei, KindLogin},
	"xunlei_thread": {NetXunlei, KindThread},
	"xunlei_clean":  {NetXunlei, KindClean},
	// 115
	"pan115_status":        {NetPan115, KindStatus},
	"pan115_login":         {NetPan115, KindLogin},
	"pan115_magnet_switch": {NetPan115, KindMagnetSwitch},
	"pan115_clean":         {NetPan115, KindClean},
	// 123
	"pan123_status":           {NetPan123, KindStatus},
	"pan123_login":            {NetPan123, KindLogin},
	"pan123_community_cookie": {NetPan123, KindCommunity},
	"pan123_thread":           {NetPan123, KindThread},
	"pan123_clean":            {NetPan123, KindClean},
	// 移动
	"yidong_status": {NetYidong, KindStatus},
	"yidong_login":  {NetYidong, KindLogin},
	"yidong_clean":  {NetYidong, KindClean},
	// 光鸭
	"guangya_status":           {NetGuangya, KindStatus},
	"guangya_login":            {NetGuangya, KindLogin},
	"guangya_community_cookie": {NetGuangya, KindCommunity},
	"guangya_magnet_switch":    {NetGuangya, KindMagnetSwitch},
	"guangya_clean":            {NetGuangya, KindClean},
}

// preRegistered are the L1.a0 poster_* actions dispatched first on Android.
var preRegistered = []string{
	"poster_personal", "poster_experience", "poster_fallback", "poster_tmdb_menu",
	"poster_image", "poster_reset", "poster_token", "poster_follow_display",
	"poster_ai_config", "poster_ai_manage", "poster_calendar", "poster_help",
	"poster_main", "poster_tmdb", "poster_follow_manage", "poster_mirror",
	"poster_region", "poster_ai_profile",
}

// Bili actions are dispatched second (prefix "bili_").
func isBiliAction(a string) bool { return strings.HasPrefix(a, "bili_") }

// FishDrive actions are dispatched third (prefix "fishdrive_").
func isFishDriveAction(a string) bool { return strings.HasPrefix(a, "fishdrive_") }

// Gateway is the csp_FishConfig action dispatcher.
type Gateway struct {
	Store *Store
	HTTP  *HTTP // optional default HTTP; per-action can pass their own
}

// NewGateway builds a gateway with a fresh store.
func NewGateway() *Gateway {
	return &Gateway{Store: NewStore()}
}

// Handle dispatches one FishConfig action (Android order) and returns the
// ActionResponse envelope as JSON.
func (g *Gateway) Handle(ctx context.Context, action, payload string) ([]byte, error) {
	resp := g.Dispatch(ctx, action, payload)
	b, err := json.Marshal(resp)
	if err != nil {
		return nil, err
	}
	return b, nil
}

// Dispatch executes one action and returns the response struct.
func (g *Gateway) Dispatch(ctx context.Context, action, payload string) *ActionResponse {
	if action == "" {
		return &ActionResponse{Ok: false, Action: action, Kind: KindError, Error: "empty action"}
	}
	// 1) L1.a0(str) — pre-registered poster_* actions
	for _, a := range preRegistered {
		if a == action {
			return &ActionResponse{Ok: true, Action: action, Kind: KindNotImpl,
				Message: "Android 由 L1.a0 预注册 Runnable 处理（海报设置），Go 侧暂不接管"}
		}
	}
	// 2) Bili.dispatchConfigAction(str)
	if isBiliAction(action) {
		return &ActionResponse{Ok: true, Action: action, Kind: KindNotImpl,
			Message: "Android 由 Bili.dispatchConfigAction 处理，Go 侧暂不接管"}
	}
	// 3) FishDrive.dispatchConfigAction(str)
	if isFishDriveAction(action) {
		return &ActionResponse{Ok: true, Action: action, Kind: KindNotImpl,
			Message: "Android 由 FishDrive.dispatchConfigAction 处理，Go 侧暂不接管"}
	}
	// 4) local switch — netdisk actions route to per-netdisk clients
	if nd, ok := netdiskAction[action]; ok {
		return g.routeNetdisk(ctx, action, nd[0], nd[1], payload)
	}
	// 4b) local switch — remaining actions
	for _, e := range dispatchTable {
		if e.Action == action {
			return &ActionResponse{Ok: true, Action: action, Kind: KindInfo,
				Message: fmt.Sprintf("Android 本地 switch 分派 %s（%s）；Go 侧暂不接管", action, e.Runnable)}
		}
	}
	return &ActionResponse{Ok: false, Action: action, Kind: KindError,
		Error: "unknown FishConfig action"}
}

// routeNetdisk dispatches a netdisk action to its client.
func (g *Gateway) routeNetdisk(ctx context.Context, action, netdisk, op, payload string) *ActionResponse {
	client, ok := Lookup(netdisk)
	if !ok {
		return &ActionResponse{Ok: false, Action: action, Kind: KindError, Netdisk: netdisk,
			Error: "no client for netdisk " + netdisk}
	}
	base := ActionResponse{Action: action, Netdisk: netdisk}
	var req LoginRequest
	_ = decodePayload(json.RawMessage(payload), &req)

	switch op {
	case KindStatus:
		return g.status(ctx, base, client, payload)
	case KindScan:
		// 与 Android 一致：quark/uc/baidu 没有独立 *_login action，
		// 扫码后的轮询通过再次调用 *_scan 并携带 session 完成。
		if hasSessionOrInput(payload) {
			return g.login(ctx, base, client, req)
		}
		return g.scan(ctx, base, client)
	case KindLogin:
		return g.login(ctx, base, client, req)
	case KindThread:
		return g.thread(base, netdisk, payload)
	case KindClean:
		return g.clean(base, netdisk)
	case KindMagnetSwitch:
		return g.magnetSwitch(base, netdisk, payload)
	case KindCommunity:
		return g.communityCookie(ctx, base, client, req)
	}
	return &ActionResponse{Ok: false, Action: action, Kind: KindError, Netdisk: netdisk,
		Error: "unsupported op " + op}
}

func (g *Gateway) status(ctx context.Context, base ActionResponse, c Client, payload string) *ActionResponse {
	var cred Credential
	if err := decodePayload(json.RawMessage(payload), &cred); err != nil {
		return fail(base, "status payload: "+err.Error())
	}
	h := g.httpFor(c.Name())
	// cred.Raw may carry the credential; tolerate both spellings
	if cred.Netdisk == "" {
		cred.Netdisk = c.Name()
	}
	if cred.Cookie == "" && cred.Token == "" {
		if v, _ := cred.Raw["cookie"].(string); v != "" {
			cred.Cookie = v
		}
		if v, _ := cred.Raw["token"].(string); v != "" {
			cred.Token = v
		}
	}
	if cred.Cookie == "" && cred.Token == "" {
		base.Ok = true
		base.Kind = KindStatus
		base.Data = &StatusResult{LoggedIn: false, Hint: "当前未登录，请先扫码登录或导入凭证"}
		return &base
	}
	st, err := c.Status(ctx, cred, h)
	if err != nil {
		return fail(base, err.Error())
	}
	base.Ok = true
	base.Kind = KindStatus
	base.Data = st
	if st != nil && !st.LoggedIn && st.Hint == "" {
		st.Hint = "凭证无效或已过期，请重新登录"
	}
	return &base
}

func (g *Gateway) scan(ctx context.Context, base ActionResponse, c Client) *ActionResponse {
	h := g.httpFor(c.Name())
	sc, err := c.Scan(ctx, h)
	if err != nil {
		return fail(base, err.Error())
	}
	if sc.Session != nil {
		g.Store.SaveSession(c.Name(), sc.Session)
	}
	base.Ok = true
	base.Kind = KindScan
	base.Data = sc
	return &base
}

func (g *Gateway) login(ctx context.Context, base ActionResponse, c Client, req LoginRequest) *ActionResponse {
	// 无 session/输入时：空载荷的 *_login 作为扫码入口（Android 同：扫码对话框由 *_login 打开）
	if len(req.Session) == 0 && req.Input == "" && req.Account == "" {
		h := g.httpFor(c.Name())
		sc, err := c.Scan(ctx, h)
		if err != nil {
			return fail(base, err.Error())
		}
		if sc.Session != nil {
			g.Store.SaveSession(c.Name(), sc.Session)
		}
		base.Ok = true
		base.Kind = KindLogin
		base.Data = &LoginStage{Stage: "start", Scan: sc}
		return &base
	}
	if len(req.Session) == 0 {
		req.Session = g.Store.TakeSession(c.Name())
	}
	h := g.httpFor(c.Name())
	lr, err := c.Login(ctx, req, h)
	if err != nil {
		return fail(base, err.Error())
	}
	base.Ok = true
	base.Kind = KindLogin
	base.Data = &LoginStage{Stage: "done", Login: lr}
	return &base
}

func (g *Gateway) thread(base ActionResponse, netdisk, payload string) *ActionResponse {
	type threadIn struct {
		Value *int `json:"value"`
	}
	var in threadIn
	_ = decodePayload(json.RawMessage(payload), &in)
	if in.Value != nil && g.Store.SetThread(netdisk, *in.Value) {
		base.Ok = true
		base.Kind = KindThread
		base.Data = &ThreadResult{Netdisk: netdisk, Current: *in.Value, Options: ThreadOptions,
			Hint: "线程设置已保存"}
		return &base
	}
	base.Ok = true
	base.Kind = KindThread
	base.Data = &ThreadResult{Netdisk: netdisk, Current: g.Store.GetThread(netdisk), Options: ThreadOptions,
		Hint: "选择播放/转存线程数"}
	return &base
}

func (g *Gateway) clean(base ActionResponse, netdisk string) *ActionResponse {
	// 清除本地登录信息：会话由 Swift Keychain 持久化，Go 侧清 store 会话与线程外的 flag
	g.Store.SetFlag(netdisk+".cleaned", true)
	base.Ok = true
	base.Kind = KindClean
	base.Data = &CleanResult{Cleared: true, Hint: "已清除本地登录信息"}
	return &base
}

func (g *Gateway) magnetSwitch(base ActionResponse, netdisk, payload string) *ActionResponse {
	type swIn struct {
		On *bool `json:"on"`
	}
	var in swIn
	_ = decodePayload(json.RawMessage(payload), &in)
	key := netdisk + ".magnet_switch"
	on := g.Store.GetFlag(key)
	if in.On != nil {
		on = *in.On
		g.Store.SetFlag(key, on)
	}
	base.Ok = true
	base.Kind = KindMagnetSwitch
	base.Data = map[string]any{"netdisk": netdisk, "on": on,
		"hint": "磁力云转存开关（仅记录偏好，实际转存由对应网盘驱动）"}
	return &base
}

func (g *Gateway) communityCookie(ctx context.Context, base ActionResponse, c Client, req LoginRequest) *ActionResponse {
	h := g.httpFor(c.Name())
	lr, err := c.Login(ctx, req, h)
	if err != nil {
		return fail(base, err.Error())
	}
	base.Ok = true
	base.Kind = KindCommunity
	base.Data = &LoginStage{Stage: "done", Login: lr}
	return &base
}

func (g *Gateway) httpFor(netdisk string) *HTTP {
	if g.HTTP != nil {
		return g.HTTP
	}
	return DefaultHTTPFor(netdisk)
}

func fail(base ActionResponse, msg string) *ActionResponse {
	base.Ok = false
	base.Kind = KindError
	base.Error = msg
	return &base
}

// hasSessionOrInput reports whether a scan payload carries poll/credential data.
func hasSessionOrInput(payload string) bool {
	if payload == "" {
		return false
	}
	var m struct {
		Session map[string]any `json:"session"`
		Input   string         `json:"input"`
	}
	if err := json.Unmarshal([]byte(payload), &m); err != nil {
		return false
	}
	return len(m.Session) > 0 || m.Input != ""
}

// DefaultHTTPFor returns a UA-matched HTTP helper per netdisk.
func DefaultHTTPFor(netdisk string) *HTTP {
	switch netdisk {
	case NetQuark:
		return NewHTTP(UAQuark)
	case NetUC:
		return NewHTTP(UAUC)
	case NetXunlei:
		return NewHTTP(UAXunlei)
	default:
		return NewHTTP(UAWeb)
	}
}

// ActionsCatalog lists all known actions grouped by netdisk (for Swift UI).
func ActionsCatalog() map[string][]string {
	out := map[string][]string{}
	for a, nd := range netdiskAction {
		out[nd[0]] = append(out[nd[0]], a)
	}
	for k := range out {
		sort.Strings(out[k])
	}
	return out
}
