package web

import (
	"bytes"
	"html/template"
	"image"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"jornalismocomfonte/internal/config"
	"jornalismocomfonte/internal/db"
)

func testServer(t *testing.T) *Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelError + 1}))
	return New(nil, nil, log, nil)
}

func TestHealthz(t *testing.T) {
	h := testServer(t).Routes()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "ok") {
		t.Fatalf("healthz: %d %s", rec.Code, rec.Body.String())
	}
}

func TestReadyzWithoutPoolIs503(t *testing.T) {
	h := testServer(t).Routes()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("readyz: %d", rec.Code)
	}
}

func TestInvalidArticleIDIs404HTML(t *testing.T) {
	h := testServer(t).Routes()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/a/nao-e-uuid", nil))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status %d", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); !strings.Contains(ct, "text/html") {
		t.Fatalf("content-type %s", ct)
	}
	if strings.Contains(rec.Body.String(), "sql") || strings.Contains(rec.Body.String(), "pq:") {
		t.Fatal("404 vazou detalhe interno")
	}
}

func TestSecurityTxtAndRobots(t *testing.T) {
	h := testServer(t).Routes()
	for _, path := range []string{"/.well-known/security.txt", "/robots.txt"} {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		if rec.Code != http.StatusOK {
			t.Fatalf("%s: %d", path, rec.Code)
		}
	}
}

func TestPublicHandlerSetsCSP(t *testing.T) {
	cfg := config.Config{Env: "dev", IPHashSalt: "test", MaxBodyBytes: 1024}
	h := testServer(t).Handler(cfg)
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	req.RemoteAddr = "127.0.0.1:9"
	h.ServeHTTP(rec, req)
	csp := rec.Header().Get("Content-Security-Policy")
	if !strings.Contains(csp, "default-src 'none'") {
		t.Fatalf("CSP: %s", csp)
	}
	if rec.Header().Get("Set-Cookie") != "" {
		t.Fatal("página pública não pode definir cookie")
	}
}

func TestKindAndRemovalLabels(t *testing.T) {
	if kindLabel(db.ArticleKindAnalysis) != "Análise" {
		t.Fatal(kindLabel(db.ArticleKindAnalysis))
	}
	if journalistStatusLabel(db.JournalistStatusVerified) != "" {
		t.Fatal("status verified não gera selo público")
	}
	if journalistStatusLabel(db.JournalistStatusSuspended) != "Conta suspensa" {
		t.Fatal(journalistStatusLabel(db.JournalistStatusSuspended))
	}
}

func TestSniffJPEGOrPNG(t *testing.T) {
	if !sniffJPEGOrPNG([]byte{0xff, 0xd8, 0xff, 0xe0}) {
		t.Fatal("JPEG não reconhecido")
	}
	if !sniffJPEGOrPNG([]byte{0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a}) {
		t.Fatal("PNG não reconhecido")
	}
	if sniffJPEGOrPNG([]byte("not-an-image")) {
		t.Fatal("lixo aceito")
	}
}

func TestResizeMaxShrinks(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 2000, 1000))
	out := resizeMax(img, 512)
	b := out.Bounds()
	if b.Dx() != 512 || b.Dy() != 256 {
		t.Fatalf("got %dx%d", b.Dx(), b.Dy())
	}
}

func TestBodyAllowsNewlines(t *testing.T) {
	if hasDangerousControl("linha um\nlinha dois\r\n\tfim") {
		t.Fatal("quebra de linha no corpo rejeitada")
	}
	if !hasDangerousControl("com\x00nulo") {
		t.Fatal("NUL aceito")
	}
}

func TestSameOriginAvatarRejectsHotlink(t *testing.T) {
	if got := sameOriginAvatar("https://avatars.example/ana.png"); got != "" {
		t.Fatalf("hotlink aceito: %q", got)
	}
	if got := sameOriginAvatar("/static/avatars/../app.css"); got != "" {
		t.Fatalf("caminho relativo aceito: %q", got)
	}
	if got := sameOriginAvatar("/static/avatars/ana.svg"); got != "/static/avatars/ana.svg" {
		t.Fatalf("retrato local recusado: %q", got)
	}
	if got := sameOriginAvatar("/media/a/10000000-0000-4000-8000-000000000001.jpg"); got == "" {
		t.Fatal("avatar enviado recusado")
	}
	if got := sameOriginAvatar("/media/a/../secret.jpg"); got != "" {
		t.Fatalf("traversal aceito: %q", got)
	}
}

func TestSearchRejectsBadFilterBeforeQuery(t *testing.T) {
	h := testServer(t).Routes()
	for _, path := range []string{"/busca?tipo=falso", "/busca?de=32-13-99", "/busca?jornalista=nao-e-uuid"} {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("%s: %d", path, rec.Code)
		}
	}
}

func TestLikeContainsEscapesWildcards(t *testing.T) {
	if got := likeContains(`100%_a\b`); got != `%100\%\_a\\b%` {
		t.Fatalf("like: %q", got)
	}
}

func TestJSONLDRendersAsObjectNotJSString(t *testing.T) {
	rd := newRenderer(slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelError + 1})))
	var buf bytes.Buffer
	p := page{
		Title:  "t",
		JSONLD: template.JS(`{"@type":"NewsArticle","headline":"x"}`),
		Path:   "/",
	}
	if err := rd.tpl.ExecuteTemplate(&buf, "header", p); err != nil {
		t.Fatal(err)
	}
	body := buf.String()
	if strings.Contains(body, `\"@type\"`) || strings.Contains(body, `"{"@type"`) {
		t.Fatalf("JSON-LD citado como string JS: %s", body)
	}
	if !strings.Contains(body, `"@type":"NewsArticle"`) {
		t.Fatalf("JSON-LD ausente: %s", body)
	}
}
