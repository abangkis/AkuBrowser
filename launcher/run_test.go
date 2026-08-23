package launcher

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestNewControlTokenMatchesSidecarContract(t *testing.T) {
	token, err := newControlToken()
	if err != nil {
		t.Fatal(err)
	}
	if len(token) != 64 || token != strings.ToLower(token) {
		t.Fatalf("control token has unexpected shape: %q", token)
	}
}

func TestRequestCooperativeShutdownUsesScopedToken(t *testing.T) {
	const token = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodPost || request.URL.Path != "/api/runtime/shutdown-if-idle" {
			t.Fatalf("unexpected shutdown request: %s %s", request.Method, request.URL.Path)
		}
		if got := request.Header.Get("X-Aku-Runtime-Control-Token"); got != token {
			t.Fatalf("runtime control token=%q", got)
		}
		w.WriteHeader(http.StatusAccepted)
	}))
	defer server.Close()
	if !requestCooperativeShutdown(server.Client(), server.URL+"/api/health", token) {
		t.Fatal("cooperative shutdown was not accepted")
	}
}
