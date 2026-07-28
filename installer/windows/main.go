package main

import (
	"embed"
	"errors"
	"flag"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
)

//go:embed payload
var embeddedPayload embed.FS

func main() {
	os.Exit(runInstaller())
}

func runInstaller() int {
	var (
		repair    = flag.Bool("repair", false, "repair the current AkuBrowser Runtime installation")
		uninstall = flag.Bool("uninstall", false, "uninstall AkuBrowser Runtime while preserving user data")
		quiet     = flag.Bool("quiet", false, "suppress completion UI")
	)
	flag.Parse()
	if *repair && *uninstall {
		finish(*quiet, errors.New("repair and uninstall cannot be requested together"))
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
	executable, err := os.Executable()
	if err != nil {
		finish(*quiet, err)
		return 2
	}
	installer := Installer{
		Payload:          payload,
		Manifest:         manifest,
		InstallRoot:      defaultInstallRoot(localAppData),
		DataRoot:         filepath.Join(localAppData, "AkuBrowser", "data"),
		SourceExecutable: executable,
		Registry:         WindowsRegistry{},
	}
	action := "installed"
	if *uninstall {
		action = "uninstalled"
		err = installer.Uninstall()
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
	finish(*quiet, nil, fmt.Sprintf("AkuBrowser Runtime %s successfully.", action))
	return 0
}
