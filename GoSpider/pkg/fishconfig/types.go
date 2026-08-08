// Package fishconfig implements the csp_FishConfig settings-center gateway
// (TVBox site type 3) plus per-netdisk action clients (quark/uc/tianyi/ali/
// baidu/xunlei/pan115/pan123/yidong/guangya).
//
// The action dispatch order mirrors Android FishConfig.action():
//
//  1. L1.a0(str)            pre-registered poster_* actions
//  2. Bili.dispatchConfigAction(str)
//  3. FishDrive.dispatchConfigAction(str)
//  4. local obfuscated switch (76 cases, see gateway.go dispatchTable)
//
// Swift calls the C bridge ok4k_action() with siteJSON {"api":"csp_FishConfig",
// "params":{"action":"quark_status","payload":"..."}} and receives an
// ActionResponse JSON envelope (see API.md).
package fishconfig

import (
	"context"
	"encoding/json"
)

// Netdisk identifiers used by the action gateway (action prefix -> netdisk).
const (
	NetQuark   = "quark"
	NetUC      = "uc"
	NetTianyi  = "tianyi"
	NetAli     = "ali"
	NetBaidu   = "baidu"
	NetXunlei  = "xunlei"
	NetPan115  = "pan115"
	NetPan123  = "pan123"
	NetYidong  = "yidong"
	NetGuangya = "guangya"
)

// Action kinds returned in ActionResponse.Kind.
const (
	KindStatus       = "status"
	KindScan         = "scan"
	KindLogin        = "login"
	KindThread       = "thread"
	KindClean        = "clean"
	KindMagnetSwitch = "magnet_switch"
	KindCommunity    = "community_cookie"
	KindInfo         = "info"
	KindNotImpl      = "not_implemented"
	KindError        = "error"
)

// ActionRequest is what the gateway parses from params.
type ActionRequest struct {
	Action  string          `json:"action"`
	Payload json.RawMessage `json:"payload"` // optional; per-action input
}

// GatewayRequest is the full siteJSON payload Swift passes to ok4k_action().
type GatewayRequest struct {
	Site   string            `json:"site"` // "FishConfig"
	API    string            `json:"api"`  // "csp_FishConfig"
	Host   string            `json:"host"`
	Params map[string]string `json:"params"` // action / payload
}

// ActionResponse is the JSON envelope returned to Swift for every action.
type ActionResponse struct {
	Ok      bool   `json:"ok"`
	Action  string `json:"action"`
	Kind    string `json:"kind"` // status|scan|login|thread|clean|magnet_switch|community_cookie|info|not_implemented|error
	Netdisk string `json:"netdisk,omitempty"`
	Data    any    `json:"data,omitempty"`
	Message string `json:"message,omitempty"` // UI 文案（中文，对齐 Android）
	Error   string `json:"error,omitempty"`
}

// Credential is a saved netdisk credential. Swift persists the JSON produced
// by LoginResult.Credential (Keychain) and passes it back in the payload of
// status/login calls.
type Credential struct {
	Netdisk string         `json:"netdisk"`
	Cookie  string         `json:"cookie,omitempty"`
	Token   string         `json:"token,omitempty"`
	Raw     map[string]any `json:"raw,omitempty"` // preserved raw auth response
}

// AccountInfo is the normalized account shape extracted from each netdisk
// account/user-info endpoint.
type AccountInfo struct {
	Name   string         `json:"name"`
	Avatar string         `json:"avatar,omitempty"`
	UserID string         `json:"user_id,omitempty"`
	VIP    bool           `json:"vip,omitempty"`
	Extra  map[string]any `json:"extra,omitempty"`
}

// UsageInfo is the normalized storage usage shape.
type UsageInfo struct {
	Used  int64 `json:"used,omitempty"`
	Total int64 `json:"total,omitempty"`
}

// StatusResult is returned by the *_status actions.
type StatusResult struct {
	LoggedIn bool         `json:"logged_in"`
	Account  *AccountInfo `json:"account,omitempty"`
	Usage    *UsageInfo   `json:"usage,omitempty"`
	Hint     string       `json:"hint,omitempty"`
}

// ScanResult is returned by the *_scan actions (initiate QR / device-code login).
type ScanResult struct {
	Kind      string         `json:"kind"` // qrcode|device_code|oauth_url|web
	QRImage   string         `json:"qr_image,omitempty"`
	QRURL     string         `json:"qr_url,omitempty"`
	QRContent string         `json:"qr_content,omitempty"`
	Session   map[string]any `json:"session"` // opaque; feed back to login
	Interval  int            `json:"interval_seconds"`
	Timeout   int            `json:"timeout_seconds"`
	Hint      string         `json:"hint,omitempty"`
}

// LoginRequest is the payload input for *_login / *_token / *_community_cookie.
type LoginRequest struct {
	Session  map[string]any `json:"session,omitempty"` // from ScanResult
	Input    string         `json:"input,omitempty"`   // pasted cookie / token JSON / sms code
	Account  string         `json:"account,omitempty"` // username / phone
	Password string         `json:"password,omitempty"`
	Code     string         `json:"code,omitempty"` // sms verification code
}

// LoginStage wraps every *_login-kind response so Swift can render the QR step
// (stage=start) or the finished credential (stage=done) uniformly. Netdisks
// without a dedicated *_scan action start their login flow by calling *_login
// with an empty payload.
type LoginStage struct {
	Stage string       `json:"stage"` // start | done
	Scan  *ScanResult  `json:"scan,omitempty"`
	Login *LoginResult `json:"login,omitempty"`
}

// LoginResult is returned by *_login after polling or credential verification.
type LoginResult struct {
	Success    bool         `json:"success"`
	Credential Credential   `json:"credential"`
	Account    *AccountInfo `json:"account,omitempty"`
	Hint       string       `json:"hint,omitempty"`
}

// ThreadResult is returned by *_thread actions.
type ThreadResult struct {
	Netdisk string `json:"netdisk"`
	Current int    `json:"current"`
	Options []int  `json:"options"`
	Hint    string `json:"hint"`
}

// CleanResult is returned by *_clean actions.
type CleanResult struct {
	Cleared bool   `json:"cleared"`
	Hint    string `json:"hint"`
}

// Client is the per-netdisk action client interface. The gateway routes
// netdisk actions through it.
type Client interface {
	Name() string
	Status(ctx context.Context, cred Credential, h *HTTP) (*StatusResult, error)
	Scan(ctx context.Context, h *HTTP) (*ScanResult, error)
	Login(ctx context.Context, req LoginRequest, h *HTTP) (*LoginResult, error)
}

// registry of netdisk clients.
var registry = map[string]Client{}

func register(c Client) { registry[c.Name()] = c }

// Lookup returns the client for a netdisk id.
func Lookup(name string) (Client, bool) {
	c, ok := registry[name]
	return c, ok
}
