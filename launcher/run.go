package launcher

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

type RunOptions struct {
	InstallRoot          string
	DevelopmentWorkspace string
	VerifyOnly           bool
}

const (
	installedApplicationID   = "AI4U.AkuBrowser"
	developmentApplicationID = "AI4U.AkuBrowser.Development"
)

type ExitError struct {
	Code int
	Err  error
}

func (e *ExitError) Error() string { return e.Err.Error() }
func (e *ExitError) Unwrap() error { return e.Err }

func DefaultInstallRoot() (string, error) {
	executable, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("resolve launcher executable: %w", err)
	}
	return filepath.Dir(executable), nil
}

func Run(ctx context.Context, options RunOptions) error {
	if workspace := strings.TrimSpace(options.DevelopmentWorkspace); workspace != "" {
		if options.InstallRoot != "" || options.VerifyOnly {
			return errors.New("--development-workspace cannot be combined with --install-root or --verify-only")
		}
		if err := setCurrentApplicationID(developmentApplicationID); err != nil {
			return err
		}
		return runDevelopmentSupervisor(ctx, workspace)
	}
	if err := setCurrentApplicationID(installedApplicationID); err != nil {
		return err
	}
	root := options.InstallRoot
	if root == "" {
		var err error
		root, err = DefaultInstallRoot()
		if err != nil {
			return err
		}
	}
	tuple, err := LoadActiveTuple(root)
	if err != nil {
		return fmt.Errorf("AkuBrowser verification failed: %w", err)
	}
	if options.VerifyOnly {
		return nil
	}
	localAppData := os.Getenv("LOCALAPPDATA")
	paths, err := tuple.LaunchPaths(localAppData)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(paths.DataDirectory, 0o700); err != nil {
		return fmt.Errorf("create user data directory: %w", err)
	}
	if err := os.MkdirAll(paths.BrowserProfile, 0o700); err != nil {
		return fmt.Errorf("create browser profile directory: %w", err)
	}
	release, err := acquireInstance()
	if err != nil {
		return err
	}
	defer release()
	return runSidecar(ctx, tuple, paths)
}

func runSidecar(ctx context.Context, tuple Tuple, paths LaunchPaths) error {
	controlToken, err := newControlToken()
	if err != nil {
		return fmt.Errorf("create runtime control token: %w", err)
	}
	relaunchCommand, err := installedRelaunchCommand(tuple.InstallRoot)
	if err != nil {
		return err
	}
	args := append(tuple.SidecarArgs(paths),
		"--app-user-model-id", installedApplicationID,
		"--app-relaunch-command", relaunchCommand,
		"--app-relaunch-display-name", "AkuBrowser",
		"--runtime-control-token", controlToken,
	)
	command := exec.Command(paths.SidecarPath, args...)
	command.Dir = tuple.VersionRoot
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	if err := command.Start(); err != nil {
		return fmt.Errorf("start AkuSidecar: %w", err)
	}
	waitResult := make(chan error, 1)
	go func() { waitResult <- command.Wait() }()

	healthURL := fmt.Sprintf("http://%s:%d%s", tuple.Manifest.Health.Host, tuple.Manifest.Health.Port, tuple.Manifest.Health.Path)
	healthDeadline := time.NewTimer(time.Duration(tuple.Manifest.Health.TimeoutMS) * time.Millisecond)
	defer healthDeadline.Stop()
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()
	client := &http.Client{Timeout: time.Second}
	healthy := false
	for !healthy {
		select {
		case err := <-waitResult:
			return sidecarExitError(command, err, "exited before health became ready")
		case <-ctx.Done():
			stopOwnedProcess(command, waitResult, client, healthURL, controlToken)
			return nil
		case <-healthDeadline.C:
			stopOwnedProcess(command, waitResult, client, healthURL, controlToken)
			return fmt.Errorf("AkuSidecar health timeout after %dms at %s", tuple.Manifest.Health.TimeoutMS, healthURL)
		case <-ticker.C:
			status, version, err := checkHealth(client, healthURL)
			if err == nil && status == "ok" && version == tuple.Manifest.Version {
				healthy = true
				continue
			}
		}
	}
	select {
	case err := <-waitResult:
		return sidecarExitError(command, err, "exited after health became ready")
	case <-ctx.Done():
		stopOwnedProcess(command, waitResult, client, healthURL, controlToken)
		return nil
	}
}

