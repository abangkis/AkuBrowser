package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io/fs"
	"os"
	"path/filepath"
	"testing"
	"testing/fstest"
)

const installerTestOrigin = "chrome-extension://abcdefghijklmnopabcdefghijklmnop/"

func TestInstallRepairAndUninstallPreserveUserData(t *testing.T) {
	payload, manifest := installerFixture(t)
	base := t.TempDir()
	installRoot := filepath.Join(base, "Programs", "AkuBrowser")
	dataRoot := filepath.Join(base, "AkuBrowser", "data")
	sourceSetup := filepath.Join(base, "download", "AkuBrowserRuntimeSetup.exe")
	writeTestFile(t, sourceSetup, []byte("signed-setup-binary"))
	userData := filepath.Join(dataRoot, "aku-browser.db")
	writeTestFile(t, userData, []byte("durable-user-data"))
	registry := &memoryRegistry{}
	installer := Installer{
		Payload:          payload,
		Manifest:         manifest,
		InstallRoot:      installRoot,
		DataRoot:         dataRoot,
		SourceExecutable: sourceSetup,
		Registry:         registry,
	}

	if err := installer.Install(); err != nil {
		t.Fatalf("install: %v", err)
	}
	assertFileContent(t, filepath.Join(installRoot, "host", "AkuBrowserRuntimeHost.exe"), "native-host")
	assertFileContent(t, filepath.Join(installRoot, "runtime", "current.json"), `{"version":"0.7.4"}`)
	assertFileContent(t, filepath.Join(installRoot, installedSetupPath), "signed-setup-binary")
	if registry.nativeManifest != filepath.Join(installRoot, "host", "com.akubrowser.runtime.json") {
		t.Fatalf("unexpected native host registration: %s", registry.nativeManifest)
	}
	if registry.registration.DisplayVersion != "0.7.4" ||
		registry.registration.InstallLocation != installRoot {
		t.Fatalf("unexpected uninstall registration: %#v", registry.registration)
	}

	writeTestFile(t, filepath.Join(installRoot, "host", "AkuBrowserRuntimeHost.exe"), []byte("corrupt"))
	if err := installer.Install(); err != nil {
		t.Fatalf("repair: %v", err)
	}
	assertFileContent(t, filepath.Join(installRoot, "host", "AkuBrowserRuntimeHost.exe"), "native-host")

	if err := installer.Uninstall(false); err != nil {
		t.Fatalf("uninstall: %v", err)
	}
	if !registry.nativeRemoved || !registry.uninstallerRemoved {
		t.Fatalf("registrations were not removed: %#v", registry)
	}
	assertFileContent(t, userData, "durable-user-data")
	if _, err := os.Stat(filepath.Join(installRoot, "host", "AkuBrowserRuntimeHost.exe")); !os.IsNotExist(err) {
		t.Fatalf("program file survived uninstall: %v", err)
	}

	if err := installer.Install(); err != nil {
		t.Fatalf("reinstall: %v", err)
	}
	assertFileContent(t, userData, "durable-user-data")
	assertFileContent(t, filepath.Join(installRoot, "runtime", "current.json"), `{"version":"0.7.4"}`)
}

func TestExternalSetupOwnsUninstallerRegistration(t *testing.T) {
	payload, manifest := installerFixture(t)
	base := t.TempDir()
	registry := &memoryRegistry{}
	installer := Installer{
		Payload:                     payload,
		Manifest:                    manifest,
		InstallRoot:                 filepath.Join(base, "Programs", "AkuBrowser"),
		DataRoot:                    filepath.Join(base, "AkuBrowser", "data"),
		SourceExecutable:            filepath.Join(base, "download", "AkuBrowserRuntimeMaintenance.exe"),
		Registry:                    registry,
		SkipUninstallerRegistration: true,
	}
	writeTestFile(t, installer.SourceExecutable, []byte("maintenance-engine"))

	if err := installer.Install(); err != nil {
		t.Fatalf("install: %v", err)
	}
	if registry.registration.DisplayName != "" {
		t.Fatalf("engine replaced outer setup registration: %#v", registry.registration)
	}
	if err := installer.Uninstall(false); err != nil {
		t.Fatalf("uninstall: %v", err)
	}
	if registry.uninstallerRemoved {
		t.Fatal("engine removed outer setup registration")
	}
}

