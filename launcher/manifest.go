package launcher

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

const (
	ActivePointerSchemaVersion  = 1
	BundleManifestSchemaVersion = 1
	currentPointerPath          = "runtime/current.json"
	manifestFileName            = "manifest.json"
	mutexName                   = `Local\AkuBrowser.InstalledApp.v1`
)

var (
	versionPattern     = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`)
	extensionIDPattern = regexp.MustCompile(`^[a-p]{32}$`)
	hashPattern        = regexp.MustCompile(`^[a-f0-9]{64}$`)
)

// ActivePointer is the only mutable selection in an installed tree. It is
// written by the installer only after a complete version tuple has been
// staged and verified.
type ActivePointer struct {
	SchemaVersion int    `json:"schemaVersion"`
	Version       string `json:"version"`
	ManifestPath  string `json:"manifestPath"`
}

type BridgeIdentity struct {
	Profile            string `json:"profile"`
	Environment        string `json:"environment"`
	Distribution       string `json:"distribution"`
	RuntimeLifecycle   string `json:"runtimeLifecycle"`
	RuntimeAcquisition string `json:"runtimeAcquisition"`
	ExtensionID        string `json:"extensionId"`
	Origin             string `json:"origin"`
}

type HealthContract struct {
	Host      string `json:"host"`
	Port      int    `json:"port"`
	Path      string `json:"path"`
	TimeoutMS int    `json:"timeoutMs"`
}

type StoragePolicy struct {
	UserDataRoot               string `json:"userDataRoot"`
	UserDataRelativePath       string `json:"userDataRelativePath"`
	BrowserProfileRoot         string `json:"browserProfileRoot"`
	BrowserProfileRelativePath string `json:"browserProfileRelativePath"`
}

type PayloadFile struct {
	Path   string `json:"path"`
	Size   int64  `json:"size"`
	SHA256 string `json:"sha256"`
}

// BundleManifest describes one complete, versioned installed-app tuple. All
// component paths are relative to the version directory containing this file.
type BundleManifest struct {
	SchemaVersion       int            `json:"schemaVersion"`
	Product             string         `json:"product"`
	Platform            string         `json:"platform"`
	Version             string         `json:"version"`
	ChromiumVersion     string         `json:"chromiumVersion"`
	BridgeVersion       string         `json:"bridgeVersion"`
	BridgeContract      string         `json:"bridgeContract"`
	SidecarPath         string         `json:"sidecarPath"`
	ConfigPath          string         `json:"configPath"`
	ChromiumPath        string         `json:"chromiumPath"`
	BridgeExtensionPath string         `json:"bridgeExtensionPath"`
	BridgeIdentity      BridgeIdentity `json:"bridgeIdentity"`
	Storage             StoragePolicy  `json:"storage"`
	Health              HealthContract `json:"health"`
	Payload             []PayloadFile  `json:"payload"`
}

// Tuple is the verified active version and its resolved filesystem boundary.
type Tuple struct {
	InstallRoot  string
	VersionRoot  string
	ManifestPath string
	Pointer      ActivePointer
	Manifest     BundleManifest
}

type LaunchPaths struct {
	SidecarPath         string
	ConfigPath          string
	ChromiumPath        string
	BridgeExtensionPath string
	DataDirectory       string
	BrowserProfile      string
	DatabasePath        string
}

func decodeStrict(data []byte, target any) error {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		if err == nil {
			return errors.New("JSON contains more than one value")
		}
		return fmt.Errorf("trailing JSON: %w", err)
	}
	return nil
}

func readStrictJSON(path string, target any) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return decodeStrict(data, target)
}

func validateVersion(version string) error {
	if !versionPattern.MatchString(version) {
		return fmt.Errorf("invalid release version %q", version)
	}
	return nil
}

func validateRelativePath(path string) error {
	if path == "" || strings.Contains(path, `\`) || strings.ContainsRune(path, 0) {
		return fmt.Errorf("path %q is not a portable relative path", path)
	}
	if filepath.IsAbs(filepath.FromSlash(path)) || filepath.VolumeName(filepath.FromSlash(path)) != "" {
		return fmt.Errorf("path %q must be relative", path)
	}
	clean := filepath.ToSlash(filepath.Clean(filepath.FromSlash(path)))
	if clean == "." || clean != path || clean == ".." || strings.HasPrefix(clean, "../") {
		return fmt.Errorf("path %q contains traversal or is not normalized", path)
	}
	return nil
}

func validatePointer(pointer ActivePointer) error {
	if pointer.SchemaVersion != ActivePointerSchemaVersion {
		return fmt.Errorf("unsupported active pointer schema %d", pointer.SchemaVersion)
	}
	if err := validateVersion(pointer.Version); err != nil {
		return err
	}
	expected := filepath.ToSlash(filepath.Join("runtime", "versions", pointer.Version, manifestFileName))
	if pointer.ManifestPath != expected {
		return fmt.Errorf("active manifest path %q must be %q", pointer.ManifestPath, expected)
	}
	return nil
}

func (m BundleManifest) validate() error {
	if m.SchemaVersion != BundleManifestSchemaVersion {
		return fmt.Errorf("unsupported bundle manifest schema %d", m.SchemaVersion)
	}
	if err := validateVersion(m.Version); err != nil {
		return err
	}
	if m.Product != "AkuBrowser" || m.Platform != "windows-x64" {
		return errors.New("bundle must identify AkuBrowser for windows-x64")
	}
	if strings.TrimSpace(m.ChromiumVersion) == "" || strings.TrimSpace(m.BridgeVersion) == "" || m.BridgeContract != "aku-browser.bridge.v2" {
		return errors.New("bundle must pin Chromium and the supported Bridge contract")
	}
	for label, path := range map[string]string{
		"sidecar":  m.SidecarPath,
		"config":   m.ConfigPath,
		"chromium": m.ChromiumPath,
		"bridge":   m.BridgeExtensionPath,
	} {
		if err := validateRelativePath(path); err != nil {
			return fmt.Errorf("%s path: %w", label, err)
		}
	}
	if m.BridgeIdentity.Profile != "production-app" ||
		m.BridgeIdentity.Environment != "production" ||
		m.BridgeIdentity.Distribution != "installed-app" ||
		m.BridgeIdentity.RuntimeLifecycle != "managed" ||
		m.BridgeIdentity.RuntimeAcquisition != "bundled-installer" {
		return errors.New("bundle must bind the production-app managed installed-app identity")
	}
	if !extensionIDPattern.MatchString(m.BridgeIdentity.ExtensionID) {
		return fmt.Errorf("invalid Bridge extension ID %q", m.BridgeIdentity.ExtensionID)
	}
	expectedOrigin := "chrome-extension://" + m.BridgeIdentity.ExtensionID + "/"
	if m.BridgeIdentity.Origin != expectedOrigin {
		return fmt.Errorf("Bridge origin %q does not match extension ID", m.BridgeIdentity.Origin)
	}
	parsedOrigin, err := url.Parse(m.BridgeIdentity.Origin)
	if err != nil || parsedOrigin.Scheme != "chrome-extension" || parsedOrigin.Path != "/" || parsedOrigin.RawQuery != "" || parsedOrigin.Fragment != "" {
		return fmt.Errorf("Bridge origin %q is not an exact extension origin", m.BridgeIdentity.Origin)
	}
	if m.Storage.UserDataRoot != "local-app-data" || m.Storage.BrowserProfileRoot != "local-app-data" {
		return errors.New("user data and browser profile must use local-app-data roots")
	}
	if m.Storage.UserDataRelativePath != `AkuBrowser/data` || m.Storage.BrowserProfileRelativePath != `AkuBrowser/browser-profile` {
		return errors.New("user data/profile paths must use the stable AkuBrowser local-app-data policy")
	}
	if err := validateRelativePath(m.Storage.UserDataRelativePath); err != nil {
		return fmt.Errorf("user data path: %w", err)
	}
	if err := validateRelativePath(m.Storage.BrowserProfileRelativePath); err != nil {
		return fmt.Errorf("browser profile path: %w", err)
	}
	if m.Health.Host != "127.0.0.1" || m.Health.Port < 1 || m.Health.Port > 65535 || m.Health.Path != "/api/health" || m.Health.TimeoutMS < 1000 || m.Health.TimeoutMS > 120000 {
		return errors.New("health contract must use bounded loopback /api/health settings")
	}
	if len(m.Payload) == 0 {
		return errors.New("bundle payload is empty")
	}
	seen := make(map[string]struct{}, len(m.Payload))
	for _, file := range m.Payload {
		if err := validateRelativePath(file.Path); err != nil {
			return fmt.Errorf("payload path: %w", err)
		}
		key := strings.ToLower(file.Path)
		if _, ok := seen[key]; ok {
			return fmt.Errorf("duplicate payload path %q", file.Path)
		}
		seen[key] = struct{}{}
		if file.Size < 0 || !hashPattern.MatchString(file.SHA256) {
			return fmt.Errorf("payload file %q has invalid size or SHA-256", file.Path)
		}
	}
	for label, required := range map[string]string{
		"sidecar":  m.SidecarPath,
		"config":   m.ConfigPath,
		"chromium": m.ChromiumPath,
	} {
		if _, ok := seen[strings.ToLower(required)]; !ok {
			return fmt.Errorf("required %s path %q is not declared in payload", label, required)
		}
	}
	return nil
}

func evalContained(root, relative string, wantDir bool) (string, error) {
	if err := validateRelativePath(relative); err != nil {
		return "", err
	}
	rootAbs, err := filepath.Abs(root)
	if err != nil {
		return "", err
	}
	rootReal, err := filepath.EvalSymlinks(rootAbs)
	if err != nil {
		return "", fmt.Errorf("resolve root: %w", err)
	}
	candidate := filepath.Join(rootAbs, filepath.FromSlash(relative))
	real, err := filepath.EvalSymlinks(candidate)
	if err != nil {
		return "", err
	}
	rel, err := filepath.Rel(rootReal, real)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) || filepath.IsAbs(rel) {
		return "", fmt.Errorf("path %q escapes its verified root", relative)
	}
	info, err := os.Stat(real)
	if err != nil {
		return "", err
	}
	if wantDir && !info.IsDir() {
		return "", fmt.Errorf("path %q is not a directory", relative)
	}
	if !wantDir && !info.Mode().IsRegular() {
		return "", fmt.Errorf("path %q is not a regular file", relative)
	}
	return real, nil
}

// LoadActiveTuple strictly decodes and verifies runtime/current.json and the
// selected version manifest. It does not start a process.
func LoadActiveTuple(installRoot string) (Tuple, error) {
	rootAbs, err := filepath.Abs(installRoot)
	if err != nil {
		return Tuple{}, fmt.Errorf("resolve install root: %w", err)
	}
	rootReal, err := filepath.EvalSymlinks(rootAbs)
	if err != nil {
		return Tuple{}, fmt.Errorf("resolve install root: %w", err)
	}
	pointerPath, err := evalContained(rootReal, currentPointerPath, false)
	if err != nil {
		return Tuple{}, fmt.Errorf("read active pointer: %w", err)
	}
	var pointer ActivePointer
	if err := readStrictJSON(pointerPath, &pointer); err != nil {
		return Tuple{}, fmt.Errorf("decode active pointer: %w", err)
	}
	if err := validatePointer(pointer); err != nil {
		return Tuple{}, err
	}
	manifestPath, err := evalContained(rootReal, pointer.ManifestPath, false)
	if err != nil {
		return Tuple{}, fmt.Errorf("resolve active manifest: %w", err)
	}
	var manifest BundleManifest
	if err := readStrictJSON(manifestPath, &manifest); err != nil {
		return Tuple{}, fmt.Errorf("decode bundle manifest: %w", err)
	}
	if err := manifest.validate(); err != nil {
		return Tuple{}, err
	}
	if manifest.Version != pointer.Version {
		return Tuple{}, fmt.Errorf("active version mismatch: pointer=%q manifest=%q", pointer.Version, manifest.Version)
	}
	versionRoot := filepath.Dir(manifestPath)
	for label, relative := range map[string]string{
		"sidecar":  manifest.SidecarPath,
		"config":   manifest.ConfigPath,
		"chromium": manifest.ChromiumPath,
	} {
		if _, err := evalContained(versionRoot, relative, false); err != nil {
			return Tuple{}, fmt.Errorf("resolve %s: %w", label, err)
		}
	}
	if _, err := evalContained(versionRoot, manifest.BridgeExtensionPath, true); err != nil {
		return Tuple{}, fmt.Errorf("resolve bridge extension: %w", err)
	}
	if err := verifyBridgeIdentity(versionRoot, manifest); err != nil {
		return Tuple{}, err
	}
	for _, file := range manifest.Payload {
		path, err := evalContained(versionRoot, file.Path, false)
		if err != nil {
			return Tuple{}, fmt.Errorf("resolve payload %q: %w", file.Path, err)
		}
		if err := verifyFile(path, file); err != nil {
			return Tuple{}, err
		}
	}
	if err := verifyNoUndeclaredFiles(versionRoot, manifest.Payload); err != nil {
		return Tuple{}, err
	}
	return Tuple{InstallRoot: rootReal, VersionRoot: versionRoot, ManifestPath: manifestPath, Pointer: pointer, Manifest: manifest}, nil
}

func verifyBridgeIdentity(versionRoot string, manifest BundleManifest) error {
	relative := filepath.ToSlash(filepath.Join(manifest.BridgeExtensionPath, "manifest.json"))
	declared := false
	for _, file := range manifest.Payload {
		if strings.EqualFold(file.Path, relative) {
			declared = true
			break
		}
	}
	if !declared {
		return errors.New("Bridge manifest is not declared in the verified payload")
	}
	path, err := evalContained(versionRoot, relative, false)
	if err != nil {
		return fmt.Errorf("resolve Bridge manifest: %w", err)
	}
	var bridge struct {
		ManifestVersion int    `json:"manifest_version"`
		Key             string `json:"key"`
		VersionName     string `json:"version_name"`
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read Bridge manifest: %w", err)
	}
	if err := json.Unmarshal(data, &bridge); err != nil {
		return fmt.Errorf("decode Bridge manifest: %w", err)
	}
	if bridge.ManifestVersion != 3 || bridge.VersionName != manifest.BridgeVersion {
		return errors.New("Bridge manifest version does not match the installed tuple")
	}
	key, err := base64.StdEncoding.DecodeString(bridge.Key)
	if err != nil || base64.StdEncoding.EncodeToString(key) != bridge.Key {
		return errors.New("Bridge manifest key is not canonical base64")
	}
	digest := sha256.Sum256(key)
	var id strings.Builder
	id.Grow(32)
	for _, value := range digest[:16] {
		id.WriteByte('a' + value>>4)
		id.WriteByte('a' + value&0x0f)
	}
	if id.String() != manifest.BridgeIdentity.ExtensionID {
		return fmt.Errorf("Bridge manifest key derives %q, expected %q", id.String(), manifest.BridgeIdentity.ExtensionID)
	}
	return nil
}

func verifyNoUndeclaredFiles(versionRoot string, payload []PayloadFile) error {
	declared := make(map[string]struct{}, len(payload))
	for _, file := range payload {
		declared[strings.ToLower(file.Path)] = struct{}{}
	}
	return filepath.WalkDir(versionRoot, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if path == versionRoot {
			return nil
		}
		relative, err := filepath.Rel(versionRoot, path)
		if err != nil {
			return err
		}
		relative = filepath.ToSlash(relative)
		if entry.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("bundle path %q is a symbolic link or reparse point", relative)
		}
		if entry.IsDir() {
			return nil
		}
		if relative == manifestFileName {
			return nil
		}
		if !entry.Type().IsRegular() {
			return fmt.Errorf("bundle path %q is not a regular file", relative)
		}
		if _, ok := declared[strings.ToLower(relative)]; !ok {
			return fmt.Errorf("undeclared payload file %q", relative)
		}
		return nil
	})
}

func verifyFile(path string, expected PayloadFile) error {
	info, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("verify payload %q: %w", expected.Path, err)
	}
	if info.Size() != expected.Size {
		return fmt.Errorf("payload size mismatch for %q: got=%d expected=%d", expected.Path, info.Size(), expected.Size)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read payload %q: %w", expected.Path, err)
	}
	digest := sha256.Sum256(data)
	actual := hex.EncodeToString(digest[:])
	if actual != expected.SHA256 {
		return fmt.Errorf("payload SHA-256 mismatch for %q: got=%s expected=%s", expected.Path, actual, expected.SHA256)
	}
	return nil
}

func (t Tuple) LaunchPaths(localAppData string) (LaunchPaths, error) {
	if strings.TrimSpace(localAppData) == "" {
		return LaunchPaths{}, errors.New("LOCALAPPDATA is unavailable")
	}
	dataDir := filepath.Join(localAppData, filepath.FromSlash(t.Manifest.Storage.UserDataRelativePath))
	profileDir := filepath.Join(localAppData, filepath.FromSlash(t.Manifest.Storage.BrowserProfileRelativePath))
	for label, path := range map[string]string{"user data": dataDir, "browser profile": profileDir} {
		abs, err := filepath.Abs(path)
		if err != nil {
			return LaunchPaths{}, fmt.Errorf("resolve %s: %w", label, err)
		}
		rel, err := filepath.Rel(t.InstallRoot, abs)
		if err != nil {
			return LaunchPaths{}, fmt.Errorf("compare %s with install root: %w", label, err)
		}
		if rel == "." || (rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))) {
			return LaunchPaths{}, fmt.Errorf("%s path must remain outside install root", label)
		}
	}
	return LaunchPaths{
		SidecarPath:         mustJoin(t.VersionRoot, t.Manifest.SidecarPath),
		ConfigPath:          mustJoin(t.VersionRoot, t.Manifest.ConfigPath),
		ChromiumPath:        mustJoin(t.VersionRoot, t.Manifest.ChromiumPath),
		BridgeExtensionPath: mustJoin(t.VersionRoot, t.Manifest.BridgeExtensionPath),
		DataDirectory:       dataDir,
		BrowserProfile:      profileDir,
		DatabasePath:        filepath.Join(dataDir, "aku-sidecar.db"),
	}, nil
}

func mustJoin(root, relative string) string { return filepath.Join(root, filepath.FromSlash(relative)) }

func (t Tuple) SidecarArgs(paths LaunchPaths) []string {
	return []string{
		"--config", paths.ConfigPath,
		"--database", paths.DatabasePath,
		"--app-shell",
		"--chromium-path", paths.ChromiumPath,
		"--bridge-extension-path", paths.BridgeExtensionPath,
		"--bridge-extension-origin", t.Manifest.BridgeIdentity.Origin,
		"--browser-profile", paths.BrowserProfile,
	}
}
