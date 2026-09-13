//go:build !windows

package launcher

import "errors"

func promptDatabaseChoice(databaseCompatibilityReport, string) (databaseChoice, error) {
	return choiceKeep, errors.New("database recovery requires the interactive Windows installed-app launcher")
}

func showDatabasePreflightError(error, string, error) {}
func showDatabasePrepared(databaseChoice, string)     {}
