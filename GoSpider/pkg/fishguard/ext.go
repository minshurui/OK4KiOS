// Package fishguard implements the portable parts of FishGuard's encrypted
// extension envelope. It does not load or depend on the Android native library.
package fishguard

import (
	"crypto/aes"
	"crypto/cipher"
	"encoding/base64"
	"errors"
	"fmt"
)

const ExtVersionV1 byte = 1

var (
	extKeyV1  = [16]byte{'s', 'j', 'k', 'l', 'o', 'p', 'q', 'i', 'o', 'a', 'n', 's', 'j', 'w', 'i', '!'}
	extMaskV1 = [32]byte{0x99, 0x6a, 0xaa, 0x16, 0x77, 0xa6, 0x7d, 0x72, 0x59, 0xb4, 0xfc, 0xd9, 0x2d, 0x63, 0x77, 0xf3, 0x53, 0xec, 0x7b, 0xe9, 0xdd, 0xfe, 0x90, 0x80, 0xcb, 0x1d, 0x91, 0x26, 0xcc, 0xeb, 0x2c, 0x9e}
)

// DecryptExt decrypts a FishGuard extDe v1 Base64 envelope.
// The decoded layout is version || masked-IV || masked-AES-CBC ciphertext.
func DecryptExt(encoded string) ([]byte, error) {
	raw, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return nil, fmt.Errorf("fishguard ext base64: %w", err)
	}
	if len(raw) < 33 || (len(raw)-17)%aes.BlockSize != 0 {
		return nil, errors.New("fishguard ext: invalid envelope length")
	}
	if raw[0] != ExtVersionV1 {
		return nil, fmt.Errorf("fishguard ext: unsupported version %d", raw[0])
	}

	body := make([]byte, len(raw)-1)
	for i, b := range raw[1:] {
		body[i] = b ^ extMaskV1[i%len(extMaskV1)]
	}
	block, err := aes.NewCipher(extKeyV1[:])
	if err != nil {
		return nil, err
	}
	plain := make([]byte, len(body)-aes.BlockSize)
	cipher.NewCBCDecrypter(block, body[:aes.BlockSize]).CryptBlocks(plain, body[aes.BlockSize:])
	return unpadPKCS7(plain, aes.BlockSize)
}

func unpadPKCS7(data []byte, blockSize int) ([]byte, error) {
	if len(data) == 0 || len(data)%blockSize != 0 {
		return nil, errors.New("fishguard ext: invalid padded plaintext length")
	}
	padding := int(data[len(data)-1])
	if padding == 0 || padding > blockSize || padding > len(data) {
		return nil, errors.New("fishguard ext: invalid PKCS#7 padding")
	}
	for _, b := range data[len(data)-padding:] {
		if int(b) != padding {
			return nil, errors.New("fishguard ext: invalid PKCS#7 padding")
		}
	}
	return data[:len(data)-padding], nil
}
