package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

const (
	nativeHostRegistryPath = `Software\Google\Chrome\NativeMessagingHosts\com.akubrowser.runtime`
	uninstallRegistryPath  = `Software\Microsoft\Windows\CurrentVersion\Uninstall\AkuBrowserRuntime`
	installedSetupPath     = `host\AkuBrowserRuntimeMaintenance.exe`
	legacySetupPath        = `host\AkuBrowserRuntimeSetup.exe`
)

type Registry interface {
	RegisterNativeHost(manifestPath string) error
	RegisterUninstaller(product InstallRegistration) error
	RemoveNativeHost() error
	RemoveUninstaller() error
}

type InstallRegistration struct {
	DisplayName     string
	DisplayVersion  string
	Publisher       string
	InstallLocation string
	UninstallString string
	RepairString    string
}

type Installer struct {
	Payload                     fs.FS
	Manifest                    PayloadManifest
	InstallRoot                 string
	DataRoot                    string
	SourceExecutable            string
	Registry                    Registry
	SkipUninstallerRegistration bool
}

type InstalledManifest struct {
	SchemaVersion   int           `json:"schemaVersion"`
	Product         string        `json:"product"`
	Version         string        `json:"version"`
	ExtensionOrigin string        `json:"extensionOrigin"`
	Files           []PayloadFile `json:"files"`
	Preserves       []string      `json:"preserves"`
}

func (installer Installer) Install() error {
	if err := installer.validateRoots(); err != nil {
		return err
	}
	if err := verifyPayload(installer.Payload, installer.Manifest); err != nil {
		return err
	}
	for _, item := range installationOrder(installer.Manifest.Files) {
		if err := installer.installPayloadFile(item); err != nil {
			return err
		}
	}
	setupDestination := filepath.Join(installer.InstallRoot, installedSetupPath)
	if err := copyFileAtomic(installer.SourceExecutable, setupDestination); err != nil {
		return fmt.Errorf("install repair executable: %w", err)
	}
	legacySetup := filepath.Join(installer.InstallRoot, legacySetupPath)
	if !samePath(installer.SourceExecutable, legacySetup) {
		if err := removeInstalledFile(legacySetup); err != nil && !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("remove legacy setup executable: %w", err)
		}
	}
	installed := InstalledManifest{
		SchemaVersion:   1,
		Product:         "AkuBrowser",
		Version:         installer.Manifest.Version,
		ExtensionOrigin: installer.Manifest.ExtensionOrigin,
		Files:           append([]PayloadFile(nil), installer.Manifest.Files...),
		Preserves:       []string{installer.DataRoot},
	}
	installedData, err := json.MarshalIndent(installed, "", "  ")
	if err != nil {
		return fmt.Errorf("encode installed manifest: %w", err)
	}
	if err := writeBytesAtomic(filepath.Join(installer.InstallRoot, "install-manifest.json"), installedData); err != nil {
		return fmt.Errorf("write installed manifest: %w", err)
	}
	hostManifest := filepath.Join(installer.InstallRoot, "host", "com.akubrowser.runtime.json")
	if err := installer.Registry.RegisterNativeHost(hostManifest); err != nil {
		return fmt.Errorf("register native messaging host: %w", err)
	}
	if !installer.SkipUninstallerRegistration {
		quotedSetup := quoteWindowsArgument(setupDestination)
		registration := InstallRegistration{
			DisplayName:     "AkuBrowser Runtime",
			DisplayVersion:  installer.Manifest.Version,
			Publisher:       "AkuBrowser",
			InstallLocation: installer.InstallRoot,
			UninstallString: quotedSetup + " --uninstall",
			RepairString:    quotedSetup + " --repair",
		}
		if err := installer.Registry.RegisterUninstaller(registration); err != nil {
			return fmt.Errorf("register AkuBrowser Runtime uninstaller: %w", err)
		}
	}
	return nil
}

