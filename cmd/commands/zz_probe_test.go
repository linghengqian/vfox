//go:build windows

package commands

import (
	"flag"
	"os"
	"testing"
)

// PROBE, not for merging: make the Windows run of this package print every test
// and then fail, so that the log of a plain `go test ./...` shows which tests
// ran and which were skipped, and why.
func TestMain(m *testing.M) {
	// The children that the CLI tests start print what the tests parse.
	if os.Getenv("VFOX_TEST_CLI") == "1" || os.Getenv("VFOX_TEST_ENV_COMMAND") == "1" {
		os.Exit(m.Run())
	}
	testing.Init()
	_ = flag.Set("test.v", "true")
	code := m.Run()
	println("PROBE: forcing a failure so that go test prints the output above; the real exit code was", code)
	os.Exit(1)
}
