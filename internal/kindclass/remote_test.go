package kindclass

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestParseModelContentStripsFence(t *testing.T) {
	raw := "```json\n{\"kind\":\"opinion\",\"reason\":\"Opinião: o autor defende uma posição sobre a tarifa.\"}\n```"
	got, err := ParseModelContent(raw)
	if err != nil {
		t.Fatal(err)
	}
	if got.Kind != KindOpinion {
		t.Fatal(got.Kind)
	}
}

func TestParseModelContentRejectsTruthLabel(t *testing.T) {
	_, err := ParseModelContent(`{"kind":"false","reason":"o texto não se sustenta nas fontes citadas"}`)
	if err == nil {
		t.Fatal("kind fora da tag foi aceito")
	}
}

func TestClassifyRemoteReadsJSON(t *testing.T) {
	var sawAuth, sawPrompt bool
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" {
			t.Errorf("path %s", r.URL.Path)
		}
		sawAuth = r.Header.Get("Authorization") == "Bearer segredo"
		body, _ := io.ReadAll(r.Body)
		sawPrompt = strings.Contains(string(body), "Não julgue se o texto é verdadeiro")
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"choices":[{"message":{"content":"{\"kind\":\"report\",\"reason\":\"Reportagem: o texto relata a votação, sem posição do autor.\"}"}}]}`)
	}))
	defer srv.Close()

	got, err := ClassifyRemote(context.Background(), srv.URL+"/v1", "segredo", "modelo-teste", "O plenário aprovou o texto.", true)
	if err != nil {
		t.Fatal(err)
	}
	if got.Kind != KindReport || !sawAuth || !sawPrompt {
		t.Fatalf("got=%+v auth=%v prompt=%v", got, sawAuth, sawPrompt)
	}
}

func TestClassifyRemoteRejectsInsecureURL(t *testing.T) {
	_, err := ClassifyRemote(context.Background(), "http://modelo.example/v1", "k", "m", "texto", false)
	if err == nil {
		t.Fatal("http em produção foi aceito")
	}
}
