//go:build windows

package launcher

import (
	"errors"
	"fmt"

	"golang.org/x/sys/windows"
)

func acquireInstance() (func(), error) {
	name, err := windows.UTF16PtrFromString(mutexName)
	if err != nil {
		return nil, fmt.Errorf("encode instance mutex name: %w", err)
	}
	handle, err := windows.CreateMutex(nil, false, name)
	if err != nil && !errors.Is(err, windows.ERROR_ALREADY_EXISTS) {
		return nil, fmt.Errorf("create instance mutex: %w", err)
	}
	if errors.Is(err, windows.ERROR_ALREADY_EXISTS) {
		if handle != 0 {
			_ = windows.CloseHandle(handle)
		}
		return nil, errors.New("AkuBrowser is already running")
	}
	return func() { _ = windows.CloseHandle(handle) }, nil
}