func runDevelopmentSupervisor(ctx context.Context, workspace string) error {
	workspace, err := filepath.Abs(workspace)
	if err != nil {
		return fmt.Errorf("resolve development workspace: %w", err)
	}
	supervisor := filepath.Join(workspace, "AkuSupervisor", "target", "dev", "aku-supervisor.exe")
	info, err := os.Stat(supervisor)
	if err != nil {
		return fmt.Errorf("locate development AkuSupervisor at %s: %w", supervisor, err)
	}
	if info.IsDir() {
		return fmt.Errorf("development AkuSupervisor path is a directory: %s", supervisor)
	}
	command := exec.CommandContext(ctx, supervisor, "start", "akusidecar", "--actor", "user", "--reason", "AkuBrowser taskbar launch")
	command.Dir = filepath.Dir(supervisor)
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	if err := command.Run(); err != nil {
		return fmt.Errorf("start development AkuSidecar through AkuSupervisor: %w", err)
	}
	return nil
}

func installedRelaunchCommand(installRoot string) (string, error) {
	executable, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("resolve launcher executable for relaunch: %w", err)
	}
	quotedExecutable, err := quoteWindowsCommandArgument(executable)
	if err != nil {
		return "", err
	}
	quotedRoot, err := quoteWindowsCommandArgument(installRoot)
	if err != nil {
		return "", err
	}
	return quotedExecutable + " --install-root " + quotedRoot, nil
}

func quoteWindowsCommandArgument(value string) (string, error) {
	if strings.ContainsRune(value, '"') {
		return "", fmt.Errorf("Windows relaunch argument contains an unsupported quote: %q", value)
	}
	return `"` + value + `"`, nil
}

func checkHealth(client *http.Client, endpoint string) (string, string, error) {
	response, err := client.Get(endpoint)
	if err != nil {
		return "", "", err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return "", "", fmt.Errorf("health returned HTTP %d", response.StatusCode)
	}
	var payload struct {
		Status  string `json:"status"`
		Version string `json:"version"`
	}
	if err := json.NewDecoder(io.LimitReader(response.Body, 16*1024)).Decode(&payload); err != nil {
		return "", "", err
	}
	return payload.Status, payload.Version, nil
}

func sidecarExitError(command *exec.Cmd, waitErr error, context string) error {
	if waitErr == nil {
		return fmt.Errorf("AkuSidecar %s", context)
	}
	code := 1
	if command.ProcessState != nil {
		code = command.ProcessState.ExitCode()
		if code < 0 {
			code = 1
		}
	}
	return &ExitError{Code: code, Err: fmt.Errorf("AkuSidecar %s: %w", context, waitErr)}
}

func newControlToken() (string, error) {
	value := make([]byte, 32)
	if _, err := rand.Read(value); err != nil {
		return "", err
	}
	return hex.EncodeToString(value), nil
}

func requestCooperativeShutdown(client *http.Client, healthURL, controlToken string) bool {
	endpoint := strings.TrimSuffix(healthURL, "/api/health") + "/api/runtime/shutdown-if-idle"
	request, err := http.NewRequest(http.MethodPost, endpoint, nil)
	if err != nil {
		return false
	}
	request.Header.Set("X-Aku-Runtime-Control-Token", controlToken)
	response, err := client.Do(request)
	if err != nil {
		return false
	}
	defer response.Body.Close()
	return response.StatusCode == http.StatusAccepted
}

func stopOwnedProcess(command *exec.Cmd, waitResult <-chan error, client *http.Client, healthURL, controlToken string) {
	if command.Process == nil || command.ProcessState != nil {
		return
	}
	_ = requestCooperativeShutdown(client, healthURL, controlToken)
	select {
	case <-waitResult:
		return
	case <-time.After(3 * time.Second):
		_ = command.Process.Kill()
		select {
		case <-waitResult:
		case <-time.After(2 * time.Second):
		}
	}
}

// NotifyContext is kept in this package so the command entry point and tests
// share the same cooperative cancellation boundary.
func SignalContext(parent context.Context) (context.Context, context.CancelFunc) {
	return signal.NotifyContext(parent, os.Interrupt, syscall.SIGTERM)
}
