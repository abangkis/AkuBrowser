//go:build !windows

package launcher

func acquireInstance() (func(), error)     { return func() {}, nil }
func setCurrentApplicationID(string) error { return nil }
