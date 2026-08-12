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

func TestRunSignsLegacyV1ManifestWithoutExposingPrivateKey(t *testing.T) {
	unsigned := unsignedManifestV1{
		SchemaVersion: 1, Product: "AkuBrowser", Channel: "stable",
		Version: "0.7.9", RuntimeRevision: "source-adapters-v91",
		BridgeContractVersion: "aku-browser.bridge.v2",
		PublishedAt:           "2026-07-29T00:00:00Z",
		Artifact: artifactV1{
			URL:  "https://github.com/abangkis/AkuBrowser/releases/download/v0.7.9/AkuBrowserRuntime-0.7.9-windows-x64.zip",
			Size: 42, SHA256: strings.Repeat("a", 64),
		},
	}
	output := signFixture(t, unsigned)
	var signed signedManifestV1
	if err := json.Unmarshal(output, &signed); err != nil {
		t.Fatal(err)
	}
	verifySignature(t, unsigned, signed.Signature)
	root := t.TempDir()
	signedPath := filepath.Join(root, "signed.json")
	if err := os.WriteFile(signedPath, output, 0o600); err != nil {
		t.Fatal(err)
	}
	publicKey := ed25519.NewKeyFromSeed(testSeed()).Public().(ed25519.PublicKey)
	if err := verifySigned(signedPath, base64.StdEncoding.EncodeToString(publicKey)); err != nil {
		t.Fatalf("verify signed legacy manifest: %v", err)
	}
}

func TestVerifySignedRejectsChangedLegacyManifest(t *testing.T) {
	unsigned := unsignedManifestV1{
		SchemaVersion: 1, Product: "AkuBrowser", Channel: "stable",
		Version: "0.7.9", RuntimeRevision: "source-adapters-v91",
		BridgeContractVersion: "aku-browser.bridge.v2", PublishedAt: "2026-07-29T00:00:00Z",
		Artifact: artifactV1{URL: "https://github.com/abangkis/AkuBrowser/releases/download/v0.7.9/AkuBrowserRuntime-0.7.9-windows-x64.zip", Size: 42, SHA256: strings.Repeat("a", 64)},
	}
	output := signFixture(t, unsigned)
	output = []byte(strings.Replace(string(output), `"version": "0.7.9"`, `"version": "0.8.0"`, 1))
	root := t.TempDir()
	signedPath := filepath.Join(root, "changed.json")
	if err := os.WriteFile(signedPath, output, 0o600); err != nil {
		t.Fatal(err)
	}
	publicKey := ed25519.NewKeyFromSeed(testSeed()).Public().(ed25519.PublicKey)
	if err := verifySigned(signedPath, base64.StdEncoding.EncodeToString(publicKey)); err == nil || !strings.Contains(err.Error(), "signature is invalid") {
		t.Fatalf("expected changed signed manifest rejection, got %v", err)
	}
}

func TestRunSignsIndependentSidecarV2Manifest(t *testing.T) {
	unsigned := unsignedManifestV2{
		SchemaVersion: 2, Product: "AkuSidecar", Channel: "stable",
		SidecarVersion: "0.8.1", RuntimeRevision: "source-adapters-v93",
		MinHostVersion: "0.7.9",
		BridgeCompatibility: bridgeCompatibility{
			Protocol: "aku-browser.bridge", MinVersion: 2, MaxVersion: 3,
			RequiredCapabilities: []string{"collect_visible", "authority.read_only_bounded", "capture.bounded"},
		},
		DatabaseCompatibility: databaseCompatibility{MinSchemaVersion: 7, MaxSchemaVersion: 7, RollbackSafe: true},
		PublishedAt:           "2026-08-12T00:00:00Z", Urgency: "required",
		Deadline: "2026-08-19T00:00:00Z",
		Artifact: artifactV2{
			Platform: "windows-x64",
			URL:      "https://github.com/abangkis/AkuBrowser/releases/download/v0.8.1/AkuSidecar-0.8.1-windows-x64.zip",
			Size:     84, SHA256: strings.Repeat("b", 64),
		},
	}
	output := signFixture(t, unsigned)
	var signed signedManifestV2
	if err := json.Unmarshal(output, &signed); err != nil {
		t.Fatal(err)
	}
	if signed.SidecarVersion != unsigned.SidecarVersion || signed.Artifact.Platform != "windows-x64" {
		t.Fatalf("v2 identity drifted: %#v", signed)
	}
	verifySignature(t, unsigned, signed.Signature)
}

func TestRunRejectsUnknownFieldsForBothSchemas(t *testing.T) {
	for _, fixture := range []string{
		`{"schemaVersion":1,"product":"AkuBrowser","unexpected":true}`,
		`{"schemaVersion":2,"product":"AkuSidecar","unexpected":true}`,
	} {
		root, keyPath := signingFixture(t)
		manifestPath := filepath.Join(root, "unsigned.json")
		if err := os.WriteFile(manifestPath, []byte(fixture), 0o600); err != nil {
			t.Fatal(err)
		}
		if err := run(manifestPath, keyPath, filepath.Join(root, "signed.json")); err == nil || !strings.Contains(err.Error(), "unknown field") {
			t.Fatalf("expected unknown-field rejection, got %v", err)
		}
	}
}

