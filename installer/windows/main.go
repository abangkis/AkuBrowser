package main

import (
	"embed"
	"errors"
	"flag"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

//go:embed payload
var embeddedPayload embed.FS

func main() {
	os.Exit(runInstaller())
}

func runInstaller() int {
	var (
		repair              = flag.Bool("repair", false, "repair the current AkuBrowser Runtime installation")
		uninstall           = flag.Bool("uninstall", false, "uninstall AkuBrowser Runtime while preserving user data")
		fullReset           = flag.Bool("full-reset", false, "remove user data during uninstall")
		quiet               = flag.Bool("quiet", false, "suppress completion UI")
		installRoot         = flag.String("install-root", "", "absolute AkuBrowser Runtime installation directory")
		externalUninstaller = flag.Bool("external-uninstaller", false, "let an outer setup wizard own Add or Remove Programs registration")
	)
	flag.Parse()
	if *repair && *uninstall {
		finish(*quiet, errors.New("repair and uninstall cannot be requested together"))
		return 2
	}
	if *fullReset && !*uninstall {
		finish(*quiet, errors.New("full reset requires uninstall"))
		return 2
	}
	payload, err := fs.Sub(embeddedPayload, "payload")
	if err != nil {
		finish(*quiet, err)
		return 2
	}
	manifest, err := loadPayloadManifest(payload)
	if err != nil {
		finish(*quiet, err)
		return 2
	}
	localAppData := os.Getenv("LOCALAPPDATA")
	if localAppData == "" {
		finish(*quiet, errors.New("LOCALAPPDATA is unavailable"))
		return 2
	}
	resolvedInstallRoot, err := resolveInstallRoot(localAppData, *installRoot)
	if err != nil {
		finish(*quiet, err)
		return 2
	}
	executable, err := os.Executable()
	if err != nil {
		finish(*quiet, err)
		return 2
	}
	installer := Installer{
		Payload:                     payload,
		Manifest:                    manifest,
		InstallRoot:                 resolvedInstallRoot,
		DataRoot:                    filepath.Join(localAppData, "AkuBrowser", "data"),
		SourceExecutable:            executable,
		Registry:                    WindowsRegistry{},
		SkipUninstallerRegistration: *externalUninstaller,
	}
	action := "installed"
	if *uninstall {
		action = "uninstalled"
		if *fullReset {
			action = "fully reset"
		}
		err = installer.Uninstall(*fullReset)
	} else {
		if *repair {
			action = "repaired"
		}
		err = installer.Install()
	}
	if err != nil {
		finish(*quiet, err)
		return 1
	}
	finish(*quiet, nil, completionMessage(action))
	return 0
}

func resolveInstallRoot(localAppData, requested string) (string, error) {
	if strings.TrimSpace(requested) == "" {
		return defaultInstallRoot(localAppData), nil
	}
	if !filepath.IsAbs(requested) {
		return "", errors.New("installation directory must be an absolute Windows path")
	}
	return filepath.Clean(requested), nil
}

func completionMessage(action string) string {
	message := fmt.Sprintf("AkuBrowser Runtime %s successfully.", action)
	if action == "uninstalled" || action == "fully reset" {
		return message
	}
	return message + "\n\nReturn to Chrome and select Check runtime in AkuBrowser Setup. " +
		"If an older portable AkuBrowser Runtime is still running, close it first."
}
