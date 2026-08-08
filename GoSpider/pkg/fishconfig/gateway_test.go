package fishconfig

import (
	"encoding/json"
	"testing"
)

// TestGatewayDispatchOrder verifies the Android FishConfig.action dispatch
// order: L1.a0 -> Bili -> FishDrive -> local switch (netdisk actions).
func TestGatewayDispatchOrder(t *testing.T) {
	gw := NewGateway()
	// 1) L1.a0 pre-registered poster_* actions
	for _, a := range preRegistered {
		r := gw.Dispatch(t.Context(), a, "")
		if r.Kind != KindNotImpl {
			t.Errorf("%s: want not_implemented, got %s", a, r.Kind)
		}
	}
	// 2) Bili
	if r := gw.Dispatch(t.Context(), "bili_status", ""); r.Kind != KindNotImpl {
		t.Errorf("bili_status: want not_implemented, got %s", r.Kind)
	}
	// 3) FishDrive
	if r := gw.Dispatch(t.Context(), "fishdrive_media_maintenance", ""); r.Kind != KindNotImpl {
		t.Errorf("fishdrive_*: want not_implemented, got %s", r.Kind)
	}
	// 4) netdisk action routing
	if r := gw.Dispatch(t.Context(), "quark_status", ""); r.Kind != KindStatus {
		t.Errorf("quark_status: want status, got %s (%s)", r.Kind, r.Error)
	}
	if r := gw.Dispatch(t.Context(), "pan123_clean", ""); r.Kind != KindClean {
		t.Errorf("pan123_clean: want clean, got %s", r.Kind)
	}
	// 4b) other local-switch actions stay info
	if r := gw.Dispatch(t.Context(), "config_health", ""); r.Kind != KindInfo {
		t.Errorf("config_health: want info, got %s", r.Kind)
	}
	// unknown
	if r := gw.Dispatch(t.Context(), "no_such_action", ""); r.Kind != KindError {
		t.Errorf("unknown: want error, got %s", r.Kind)
	}
	// empty
	if r := gw.Dispatch(t.Context(), "", ""); r.Kind != KindError {
		t.Errorf("empty: want error, got %s", r.Kind)
	}
}

// TestDispatchTableFidelity ensures every netdisk action from PROTOCOL.md §2
// is present in the routing table and maps to the documented runnable.
func TestDispatchTableFidelity(t *testing.T) {
	want := map[string]string{
		"quark_status": "RunnableC0234b0(27)", "quark_scan": "RunnableC0234b0(6)",
		"quark_thread": "RunnableC0380g(9)", "quark_clean": "RunnableC0380g(20)",
		"uc_status": "RunnableC0381h(2)", "uc_scan": "RunnableC0381h(14)",
		"uc_token_scan": "RunnableC0381h(29)", "uc_thread": "RunnableC0381h(26)", "uc_clean": "RunnableC0382i(0)",
		"tianyi_status": "RunnableC0382i(2)", "tianyi_login": "RunnableC0380g(6)",
		"tianyi_thread": "RunnableC0380g(17)", "tianyi_clean": "RunnableC0380g(28)",
		"ali_status": "RunnableC0380g(0)", "ali_scan": "RunnableC0380g(1)",
		"ali_token": "RunnableC0380g(1)", "ali_thread": "RunnableC0380g(2)", "ali_clean": "RunnableC0379f(1)",
		"baidu_status": "RunnableC0382i(12)", "baidu_scan": "RunnableC0382i(13)",
		"baidu_thread": "RunnableC0234b0(28)", "baidu_clean": "RunnableC0379f(0)",
		"xunlei_status": "RunnableC0380g(3)", "xunlei_login": "RunnableC0380g(4)",
		"xunlei_thread": "RunnableC0380g(5)", "xunlei_clean": "RunnableC0380g(7)",
		"pan115_status": "RunnableC0380g(8)", "pan115_magnet_switch": "RunnableC0380g(11)",
		"pan115_clean":  "RunnableC0380g(13)",
		"pan123_status": "RunnableC0380g(14)", "pan123_community_cookie": "RunnableC0380g(15)",
		"pan123_thread": "RunnableC0380g(16)",
		"yidong_status": "RunnableC0381h(20)", "yidong_clean": "RunnableC0382i(9)",
		"guangya_status": "RunnableC0380g(19)", "guangya_clean": "RunnableC0380g(24)",
	}
	for action, runnable := range want {
		found := false
		for _, e := range dispatchTable {
			if e.Action == action {
				found = true
				if e.Runnable != runnable {
					t.Errorf("%s: runnable %s != %s", action, e.Runnable, runnable)
				}
			}
		}
		if !found {
			t.Errorf("%s: missing from dispatch table", action)
		}
	}
	if _, ok := netdiskAction["pan115_login"]; !ok {
		t.Error("pan115_login missing (L1.a0/W0 pre-registered on Android)")
	}
}

// TestThreadAndClean checks generic thread/clean semantics.
func TestThreadAndClean(t *testing.T) {
	gw := NewGateway()
	// thread default
	r := gw.Dispatch(t.Context(), "quark_thread", "")
	assertOK(t, r)
	tr, _ := r.Data.(*ThreadResult)
	if tr == nil || tr.Current != 4 || len(tr.Options) != 5 {
		t.Fatalf("thread default: %+v", r.Data)
	}
	// set thread
	r = gw.Dispatch(t.Context(), "quark_thread", `{"value":16}`)
	assertOK(t, r)
	tr, _ = r.Data.(*ThreadResult)
	if tr == nil || tr.Current != 16 {
		t.Fatalf("thread set: %+v", r.Data)
	}
	// invalid value -> returns current
	r = gw.Dispatch(t.Context(), "quark_thread", `{"value":7}`)
	tr, _ = r.Data.(*ThreadResult)
	if tr == nil || tr.Current != 16 {
		t.Fatalf("thread invalid: %+v", r.Data)
	}
	// clean
	r = gw.Dispatch(t.Context(), "quark_clean", "")
	assertOK(t, r)
	if c, _ := r.Data.(*CleanResult); c == nil || !c.Cleared {
		t.Fatalf("clean: %+v", r.Data)
	}
	// magnet switch
	r = gw.Dispatch(t.Context(), "pan115_magnet_switch", `{"on":true}`)
	assertOK(t, r)
	if m, _ := r.Data.(map[string]any); m == nil || m["on"] != true {
		t.Fatalf("magnet switch: %+v", r.Data)
	}
	// community cookie with empty input -> error path handled by client
	r = gw.Dispatch(t.Context(), "pan123_community_cookie", "")
	if r.Kind == KindError {
		t.Logf("pan123_community_cookie without input: %s", r.Error)
	}
	recordEvidence(t, "gateway", r, "thread/clean/magnet dispatch")
}

// TestActionCatalog lists all netdisk actions (documented for API.md).
func TestActionCatalog(t *testing.T) {
	cat := ActionsCatalog()
	b, _ := json.MarshalIndent(cat, "", "  ")
	t.Logf("actions catalog:\n%s", string(b))
	if len(cat) < 9 {
		t.Fatalf("expected >=9 netdisks, got %d", len(cat))
	}
}
