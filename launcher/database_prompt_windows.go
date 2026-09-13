//go:build windows

package launcher

import (
	"fmt"
	"strings"

	"golang.org/x/sys/windows"
)

const (
	messageBoxCancel = 2
	messageBoxYes    = 6
	messageBoxNo     = 7
)

func promptDatabaseChoice(report databaseCompatibilityReport, path string) (databaseChoice, error) {
	version := "unknown"
	if report.DatabaseSchemaVersion > 0 {
		version = fmt.Sprintf("%d", report.DatabaseSchemaVersion)
	}
	intro := fmt.Sprintf("AkuBrowser found an existing database.\n\nLocation: %s\nDatabase schema: %s\nRequired schema: %d\nStatus: %s", path, version, report.TargetSchemaVersion, report.Status)
	if reason := strings.TrimSpace(report.Reason); reason != "" {
		intro += "\nDetails: " + reason
	}
	if strings.TrimSpace(report.Fingerprint) == "" {
		_, err := databaseMessageBox(intro+"\n\nAkuBrowser cannot safely verify this database's identity, so no migration or reset is available. The database has been kept unchanged. Close other programs using it, check file access, then try again.", windows.MB_OK|windows.MB_ICONERROR)
		return choiceKeep, err
	}
	if report.Status == "migratable" {
		response, err := databaseMessageBox(intro+"\n\nYes: Make a backup and migrate, then open AkuBrowser.\nNo: Archive the old database and start with a new one.\nCancel: Keep the database unchanged and exit.", windows.MB_YESNOCANCEL|windows.MB_ICONWARNING|windows.MB_DEFBUTTON3)
		if err != nil {
			return choiceKeep, err
		}
		switch response {
		case messageBoxYes:
			return choiceMigrate, nil
		case messageBoxNo:
			return confirmFreshDatabase()
		case messageBoxCancel:
			return choiceKeep, nil
		}
		return choiceKeep, fmt.Errorf("unexpected database dialog response %d", response)
	}
	response, err := databaseMessageBox(intro+"\n\nThis database cannot be migrated by the installed AkuBrowser version.\n\nYes: Archive the old database and start with a new one.\nNo: Keep the database unchanged and exit.", windows.MB_YESNO|windows.MB_ICONWARNING|windows.MB_DEFBUTTON2)
	if err != nil {
		return choiceKeep, err
	}
	switch response {
	case messageBoxYes:
		return confirmFreshDatabase()
	case messageBoxNo:
		return choiceKeep, nil
	}
	return choiceKeep, fmt.Errorf("unexpected database dialog response %d", response)
}

func confirmFreshDatabase() (databaseChoice, error) {
	response, err := databaseMessageBox("Start AkuBrowser with an empty database? The existing database will be archived first, not permanently deleted. Your isolated browser profile and sign-in sessions will not be removed.\n\nYes: Archive and start fresh.\nNo: Keep the database unchanged and exit.", windows.MB_YESNO|windows.MB_ICONWARNING|windows.MB_DEFBUTTON2)
	if err != nil {
		return choiceKeep, err
	}
	if response == messageBoxYes {
		return choiceFresh, nil
	}
	if response == messageBoxNo {
		return choiceKeep, nil
	}
	return choiceKeep, fmt.Errorf("unexpected fresh database dialog response %d", response)
}

func showDatabasePreflightError(err error) {
	_, _ = databaseMessageBox("AkuBrowser could not safely prepare its database. No automatic reset was performed.\n\n"+err.Error(), windows.MB_OK|windows.MB_ICONERROR)
}

func showDatabasePrepared(choice databaseChoice, backupPath string) {
	operation := "migrated"
	if choice == choiceFresh {
		operation = "archived before starting fresh"
	}
	_, _ = databaseMessageBox("Your previous database was "+operation+".\n\nRecoverable archive: "+backupPath+"\n\nAkuBrowser will now start.", windows.MB_OK|windows.MB_ICONINFORMATION)
}

func databaseMessageBox(message string, flags uint32) (int32, error) {
	text, err := windows.UTF16PtrFromString(message)
	if err != nil {
		return 0, err
	}
	title, err := windows.UTF16PtrFromString("AkuBrowser database")
	if err != nil {
		return 0, err
	}
	return windows.MessageBox(0, text, title, flags)
}
