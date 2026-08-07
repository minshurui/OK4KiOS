// Package rules implements a minimal XPath/JSONPath/URL-template engine
// used by the TVBox type 4 rule adapter. It intentionally supports the
// selector subset found in real TVBox spider rules:
//
//	//div[contains(@class,'item')]     tag with attribute contains
//	//a[@href]                          tag with attribute present
//	.//a                                relative descendant
//	//a/@href                           attribute extraction
//	//h2/text()                         text extraction
package rules

import (
	"strings"

	"golang.org/x/net/html"
)

type AttrCond struct {
	Name string // attribute name, or "" for tag text conditions
	Op   string // "=" or "contains"
	Val  string
}

type Part struct {
	Tag  string // "" matches any tag
	Atts []AttrCond
}

// Selector is a parsed XPath-like selector.
type Selector struct {
	Parts      []Part
	Extraction string // "", "attr", "text"
	AttrName   string
	Relative   bool // started with .//
}

// ParseSelector parses the supported XPath subset.
func ParseSelector(expr string) (Selector, error) {
	s := Selector{}
	e := strings.TrimSpace(expr)
	if strings.HasPrefix(e, ".//") {
		s.Relative = true
		e = e[3:]
	} else if strings.HasPrefix(e, "//") {
		e = e[2:]
	}
	// Extraction suffix: /@attr or /text()
	if idx := strings.LastIndex(e, "/@"); idx >= 0 {
		s.Extraction = "attr"
		s.AttrName = e[idx+2:]
		e = e[:idx]
	} else if strings.HasSuffix(e, "/text()") {
		s.Extraction = "text"
		e = strings.TrimSuffix(e, "/text()")
	}
	segments := strings.Split(e, "//")
	for _, seg := range segments {
		if strings.TrimSpace(seg) == "" {
			continue
		}
		part := Part{Tag: ""}
		// tag[cond][cond]
		rest := seg
		if i := strings.Index(rest, "["); i >= 0 {
			part.Tag = strings.TrimSpace(rest[:i])
			rest = rest[i:]
		} else {
			part.Tag = strings.TrimSpace(rest)
			rest = ""
		}
		for rest != "" {
			if !strings.HasPrefix(rest, "[") {
				break
			}
			end := strings.Index(rest, "]")
			if end < 0 {
				break
			}
			cond := rest[1:end]
			rest = rest[end+1:]
			part.Atts = append(part.Atts, parseCond(cond))
		}
		s.Parts = append(s.Parts, part)
	}
	return s, nil
}

func parseCond(cond string) AttrCond {
	cond = strings.TrimSpace(cond)
	if strings.HasPrefix(cond, "contains(") && strings.HasSuffix(cond, ")") {
		inner := cond[len("contains(") : len(cond)-1]
		if i := strings.Index(inner, ","); i >= 0 {
			name := strings.TrimSpace(inner[:i])
			name = strings.TrimPrefix(name, "@")
			val := strings.TrimSpace(inner[i+1:])
			val = strings.Trim(val, "'\"")
			return AttrCond{Name: name, Op: "contains", Val: val}
		}
	}
	if i := strings.Index(cond, "="); i >= 0 {
		name := strings.TrimSpace(cond[:i])
		val := strings.Trim(strings.TrimSpace(cond[i+1:]), "'\"")
		return AttrCond{Name: name, Op: "=", Val: val}
	}
	// @attr present
	if strings.HasPrefix(cond, "@") {
		return AttrCond{Name: strings.TrimSpace(cond[1:]), Op: "present"}
	}
	return AttrCond{Name: "", Op: "text", Val: cond}
}

func nodeMatches(n *html.Node, p Part) bool {
	if p.Tag != "" && n.Data != p.Tag {
		return false
	}
	for _, c := range p.Atts {
		switch c.Op {
		case "present":
			for _, a := range n.Attr {
				if a.Key == c.Name {
					return true
				}
			}
			return false
		case "contains":
			found := false
			for _, a := range n.Attr {
				if a.Key == c.Name && strings.Contains(a.Val, c.Val) {
					found = true
					break
				}
			}
			if !found {
				return false
			}
		case "=":
			found := false
			for _, a := range n.Attr {
				if a.Key == c.Name && a.Val == c.Val {
					found = true
					break
				}
			}
			if !found {
				return false
			}
		case "text":
			if !strings.Contains(collectText(n), c.Val) {
				return false
			}
		}
	}
	return true
}

func children(n *html.Node) []*html.Node {
	var out []*html.Node
	for c := n.FirstChild; c != nil; c = c.NextSibling {
		out = append(out, c)
	}
	return out
}

// Select returns the attribute/text values extracted by the selector,
// or the matched element nodes themselves when there is no extraction.
func (s Selector) Select(root *html.Node) ([]*html.Node, []string) {
	var matches []*html.Node
	var matchFrom func(n *html.Node, partIdx int)
	matchFrom = func(n *html.Node, partIdx int) {
		if partIdx >= len(s.Parts) {
			return
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			if c.Type != html.ElementNode {
				continue
			}
			if nodeMatches(c, s.Parts[partIdx]) {
				if partIdx == len(s.Parts)-1 {
					matches = append(matches, c)
				} else {
					// Subsequent parts match any descendant (like //).
					matchFrom(c, partIdx+1)
				}
			}
			// All segments search descendants for further matches.
			matchFrom(c, partIdx)
		}
	}
	matchFrom(root, 0)
	if s.Extraction == "" {
		return matches, nil
	}
	var values []string
	for _, m := range matches {
		switch s.Extraction {
		case "attr":
			found := false
			for _, a := range m.Attr {
				if a.Key == s.AttrName {
					values = append(values, a.Val)
					found = true
					break
				}
			}
			if !found {
				values = append(values, "")
			}
		case "text":
			values = append(values, strings.TrimSpace(collectText(m)))
		}
	}
	return nil, values
}

func allDescendants(n *html.Node) []*html.Node {
	var out []*html.Node
	var walk func(*html.Node)
	walk = func(node *html.Node) {
		for c := node.FirstChild; c != nil; c = c.NextSibling {
			if c.Type == html.ElementNode {
				out = append(out, c)
			}
			walk(c)
		}
	}
	walk(n)
	return out
}

func collectText(n *html.Node) string {
	var b strings.Builder
	var walk func(*html.Node)
	walk = func(node *html.Node) {
		if node.Type == html.TextNode {
			b.WriteString(node.Data)
		}
		for c := node.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(n)
	return b.String()
}

// SelectFirst returns the first extracted value (or first matched node's text).
func (s Selector) SelectFirst(root *html.Node) (string, bool) {
	_, values := s.Select(root)
	if len(values) > 0 && values[0] != "" {
		return values[0], true
	}
	return "", false
}
