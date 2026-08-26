//go:build windows

package launcher

import (
	"errors"
	"fmt"
	"unsafe"

	"golang.org/x/sys/windows"
)

var setCurrentProcessExplicitAppUserModelID = windows.NewLazySystemDLL("shell32.dll").NewProc("SetCurrentProcessExplicitAppUserModelID")

func setCurrentApplicationID(applicationID string) error {
	value, err := windows.UTF16PtrFromString(applicationID)
	if err != nil {
		return fmt.Errorf("encode application identity: %w", err)
	}
	hresult, _, _ := setCurrentProcessExplicitAppUserModelID.Call(uintptr(unsafe.Pointer(value)))
	if int32(hresult) < 0 {
		return fmt.Errorf("set current application identity %q: HRESULT 0x%08x", applicationID, uint32(hresult))
	}
	return nil
}

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