func (installer Installer) Uninstall() error {
	if err := installer.validateRoots(); err != nil {
		return err
	}
	var failures []error
	if err := installer.Registry.RemoveNativeHost(); err != nil {
		failures = append(failures, fmt.Errorf("remove native messaging registration: %w", err))
	}
	if !installer.SkipUninstallerRegistration {
		if err := installer.Registry.RemoveUninstaller(); err != nil {
			failures = append(failures, fmt.Errorf("remove uninstall registration: %w", err))
		}
	}
	paths := make([]string, 0, len(installer.Manifest.Files)+3)
	if installer.hasOwnedInstallMarker() {
		for _, relative := range []string{"host", "runtime"} {
			if err := installer.removeOwnedTree(relative); err != nil {
				failures = append(failures, err)
			}
		}
	} else {
		for _, item := range installer.Manifest.Files {
			paths = append(paths, filepath.FromSlash(item.Path))
		}
	}
	paths = append(paths, installedSetupPath, legacySetupPath, "install-manifest.json")
	for _, relative := range paths {
		target, err := installer.resolveTarget(relative)
		if err != nil {
			failures = append(failures, err)
			continue
		}
		if err := removeInstalledFile(target); err != nil && !errors.Is(err, os.ErrNotExist) {
			failures = append(failures, fmt.Errorf("remove installed file %q: %w", filepath.Base(target), err))
		}
	}
	removeEmptyDirectories(installer.InstallRoot)
	return errors.Join(failures...)
}

func (installer Installer) hasOwnedInstallMarker() bool {
	data, err := os.ReadFile(filepath.Join(installer.InstallRoot, "install-manifest.json"))
	if err != nil {
		return false
	}
	var installed InstalledManifest
	return json.Unmarshal(data, &installed) == nil && installed.SchemaVersion == 1 && installed.Product == "AkuBrowser"
}

func (installer Installer) removeOwnedTree(relative string) error {
	root, err := installer.resolveTarget(relative)
	if err != nil {
		return err
	}
	var files []string
	var directories []string
	err = filepath.WalkDir(root, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			if errors.Is(walkErr, os.ErrNotExist) {
				return nil
			}
			return walkErr
		}
		if entry.IsDir() {
			directories = append(directories, path)
		} else {
			files = append(files, path)
		}
		return nil
	})
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("enumerate installed %s files: %w", relative, err)
	}
	var failures []error
	for _, path := range files {
		if err := removeInstalledFile(path); err != nil && !errors.Is(err, os.ErrNotExist) {
			failures = append(failures, fmt.Errorf("remove installed file %q: %w", filepath.Base(path), err))
		}
	}
	sort.Slice(directories, func(first, second int) bool {
		return len(directories[first]) > len(directories[second])
	})
	for _, directory := range directories {
		if err := os.Remove(directory); err != nil && !errors.Is(err, os.ErrNotExist) && !errors.Is(err, os.ErrPermission) {
			failures = append(failures, fmt.Errorf("remove installed directory %q: %w", filepath.Base(directory), err))
		}
	}
	return errors.Join(failures...)
}

func samePath(first, second string) bool {
	firstAbsolute, firstErr := filepath.Abs(first)
	secondAbsolute, secondErr := filepath.Abs(second)
	return firstErr == nil && secondErr == nil && strings.EqualFold(filepath.Clean(firstAbsolute), filepath.Clean(secondAbsolute))
}

func (installer Installer) installPayloadFile(item PayloadFile) error {
	source, err := installer.Payload.Open(item.Path)
	if err != nil {
		return fmt.Errorf("open payload %q: %w", item.Path, err)
	}
	defer source.Close()
	destination, err := installer.resolveTarget(filepath.FromSlash(item.Path))
	if err != nil {
		return err
	}
	if matches, err := fileMatches(destination, item); err == nil && matches {
		return nil
	}
	if err := writeStreamAtomic(destination, source, item); err != nil {
		return fmt.Errorf("install payload %q: %w", item.Path, err)
	}
	return nil
}

