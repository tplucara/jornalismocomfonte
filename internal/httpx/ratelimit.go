package httpx

import (
	"net/http"
	"sync"

	"golang.org/x/time/rate"
)

// LimitByIP aplica um token bucket por hash de IP. Precisa rodar depois de HashClientIP.
// Páginas públicas são baratas; o teto existe para absorver abuso, não para punir leitores.
func LimitByIP(rps, burst int) func(http.Handler) http.Handler {
	lim := &ipLimiter{
		r:      rate.Limit(rps),
		burst:  burst,
		byHash: make(map[string]*rate.Limiter),
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			key := IPHash(r.Context())
			if key == "" {
				key = r.RemoteAddr
			}
			if !lim.allow(key) {
				http.Error(w, "muitas requisições", http.StatusTooManyRequests)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

type ipLimiter struct {
	mu     sync.Mutex
	r      rate.Limit
	burst  int
	byHash map[string]*rate.Limiter
}

func (l *ipLimiter) allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	lim, ok := l.byHash[key]
	if !ok {
		lim = rate.NewLimiter(l.r, l.burst)
		l.byHash[key] = lim
	}
	return lim.Allow()
}
