package web

import (
	"log/slog"
	"net/http"

	"github.com/alexedwards/scs/v2"
	"github.com/jackc/pgx/v5/pgxpool"

	"jornalismocomfonte/internal/config"
	"jornalismocomfonte/internal/db"
	"jornalismocomfonte/internal/httpx"
	"jornalismocomfonte/internal/media"
)

// Server agrupa dependências dos handlers. Sem estado mutável compartilhado entre pedidos.
type Server struct {
	q        *db.Queries
	pool     *pgxpool.Pool
	log      *slog.Logger
	rd       *renderer
	sessions *scs.SessionManager
	media    *media.Store
}

func New(q *db.Queries, pool *pgxpool.Pool, log *slog.Logger, mediaStore *media.Store) *Server {
	return &Server{
		q:        q,
		pool:     pool,
		log:      log,
		rd:       newRenderer(log),
		sessions: newSessionManager(q, log),
		media:    mediaStore,
	}
}

// Handler aplica o middleware transversal (cabeçalhos, CSRF, limite de corpo, log, pânico)
// em volta das rotas. Páginas públicas não definem cookie.
func (s *Server) Handler(cfg config.Config) http.Handler {
	// __Host- exige Secure. Em HTTP local o navegador descartaria esse cookie,
	// então o nome com prefixo fica para produção, atrás de TLS.
	if cfg.IsProd() {
		s.sessions.Cookie.Secure = true
		s.sessions.Cookie.Name = "__Host-session"
	}
	csrf := http.NewCrossOriginProtection()
	return httpx.Chain(s.sessions.LoadAndSave(s.Routes()),
		httpx.Log(s.log),
		httpx.Recover(s.log),
		httpx.SecureHeaders(cfg.IsProd()),
		httpx.HashClientIP(cfg.IPHashSalt),
		httpx.MaxBody(cfg.MaxBodyBytes),
		httpx.LimitByIP(30, 60),
		func(next http.Handler) http.Handler { return csrf.Handler(next) },
	)
}

// Routes monta o mux com padrões do Go 1.22+ (método + caminho).
// Leitura pública é GET. A conta do jornalista escreve em POST.
func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /{$}", s.handleFeed)
	mux.HandleFunc("GET /cadastro", s.handleSignup)
	mux.HandleFunc("POST /cadastro", s.handleSignupPost)
	mux.HandleFunc("GET /entrar", s.handleLogin)
	mux.HandleFunc("POST /entrar", s.handleLoginPost)
	mux.HandleFunc("GET /conta", s.handleAccount)
	mux.HandleFunc("POST /conta/foto", s.handleAvatarUpload)
	mux.HandleFunc("POST /conta/comprovante", s.handleProofUpload)
	mux.HandleFunc("GET /escrever", s.handlePublishGet)
	mux.HandleFunc("POST /escrever", s.handlePublishPost)
	mux.HandleFunc("GET /equipe/verificacoes", s.handleStaffVerifications)
	mux.HandleFunc("POST /equipe/verificacoes", s.handleStaffVerifications)
	mux.HandleFunc("GET /media/a/{name}", s.handleMediaAvatar)
	mux.HandleFunc("POST /sair", s.handleLogout)
	mux.HandleFunc("GET /a/{id}", s.handleArticle)
	mux.HandleFunc("GET /j/{id}", s.handleProfile)
	mux.HandleFunc("GET /busca", s.handleSearch)
	mux.HandleFunc("GET /fontes", s.handleOutlets)
	mux.HandleFunc("GET /lista-branca", s.handleOutlets)
	mux.HandleFunc("GET /sobre", s.handleAbout)
	mux.HandleFunc("GET /termos", s.handleTerms)
	mux.HandleFunc("GET /privacidade", s.handlePrivacy)
	mux.HandleFunc("GET /conteudo", s.handleContentPolicy)
	mux.HandleFunc("GET /seguranca", s.handleSecurity)
	mux.HandleFunc("GET /healthz", s.handleHealthz)
	mux.HandleFunc("GET /readyz", s.handleReadyz)
	mux.HandleFunc("GET /.well-known/security.txt", s.handleSecurityTxt)
	mux.HandleFunc("GET /robots.txt", s.handleRobots)
	mux.HandleFunc("/", s.handleNotFound)

	static := http.StripPrefix("/static/", http.FileServerFS(StaticFS()))
	mux.Handle("GET /static/", cacheLong(static))

	return mux
}

// cacheLong: estáticos imutáveis por versão (o caminho muda quando o conteúdo muda).
func cacheLong(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "public, max-age=86400")
		next.ServeHTTP(w, r)
	})
}

// cachePublic: páginas públicas não têm cookie; podem ser cacheadas por CDN/navegador por pouco tempo.
func cachePublic(w http.ResponseWriter) {
	w.Header().Set("Cache-Control", "public, max-age=60, stale-while-revalidate=300")
}
