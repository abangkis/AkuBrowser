package main

import (
	"bytes"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/url"
	"os"
	"path"
	"regexp"
	"strings"
	"time"
)

type artifactV1 struct {
	URL    string `json:"url"`
	Size   int64  `json:"size"`
	SHA256 string `json:"sha256"`
}

type artifactV2 struct {
	Platform string `json:"platform"`
	URL      string `json:"url"`
	Size     int64  `json:"size"`
	SHA256   string `json:"sha256"`
}

type bridgeCompatibility struct {
	Protocol             string   `json:"protocol"`
	MinVersion           int      `json:"minVersion"`
	MaxVersion           int      `json:"maxVersion"`
	RequiredCapabilities []string `json:"requiredCapabilities"`
}

type databaseCompatibility struct {
	MinSchemaVersion int  `json:"minSchemaVersion"`
	MaxSchemaVersion int  `json:"maxSchemaVersion"`
	RollbackSafe     bool `json:"rollbackSafe"`
}

var versionPattern = regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$`)
var runtimeRevisionPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9._-]{2,79}$`)
var capabilityPattern = regexp.MustCompile(`^[a-z][a-z0-9._-]{1,63}$`)
var sha256Pattern = regexp.MustCompile(`^[a-f0-9]{64}$`)

type unsignedManifestV1 struct {
	SchemaVersion         int        `json:"schemaVersion"`
	Product               string     `json:"product"`
	Channel               string     `json:"channel"`
	Version               string     `json:"version"`
	RuntimeRevision       string     `json:"runtimeRevision"`
	BridgeContractVersion string     `json:"bridgeContractVersion"`
	PublishedAt           string     `json:"publishedAt"`
	Artifact              artifactV1 `json:"artifact"`
}

type unsignedManifestV2 struct {
	SchemaVersion         int                   `json:"schemaVersion"`
	Product               string                `json:"product"`
	Channel               string                `json:"channel"`
	SidecarVersion        string                `json:"sidecarVersion"`
	RuntimeRevision       string                `json:"runtimeRevision"`
	MinHostVersion        string                `json:"minHostVersion"`
	BridgeCompatibility   bridgeCompatibility   `json:"bridgeCompatibility"`
	DatabaseCompatibility databaseCompatibility `json:"databaseCompatibility"`
	PublishedAt           string                `json:"publishedAt"`
	Urgency               string                `json:"urgency,omitempty"`
	Deadline              string                `json:"deadline,omitempty"`
	Artifact              artifactV2            `json:"artifact"`
}

type signature struct {
	Algorithm string `json:"algorithm"`
	KeyID     string `json:"keyId"`
	Value     string `json:"value"`
}

type signedManifestV1 struct {
	SchemaVersion         int        `json:"schemaVersion"`
	Product               string     `json:"product"`
	Channel               string     `json:"channel"`
	Version               string     `json:"version"`
	RuntimeRevision       string     `json:"runtimeRevision"`
	BridgeContractVersion string     `json:"bridgeContractVersion"`
	PublishedAt           string     `json:"publishedAt"`
	Artifact              artifactV1 `json:"artifact"`
	Signature             signature  `json:"signature"`
}

type signedManifestV2 struct {
	SchemaVersion         int                   `json:"schemaVersion"`
	Product               string                `json:"product"`
	Channel               string                `json:"channel"`
	SidecarVersion        string                `json:"sidecarVersion"`
	RuntimeRevision       string                `json:"runtimeRevision"`
	MinHostVersion        string                `json:"minHostVersion"`
	BridgeCompatibility   bridgeCompatibility   `json:"bridgeCompatibility"`
	DatabaseCompatibility databaseCompatibility `json:"databaseCompatibility"`
	PublishedAt           string                `json:"publishedAt"`
	Urgency               string                `json:"urgency,omitempty"`
	Deadline              string                `json:"deadline,omitempty"`
	Artifact              artifactV2            `json:"artifact"`
	Signature             signature             `json:"signature"`
}

