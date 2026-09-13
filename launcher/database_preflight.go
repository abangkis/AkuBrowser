package launcher

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// databaseCompatibilityReport is emitted by the active Sidecar binary. The
// launcher deliberately does not maintain an independent schema allowlist.
type databaseCompatibilityReport struct {
	SchemaVersion         int    `json:"schemaVersion"`
	Status                string `json:"status"`
	DatabaseSchemaVersion int    `json:"databaseSchemaVersion"`
	TargetSchemaVersion   int    `json:"targetSchemaVersion"`
	Reason                string `json:"reason"`
	Fingerprint           string `json:"fingerprint"`
	BackupPath            string `json:"backupPath"`
}

type databaseChoice string

const (
	choiceKeep    databaseChoice = "keep"
	choiceMigrate databaseChoice = "migrate"
	choiceFresh   databaseChoice = "fresh"
)

func prepareInstalledDatabase(ctx context.Context, tuple Tuple, paths LaunchPaths) (bool, error) {
	return prepareInstalledDatabaseWith(ctx, tuple, paths, sidecarDatabaseCommand, promptDatabaseChoice, showDatabasePrepared)
}

type databaseCommandFunc func(context.Context, Tuple, LaunchPaths, ...string) (databaseCompatibilityReport, error)
type databasePromptFunc func(databaseCompatibilityReport, string) (databaseChoice, error)
type databasePreparedFunc func(databaseChoice, string)

func prepareInstalledDatabaseWith(ctx context.Context, tuple Tuple, paths LaunchPaths, command databaseCommandFunc, prompt databasePromptFunc, preparedNotice databasePreparedFunc) (bool, error) {
	report, err := command(ctx, tuple, paths, "--database-inspect")
	if err != nil {
		return false, fmt.Errorf("inspect existing AkuBrowser database: %w", err)
	}
	if err := validateDatabaseReport(report); err != nil {
		return false, err
	}
	switch report.Status {
	case "absent", "current":
		return true, nil
	case "migratable", "unsupported", "newer", "unknown":
		choice, err := prompt(report, paths.DatabasePath)
		if err != nil {
			return false, err
		}
		if choice == choiceKeep {
			return false, nil
		}
		if choice == choiceMigrate && report.Status != "migratable" {
			return false, errors.New("migration is unavailable for this database")
		}
		if choice != choiceMigrate && choice != choiceFresh {
			return false, fmt.Errorf("unsupported database choice %q", choice)
		}
		if strings.TrimSpace(report.Fingerprint) == "" {
			return false, errors.New("database identity could not be verified; the original was kept unchanged")
		}
		prepared, err := command(ctx, tuple, paths, "--database-action="+string(choice), "--database-confirm", "--database-expected-fingerprint", report.Fingerprint)
		if err != nil {
			return false, fmt.Errorf("prepare AkuBrowser database: %w", err)
		}
		if err := validateDatabaseReport(prepared); err != nil {
			return false, err
		}
		expected := "current"
		if choice == choiceFresh {
			expected = "absent"
		}
		if prepared.Status != expected || strings.TrimSpace(prepared.BackupPath) == "" {
			return false, fmt.Errorf("database preparation did not confirm a %s state with a backup", expected)
		}
		preparedNotice(choice, prepared.BackupPath)
		return true, nil
	default:
		return false, fmt.Errorf("unrecognized database compatibility status %q", report.Status)
	}
}

func sidecarDatabaseCommand(ctx context.Context, tuple Tuple, paths LaunchPaths, actionArgs ...string) (databaseCompatibilityReport, error) {
	// Use the same active-tuple configuration as the eventual runtime so the
	// compatibility decision cannot be based on a different config/database.
	args := append(tuple.SidecarArgs(paths), actionArgs...)
	command := exec.CommandContext(ctx, paths.SidecarPath, args...)
	command.Dir = tuple.VersionRoot
	output, err := command.Output()
	if err != nil {
		var exit *exec.ExitError
		if errors.As(err, &exit) {
			message := strings.TrimSpace(string(append(output, exit.Stderr...)))
			if message != "" {
				if len(message) > 4096 {
					message = message[:4096] + "..."
				}
				return databaseCompatibilityReport{}, fmt.Errorf("%s: %w", message, err)
			}
		}
		return databaseCompatibilityReport{}, err
	}
	if len(output) > 64*1024 {
		return databaseCompatibilityReport{}, errors.New("database inspection response is too large")
	}
	var report databaseCompatibilityReport
	if err := json.Unmarshal(output, &report); err != nil {
		return databaseCompatibilityReport{}, fmt.Errorf("parse database inspection response: %w", err)
	}
	return report, nil
}

func validateDatabaseReport(report databaseCompatibilityReport) error {
	if report.SchemaVersion != 1 {
		return fmt.Errorf("unsupported database inspection contract version %d", report.SchemaVersion)
	}
	if report.TargetSchemaVersion <= 0 {
		return errors.New("database inspection omitted the target schema")
	}
	if report.DatabaseSchemaVersion < 0 {
		return errors.New("database inspection returned a negative schema version")
	}
	return nil
}

func writeDatabaseDiagnostic(dataDirectory string, failure error) (string, error) {
	path := filepath.Join(dataDirectory, "database-recovery.log")
	file, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return "", err
	}
	message := failure.Error()
	if len(message) > 4096 {
		message = message[:4096] + "..."
	}
	_, writeErr := fmt.Fprintf(file, "%s %s\n", time.Now().UTC().Format(time.RFC3339), message)
	closeErr := file.Close()
	if writeErr != nil {
		return "", writeErr
	}
	if closeErr != nil {
		return "", closeErr
	}
	return path, nil
}
