package fishguard

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestDecryptExtMatchesNativeFishGuard(t *testing.T) {
	const encrypted = "AdYEovlEKsDy77+R58YGahWCxrDZyBxExcQNC2NSeH0n1b5mu6tvh8b4Eh0RCpoPF6eivKdrR1Hsb8X4sSVBS8zF6jkwLW+wze9yh+hSY5iimm4gM9mAtmt0obTi+6Iox/Jp4GCsN4MQyFebMK162SKnILklpXc1UMiJv9gnPOe5aOPUxCftL+x7/UGhBdFYWIegpiHvKeavUtCUkhxtDyC8KqVVPPW0StI5GdmUA3WBbnnrNiKqNc5GBmrffd6pDN+Cf9IIjzNNvos/5KXJmBbe/baAzTLkoafeIoDhO451"
	const native = `{"site":"https://daen-1256234123.cos.ap-shanghai.myqcloud.com/MuQi/mqxhqj.txt","dataKey":"kj37zs29q22jk96t","dataIv":"kj37zs29q22jk96t","init":"initV122","playname":"怀桑","ua":"okhttp/3.10.0"}`

	plain, err := DecryptExt(encrypted)
	if err != nil {
		t.Fatal(err)
	}
	if string(plain) != native {
		t.Fatalf("native mismatch\ngot:  %s\nwant: %s", plain, native)
	}
	var value map[string]any
	if err := json.Unmarshal(plain, &value); err != nil {
		t.Fatalf("plaintext is not JSON: %v", err)
	}
}

func TestDecryptExtRejectsInvalidInput(t *testing.T) {
	for _, input := range []string{"not-base64", "AQ==", strings.Repeat("A", 44)} {
		if _, err := DecryptExt(input); err == nil {
			t.Fatalf("expected error for %q", input)
		}
	}
}
