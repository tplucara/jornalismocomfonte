package auth

import (
	"strings"
	"testing"

	"golang.org/x/crypto/bcrypt"
)

func TestHashPasswordRoundTrip(t *testing.T) {
	hash, err := HashPassword("uma frase longa")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(hash, "$argon2id$") {
		t.Fatalf("formato: %s", hash)
	}
	ok, err := CheckPassword(hash, "uma frase longa")
	if err != nil || !ok {
		t.Fatalf("acerto: ok=%v err=%v", ok, err)
	}
	ok, err = CheckPassword(hash, "outra frase longa")
	if err != nil || ok {
		t.Fatalf("erro: ok=%v err=%v", ok, err)
	}
}

func TestCheckPasswordAcceptsBcryptSeed(t *testing.T) {
	hash, err := bcrypt.GenerateFromPassword([]byte("jcf-dev-123"), bcrypt.MinCost)
	if err != nil {
		t.Fatal(err)
	}
	ok, err := CheckPassword(string(hash), "jcf-dev-123")
	if err != nil || !ok {
		t.Fatalf("bcrypt: ok=%v err=%v", ok, err)
	}
	ok, err = CheckPassword(string(hash), "senha-errada-12")
	if err != nil || ok {
		t.Fatalf("bcrypt recusa: ok=%v err=%v", ok, err)
	}
}

func TestCheckPasswordUnknownHashIsFailure(t *testing.T) {
	ok, err := CheckPassword("texto-puro", "uma frase longa")
	if err != nil || ok {
		t.Fatalf("hash desconhecido: ok=%v err=%v", ok, err)
	}
}

func TestSessionHashHidesToken(t *testing.T) {
	h := SessionHash("token-do-cookie")
	if h == "token-do-cookie" || len(h) != 64 {
		t.Fatalf("hash: %s", h)
	}
	if SessionHash("token-do-cookie") != h {
		t.Fatal("hash instável")
	}
}