func TestUninstallRemovesUpdatedRuntimeVersionsButPreservesUnownedFiles(t *testing.T) {
	payload, manifest := installerFixture(t)
	base := t.TempDir()
	installRoot := filepath.Join(base, "Programs", "AkuBrowser")
	installer := Installer{
		Payload:          payload,
		Manifest:         manifest,
		InstallRoot:      installRoot,
		DataRoot:         filepath.Join(base, "AkuBrowser", "data"),
		SourceExecutable: filepath.Join(base, "download", "AkuBrowserRuntimeMaintenance.exe"),
		Registry:         &memoryRegistry{},
	}
	writeTestFile(t, installer.SourceExecutable, []byte("maintenance-engine"))
	if err := installer.Install(); err != nil {
		t.Fatalf("install: %v", err)
	}
	futureRuntime := filepath.Join(installRoot, "runtime", "versions", "0.7.5", "AkuSidecar.exe")
	unowned := filepath.Join(installRoot, "user-note.txt")
	writeTestFile(t, futureRuntime, []byte("future-runtime"))
	writeTestFile(t, unowned, []byte("do-not-remove"))

	if err := installer.Uninstall(false); err != nil {
		t.Fatalf("uninstall: %v", err)
	}
	if _, err := os.Stat(futureRuntime); !os.IsNotExist(err) {
		t.Fatalf("future runtime survived uninstall: %v", err)
	}
	assertFileContent(t, unowned, "do-not-remove")
}

func TestFullResetUninstallRemovesUserData(t *testing.T) {
	payload, manifest := installerFixture(t)
	base := t.TempDir()
	installer := Installer{
		Payload:          payload,
		Manifest:         manifest,
		InstallRoot:      filepath.Join(base, "Programs", "AkuBrowser"),
		DataRoot:         filepath.Join(base, "AkuBrowser", "data"),
		SourceExecutable: filepath.Join(base, "download", "AkuBrowserRuntimeMaintenance.exe"),
		Registry:         &memoryRegistry{},
	}
	writeTestFile(t, installer.SourceExecutable, []byte("maintenance-engine"))
	writeTestFile(t, filepath.Join(installer.DataRoot, "aku-browser.db"), []byte("testing-data"))
	dataContainer := filepath.Dir(installer.DataRoot)
	writeTestFile(t, filepath.Join(dataContainer, "data-backups", "pre-downgrade-test", "aku-browser.db"), []byte("archived-data"))
	writeTestFile(t, filepath.Join(dataContainer, "downgrade-receipt.txt"), []byte("backup=pre-downgrade-test"))
	if err := installer.Install(); err != nil {
		t.Fatal(err)
	}
	if err := installer.Uninstall(true); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(installer.DataRoot); !os.IsNotExist(err) {
		t.Fatalf("full reset preserved user data: %v", err)
	}
	for _, target := range []string{
		filepath.Join(dataContainer, "data-backups"),
		filepath.Join(dataContainer, "downgrade-receipt.txt"),
	} {
		if _, err := os.Stat(target); !os.IsNotExist(err) {
			t.Fatalf("full reset preserved %s: %v", target, err)
		}
	}
}

func TestInstallerRejectsPayloadTraversalAndChecksumMismatch(t *testing.T) {
	payload, manifest := installerFixture(t)
	manifest.Files[0].Path = "../outside.exe"
	if err := validatePayloadPath(manifest.Files[0].Path, manifest.Version); err == nil {
		t.Fatal("payload traversal path was accepted")
	}

	payload, manifest = installerFixture(t)
	manifest.Files[0].SHA256 = string(make([]byte, 64))
	if err := verifyPayload(payload, manifest); err == nil {
		t.Fatal("payload checksum mismatch was accepted")
	}
}

func TestInstallerRequiresDataOutsideProgramRoot(t *testing.T) {
	payload, manifest := installerFixture(t)
	root := t.TempDir()
	sourceSetup := filepath.Join(root, "setup.exe")
	writeTestFile(t, sourceSetup, []byte("setup"))
	installer := Installer{
		Payload:          payload,
		Manifest:         manifest,
		InstallRoot:      filepath.Join(root, "program"),
		DataRoot:         filepath.Join(root, "program", "data"),
		SourceExecutable: sourceSetup,
		Registry:         &memoryRegistry{},
	}
	if err := installer.Install(); err == nil {
		t.Fatal("installer accepted user data inside the replaceable program root")
	}
}

func TestInstallerRejectsBroadOrUnexpectedDataRoot(t *testing.T) {
	payload, manifest := installerFixture(t)
	root := t.TempDir()
	sourceSetup := filepath.Join(root, "setup.exe")
	writeTestFile(t, sourceSetup, []byte("setup"))
	for _, dataRoot := range []string{
		filepath.VolumeName(root) + string(filepath.Separator),
		filepath.Join(root, "AkuBrowser"),
	} {
		installer := Installer{
			Payload:          payload,
			Manifest:         manifest,
			InstallRoot:      filepath.Join(root, "program"),
			DataRoot:         dataRoot,
			SourceExecutable: sourceSetup,
			Registry:         &memoryRegistry{},
		}
		if err := installer.Uninstall(true); err == nil {
			t.Fatalf("full reset accepted unsafe data root %q", dataRoot)
		}
	}
}

