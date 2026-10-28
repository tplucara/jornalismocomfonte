// Package auth guarda senha e o identificador técnico da sessão.
// Argon2id com os parâmetros do OWASP Password Storage Cheat Sheet: 19 MiB, 2 iterações, paralelismo 1.
package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"

	"golang.org/x/crypto/argon2"
	"golang.org/x/crypto/bcrypt"
)

const (
	MinPasswordRunes = 12
	MaxPasswordBytes = 128

	argonMemory  = 19 * 1024
	argonTime    = 2
	argonThreads = 1
	argonKeyLen  = 32
	argonSaltLen = 16
)

// dummyHash iguala o tempo de uma senha inexistente ao de uma senha Argon2id real.
var dummyHash = mustHash("dummy-password-not-a-secret")

func mustHash(password string) string {
	h, err := HashPassword(password)
	if err != nil {
		panic(err)
	}
	return h
}

// HashPassword devolve o hash no formato PHC. A senha em claro não é armazenada.
func HashPassword(password string) (string, error) {
	salt := make([]byte, argonSaltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	sum := argon2.IDKey([]byte(password), salt, argonTime, argonMemory, argonThreads, argonKeyLen)
	return fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version, argonMemory, argonTime, argonThreads,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(sum),
	), nil
}

// CheckPassword confere Argon2id e, para contas já gravadas com bcrypt no seed, o hash antigo.
// Senha ausente ou longa demais falha sem revelar se a conta existe.
func CheckPassword(encoded, password string) (bool, error) {
	if password == "" || len(password) > MaxPasswordBytes {
		encoded = dummyHash
	}
	switch {
	case strings.HasPrefix(encoded, "$argon2id$"):
		return verifyArgon2id(encoded, password)
	case strings.HasPrefix(encoded, "$2a$"), strings.HasPrefix(encoded, "$2b$"), strings.HasPrefix(encoded, "$2y$"):
		err := bcrypt.CompareHashAndPassword([]byte(encoded), []byte(password))
		if err == nil {
			return true, nil
		}
		if errors.Is(err, bcrypt.ErrMismatchedHashAndPassword) || errors.Is(err, bcrypt.ErrPasswordTooLong) {
			return false, nil
		}
		return false, err
	default:
		_, err := verifyArgon2id(dummyHash, password)
		return false, err
	}
}

func verifyArgon2id(encoded, password string) (bool, error) {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[1] != "argon2id" {
		return false, errors.New("hash argon2id malformado")
	}
	var version int
	if _, err := fmt.Sscanf(parts[2], "v=%d", &version); err != nil || version != argon2.Version {
		return false, errors.New("versão argon2id inesperada")
	}
	var memory, timeCost uint32
	var threads uint8
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &memory, &timeCost, &threads); err != nil {
		return false, errors.New("parâmetros argon2id malformados")
	}
	if memory == 0 || memory > 64*1024 || timeCost == 0 || timeCost > 8 || threads == 0 || threads > 4 {
		return false, errors.New("parâmetros argon2id fora do limite")
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil || len(salt) < 16 {
		return false, errors.New("salt argon2id inválido")
	}
	want, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil || len(want) == 0 {
		return false, errors.New("hash argon2id inválido")
	}
	got := argon2.IDKey([]byte(password), salt, timeCost, memory, threads, uint32(len(want)))
	if subtle.ConstantTimeCompare(got, want) == 1 {
		return true, nil
	}
	return false, nil
}

// SessionHash é o identificador técnico gravado no aceite e na auditoria.
// O token do cookie não entra no banco de conteúdo.
func SessionHash(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
