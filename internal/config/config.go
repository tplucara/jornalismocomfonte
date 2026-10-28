// Package config lê a configuração exclusivamente de variáveis de ambiente.
// Nenhum segredo vive no repositório (white-hat.mdc, stack-e-seguranca.mdc).
package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"time"
)

type Config struct {
	Env         string // dev | prod
	HTTPAddr    string
	DatabaseURL string
	IPHashSalt  string
	MediaDir    string // volume local; MinIO entra quando a imagem estiver acessível

	ReadHeaderTimeout time.Duration
	ReadTimeout       time.Duration
	WriteTimeout      time.Duration
	IdleTimeout       time.Duration
	ShutdownTimeout   time.Duration
	MaxBodyBytes      int64

	// Provedor opcional da tag do artigo. Vazio: o worker usa a rubrica local.
	AIBaseURL string
	AIAPIKey  string
	AIModel   string
}

func Load() (Config, error) {
	c := Config{
		Env:               getenv("ENV", "dev"),
		HTTPAddr:          getenv("HTTP_ADDR", ":8080"),
		DatabaseURL:       os.Getenv("DATABASE_URL"),
		IPHashSalt:        os.Getenv("IP_HASH_SALT"),
		MediaDir:          os.Getenv("MEDIA_DIR"),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       60 * time.Second,
		ShutdownTimeout:   20 * time.Second,
		MaxBodyBytes:      6 << 20, // 6 MiB: foto de celular (até 5 MiB) + comprovante; cada rota ainda aplica o próprio teto
		AIBaseURL:         os.Getenv("JCF_AI_BASE_URL"),
		AIAPIKey:          os.Getenv("JCF_AI_API_KEY"),
		AIModel:           os.Getenv("JCF_AI_MODEL"),
	}
	if c.DatabaseURL == "" {
		return c, errors.New("DATABASE_URL é obrigatória")
	}
	if c.IPHashSalt == "" {
		return c, errors.New("IP_HASH_SALT é obrigatória")
	}
	if v := os.Getenv("MAX_BODY_BYTES"); v != "" {
		n, err := strconv.ParseInt(v, 10, 64)
		if err != nil || n <= 0 {
			return c, fmt.Errorf("MAX_BODY_BYTES inválido: %q", v)
		}
		c.MaxBodyBytes = n
	}
	return c, nil
}

func (c Config) IsProd() bool { return c.Env == "prod" }

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
