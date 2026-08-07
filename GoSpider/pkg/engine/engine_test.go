package engine

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestJSSignature(t *testing.T) {
	out, err := JSSignature(`(function(){ var t = Date.now(); return "sig=" + (t % 1000) + "&k=" + (url.length + (params["wd"]||"").length); })()`, "http://x.test/", map[string]string{"wd": "abc"})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(out, "sig=") {
		t.Fatalf("js out: %s", out)
	}
}

func TestEngineHomeHTML(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`<html><body>
<div class="item"><a href="/d/1.html" title="A"><img src="/i/a.jpg"/><span class="t">HD</span></a></div>
<div class="item"><a href="/d/2.html" title="B"><img src="/i/b.jpg"/></a></div>
</body></html>`))
	}))
	defer srv.Close()

	e := New(SiteRules{
		Host: srv.URL,
		Home: Rule{
			List:   "//div[contains(@class,'item')]",
			Name:   ".//a/@title",
			Pic:    ".//img/@src",
			URLSel: ".//a/@href",
		},
	})
	items, err := e.Home()
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 2 || items[0].Name != "A" || items[0].URL != srv.URL+"/d/1.html" {
		t.Fatalf("items: %+v", items)
	}
}

func TestEngineHomeJSON(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"code":1,"list":[{"vod_id":1,"vod_name":"A","vod_pic":"/p/a.jpg","vod_remarks":"HD"},{"vod_id":2,"vod_name":"B","vod_pic":"/p/b.jpg"}]}`))
	}))
	defer srv.Close()

	e := New(SiteRules{
		Host: srv.URL,
		Home: Rule{
			List:   "$.list",
			Name:   "$.vod_name",
			Pic:    "$.vod_pic",
			URLSel: "$.vod_id",
			Remark: "$.vod_remarks",
		},
	})
	items, err := e.Home()
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 2 || items[0].Name != "A" || items[0].Remark != "HD" {
		t.Fatalf("items: %+v", items)
	}
}

func TestEngineCategoryTemplate(t *testing.T) {
	var got string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got = r.URL.String()
		w.Write([]byte(`<html><body><div class="item"><a href="/d/1.html" title="X"></a></div></body></html>`))
	}))
	defer srv.Close()

	e := New(SiteRules{
		Host: srv.URL,
		Category: Rule{
			URL:    "/vodshow/{cateId}-{catePg}.html",
			List:   "//div[contains(@class,'item')]",
			Name:   ".//a/@title",
			URLSel: ".//a/@href",
		},
	})
	if _, err := e.Category("5", 2); err != nil {
		t.Fatal(err)
	}
	if got != "/vodshow/5-2.html" {
		t.Fatalf("category url: %s", got)
	}
}

func TestEngineDetailPlay(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/d/1.html" {
			w.Write([]byte(`<html><body>
<div class="info">简介</div>
<div class="line">线路1</div><ul class="eps"><li><a href="/p/1.m3u8">第1集</a></li><li><a href="/p/2.m3u8">第2集</a></li></ul>
</body></html>`))
			return
		}
		w.Write([]byte("not found"))
	}))
	defer srv.Close()

	e := New(SiteRules{
		Host: srv.URL,
		Detail: DetailRule{
			URL:      "/d/{id}.html",
			Info:     "//div[contains(@class,'info')]/text()",
			PlayFrom: "//div[contains(@class,'line')]/text()",
			PlayURL:  "//ul[contains(@class,'eps')]//a/@href",
		},
	})
	d, err := e.Detail("1")
	if err != nil {
		t.Fatal(err)
	}
	if len(d.PlayFrom) != 1 || d.PlayFrom[0] != "线路1" {
		t.Fatalf("playFrom: %+v", d.PlayFrom)
	}
	if !strings.Contains(d.PlayURL["线路1"], "/p/1.m3u8") {
		t.Fatalf("playURL: %+v", d.PlayURL)
	}
}