func TestCurrentMetadataIsAlwaysActivatedLast(t *testing.T) {
	files := []PayloadFile{
		{Path: "runtime/current.json"},
		{Path: "host/AkuBrowserRuntimeHost.exe"},
		{Path: "runtime/versions/0.7.4/AkuSidecar.exe"},
	}
	ordered := installationOrder(files)
	if ordered[len(ordered)-1].Path != "runtime/current.json" {
		t.Fatalf("active runtime metadata was not last: %#v", ordered)
	}
}

func TestInterruptedInstallPreservesActiveMetadataAndUserData(t *testing.T) {
	payload, manifest := installerFixture(t)
	base := t.TempDir()
	installRoot := filepath.Join(base, "Programs", "AkuBrowser")
	dataRoot := filepath.Join(base, "AkuBrowser", "data")
	sourceSetup := filepath.Join(base, "download", "AkuBrowserRuntimeSetup.exe")
	currentPath := filepath.Join(installRoot, "runtime", "current.json")
	userData := filepath.Join(dataRoot, "aku-browser.db")
	writeTestFile(t, sourceSetup, []byte("signed-setup-binary"))
	writeTestFile(t, currentPath, []byte(`{"version":"0.7.3","knownGood":true}`))
	writeTestFile(t, userData, []byte("durable-user-data"))

	// A file occupying the candidate version directory simulates an interrupted
	// or otherwise unwritable staging destination before current.json activates.
	writeTestFile(t, filepath.Join(installRoot, "runtime", "versions", manifest.Version), []byte("blocked"))
	registry := &memoryRegistry{}
	installer := Installer{
		Payload:          payload,
		Manifest:         manifest,
		InstallRoot:      installRoot,
		DataRoot:         dataRoot,
		SourceExecutable: sourceSetup,
		Registry:         registry,
	}

	if err := installer.Install(); err == nil {
		t.Fatal("interrupted staging unexpectedly completed")
	}
	assertFileContent(t, currentPath, `{"version":"0.7.3","knownGood":true}`)
	assertFileContent(t, userData, "durable-user-data")
	if registry.nativeManifest != "" || registry.registration.DisplayName != "" {
		t.Fatalf("failed staging changed registration: %#v", registry)
	}
}

func installerFixture(t *testing.T) (fs.FS, PayloadManifest) {
	t.Helper()
	files := map[string][]byte{
		"host/AkuBrowserRuntimeHost.exe":             []byte("native-host"),
		"host/com.akubrowser.runtime.json":           []byte(`{"name":"com.akubrowser.runtime"}`),
		"runtime/versions/0.7.4/AkuSidecar.exe":      []byte("sidecar"),
		"runtime/versions/0.7.4/config/sidecar.json": []byte(`{"version":1}`),
		"runtime/current.json":                       []byte(`{"version":"0.7.4"}`),
	}
	manifest := PayloadManifest{
		SchemaVersion:   1,
		Product:         "AkuBrowser",
		Version:         "0.7.4",
		Architecture:    "windows-x64",
		ExtensionOrigin: installerTestOrigin,
	}
	mapFS := fstest.MapFS{}
	for name, data := range files {
		sum := sha256.Sum256(data)
		manifest.Files = append(manifest.Files, PayloadFile{
			Path:   name,
			Size:   int64(len(data)),
			SHA256: hex.EncodeToString(sum[:]),
		})
		mapFS[name] = &fstest.MapFile{Data: data}
	}
	manifestData, err := json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	mapFS[payloadManifestName] = &fstest.MapFile{Data: manifestData}
	loaded, err := loadPayloadManifest(mapFS)
	if err != nil {
		t.Fatalf("fixture manifest: %v", err)
	}
	return mapFS, loaded
}

type memoryRegistry struct {
	nativeManifest     string
	registration       InstallRegistration
	nativeRemoved      bool
	uninstallerRemoved bool
}

func (registry *memoryRegistry) RegisterNativeHost(path string) error {
	registry.nativeManifest = path
	return nil
}

func (registry *memoryRegistry) RegisterUninstaller(product InstallRegistration) error {
	registry.registration = product
	return nil
}

func (registry *memoryRegistry) RemoveNativeHost() error {
	registry.nativeRemoved = true
	return nil
}

func (registry *memoryRegistry) RemoveUninstaller() error {
	registry.uninstallerRemoved = true
	return nil
}

func writeTestFile(t *testing.T, path string, data []byte) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
}

func assertFileContent(t *testing.T, path, expected string) {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	if string(data) != expected {
		t.Fatalf("unexpected content at %s: %q", path, data)
	}
}
