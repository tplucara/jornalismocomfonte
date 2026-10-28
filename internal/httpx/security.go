// Package httpx reúne o middleware HTTP transversal: cabeçalhos de segurança com CSP por nonce,
// hash de IP, recuperação de pânico, limite de corpo e logging estruturado sem PII.
package httpx

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"log/slog"
	"net"
	"net/http"
	"runtime/debug"
	"time"
)

type ctxKey int

const (
	ctxNonce ctxKey = iota
	ctxIPHash
)

// Nonce devolve o nonce de CSP gerado para a requisição. Templates o usam em <script nonce="…">.
func Nonce(ctx context.Context) string {
	v, _ := ctx.Value(ctxNonce).(string)
	return v
}

// IPHash devolve o hash salgado do IP do cliente. Nunca registramos o IP em claro.
func IPHash(ctx context.Context) string {
	v, _ := ctx.Value(ctxIPHash).(string)
	return v
}

// SecureHeaders aplica a política de cabeçalhos de stack-e-seguranca.mdc a toda resposta.
// A CSP é estrita: nada de terceiros, scripts só com nonce, sem iframes, sem base-uri.
func SecureHeaders(isProd bool) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			nonce := newNonce()
			h := w.Header()
			h.Set("Content-Security-Policy",
				"default-src 'none'; "+
					"script-src 'nonce-"+nonce+"' 'strict-dynamic'; "+
					"style-src 'self'; "+
					"img-src 'self' data:; "+
					"font-src 'self'; "+
					"connect-src 'self'; "+
					"form-action 'self'; "+
					"frame-ancestors 'none'; "+
					"base-uri 'none'; "+
					"object-src 'none'; "+
					"upgrade-insecure-requests")
			h.Set("X-Content-Type-Options", "nosniff")
			h.Set("Referrer-Policy", "strict-origin-when-cross-origin")
			h.Set("Cross-Origin-Opener-Policy", "same-origin")
			h.Set("Cross-Origin-Resource-Policy", "same-origin")
			h.Set("X-Frame-Options", "DENY")
			h.Set("Permissions-Policy",
				"accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), "+
					"microphone=(), payment=(), usb=(), interest-cohort=(), browsing-topics=()")
			if isProd {
				h.Set("Strict-Transport-Security", "max-age=63072000; includeSubDomains; preload")
			}
			ctx := context.WithValue(r.Context(), ctxNonce, nonce)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func newNonce() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic("crypto/rand indisponível: " + err.Error())
	}
	return base64.StdEncoding.EncodeToString(b)
}

// HashClientIP calcula sha256(salt || ip) e guarda no contexto. Só o hash é logado ou auditado.
// X-Real-IP vem do Caddy, que sobrescreve o cabeçalho com o cliente. Sem ele, usa o endereço da conexão.
func HashClientIP(salt string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ip := r.Header.Get("X-Real-IP")
			if net.ParseIP(ip) == nil {
				var err error
				ip, _, err = net.SplitHostPort(r.RemoteAddr)
				if err != nil {
					ip = r.RemoteAddr
				}
			}
			sum := sha256.Sum256([]byte(salt + "|" + ip))
			ctx := context.WithValue(r.Context(), ctxIPHash, hex.EncodeToString(sum[:16]))
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// MaxBody limita o corpo de toda requisição. Rotas de upload definem o próprio limite.
func MaxBody(n int64) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Body != nil {
				r.Body = http.MaxBytesReader(w, r.Body, n)
			}
			next.ServeHTTP(w, r)
		})
	}
}

// Recover converte pânico em 500 genérico. Detalhe só no log, nunca na resposta.
func Recover(log *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			defer func() {
				if rec := recover(); rec != nil {
					log.Error("panic", "err", rec, "stack", string(debug.Stack()), "path", r.URL.Path)
					http.Error(w, "erro interno", http.StatusInternalServerError)
				}
			}()
			next.ServeHTTP(w, r)
		})
	}
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (s *statusWriter) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

// Log registra método, caminho, status e duração. Sem query string (pode conter dados), sem IP em claro.
func Log(log *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
			next.ServeHTTP(sw, r)
			log.Info("http",
				"method", r.Method,
				"path", r.URL.Path,
				"status", sw.status,
				"dur_ms", time.Since(start).Milliseconds(),
				"ip_hash", IPHash(r.Context()),
			)
		})
	}
}

// Chain aplica middlewares na ordem dada (o primeiro é o mais externo).
func Chain(h http.Handler, mws ...func(http.Handler) http.Handler) http.Handler {
	for i := len(mws) - 1; i >= 0; i-- {
		h = mws[i](h)
	}
	return h
}
