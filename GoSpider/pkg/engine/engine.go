// Package engine is the TVBox type 4 rule engine: it renders page URLs from
// templates, fetches HTML or JSON, and extracts list items / detail fields /
// play URLs using the rules package selectors.
package engine

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"golang.org/x/net/html"

	"ok4kspider/pkg/rules"
)

// Item is one extracted media entry.
type Item struct {
	Name   string `json:"name"`
	Pic    string `json:"pic"`
	URL    string `json:"url"`
	Remark string `json:"remark"`
}

// Rule describes one extraction page (home/category/search).
type Rule struct {
	URL    string `json:"url"` // URL template
	List   string `json:"list"`
	Name   string `json:"name"`
	Pic    string `json:"pic"`
	URLSel string `json:"url_sel"` // item URL selector
	Remark string `json:"remark"`
}

// DetailRule describes the detail page extraction.
type DetailRule struct {
	URL      string `json:"url"`
	Info     string `json:"info"`
	PlayFrom string `json:"play_from"`
	PlayURL  string `json:"play_url"`
}

// SiteRules is the full type 4 site rule set.
type SiteRules struct {
	Host     string            `json:"host"`
	Headers  map[string]string `json:"headers"`
	Home     Rule              `json:"home"`
	Category Rule              `json:"category"`
	Search   Rule              `json:"search"`
	Detail   DetailRule        `json:"detail"`
	PlayURL  string            `json:"play_url"` // play URL template
}

// Engine executes a SiteRules.
type Engine struct {
	Rules   SiteRules
	Client  *http.Client
	Headers map[string]string
}

// New creates an engine with a default 25s HTTP client.
func New(sr SiteRules) *Engine {
	return &Engine{
		Rules: sr,
		Client: &http.Client{Timeout: 25 * time.Second},
		Headers: map[string]string{
			"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 15_4 like Mac OS X) Mobile/15E148",
		},
	}
}

func (e *Engine) fetch(urlStr string) ([]byte, error) {
	req, err := http.NewRequest(http.MethodGet, urlStr, nil)
	if err != nil {
		return nil, err
	}
	for k, v := range e.Headers {
		req.Header.Set(k, v)
	}
	for k, v := range e.Rules.Headers {
		req.Header.Set(k, v)
	}
	resp, err := e.Client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return nil, fmt.Errorf("http %d", resp.StatusCode)
	}
	return io.ReadAll(resp.Body)
}

// Home returns the home page items.
func (e *Engine) Home() ([]Item, error) {
	u := rules.ResolveURL(e.Rules.Host, rules.BuildURL(e.Rules.Home.URL, map[string]string{}))
	return e.extractPage(e.Rules.Home, u)
}

// Category returns category page items.
func (e *Engine) Category(id string, pg int) ([]Item, error) {
	u := rules.ResolveURL(e.Rules.Host, rules.BuildURL(e.Rules.Category.URL, map[string]string{
		"cateId": id, "catePg": fmt.Sprintf("%d", pg), "pg": fmt.Sprintf("%d", pg),
	}))
	return e.extractPage(e.Rules.Category, u)
}

// Search returns search results.
func (e *Engine) Search(wd string, pg int) ([]Item, error) {
	u := rules.ResolveURL(e.Rules.Host, rules.BuildURL(e.Rules.Search.URL, map[string]string{
		"wd": wd, "pg": fmt.Sprintf("%d", pg),
	}))
	return e.extractPage(e.Rules.Search, u)
}

// Detail returns the play lines for a media detail page.
type Detail struct {
	Info     string            `json:"info"`
	PlayFrom []string          `json:"play_from"`
	PlayURL  map[string]string `json:"play_url"` // from -> eps string
}

func (e *Engine) Detail(id string) (*Detail, error) {
	u := rules.ResolveURL(e.Rules.Host, rules.BuildURL(e.Rules.Detail.URL, map[string]string{"id": id}))
	data, err := e.fetch(u)
	if err != nil {
		return nil, err
	}
	d := &Detail{PlayURL: map[string]string{}}
	body := string(data)
	if strings.HasPrefix(strings.TrimSpace(body), "{") {
		var obj any
		if json.Unmarshal(data, &obj) == nil {
			d.Info = rules.JSONPathString(obj, e.Rules.Detail.Info)
			froms := extractListStrings(obj, e.Rules.Detail.PlayFrom)
			urls := extractListStrings(obj, e.Rules.Detail.PlayURL)
			if len(froms) == len(urls) {
				for i := range froms {
					d.PlayFrom = append(d.PlayFrom, froms[i])
					d.PlayURL[froms[i]] = urls[i]
				}
			}
			return d, nil
		}
	}
	doc, err := html.Parse(strings.NewReader(body))
	if err != nil {
		return nil, err
	}
	d.Info = firstText(doc, e.Rules.Detail.Info)
	if sel, err := rules.ParseSelector(e.Rules.Detail.PlayFrom); err == nil {
		_, vals := sel.Select(doc)
		for _, v := range vals {
			v = strings.TrimSpace(v)
			if v != "" {
				d.PlayFrom = append(d.PlayFrom, v)
			}
		}
	}
	if sel, err := rules.ParseSelector(e.Rules.Detail.PlayURL); err == nil {
		_, vals := sel.Select(doc)
		// Assume each line's episodes are separated by # with name$url pairs.
		for i, v := range vals {
			if i < len(d.PlayFrom) {
				d.PlayURL[d.PlayFrom[i]] = strings.TrimSpace(v)
			}
		}
	}
	return d, nil
}

