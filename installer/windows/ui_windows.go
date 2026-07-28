//go:build windows

package main

import (
	"fmt"
	"os"
	"syscall"
	"unsafe"
)

var (
	user32DLL      = syscall.NewLazyDLL("user32.dll")
	messageBoxProc = user32DLL.NewProc("MessageBoxW")
)

const (
	messageBoxOK        = 0x00000000
	messageBoxIconError = 0x00000010
	messageBoxIconInfo  = 0x00000040
)

func finish(quiet bool, err error, messages ...string) {
	if quiet {
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
		}
		return
	}
	message := "AkuBrowser Runtime is ready."
	flags := uintptr(messageBoxOK | messageBoxIconInfo)
	if len(messages) > 0 {
		message = messages[0]
	}
	if err != nil {
		message = "AkuBrowser Runtime setup failed:\n\n" + err.Error()
		flags = messageBoxOK | messageBoxIconError
	}
	title, _ := syscall.UTF16PtrFromString("AkuBrowser Runtime Setup")
	body, _ := syscall.UTF16PtrFromString(message)
	_, _, _ = messageBoxProc.Call(
		0,
		uintptr(unsafe.Pointer(body)),
		uintptr(unsafe.Pointer(title)),
		flags,
	)
}
