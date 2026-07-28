//go:build windows

package main

import (
	"errors"
	"os"
	"path/filepath"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

const moveFileDelayUntilReboot = 0x00000004

type WindowsRegistry struct{}

func (WindowsRegistry) RegisterNativeHost(manifestPath string) error {
	key, _, err := registry.CreateKey(
		registry.CURRENT_USER,
		nativeHostRegistryPath,
		registry.SET_VALUE|registry.QUERY_VALUE,
	)
	if err != nil {
		return err
	}
	defer key.Close()
	return key.SetStringValue("", manifestPath)
}

func (WindowsRegistry) RegisterUninstaller(product InstallRegistration) error {
	key, _, err := registry.CreateKey(
		registry.CURRENT_USER,
		uninstallRegistryPath,
		registry.SET_VALUE|registry.QUERY_VALUE,
	)
	if err != nil {
		return err
	}
	defer key.Close()
	values := map[string]string{
		"DisplayName":     product.DisplayName,
		"DisplayVersion":  product.DisplayVersion,
		"Publisher":       product.Publisher,
		"InstallLocation": product.InstallLocation,
		"UninstallString": product.UninstallString,
		"ModifyPath":      product.RepairString,
	}
	for name, value := range values {
		if err := key.SetStringValue(name, value); err != nil {
			return err
		}
	}
	return key.SetDWordValue("NoModify", 0)
}

func (WindowsRegistry) RemoveNativeHost() error {
	return removeRegistryKey(nativeHostRegistryPath)
}

func (WindowsRegistry) RemoveUninstaller() error {
	return removeRegistryKey(uninstallRegistryPath)
}

func removeRegistryKey(path string) error {
	err := registry.DeleteKey(registry.CURRENT_USER, path)
	if errors.Is(err, registry.ErrNotExist) {
		return nil
	}
	return err
}

func replaceFile(source, destination string) error {
	sourcePointer, err := windows.UTF16PtrFromString(source)
	if err != nil {
		return err
	}
	destinationPointer, err := windows.UTF16PtrFromString(destination)
	if err != nil {
		return err
	}
	if err := windows.MoveFileEx(
		sourcePointer,
		destinationPointer,
		windows.MOVEFILE_REPLACE_EXISTING|windows.MOVEFILE_WRITE_THROUGH,
	); err != nil {
		return err
	}
	return nil
}

func removeInstalledFile(path string) error {
	err := os.Remove(path)
	if err == nil || errors.Is(err, os.ErrNotExist) {
		return err
	}
	pointer, pointerErr := windows.UTF16PtrFromString(path)
	if pointerErr != nil {
		return err
	}
	if scheduleErr := windows.MoveFileEx(pointer, nil, moveFileDelayUntilReboot); scheduleErr != nil {
		return err
	}
	return nil
}

func defaultInstallRoot(localAppData string) string {
	return filepath.Join(localAppData, "Programs", "AkuBrowser")
}
