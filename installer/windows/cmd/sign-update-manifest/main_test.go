package main

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRunSignsCanonicalManifestWithoutExposingPrivateKey(t *testing.T) {
	root := t.TempDir()
	seed := make([]byte, ed25519.SeedSize)
	for index := range seed {
		seed[index] = byte(index + 1)
	}
	keyPath := filepath.Join(root, "update.key")
	if err := os.WriteFile(keyPath, []byte(base64.StdEncoding.EncodeToString(seed)), 0o600); err != nil {
		t.Fatal(err)
	}
	unsigned := unsignedManifest{
		SchemaVersion: 1, Product: "AkuBrowser", Channel: "stable",
		Version: "0.7.5", RuntimeRevision: "source-adapters-v85",
		BridgeContractVersion: "aku-browser.bridge.v2",
		PublishedAt:           "2026-07-29T00:00:00Z",
		Artifact: artifact{
			URL:  "https://github.com/abangkis/AkuBrowser/releases/download/v0.7.5/AkuBrowserRuntime-0.7.5-windows-x64.zip",
			Size: 42, SHA256: strings.Repeat("a", 64),
		},
	}
	unsignedData, _ := json.Marshal(unsigned)
	unsignedPath := filepath.Join(root, "unsigned.json")
	outputPath := filepath.Join(root, "signed.json")
	if err := os.WriteFile(unsignedPath, unsignedData, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := run(unsignedPath, keyPath, outputPath); err != nil {
		t.Fatalf("sign update manifest: %v", err)
	}
	output, err := os.ReadFile(outputPath)
	if err != nil {
		t.Fatal(err)
	}
	var signed signedManifest
	if err := json.Unmarshal(output, &signed); err != nil {
		t.Fatal(err)
	}
	payload, _ := json.Marshal(unsigned)
	signatureBytes, err := base64.StdEncoding.DecodeString(signed.Signature.Value)
	if err != nil {
		t.Fatal(err)
	}
	privateKey := ed25519.NewKeyFromSeed(seed)
	if !ed25519.Verify(privateKey.Public().(ed25519.PublicKey), payload, signatureBytes) {
		t.Fatal("signed manifest did not verify")
	}
	if strings.Contains(string(output), base64.StdEncoding.EncodeToString(seed)) {
		t.Fatal("signed manifest exposed the private seed")
	}
}
