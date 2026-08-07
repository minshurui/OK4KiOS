// Package main exposes the Go spider engine as a C API for iOS (c-archive).
// Build (on macOS with Xcode):
//
//	GOOS=ios GOARCH=arm64 CGO_ENABLED=1 go build -buildmode=c-archive -o libok4kspider.a
//
// Swift calls ok4k_* functions and frees results with ok4k_free.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"fmt"
	"unsafe"

	"ok4kspider/pkg/engine"
	"ok4kspider/pkg/fishguard"
	"ok4kspider/pkg/sites/wogg"
)

// SiteRequest is the JSON payload Swift passes in: rule set plus call params.
type SiteRequest struct {
	Site   string            `json:"site"`   // "wogg" or a full type-4 rule JSON
	Host   string            `json:"host"`   // override host
	Rule   engine.SiteRules  `json:"rule"`   // full rules (type 4)
	Params map[string]string `json:"params"` // id / cateId / wd / pg etc.
}

func parseRequest(siteJSON string) (*SiteRequest, error) {
	var req SiteRequest
	if err := json.Unmarshal([]byte(siteJSON), &req); err != nil {
		return nil, err
	}
	return &req, nil
}

func engineFor(req *SiteRequest) *engine.Engine {
	switch req.Site {
	case "wogg":
		if req.Rule.Host == "" {
			req.Rule = wogg.Rules(req.Host)
		}
	default:
		if req.Rule.Host == "" && req.Host != "" {
			req.Rule.Host = req.Host
		}
	}
	return engine.New(req.Rule)
}

func cString(s string) *C.char {
	return C.CString(s)
}

//export ok4k_version
func ok4k_version() *C.char {
	return cString("ok4kspider 0.1.0 (go-ios-engine)")
}

//export ok4k_home
func ok4k_home(siteJSON *C.char) *C.char {
	out := run(func(req *SiteRequest) (any, error) {
		return engineFor(req).Home()
	}, siteJSON)
	return cString(out)
}

//export ok4k_category
func ok4k_category(siteJSON *C.char) *C.char {
	out := run(func(req *SiteRequest) (any, error) {
		pg := 1
		if v, ok := req.Params["pg"]; ok {
			fmt.Sscanf(v, "%d", &pg)
		}
		return engineFor(req).Category(req.Params["cateId"], pg)
	}, siteJSON)
	return cString(out)
}

//export ok4k_search
func ok4k_search(siteJSON *C.char) *C.char {
	out := run(func(req *SiteRequest) (any, error) {
		pg := 1
		if v, ok := req.Params["pg"]; ok {
			fmt.Sscanf(v, "%d", &pg)
		}
		return engineFor(req).Search(req.Params["wd"], pg)
	}, siteJSON)
	return cString(out)
}

//export ok4k_detail
func ok4k_detail(siteJSON *C.char) *C.char {
	out := run(func(req *SiteRequest) (any, error) {
		return engineFor(req).Detail(req.Params["id"])
	}, siteJSON)
	return cString(out)
}

//export ok4k_play
func ok4k_play(siteJSON *C.char) *C.char {
	out := run(func(req *SiteRequest) (any, error) {
		return engineFor(req).Play(req.Params["flag"], req.Params["id"])
	}, siteJSON)
	return cString(out)
}

//export ok4k_ext_decrypt
func ok4k_ext_decrypt(encoded *C.char) *C.char {
	plain, err := fishguard.DecryptExt(C.GoString(encoded))
	if err != nil {
		data, _ := json.Marshal(map[string]string{"error": err.Error()})
		return cString(string(data))
	}
	// JSON ext values are returned as-is so Swift can decode their native shape.
	if json.Valid(plain) {
		return cString(string(plain))
	}
	data, _ := json.Marshal(map[string]string{"value": string(plain)})
	return cString(string(data))
}

//export ok4k_js_sign
func ok4k_js_sign(script *C.char, urlStr *C.char, paramsJSON *C.char) *C.char {
	var params map[string]string
	_ = json.Unmarshal([]byte(C.GoString(paramsJSON)), &params)
	out, err := engine.JSSignature(C.GoString(script), C.GoString(urlStr), params)
	if err != nil {
		out = `{"error":"` + err.Error() + `"}`
	}
	return cString(out)
}

//export ok4k_free
func ok4k_free(p *C.char) {
	C.free(unsafe.Pointer(p))
}

func run(fn func(req *SiteRequest) (any, error), siteJSON *C.char) string {
	req, err := parseRequest(C.GoString(siteJSON))
	if err != nil {
		return `{"error":"` + err.Error() + `"}`
	}
	v, err := fn(req)
	if err != nil {
		return `{"error":"` + err.Error() + `"}`
	}
	data, err := json.Marshal(v)
	if err != nil {
		return `{"error":"` + err.Error() + `"}`
	}
	return string(data)
}

func main() {}
