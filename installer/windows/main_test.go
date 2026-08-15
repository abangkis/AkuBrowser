package main

import (
	"os"
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
	if strings.Contains(completionMessage("fully reset"), "select Check runtime") {
		t.Fatal("full reset completion message must not ask the user to check the runtime")
	}
}

func TestSetupDoesNotLaunchNestedUnsignedExecutables(t *testing.T) {
	data, err := os.ReadFile("setup.nsi")
	if err != nil {
		t.Fatal(err)
	}
	script := string(data)
	if strings.Contains(script, "ExecWait") || strings.Contains(script, "MAINTENANCE_EXE") {
		t.Fatal("setup launches a nested maintenance executable that antivirus can terminate")
	}
	if !strings.Contains(script, `File /r "${PAYLOAD_ROOT}\host\*"`) ||
		!strings.Contains(script, `File /oname=current.json "${PAYLOAD_ROOT}\runtime\current.json"`) {
		t.Fatal("setup does not extract the payload directly with current.json activated last")
	}
}

func TestSetupIsSingleInstanceAndRecordsDurableOutcome(t *testing.T) {
	data, err := os.ReadFile("setup.nsi")
	if err != nil {
		t.Fatal(err)
	}
	script := string(data)
	for _, required := range []string{
		"CreateMutexW",
		"ERROR_ALREADY_EXISTS",
		"Setup is already running",
		"install-result.json",
		"install.log",
		`$\"status$\":$\"installing$\"`,
		`$\"status$\":$\"completed$\"`,
		`$\"status$\":$\"failed$\"`,
		"${EXTENSION_ORIGIN}",
		"InstallAttemptCompleted",
		"AkuBrowser Runtime ${APP_VERSION} is already installed",
		"Select No to close this duplicate Setup session",
		"Avast CyberCapture may open an isolated second Setup window",
		"select No or Cancel",
		"do not run Repair twice",
	} {
		if !strings.Contains(script, required) {
			t.Fatalf("setup is missing durable single-instance contract %q", required)
		}
	}
	if strings.Index(script, "RecordInstallFailed") > strings.Index(script, "CloseHandle") {
		t.Fatal("setup closes its lifetime lock before recording an aborted install")
	}
}

func TestSetupStopsRunningSidecarOnlyAfterConfirmation(t *testing.T) {
	data, err := os.ReadFile("setup.nsi")
	if err != nil {
		t.Fatal(err)
	}
	script := string(data)
	for _, required := range []string{
		"tasklist.exe",
		"IMAGENAME eq AkuSidecar.exe",
		"want Setup to stop AkuBrowser Runtime now",
		"If another Setup window just completed",
		"isolated antivirus duplicate",
		"MB_DEFBUTTON2",
		"/SD IDNO",
		"taskkill.exe",
		"AkuBrowser Runtime (AkuSidecar.exe) is still running",
		"Call EnsureRuntimeStopped",
	} {
		if !strings.Contains(script, required) {
			t.Fatalf("setup is missing runtime-stop preflight %q", required)
		}
	}
	if strings.Index(script, "want Setup to stop AkuBrowser Runtime now") > strings.Index(script, "taskkill.exe") {
		t.Fatal("setup attempts to stop AkuSidecar before asking the user")
	}
}

func TestSetupHandlesDowngradesAndOffersFullReset(t *testing.T) {
	data, err := os.ReadFile("setup.nsi")
	if err != nil {
		t.Fatal(err)
	}
	script := string(data)
	for _, required := range []string{
		`.runtime-version`,
		`!include "TextFunc.nsh"`,
		"VersionCompare",
		"AkuBrowser data was written by newer Runtime",
		"archive the newer data and create a fresh database",
		"pre-downgrade-",
		"Preserve data for an ordinary uninstall or reinstall",
		"Full reset and permanently remove data plus downgrade archives",
		`RMDir /r /REBOOTOK "$LOCALAPPDATA\AkuBrowser\data"`,
	} {
		if !strings.Contains(script, required) {
			t.Fatalf("setup is missing downgrade/reset contract %q", required)
		}
	}
	if strings.Index(script, "Call PrepareDowngradeData") > strings.Index(script, `File /oname=current.json`) {
		t.Fatal("downgrade data is not archived before the older runtime is activated")
	}
}

func TestBuilderPassesResolvedExtensionOriginToSetup(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("..", "..", "scripts", "build-windows-runtime-installer.ps1"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), `"/DEXTENSION_ORIGIN=chrome-extension://$ExtensionId/"`) {
		t.Fatal("installer builder does not bind the Native Messaging origin into the setup contract")
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