func TestRunRejectsUnsafeV2CompatibilityRanges(t *testing.T) {
	unsigned := unsignedManifestV2{
		SchemaVersion: 2, Product: "AkuSidecar", Channel: "stable",
		SidecarVersion: "0.8.1", RuntimeRevision: "source-adapters-v93", MinHostVersion: "0.7.9",
		BridgeCompatibility:   bridgeCompatibility{Protocol: "aku-browser.bridge", MinVersion: 3, MaxVersion: 2, RequiredCapabilities: []string{}},
		DatabaseCompatibility: databaseCompatibility{MinSchemaVersion: 8, MaxSchemaVersion: 7, RollbackSafe: false},
		PublishedAt:           "2026-08-12T00:00:00Z",
		Artifact:              artifactV2{Platform: "windows-x64", URL: "https://example.invalid", Size: 1, SHA256: strings.Repeat("c", 64)},
	}
	root, keyPath := signingFixture(t)
	data, _ := json.Marshal(unsigned)
	manifestPath := filepath.Join(root, "unsigned.json")
	if err := os.WriteFile(manifestPath, data, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := run(manifestPath, keyPath, filepath.Join(root, "signed.json")); err == nil || !strings.Contains(err.Error(), "Bridge compatibility range") {
		t.Fatalf("expected compatibility-range rejection, got %v", err)
	}
}

func TestRunRejectsNonRollbackSafeV2Manifest(t *testing.T) {
	unsigned := validV2Manifest()
	unsigned.DatabaseCompatibility.RollbackSafe = false
	assertSigningError(t, unsigned, "database compatibility range")
}

func TestRunRejectsDeadlineForNonMandatoryUpdate(t *testing.T) {
	unsigned := validV2Manifest()
	unsigned.Urgency = "recommended"
	unsigned.Deadline = "2026-08-19T00:00:00Z"
	assertSigningError(t, unsigned, "deadline is invalid")
}

func TestRunRejectsDeadlineBeforePublication(t *testing.T) {
	unsigned := validV2Manifest()
	unsigned.Urgency = "security"
	unsigned.Deadline = "2026-08-11T23:59:59Z"
	assertSigningError(t, unsigned, "deadline is invalid")
}

func validV2Manifest() unsignedManifestV2 {
	return unsignedManifestV2{
		SchemaVersion: 2, Product: "AkuSidecar", Channel: "stable",
		SidecarVersion: "0.8.1", RuntimeRevision: "source-adapters-v93", MinHostVersion: "0.7.9",
		BridgeCompatibility: bridgeCompatibility{
			Protocol: "aku-browser.bridge", MinVersion: 2, MaxVersion: 2,
			RequiredCapabilities: []string{"authority.read_only_bounded", "capture.bounded"},
		},
		DatabaseCompatibility: databaseCompatibility{MinSchemaVersion: 7, MaxSchemaVersion: 7, RollbackSafe: true},
		PublishedAt:           "2026-08-12T00:00:00Z", Urgency: "routine",
		Artifact: artifactV2{
			Platform: "windows-x64",
			URL:      "https://github.com/abangkis/AkuBrowser/releases/download/v0.8.1/AkuSidecar-0.8.1-windows-x64.zip",
			Size:     84, SHA256: strings.Repeat("d", 64),
		},
	}
}

func assertSigningError(t *testing.T, unsigned any, expected string) {
	t.Helper()
	root, keyPath := signingFixture(t)
	data, err := json.Marshal(unsigned)
	if err != nil {
		t.Fatal(err)
	}
	manifestPath := filepath.Join(root, "unsigned.json")
	if err := os.WriteFile(manifestPath, data, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := run(manifestPath, keyPath, filepath.Join(root, "signed.json")); err == nil || !strings.Contains(err.Error(), expected) {
		t.Fatalf("expected %q rejection, got %v", expected, err)
	}
}

func signFixture(t *testing.T, unsigned any) []byte {
	t.Helper()
	root, keyPath := signingFixture(t)
	unsignedData, err := json.Marshal(unsigned)
	if err != nil {
		t.Fatal(err)
	}
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
	if strings.Contains(string(output), base64.StdEncoding.EncodeToString(testSeed())) {
		t.Fatal("signed manifest exposed the private seed")
	}
	return output
}

func verifySignature(t *testing.T, unsigned any, value signature) {
	t.Helper()
	payload, err := json.Marshal(unsigned)
	if err != nil {
		t.Fatal(err)
	}
	signatureBytes, err := base64.StdEncoding.DecodeString(value.Value)
	if err != nil {
		t.Fatal(err)
	}
	privateKey := ed25519.NewKeyFromSeed(testSeed())
	if !ed25519.Verify(privateKey.Public().(ed25519.PublicKey), payload, signatureBytes) {
		t.Fatal("signed manifest did not verify")
	}
}

func signingFixture(t *testing.T) (string, string) {
	t.Helper()
	root := t.TempDir()
	keyPath := filepath.Join(root, "update.key")
	if err := os.WriteFile(keyPath, []byte(base64.StdEncoding.EncodeToString(testSeed())), 0o600); err != nil {
		t.Fatal(err)
	}
	return root, keyPath
}

func testSeed() []byte {
	seed := make([]byte, ed25519.SeedSize)
	for index := range seed {
		seed[index] = byte(index + 1)
	}
	return seed
}