func (installer Installer) validateRoots() error {
	if installer.Payload == nil || installer.Registry == nil {
		return errors.New("installer dependencies are incomplete")
	}
	installRoot, err := filepath.Abs(installer.InstallRoot)
	if err != nil || installRoot == filepath.VolumeName(installRoot)+`\` {
		return errors.New("installer root is invalid")
	}
	dataRoot, err := filepath.Abs(installer.DataRoot)
	if err != nil {
		return errors.New("data root is invalid")
	}
	relative, err := filepath.Rel(installRoot, dataRoot)
	if err != nil {
		return err
	}
	if relative == "." || (!strings.HasPrefix(relative, ".."+string(filepath.Separator)) && relative != "..") {
		return errors.New("user data must remain outside the program installation root")
	}
	return nil
}

func (installer Installer) resolveTarget(relative string) (string, error) {
	target := filepath.Join(installer.InstallRoot, relative)
	root, err := filepath.Abs(installer.InstallRoot)
	if err != nil {
		return "", err
	}
	absolute, err := filepath.Abs(target)
	if err != nil {
		return "", err
	}
	within, err := filepath.Rel(root, absolute)
	if err != nil || within == ".." || strings.HasPrefix(within, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("installed path %q escapes the program root", relative)
	}
	return absolute, nil
}

func writeStreamAtomic(destination string, source io.Reader, expected PayloadFile) error {
	if err := os.MkdirAll(filepath.Dir(destination), 0o700); err != nil {
		return err
	}
	temporary, err := os.CreateTemp(filepath.Dir(destination), ".aku-install-*")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	hash := sha256.New()
	count, copyErr := io.Copy(io.MultiWriter(temporary, hash), io.LimitReader(source, maxPayloadFileBytes+1))
	if copyErr != nil {
		temporary.Close()
		return copyErr
	}
	if count != expected.Size || hex.EncodeToString(hash.Sum(nil)) != expected.SHA256 {
		temporary.Close()
		return errors.New("payload changed during installation")
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	return replaceFile(temporaryPath, destination)
}

func writeBytesAtomic(destination string, data []byte) error {
	item := PayloadFile{
		Size:   int64(len(data)),
		SHA256: hex.EncodeToString(sha256Sum(data)),
	}
	return writeStreamAtomic(destination, strings.NewReader(string(data)), item)
}

func copyFileAtomic(sourcePath, destination string) error {
	sourceAbsolute, err := filepath.Abs(sourcePath)
	if err != nil {
		return err
	}
	destinationAbsolute, err := filepath.Abs(destination)
	if err != nil {
		return err
	}
	if strings.EqualFold(filepath.Clean(sourceAbsolute), filepath.Clean(destinationAbsolute)) {
		return nil
	}
	source, err := os.Open(sourceAbsolute)
	if err != nil {
		return err
	}
	defer source.Close()
	info, err := source.Stat()
	if err != nil {
		return err
	}
	hash := sha256.New()
	if _, err := io.Copy(hash, source); err != nil {
		return err
	}
	if _, err := source.Seek(0, io.SeekStart); err != nil {
		return err
	}
	item := PayloadFile{Size: info.Size(), SHA256: hex.EncodeToString(hash.Sum(nil))}
	return writeStreamAtomic(destinationAbsolute, source, item)
}

func fileMatches(path string, expected PayloadFile) (bool, error) {
	file, err := os.Open(path)
	if err != nil {
		return false, err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil || info.Size() != expected.Size {
		return false, err
	}
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return false, err
	}
	return hex.EncodeToString(hash.Sum(nil)) == expected.SHA256, nil
}

func sha256Sum(data []byte) []byte {
	sum := sha256.Sum256(data)
	return sum[:]
}

func quoteWindowsArgument(value string) string {
	return `"` + strings.ReplaceAll(value, `"`, `\"`) + `"`
}

func removeEmptyDirectories(root string) {
	for {
		removed := false
		_ = filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
			if err == nil && entry.IsDir() && path != root {
				if removeErr := os.Remove(path); removeErr == nil {
					removed = true
				}
			}
			return nil
		})
		if !removed {
			break
		}
	}
	_ = os.Remove(root)
}