func main() {
	var manifestPath, privateKeyPath, outputPath, signedManifestPath, publicKeyText string
	flag.StringVar(&manifestPath, "manifest", "", "path to the unsigned canonical update manifest")
	flag.StringVar(&privateKeyPath, "private-key", "", "path containing one base64 Ed25519 seed or private key")
	flag.StringVar(&outputPath, "output", "", "path for the signed manifest")
	flag.StringVar(&signedManifestPath, "verify-signed", "", "path to a signed update manifest to verify")
	flag.StringVar(&publicKeyText, "public-key", "", "base64 Ed25519 public key used with -verify-signed")
	flag.Parse()
	if signedManifestPath != "" {
		if err := verifySigned(signedManifestPath, publicKeyText); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
	if err := run(manifestPath, privateKeyPath, outputPath); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func verifySigned(manifestPath, publicKeyText string) error {
	if manifestPath == "" || strings.TrimSpace(publicKeyText) == "" {
		return errors.New("verify-signed and public-key are required")
	}
	data, err := os.ReadFile(manifestPath)
	if err != nil {
		return err
	}
	publicKey, err := base64.StdEncoding.DecodeString(strings.TrimSpace(publicKeyText))
	if err != nil || len(publicKey) != ed25519.PublicKeySize {
		return errors.New("update verification key must be a base64 32-byte Ed25519 public key")
	}
	var header struct {
		SchemaVersion int `json:"schemaVersion"`
	}
	if err := json.Unmarshal(data, &header); err != nil {
		return fmt.Errorf("decode signed manifest: %w", err)
	}
	if header.SchemaVersion != 1 {
		return fmt.Errorf("signed manifest verification supports frozen schema version 1, got %d", header.SchemaVersion)
	}
	var signed signedManifestV1
	if err := decodeStrict(data, &signed); err != nil {
		return err
	}
	if signed.SchemaVersion != 1 || signed.Product != "AkuBrowser" ||
		signed.Signature.Algorithm != "ed25519" || signed.Signature.KeyID != "aku-runtime-stable-v1" {
		return errors.New("legacy signed update manifest identity is invalid")
	}
	unsigned := unsignedManifestV1{
		SchemaVersion: signed.SchemaVersion, Product: signed.Product, Channel: signed.Channel,
		Version: signed.Version, RuntimeRevision: signed.RuntimeRevision,
		BridgeContractVersion: signed.BridgeContractVersion, PublishedAt: signed.PublishedAt,
		Artifact: signed.Artifact,
	}
	payload, err := json.Marshal(unsigned)
	if err != nil {
		return err
	}
	signatureBytes, err := base64.StdEncoding.DecodeString(signed.Signature.Value)
	if err != nil || len(signatureBytes) != ed25519.SignatureSize ||
		!ed25519.Verify(ed25519.PublicKey(publicKey), payload, signatureBytes) {
		return errors.New("legacy update manifest signature is invalid")
	}
	return nil
}

func run(manifestPath, privateKeyPath, outputPath string) error {
	if manifestPath == "" || privateKeyPath == "" || outputPath == "" {
		return errors.New("manifest, private-key, and output are required")
	}
	data, err := os.ReadFile(manifestPath)
	if err != nil {
		return err
	}
	var header struct {
		SchemaVersion int `json:"schemaVersion"`
	}
	if err := json.Unmarshal(data, &header); err != nil {
		return fmt.Errorf("decode unsigned manifest: %w", err)
	}
	keyText, err := os.ReadFile(privateKeyPath)
	if err != nil {
		return err
	}
	keyBytes, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(keyText)))
	if err != nil {
		return errors.New("update signing key is not valid base64")
	}
	var privateKey ed25519.PrivateKey
	switch len(keyBytes) {
	case ed25519.SeedSize:
		privateKey = ed25519.NewKeyFromSeed(keyBytes)
	case ed25519.PrivateKeySize:
		privateKey = ed25519.PrivateKey(keyBytes)
	default:
		return errors.New("update signing key must contain a 32-byte seed or 64-byte private key")
	}
	output, err := signManifest(data, header.SchemaVersion, privateKey)
	if err != nil {
		return err
	}
	output = append(output, '\n')
	if err := os.WriteFile(outputPath, output, 0o600); err != nil {
		return err
	}
	publicKey := privateKey.Public().(ed25519.PublicKey)
	fmt.Println(base64.StdEncoding.EncodeToString(publicKey))
	return nil
}

func signManifest(data []byte, schemaVersion int, privateKey ed25519.PrivateKey) ([]byte, error) {
	sign := func(payload []byte) signature {
		return signature{
			Algorithm: "ed25519",
			KeyID:     "aku-runtime-stable-v1",
			Value:     base64.StdEncoding.EncodeToString(ed25519.Sign(privateKey, payload)),
		}
	}

	var signed any
	switch schemaVersion {
	case 1:
		var unsigned unsignedManifestV1
		if err := decodeStrict(data, &unsigned); err != nil {
			return nil, err
		}
		if unsigned.SchemaVersion != 1 || unsigned.Product != "AkuBrowser" {
			return nil, errors.New("legacy update manifest identity is invalid")
		}
		payload, err := json.Marshal(unsigned)
		if err != nil {
			return nil, err
		}
		signed = signedManifestV1{
			SchemaVersion: unsigned.SchemaVersion, Product: unsigned.Product,
			Channel: unsigned.Channel, Version: unsigned.Version,
			RuntimeRevision:       unsigned.RuntimeRevision,
			BridgeContractVersion: unsigned.BridgeContractVersion,
			PublishedAt:           unsigned.PublishedAt, Artifact: unsigned.Artifact,
			Signature: sign(payload),
		}
	case 2:
		var unsigned unsignedManifestV2
		if err := decodeStrict(data, &unsigned); err != nil {
			return nil, err
		}
		if err := validateV2(unsigned); err != nil {
			return nil, err
		}
		payload, err := json.Marshal(unsigned)
		if err != nil {
			return nil, err
		}
		signed = signedManifestV2{
			SchemaVersion: unsigned.SchemaVersion, Product: unsigned.Product,
			Channel: unsigned.Channel, SidecarVersion: unsigned.SidecarVersion,
			RuntimeRevision: unsigned.RuntimeRevision, MinHostVersion: unsigned.MinHostVersion,
			BridgeCompatibility:   unsigned.BridgeCompatibility,
			DatabaseCompatibility: unsigned.DatabaseCompatibility,
			PublishedAt:           unsigned.PublishedAt, Urgency: unsigned.Urgency,
			Deadline: unsigned.Deadline, Artifact: unsigned.Artifact,
			Signature: sign(payload),
		}
	default:
		return nil, fmt.Errorf("unsupported update manifest schema version %d", schemaVersion)
	}

	return json.MarshalIndent(signed, "", "  ")
}

