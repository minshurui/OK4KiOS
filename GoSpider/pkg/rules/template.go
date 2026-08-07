package rules

import (
	"net/url"
	"strings"
)

// BuildURL fills {placeholder} tokens in a template with values.
// Supported placeholders: {cateId} {catePg} {wd} {id} {pg} {name} {pic} {url}
// Unknown placeholders are left empty.
func BuildURL(template string, values map[string]string) string {
	var b strings.Builder
	rest := template
	for {
		start := strings.Index(rest, "{")
		if start < 0 {
			b.WriteString(rest)
			break
		}
		b.WriteString(rest[:start])
		rest = rest[start+1:]
		end := strings.Index(rest, "}")
		if end < 0 {
			b.WriteString(rest)
			break
		}
		key := strings.TrimSpace(rest[:end])
		rest = rest[end+1:]
		if v, ok := values[key]; ok {
			b.WriteString(escapePath(v))
		}
	}
	return b.String()
}

func escapePath(v string) string {
	return strings.ReplaceAll(url.QueryEscape(v), "+", "%20")
}
// ResolveURL joins a possibly-relative URL against a base URL.
func ResolveURL(base, ref string) string {
	b, err := url.Parse(base)
	if err != nil {
		return ref
	}
	r, err := url.Parse(ref)
	if err != nil {
		return ref
	}
	return b.ResolveReference(r).String()
}
