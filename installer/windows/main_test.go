package main

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestCompletionMessageExplainsPortableRuntimeHandoff(t *testing.T) {
	message := completionMessage("installed")
	for _, required := range []string{
		"select Check runtime",
		"older portable AkuBrowser Runtime",
		"close it first",
	} {
		if !strings.Contains(message, required) {
			t.Fatalf("completion message is missing %q: %s", required, message)
		}
	}
	if strings.Contains(completionMessage("uninstalled"), "select Check runtime") {
		t.Fatal("uninstall completion message must not ask the user to check the runtime")
	}
}

func TestResolveInstallRootUsesDefaultOrAbsoluteSelection(t *testing.T) {
	localAppData := filepath.Join("C:\\", "Users", "Example", "AppData", "Local")
	defaultRoot, err := resolveInstallRoot(localAppData, "")
	if err != nil || defaultRoot != defaultInstallRoot(localAppData) {
		t.Fatalf("default install root=%q err=%v", defaultRoot, err)
	}
	selected := filepath.Join("D:\\", "Apps", "AkuBrowser")
	resolved, err := resolveInstallRoot(localAppData, selected)
	if err != nil || resolved != selected {
		t.Fatalf("selected install root=%q err=%v", resolved, err)
	}
	if _, err := resolveInstallRoot(localAppData, `relative\AkuBrowser`); err == nil {
		t.Fatal("relative installation directory was accepted")
	}
}
