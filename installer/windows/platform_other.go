//go:build !windows

package main

import (
	"errors"
	"os"
	"path/filepath"
)

type WindowsRegistry struct{}

func (WindowsRegistry) RegisterNativeHost(string) error {
	return errors.New("AkuBrowser Runtime installer requires Windows")
}

func (WindowsRegistry) RegisterUninstaller(InstallRegistration) error {
	return errors.New("AkuBrowser Runtime installer requires Windows")
}

func (WindowsRegistry) RemoveNativeHost() error {
	return errors.New("AkuBrowser Runtime installer requires Windows")
}

func (WindowsRegistry) RemoveUninstaller() error {
	return errors.New("AkuBrowser Runtime installer requires Windows")
}

func replaceFile(source, destination string) error {
	_ = os.Remove(destination)
	return os.Rename(source, destination)
}

func removeInstalledFile(path string) error {
	return os.Remove(path)
}

func defaultInstallRoot(localAppData string) string {
	return filepath.Join(localAppData, "Programs", "AkuBrowser")
}
