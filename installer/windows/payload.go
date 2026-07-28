package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"path"
	"regexp"
	"sort"
	"strings"
)

const (
	payloadManifestName = "payload-manifest.json"
	maxManifestBytes    = 256 * 1024
	maxPayloadFileBytes = 512 * 1024 * 1024
)

var (
	payloadVersionPattern  = regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$`)
	extensionOriginPattern = regexp.MustCompile(`^chrome-extension://[a-p]{32}/$`)
	sha256Pattern          = regexp.MustCompile(`^[a-f0-9]{64}$`)
)

type PayloadManifest struct {
	SchemaVersion   int           `json:"schemaVersion"`
	Product         string        `json:"product"`
	Version         string        `json:"version"`
	Architecture    string        `json:"architecture"`
	ExtensionOrigin string        `json:"extensionOrigin"`
	Files           []PayloadFile `json:"files"`
}

type PayloadFile struct {
	Path   string `json:"path"`
	Size   int64  `json:"size"`
	SHA256 string `json:"sha256"`
}

func loadPayloadManifest(payload fs.FS) (PayloadManifest, error) {
	file, err := payload.Open(payloadManifestName)
	if err != nil {
		return PayloadManifest{}, fmt.Errorf("open payload manifest: %w", err)
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, maxManifestBytes+1))
	if err != nil {
		return PayloadManifest{}, fmt.Errorf("read payload manifest: %w", err)
	}
	if len(data) > maxManifestBytes {
		return PayloadManifest{}, errors.New("payload manifest exceeds bounded size")
	}
	var manifest PayloadManifest
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&manifest); err != nil {
		return PayloadManifest{}, fmt.Errorf("decode payload manifest: %w", err)
	}
	if manifest.SchemaVersion != 1 || manifest.Product != "AkuBrowser" {
		return PayloadManifest{}, errors.New("payload identity is invalid")
	}
	if !payloadVersionPattern.MatchString(manifest.Version) {
		return PayloadManifest{}, errors.New("payload version is invalid")
	}
	if manifest.Architecture != "windows-x64" {
		return PayloadManifest{}, errors.New("payload architecture is invalid")
	}
	if !extensionOriginPattern.MatchString(manifest.ExtensionOrigin) {
		return PayloadManifest{}, errors.New("payload extension origin is invalid")
	}
	if len(manifest.Files) == 0 || len(manifest.Files) > 256 {
		return PayloadManifest{}, errors.New("payload file count is invalid")
	}
	seen := make(map[string]struct{}, len(manifest.Files))
	hasHost := false
	hasCurrent := false
	for _, item := range manifest.Files {
		if err := validatePayloadPath(item.Path, manifest.Version); err != nil {
			return PayloadManifest{}, err
		}
		if _, duplicate := seen[item.Path]; duplicate {
			return PayloadManifest{}, fmt.Errorf("payload file %q is duplicated", item.Path)
		}
		seen[item.Path] = struct{}{}
		if item.Size < 0 || item.Size > maxPayloadFileBytes || !sha256Pattern.MatchString(item.SHA256) {
			return PayloadManifest{}, fmt.Errorf("payload file metadata is invalid for %q", item.Path)
		}
		if item.Path == "host/AkuBrowserRuntimeHost.exe" {
			hasHost = true
		}
		if item.Path == "runtime/current.json" {
			hasCurrent = true
		}
	}
	if !hasHost || !hasCurrent {
		return PayloadManifest{}, errors.New("payload is missing the host or active runtime metadata")
	}
	return manifest, nil
}

func validatePayloadPath(value, version string) error {
	if value == "" || strings.Contains(value, `\`) || path.IsAbs(value) {
		return fmt.Errorf("payload path %q is invalid", value)
	}
	clean := path.Clean(value)
	if clean != value || clean == "." || strings.HasPrefix(clean, "../") {
		return fmt.Errorf("payload path %q escapes its root", value)
	}
	allowedRuntimePrefix := "runtime/versions/" + version + "/"
	if value == "runtime/current.json" ||
		strings.HasPrefix(value, "host/") ||
		strings.HasPrefix(value, allowedRuntimePrefix) {
		return nil
	}
	return fmt.Errorf("payload path %q is outside installer authority", value)
}

func verifyPayload(payload fs.FS, manifest PayloadManifest) error {
	for _, item := range manifest.Files {
		file, err := payload.Open(item.Path)
		if err != nil {
			return fmt.Errorf("open payload file %q: %w", item.Path, err)
		}
		hash := sha256.New()
		count, copyErr := io.Copy(hash, io.LimitReader(file, maxPayloadFileBytes+1))
		closeErr := file.Close()
		if copyErr != nil {
			return fmt.Errorf("read payload file %q: %w", item.Path, copyErr)
		}
		if closeErr != nil {
			return fmt.Errorf("close payload file %q: %w", item.Path, closeErr)
		}
		if count != item.Size || hex.EncodeToString(hash.Sum(nil)) != item.SHA256 {
			return fmt.Errorf("payload checksum mismatch for %q", item.Path)
		}
	}
	return nil
}

func installationOrder(files []PayloadFile) []PayloadFile {
	ordered := append([]PayloadFile(nil), files...)
	sort.Slice(ordered, func(i, j int) bool {
		if ordered[i].Path == "runtime/current.json" {
			return false
		}
		if ordered[j].Path == "runtime/current.json" {
			return true
		}
		return ordered[i].Path < ordered[j].Path
	})
	return ordered
}
