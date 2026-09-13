package launcher

import (
	"context"
	"errors"
	"reflect"
	"strings"
	"testing"
)

func TestDatabasePreflightChoices(t *testing.T) {
	tests := []struct {
		name       string
		status     string
		choice     databaseChoice
		prepared   databaseCompatibilityReport
		wantStart  bool
		wantCalls  []string
		wantPrompt bool
		wantError  string
		noIdentity bool
	}{
		{name: "absent starts", status: "absent", wantStart: true, wantCalls: []string{"--database-inspect"}},
		{name: "current starts", status: "current", wantStart: true, wantCalls: []string{"--database-inspect"}},
		{name: "keep migratable", status: "migratable", choice: choiceKeep, wantCalls: []string{"--database-inspect"}, wantPrompt: true},
		{name: "migrate", status: "migratable", choice: choiceMigrate, prepared: databaseCompatibilityReport{SchemaVersion: 1, Status: "current", TargetSchemaVersion: 25, BackupPath: "backup.db"}, wantStart: true, wantCalls: []string{"--database-inspect", "--database-action=migrate", "--database-confirm", "--database-expected-fingerprint", "fixture-fingerprint"}, wantPrompt: true},
		{name: "fresh unsupported", status: "unsupported", choice: choiceFresh, prepared: databaseCompatibilityReport{SchemaVersion: 1, Status: "absent", TargetSchemaVersion: 25, BackupPath: "backup.db"}, wantStart: true, wantCalls: []string{"--database-inspect", "--database-action=fresh", "--database-confirm", "--database-expected-fingerprint", "fixture-fingerprint"}, wantPrompt: true},
		{name: "keep newer", status: "newer", choice: choiceKeep, wantCalls: []string{"--database-inspect"}, wantPrompt: true},
		{name: "keep unknown", status: "unknown", choice: choiceKeep, wantCalls: []string{"--database-inspect"}, wantPrompt: true},
		{name: "cannot migrate newer", status: "newer", choice: choiceMigrate, wantCalls: []string{"--database-inspect"}, wantPrompt: true, wantError: "unavailable"},
		{name: "missing backup stops", status: "migratable", choice: choiceMigrate, prepared: databaseCompatibilityReport{SchemaVersion: 1, Status: "current", TargetSchemaVersion: 25}, wantCalls: []string{"--database-inspect", "--database-action=migrate", "--database-confirm", "--database-expected-fingerprint", "fixture-fingerprint"}, wantPrompt: true, wantError: "backup"},
		{name: "unverifiable unknown refuses fresh", status: "unknown", choice: choiceFresh, noIdentity: true, wantCalls: []string{"--database-inspect"}, wantPrompt: true, wantError: "identity"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			var calls []string
			prompted := false
			command := func(_ context.Context, _ Tuple, _ LaunchPaths, args ...string) (databaseCompatibilityReport, error) {
				calls = append(calls, args...)
				if len(args) == 1 {
					identity := "fixture-fingerprint"
					if tc.noIdentity {
						identity = ""
					}
					return databaseCompatibilityReport{SchemaVersion: 1, Status: tc.status, DatabaseSchemaVersion: 7, TargetSchemaVersion: 25, Fingerprint: identity}, nil
				}
				return tc.prepared, nil
			}
			prompt := func(_ databaseCompatibilityReport, _ string) (databaseChoice, error) {
				prompted = true
				return tc.choice, nil
			}
			started, err := prepareInstalledDatabaseWith(context.Background(), Tuple{}, LaunchPaths{}, command, prompt, func(databaseChoice, string) {})
			if started != tc.wantStart || prompted != tc.wantPrompt || !reflect.DeepEqual(calls, tc.wantCalls) {
				t.Fatalf("started=%v prompted=%v calls=%v; want started=%v prompted=%v calls=%v", started, prompted, calls, tc.wantStart, tc.wantPrompt, tc.wantCalls)
			}
			if tc.wantError == "" && err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if tc.wantError != "" && (err == nil || !strings.Contains(err.Error(), tc.wantError)) {
				t.Fatalf("error=%v, want containing %q", err, tc.wantError)
			}
		})
	}
}

func TestDatabasePreflightProbeFailureStopsBeforePrompt(t *testing.T) {
	prompted := false
	command := func(context.Context, Tuple, LaunchPaths, ...string) (databaseCompatibilityReport, error) {
		return databaseCompatibilityReport{}, errors.New("probe failed")
	}
	prompt := func(databaseCompatibilityReport, string) (databaseChoice, error) {
		prompted = true
		return choiceFresh, nil
	}
	started, err := prepareInstalledDatabaseWith(context.Background(), Tuple{}, LaunchPaths{}, command, prompt, func(databaseChoice, string) {})
	if started || prompted || err == nil || !strings.Contains(err.Error(), "probe failed") {
		t.Fatalf("started=%v prompted=%v err=%v", started, prompted, err)
	}
}
