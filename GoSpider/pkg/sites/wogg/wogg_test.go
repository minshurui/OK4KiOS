package wogg

import (
	"os"
	"strings"
	"testing"

	"golang.org/x/net/html"

	"ok4kspider/pkg/engine"
)

// TestExtractRealFixture runs the Wogg rules against the captured home HTML.
func TestExtractRealFixture(t *testing.T) {
	data, err := os.ReadFile("/tmp/449a2b10.html")
	if err != nil {
		t.Skipf("fixture missing: %v", err)
	}
	doc, err := html.Parse(strings.NewReader(string(data)))
	if err != nil {
		t.Fatal(err)
	}
	e := engine.New(Rules("https://wogg.xxooo.cf"))
	items := e.ExtractHTML(Rules("https://wogg.xxooo.cf").Home, doc, "https://wogg.xxooo.cf")
	if len(items) == 0 {
		t.Fatal("no items extracted from fixture")
	}
	t.Logf("extracted %d items", len(items))
	for i, it := range items {
		if i >= 5 {
			break
		}
		t.Logf("  %s | %s | %s", it.Name, it.URL, it.Pic)
		if it.Name == "" || !strings.HasPrefix(it.URL, "http") {
			t.Fatalf("bad item: %+v", it)
		}
	}
}

func TestFixtureHasExpectedStructure(t *testing.T) {
	data, err := os.ReadFile("/tmp/449a2b10.html")
	if err != nil {
		t.Skipf("fixture missing: %v", err)
	}
	body := string(data)
	for _, marker := range []string{"module-item", "vodshow", "vodtype", "playlist"} {
		if !strings.Contains(body, marker) {
			t.Fatalf("missing marker %q", marker)
		}
	}
}
