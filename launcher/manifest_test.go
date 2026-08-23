package launcher

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const (
	fixtureExtensionID = "jpgekhehobljhpbdbpkllgleehcjgmjl"
	fixturePublicKey   = "AQIDBA=="
)

func TestLoadActiveTupleValidFixtureAndArguments(t *testing.T) {
	root := writeFixture(t)
	tuple, err := LoadActiveTuple(root)
	if err != nil {
		t.Fatal(err)
	}
	if tuple.Pointer.Version != "1.2.3" || tuple.Manifest.Version != "1.2.3" {
		t.Fatalf("active tuple version=%q/%q", tuple.Pointer.Version, tuple.Manifest.Version)
	}
	paths, err := tuple.LaunchPaths(filepath.Join(filepath.Dir(root), "local-app-data"))
	if err != nil {
		t.Fatal(err)
	}
	args := tuple.SidecarArgs(paths)
	want := []string{
		"--config", paths.ConfigPath,
		"--database", paths.DatabasePath,
		"--app-shell",
		"--chromium-path", paths.ChromiumPath,
		"--bridge-extension-path", paths.BridgeExtensionPath,
		"--bridge-extension-origin", "chrome-extension://" + fixtureExtensionID + "/",
		"--browser-profile", paths.BrowserProfile,
	}
	if strings.Join(args, "\x00") != strings.Join(want, "\x00") {
		t.Fatalf("args=%q want=%q", args, want)
	}
}

func TestLaunchPathsRejectInstallRootStorage(t *testing.T) {
	root := writeFixture(t)
	tuple, err := LoadActiveTuple(root)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := tuple.LaunchPaths(filepath.Join(root, "local-app-data")); err == nil || !strings.Contains(err.Error(), "outside install root") {
		t.Fatalf("install-root storage was accepted: %v", err)
	}
}

