package httpx

import (
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

func TestSecureHeadersSetsStrictCSPWithNonce(t *testing.T) {
	var seenNonce string
	h := SecureHeaders(true)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seenNonce = Nonce(r.Context())
		w.WriteHeader(http.StatusOK)
	}))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))

	if seenNonce == "" {
		t.Fatal("nonce não foi gerado")
	}
	csp := rec.Header().Get("Content-Security-Policy")
	for _, want := range []string{
		"default-src 'none'",
		"script-src 'nonce-" + seenNonce + "'",
		"frame-ancestors 'none'",
		"base-uri 'none'",
		"form-action 'self'",
	} {
		if !strings.Contains(csp, want) {
			t.Errorf("CSP sem %q: %s", want, csp)
		}
	}
	if strings.Contains(csp, "unsafe-inline") || strings.Contains(csp, "unsafe-eval") {
		t.Errorf("CSP não pode conter unsafe-*: %s", csp)
	}
	for k, want := range map[string]string{
		"X-Content-Type-Options":     "nosniff",
		"X-Frame-Options":            "DENY",
		"Referrer-Policy":            "strict-origin-when-cross-origin",
		"Cross-Origin-Opener-Policy": "same-origin",
		"Strict-Transport-Security":  "max-age=63072000; includeSubDomains; preload",
	} {
		if got := rec.Header().Get(k); got != want {
			t.Errorf("%s = %q, quer %q", k, got, want)
		}
	}
}

func TestNonceIsUniquePerRequest(t *testing.T) {
	seen := map[string]bool{}
	h := SecureHeaders(false)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seen[Nonce(r.Context())] = true
	}))
	for range 50 {
		h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/", nil))
	}
	if len(seen) != 50 {
		t.Fatalf("esperava 50 nonces distintos, obtive %d", len(seen))
	}
}

func TestHashClientIPNeverExposesRawIP(t *testing.T) {
	var got string
	h := HashClientIP("salt")(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got = IPHash(r.Context())
	}))
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.RemoteAddr = "203.0.113.9:51234"
	h.ServeHTTP(httptest.NewRecorder(), req)
	if got == "" || strings.Contains(got, "203.0.113.9") {
		t.Fatalf("hash inválido ou vazou IP: %q", got)
	}
}

func TestMaxBodyRejectsOversizedBody(t *testing.T) {
	h := MaxBody(8)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		buf := make([]byte, 64)
		_, err := r.Body.Read(buf)
		if err == nil {
			t.Error("esperava erro de corpo grande demais")
		}
	}))
	req := httptest.NewRequest(http.MethodPost, "/", strings.NewReader(strings.Repeat("x", 64)))
	h.ServeHTTP(httptest.NewRecorder(), req)
}

func TestRecoverReturnsGenericError(t *testing.T) {
	log := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelError + 1}))
	h := Recover(log)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		panic("segredo: senha=123")
	}))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status %d", rec.Code)
	}
	if strings.Contains(rec.Body.String(), "senha") {
		t.Fatal("resposta vazou detalhe do pânico")
	}
}
