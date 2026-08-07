package rules

import "testing"

const sampleHTML = `<html><body>
<div class="module">
  <div class="module-item">
    <a href="/voddetail/1.html" title="影片A">
      <img src="/pic/a.jpg" data-src="/pic/a2.jpg"/>
      <div class="module-item-text">HD</div>
    </a>
    <h2>影片A标题</h2>
  </div>
  <div class="module-item">
    <a href="/voddetail/2.html" title="影片B"><img src="/pic/b.jpg"/></a>
    <h2>影片B标题</h2>
  </div>
</div>
</body></html>`

func TestParseSelector(t *testing.T) {
	s, err := ParseSelector("//div[contains(@class,'module-item')]//a/@title")
	if err != nil {
		t.Fatal(err)
	}
	if len(s.Parts) != 2 || s.Extraction != "attr" || s.AttrName != "title" {
		t.Fatalf("parsed wrong: %+v", s)
	}
}

func TestSelectHTML(t *testing.T) {
	doc := parseSample(t)
	s, _ := ParseSelector("//div[contains(@class,'module-item')]//a/@href")
	_, vals := s.Select(doc)
	if len(vals) != 2 || vals[0] != "/voddetail/1.html" {
		t.Fatalf("hrefs: %v", vals)
	}
	s2, _ := ParseSelector("//div[contains(@class,'module-item')]//h2/text()")
	_, names := s2.Select(doc)
	if len(names) != 2 || names[0] != "影片A标题" {
		t.Fatalf("names: %v", names)
	}
	s3, _ := ParseSelector("//div[contains(@class,'module-item')]//img/@data-src")
	_, pics := s3.Select(doc)
	if len(pics) != 2 || pics[0] != "/pic/a2.jpg" {
		t.Fatalf("pics: %v", pics)
	}
}

func TestJSONPath(t *testing.T) {
	data := map[string]any{
		"list": []any{
			map[string]any{"vod_name": "A", "pic": "p1.jpg"},
			map[string]any{"vod_name": "B", "pic": "p2.jpg"},
		},
	}
	if JSONPathString(data, "$.list[0].vod_name") != "A" {
		t.Fatal("jsonpath failed")
	}
	v, ok := JSONPath(data, "$.list[*].vod_name")
	if !ok {
		t.Fatal("wildcard failed")
	}
	arr, _ := v.([]any)
	if len(arr) != 2 {
		t.Fatalf("wildcard count: %d", len(arr))
	}
}

func TestBuildURL(t *testing.T) {
	got := BuildURL("/vodshow/{cateId}-{catePg}.html", map[string]string{"cateId": "1", "catePg": "2"})
	if got != "/vodshow/1-2.html" {
		t.Fatalf("template: %s", got)
	}
	got2 := BuildURL("/vodsearch/{wd}.html", map[string]string{"wd": "三体 2"})
	if got2 != "/vodsearch/%E4%B8%89%E4%BD%93%202.html" {
		t.Fatalf("encoding: %s", got2)
	}
}
