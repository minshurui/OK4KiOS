// Package wogg implements the Wogg site rules (module-item structure).
package wogg

import (
	"ok4kspider/pkg/engine"
)

// Rules returns the Wogg type-4 style rule set.
func Rules(host string) engine.SiteRules {
	if host == "" {
		host = "https://wogg.xxooo.cf"
	}
	return engine.SiteRules{
		Host: host,
		Headers: map[string]string{
			"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 15_4 like Mac OS X) Mobile/15E148",
			"Referer":    host + "/",
		},
		Home: engine.Rule{
			URL:    "/",
			List:   "//div[contains(@class,'module-item')]",
			Name:   ".//div[contains(@class,'video-name')]//a/@title",
			Pic:    ".//img/@data-src",
			URLSel: ".//div[contains(@class,'module-item-pic')]//a/@href",
			Remark: ".//div[contains(@class,'module-item-text')]/text()",
		},
		Category: engine.Rule{
			URL:    "/vodshow/{cateId}-{catePg}.html",
			List:   "//div[contains(@class,'module-item')]",
			Name:   ".//div[contains(@class,'video-name')]//a/@title",
			Pic:    ".//img/@data-src",
			URLSel: ".//div[contains(@class,'module-item-pic')]//a/@href",
			Remark: ".//div[contains(@class,'module-item-text')]/text()",
		},
		Search: engine.Rule{
			URL:    "/vodsearch/{wd}-------------.html",
			List:   "//div[contains(@class,'module-item')]",
			Name:   ".//div[contains(@class,'video-name')]//a/@title",
			Pic:    ".//img/@data-src",
			URLSel: ".//div[contains(@class,'module-item-pic')]//a/@href",
			Remark: ".//div[contains(@class,'module-item-text')]/text()",
		},
		Detail: engine.DetailRule{
			URL:      "/voddetail/{id}.html",
			Info:     "//div[contains(@class,'module-info-introduction-content')]/text()",
			PlayFrom: "//div[contains(@class,'module-tab-item')]//span/text()",
			PlayURL:  "//div[contains(@class,'module-play-list')]//a/@href",
		},
		PlayURL: "//video/@src",
	}
}
