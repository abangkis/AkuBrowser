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
	"os"
	"strings"
)

type artifact struct {
	URL    string `json:"url"`
	Size   int64  `json:"size"`
	SHA256 string `json:"sha256"`
}

type unsignedManifest struct {
	SchemaVersion         int      `json:"schemaVersion"`
	Product               string   `json:"product"`
	Channel               string   `json:"channel"`
	Version               string   `json:"version"`
	RuntimeRevision       string   `json:"runtimeRevision"`
	BridgeContractVersion string   `json:"bridgeContractVersion"`
	PublishedAt           string   `json:"publishedAt"`
	Artifact              artifact `json:"artifact"`
}

type signature struct {
	Algorithm string `json:"algorithm"`
	KeyID     string `json:"keyId"`
	Value     string `json:"value"`
}

type signedManifest struct {
	SchemaVersion         int       `json:"schemaVersion"`
	Product               string    `json:"product"`
	Channel               string    `json:"channel"`
	Version               string    `json:"version"`
	RuntimeRevision       string    `json:"runtimeRevision"`
	BridgeContractVersion string    `json:"bridgeContractVersion"`
	PublishedAt           string    `json:"publishedAt"`
	Artifact              artifact  `json:"artifact"`
	Signature             signature `json:"signature"`
}

func main() {
	var manifestPath, privateKeyPath, outputPath string
	flag.StringVar(&manifestPath, "manifest", "", "path to the unsigned canonical update manifest")
	flag.StringVar(&privateKeyPath, "private-key", "", "path containing one base64 Ed25519 seed or private key")
	flag.StringVar(&outputPath, "output", "", "path for the signed manifest")
	flag.Parse()
	if err := run(manifestPath, privateKeyPath, outputPath); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(manifestPath, privateKeyPath, outputPath string) error {
	if manifestPath == "" || privateKeyPath == "" || outputPath == "" {
		return errors.New("manifest, private-key, and output are required")
	}
	data, err := os.ReadFile(manifestPath)
	if err != nil {
		return err
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var unsigned unsignedManifest
	if err := decoder.Decode(&unsigned); err != nil {
		return fmt.Errorf("decode unsigned manifest: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return errors.New("unsigned manifest contains trailing JSON")
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
	payload, err := json.Marshal(unsigned)
	if err != nil {
		return err
	}
	signed := signedManifest{
		SchemaVersion: unsigned.SchemaVersion, Product: unsigned.Product,
		Channel: unsigned.Channel, Version: unsigned.Version,
		RuntimeRevision:       unsigned.RuntimeRevision,
		BridgeContractVersion: unsigned.BridgeContractVersion,
		PublishedAt:           unsigned.PublishedAt, Artifact: unsigned.Artifact,
		Signature: signature{
			Algorithm: "ed25519", KeyID: "aku-runtime-stable-v1",
			Value: base64.StdEncoding.EncodeToString(ed25519.Sign(privateKey, payload)),
		},
	}
	output, err := json.MarshalIndent(signed, "", "  ")
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
