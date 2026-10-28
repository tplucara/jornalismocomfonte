package web

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"jornalismocomfonte/internal/config"
)

func TestSignupPageIsOptIn(t *testing.T) {
	h := testServer(t).Handler(config.Config{Env: "dev", IPHashSalt: "test", MaxBodyBytes: 1 << 20})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/cadastro", nil)
	req.RemoteAddr = "127.0.0.1:9"
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d", rec.Code)
	}
	body := rec.Body.String()
	if rec.Header().Get("Set-Cookie") != "" {
		t.Fatal("o formulário anônimo não define cookie")
	}
	for _, want := range []string{"accept_terms", "accept_privacy", "accept_content", "name=\"adult\"", "Criar conta"} {
		if !strings.Contains(body, want) {
			t.Fatalf("faltou %s", want)
		}
	}
	if strings.Contains(body, "checked") {
		t.Fatal("aceite veio marcado")
	}
}

func TestSignupRejectsMissingAcceptance(t *testing.T) {
	h := testServer(t).Handler(config.Config{Env: "dev", IPHashSalt: "test", MaxBodyBytes: 1 << 20})
	form := url.Values{
		"display_name":     {"Ana Ribeiro"},
		"email":            {"ana.nova@jcf.example"},
		"password":         {"uma frase longa"},
		"password_confirm": {"uma frase longa"},
	}
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/cadastro", strings.NewReader(form.Encode()))
	req.RemoteAddr = "127.0.0.1:9"
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Sec-Fetch-Site", "same-origin")
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("status %d body %s", rec.Code, rec.Body.String())
	}
	if rec.Header().Get("Set-Cookie") != "" {
		t.Fatal("recusa não pode abrir sessão")
	}
	body := rec.Body.String()
	if !strings.Contains(body, "18 anos") || !strings.Contains(body, "termos de uso") {
		t.Fatalf("erros: %s", body)
	}
	if strings.Contains(body, "uma frase longa") {
		t.Fatal("a senha voltou no HTML")
	}
}

func TestSignupValidation(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/cadastro", strings.NewReader(url.Values{
		"display_name":     {"Ana"},
		"email":            {"nao-e-email"},
		"password":         {"curta"},
		"password_confirm": {"curta"},
	}.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	form, err := parseSignup(req)
	if err != nil {
		t.Fatal(err)
	}
	if form.ok() {
		t.Fatal("formulário inválido passou")
	}
	if form.ErrEmail == "" || form.ErrPassword == "" || form.ErrAdult == "" {
		t.Fatalf("%+v", form)
	}
}
