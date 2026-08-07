package rules

import (
	"strings"
	"testing"

	"golang.org/x/net/html"
)

func parseSample(t *testing.T) *html.Node {
	t.Helper()
	doc, err := html.Parse(strings.NewReader(sampleHTML))
	if err != nil {
		t.Fatal(err)
	}
	return doc
}