func TestUndeclaredPayloadFileIsRejected(t *testing.T) {
	root := writeFixture(t)
	path := filepath.Join(root, "runtime", "versions", "1.2.3", "AkuBridge", "injected.js")
	if err := os.WriteFile(path, []byte("injected"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadActiveTuple(root); err == nil || !strings.Contains(err.Error(), "undeclared payload") {
		t.Fatalf("undeclared payload was accepted: %v", err)
	}
}

func TestBridgeIdentityMismatchIsRejected(t *testing.T) {
	root := writeFixture(t)
	manifestPath := filepath.Join(root, "runtime", "versions", "1.2.3", manifestFileName)
	var manifest BundleManifest
	readJSON(t, manifestPath, &manifest)
	manifest.BridgeIdentity.ExtensionID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	manifest.BridgeIdentity.Origin = "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/"
	writeJSON(t, manifestPath, manifest)
	if _, err := LoadActiveTuple(root); err == nil || !strings.Contains(err.Error(), "Bridge manifest key derives") {
		t.Fatalf("Bridge identity mismatch was accepted: %v", err)
	}
}

func TestStrictDecodeRejectsUnknownFields(t *testing.T) {
	root := writeFixture(t)
	path := filepath.Join(root, currentPointerPath)
	writeJSON(t, path, map[string]any{
		"schemaVersion": 1,
		"version":       "1.2.3",
		"manifestPath":  "runtime/versions/1.2.3/manifest.json",
		"unexpected":    true,
	})
	if _, err := LoadActiveTuple(root); err == nil || !strings.Contains(err.Error(), "unknown field") {
		t.Fatalf("unknown pointer field was accepted: %v", err)
	}
}

func TestHashMismatchIsRejected(t *testing.T) {
	root := writeFixture(t)
	path := filepath.Join(root, "runtime", "versions", "1.2.3", "AkuSidecar.exe")
	if err := os.WriteFile(path, []byte("tampered-values"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadActiveTuple(root); err == nil || !strings.Contains(err.Error(), "SHA-256 mismatch") {
		t.Fatalf("hash mismatch was accepted: %v", err)
	}
}

func TestMissingPayloadIsRejected(t *testing.T) {
	root := writeFixture(t)
	path := filepath.Join(root, "runtime", "versions", "1.2.3", "config", "sidecar.json")
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadActiveTuple(root); err == nil || !strings.Contains(err.Error(), "config") {
		t.Fatalf("missing payload was accepted: %v", err)
	}
}

func TestTraversalAndAbsolutePathsAreRejected(t *testing.T) {
	for name, path := range map[string]string{
		"traversal": "../outside.exe",
		"absolute":  filepath.Join(string(filepath.Separator), "outside.exe"),
	} {
		t.Run(name, func(t *testing.T) {
			root := writeFixture(t)
			manifestPath := filepath.Join(root, "runtime", "versions", "1.2.3", manifestFileName)
			var manifest BundleManifest
			readJSON(t, manifestPath, &manifest)
			manifest.SidecarPath = path
			writeJSON(t, manifestPath, manifest)
			if _, err := LoadActiveTuple(root); err == nil || !strings.Contains(err.Error(), "path") {
				t.Fatalf("unsafe path was accepted: %v", err)
			}
		})
	}
}

func TestActiveVersionMismatchIsRejected(t *testing.T) {
	root := writeFixture(t)
	manifestPath := filepath.Join(root, "runtime", "versions", "1.2.3", manifestFileName)
	var manifest BundleManifest
	readJSON(t, manifestPath, &manifest)
	manifest.Version = "9.9.9"
	writeJSON(t, manifestPath, manifest)
	if _, err := LoadActiveTuple(root); err == nil || !strings.Contains(err.Error(), "active version mismatch") {
		t.Fatalf("active-version mismatch was accepted: %v", err)
	}
}

func writeFixture(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	versionRoot := filepath.Join(root, "runtime", "versions", "1.2.3")
	for _, directory := range []string{
		filepath.Join(root, "runtime"),
		filepath.Join(versionRoot, "config"),
		filepath.Join(versionRoot, "chromium"),
		filepath.Join(versionRoot, "AkuBridge"),
	} {
		if err := os.MkdirAll(directory, 0o700); err != nil {
			t.Fatal(err)
		}
	}
	files := map[string][]byte{
		"AkuSidecar.exe":          []byte("sidecar-fixture"),
		"config/sidecar.json":     []byte(`{"version":1}`),
		"chromium/chrome.exe":     []byte("chromium-fixture"),
		"AkuBridge/manifest.json": []byte(`{"manifest_version":3}`),
	}
	files["AkuBridge/manifest.json"] = []byte(`{"manifest_version":3,"key":"` + fixturePublicKey + `","version":"1.2.3.0","version_name":"1.2.3"}`)
	payload := make([]PayloadFile, 0, len(files))
	for relative, data := range files {
		path := filepath.Join(versionRoot, filepath.FromSlash(relative))
		if err := os.WriteFile(path, data, 0o600); err != nil {
			t.Fatal(err)
		}
		digest := sha256.Sum256(data)
		payload = append(payload, PayloadFile{Path: relative, Size: int64(len(data)), SHA256: hex.EncodeToString(digest[:])})
	}
	manifest := BundleManifest{
		SchemaVersion:       1,
		Product:             "AkuBrowser",
		Platform:            "windows-x64",
		Version:             "1.2.3",
		ChromiumVersion:     "140.0.7339.185",
		BridgeVersion:       "1.2.3",
		BridgeContract:      "aku-browser.bridge.v2",
		SidecarPath:         "AkuSidecar.exe",
		ConfigPath:          "config/sidecar.json",
		ChromiumPath:        "chromium/chrome.exe",
		BridgeExtensionPath: "AkuBridge",
		BridgeIdentity: BridgeIdentity{
			Profile:            "production-app",
			Environment:        "production",
			Distribution:       "installed-app",
			RuntimeLifecycle:   "managed",
			RuntimeAcquisition: "bundled-installer",
			ExtensionID:        fixtureExtensionID,
			Origin:             "chrome-extension://" + fixtureExtensionID + "/",
		},
		Storage: StoragePolicy{
			UserDataRoot:               "local-app-data",
			UserDataRelativePath:       "AkuBrowser/data",
			BrowserProfileRoot:         "local-app-data",
			BrowserProfileRelativePath: "AkuBrowser/browser-profile",
		},
		Health:  HealthContract{Host: "127.0.0.1", Port: 11122, Path: "/api/health", TimeoutMS: 3000},
		Payload: payload,
	}
	writeJSON(t, filepath.Join(versionRoot, manifestFileName), manifest)
	writeJSON(t, filepath.Join(root, currentPointerPath), ActivePointer{
		SchemaVersion: 1,
		Version:       "1.2.3",
		ManifestPath:  "runtime/versions/1.2.3/manifest.json",
	})
	return root
}

func writeJSON(t *testing.T, path string, value any) {
	t.Helper()
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, append(data, '\n'), 0o600); err != nil {
		t.Fatal(err)
	}
}

func readJSON(t *testing.T, path string, value any) {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, value); err != nil {
		t.Fatal(err)
	}
}