// Play returns the resolved playable URL for a flag+episode.
func (e *Engine) Play(flag, id string) (string, error) {
	u := rules.ResolveURL(e.Rules.Host, rules.BuildURL(e.Rules.PlayURL, map[string]string{"id": id}))
	if u != id {
		data, err := e.fetch(u)
		if err != nil {
			return "", err
		}
		body := string(data)
		if strings.HasPrefix(strings.TrimSpace(body), "{") {
			var obj any
			if json.Unmarshal(data, &obj) == nil {
				return rules.JSONPathString(obj, e.Rules.PlayURL), nil
			}
		}
		doc, err := html.Parse(strings.NewReader(body))
		if err != nil {
			return "", err
		}
		if sel, err := rules.ParseSelector(e.Rules.PlayURL); err == nil {
			if v, ok := sel.SelectFirst(doc); ok {
				return rules.ResolveURL(u, v), nil
			}
		}
		return "", fmt.Errorf("no play url extracted")
	}
	return u, nil
}

func (e *Engine) extractPage(r Rule, u string) ([]Item, error) {
	data, err := e.fetch(u)
	if err != nil {
		return nil, err
	}
	body := string(data)
	if strings.HasPrefix(strings.TrimSpace(body), "{") || strings.HasPrefix(strings.TrimSpace(body), "[") {
		var obj any
		if json.Unmarshal(data, &obj) == nil {
			return e.extractJSON(r, obj, u)
		}
	}
	doc, err := html.Parse(strings.NewReader(body))
	if err != nil {
		return nil, err
	}
	return e.ExtractHTML(r, doc, u), nil
}

func (e *Engine) extractJSON(r Rule, obj any, base string) ([]Item, error) {
	listVal, ok := rules.JSONPath(obj, r.List)
	if !ok {
		return nil, fmt.Errorf("list path %q not found", r.List)
	}
	var list []any
	switch t := listVal.(type) {
	case []any:
		list = t
	default:
		list = []any{t}
	}
	var items []Item
	for _, entry := range list {
		it := Item{
			Name:   rules.JSONPathString(entry, r.Name),
			Pic:    rules.JSONPathString(entry, r.Pic),
			URL:    rules.JSONPathString(entry, r.URLSel),
			Remark: rules.JSONPathString(entry, r.Remark),
		}
		if it.Name == "" || it.URL == "" {
			continue
		}
		it.URL = rules.ResolveURL(base, it.URL)
		it.Pic = rules.ResolveURL(base, it.Pic)
		items = append(items, it)
	}
	return items, nil
}

func (e *Engine) ExtractHTML(r Rule, doc *html.Node, base string) []Item {
	var items []Item
	listSel, err := rules.ParseSelector(r.List)
	if err != nil {
		return nil
	}
	nodes, _ := listSel.Select(doc)
	for _, node := range nodes {
		it := Item{
			Name:   firstFrom(node, r.Name),
			Pic:    firstFrom(node, r.Pic),
			URL:    firstFrom(node, r.URLSel),
			Remark: firstFrom(node, r.Remark),
		}
		if it.Name == "" || it.URL == "" {
			continue
		}
		it.URL = rules.ResolveURL(base, it.URL)
		it.Pic = rules.ResolveURL(base, it.Pic)
		items = append(items, it)
	}
	return dedupe(items)
}

func dedupe(items []Item) []Item {
	seen := map[string]bool{}
	var out []Item
	for _, it := range items {
		if it.URL == "" || seen[it.URL] {
			continue
		}
		seen[it.URL] = true
		out = append(out, it)
	}
	return out
}

func firstFrom(node *html.Node, expr string) string {
	if expr == "" {
		return ""
	}
	sel, err := rules.ParseSelector(expr)
	if err != nil {
		return ""
	}
	v, _ := sel.SelectFirst(node)
	return v
}

func firstText(doc *html.Node, expr string) string {
	return firstFrom(doc, expr)
}

func extractListStrings(obj any, expr string) []string {
	v, ok := rules.JSONPath(obj, expr)
	if !ok {
		return nil
	}
	switch t := v.(type) {
	case []any:
		var out []string
		for _, item := range t {
			out = append(out, fmt.Sprintf("%v", item))
		}
		return out
	case string:
		return strings.Split(t, "$$$")
	default:
		return []string{fmt.Sprintf("%v", t)}
	}
}
