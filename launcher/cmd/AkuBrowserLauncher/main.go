package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"

	"github.com/abangkis/AkuBrowser/launcher"
)

func main() {
	installRoot := flag.String("install-root", "", "installed AkuBrowser root (defaults to the launcher directory)")
	developmentWorkspace := flag.String("development-workspace", "", "development workspace containing AkuSupervisor")
	verifyOnly := flag.Bool("verify-only", false, "verify the active tuple and exit without starting AkuSidecar")
	flag.Parse()
	ctx, cancel := launcher.SignalContext(context.Background())
	defer cancel()
	err := launcher.Run(ctx, launcher.RunOptions{
		InstallRoot:          *installRoot,
		DevelopmentWorkspace: *developmentWorkspace,
		VerifyOnly:           *verifyOnly,
	})
	if err == nil {
		return
	}
	var exitErr *launcher.ExitError
	if errors.As(err, &exitErr) {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(exitErr.Code)
	}
	fmt.Fprintln(os.Stderr, err)
	os.Exit(2)
}