func validateV2(manifest unsignedManifestV2) error {
	if manifest.SchemaVersion != 2 || manifest.Product != "AkuSidecar" {
		return errors.New("AkuSidecar update manifest identity is invalid")
	}
	if manifest.Channel != "stable" || !versionPattern.MatchString(manifest.SidecarVersion) ||
		!versionPattern.MatchString(manifest.MinHostVersion) ||
		!runtimeRevisionPattern.MatchString(manifest.RuntimeRevision) {
		return errors.New("AkuSidecar update version identity is invalid")
	}
	if manifest.BridgeCompatibility.Protocol != "aku-browser.bridge" ||
		manifest.BridgeCompatibility.MinVersion < 1 ||
		manifest.BridgeCompatibility.MaxVersion < manifest.BridgeCompatibility.MinVersion ||
		len(manifest.BridgeCompatibility.RequiredCapabilities) == 0 {
		return errors.New("AkuSidecar Bridge compatibility range is invalid")
	}
	seenCapabilities := make(map[string]bool, len(manifest.BridgeCompatibility.RequiredCapabilities))
	for _, capability := range manifest.BridgeCompatibility.RequiredCapabilities {
		if !capabilityPattern.MatchString(capability) || seenCapabilities[capability] {
			return errors.New("AkuSidecar Bridge capability set is invalid")
		}
		seenCapabilities[capability] = true
	}
	if manifest.DatabaseCompatibility.MinSchemaVersion < 1 ||
		manifest.DatabaseCompatibility.MaxSchemaVersion < manifest.DatabaseCompatibility.MinSchemaVersion ||
		!manifest.DatabaseCompatibility.RollbackSafe {
		return errors.New("AkuSidecar database compatibility range is invalid")
	}
	switch manifest.Artifact.Platform {
	case "windows-x64", "macos-universal", "linux-x64", "linux-arm64":
	default:
		return errors.New("AkuSidecar update artifact platform is invalid")
	}
	if manifest.Artifact.Size <= 0 || manifest.Artifact.Size > 512*1024*1024 ||
		!sha256Pattern.MatchString(manifest.Artifact.SHA256) {
		return errors.New("AkuSidecar update artifact metadata is invalid")
	}
	expectedName := "AkuSidecar-" + manifest.SidecarVersion + "-" + manifest.Artifact.Platform + ".zip"
	parsedURL, err := url.Parse(manifest.Artifact.URL)
	if err != nil || parsedURL.Scheme != "https" || parsedURL.Host != "github.com" ||
		parsedURL.RawQuery != "" || parsedURL.Fragment != "" ||
		path.Clean(parsedURL.Path) != "/abangkis/AkuBrowser/releases/download/v"+manifest.SidecarVersion+"/"+expectedName {
		return errors.New("AkuSidecar update artifact URL is invalid")
	}
	published, err := time.Parse(time.RFC3339, manifest.PublishedAt)
	if err != nil {
		return errors.New("AkuSidecar update publication time is invalid")
	}
	if manifest.Urgency != "" {
		switch manifest.Urgency {
		case "routine", "recommended", "required", "security":
		default:
			return errors.New("AkuSidecar update urgency is invalid")
		}
	}
	if manifest.Deadline != "" {
		deadline, deadlineErr := time.Parse(time.RFC3339, manifest.Deadline)
		if deadlineErr != nil || deadline.Before(published) ||
			(manifest.Urgency != "required" && manifest.Urgency != "security") {
			return errors.New("AkuSidecar update deadline is invalid")
		}
	}
	return nil
}

func decodeStrict(data []byte, destination any) error {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return fmt.Errorf("decode unsigned manifest: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return errors.New("unsigned manifest contains trailing JSON")
	}
	return nil
}
