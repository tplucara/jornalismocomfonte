package web

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"net/mail"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/alexedwards/scs/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"jornalismocomfonte/internal/auth"
	"jornalismocomfonte/internal/db"
	"jornalismocomfonte/internal/httpx"
	"jornalismocomfonte/internal/sessions"
)

// Versão dos documentos em docs/legal. O aceite grava exatamente esta versão.
const legalVersion = "1.0"

const (
	sessionJournalistID = "journalist_id"
	sessionFlash        = "flash"
)

var (
	signupAttempts = newWindow(15, time.Hour)
	loginAttempts  = newWindow(10, 15*time.Minute)
)

func newSessionManager(q *db.Queries, log *slog.Logger) *scs.SessionManager {
	m := scs.New()
	m.Store = sessions.New(q)
	m.Lifetime = 30 * 24 * time.Hour
	m.IdleTimeout = 12 * time.Hour
	m.Cookie.Name = "session"
	m.Cookie.HttpOnly = true
	m.Cookie.SameSite = http.SameSiteLaxMode
	m.Cookie.Path = "/"
	m.Cookie.Persist = false
	// O banco guarda o hash do token. O cookie continua com o token cru.
	m.HashTokenInStore = true
	m.ErrorFunc = func(w http.ResponseWriter, r *http.Request, err error) {
		log.Error("session", "path", r.URL.Path, "err", err)
		http.Error(w, "erro interno", http.StatusInternalServerError)
	}
	return m
}

func noStore(w http.ResponseWriter) {
	w.Header().Set("Cache-Control", "private, no-store")
}

type signupForm struct {
	Name, Email, Tagline                       string
	Password, PasswordConfirm                  string
	Adult, Terms, Privacy, Content, Remember   bool
	ErrName, ErrEmail, ErrPassword, ErrTagline string
	ErrAdult, ErrTerms, ErrPrivacy, ErrContent string
	ErrForm                                    string
}

func (signupForm) Robots() string { return "noindex, follow" }

func (f signupForm) ok() bool {
	return f.ErrName == "" && f.ErrEmail == "" && f.ErrPassword == "" && f.ErrTagline == "" &&
		f.ErrAdult == "" && f.ErrTerms == "" && f.ErrPrivacy == "" && f.ErrContent == ""
}

func parseSignup(r *http.Request) (signupForm, error) {
	if err := r.ParseForm(); err != nil {
		return signupForm{}, err
	}
	f := signupForm{
		Name:            strings.TrimSpace(r.PostForm.Get("display_name")),
		Email:           strings.TrimSpace(r.PostForm.Get("email")),
		Tagline:         strings.TrimSpace(r.PostForm.Get("tagline")),
		Password:        r.PostForm.Get("password"),
		PasswordConfirm: r.PostForm.Get("password_confirm"),
		Adult:           r.PostForm.Get("adult") == "on",
		Terms:           r.PostForm.Get("accept_terms") == "on",
		Privacy:         r.PostForm.Get("accept_privacy") == "on",
		Content:         r.PostForm.Get("accept_content") == "on",
		Remember:        r.PostForm.Get("remember") == "on",
	}
	f.validate()
	return f, nil
}

func (f *signupForm) validate() {
	if n := utf8.RuneCountInString(f.Name); n < 2 || n > 80 || hasControl(f.Name) || !hasLetterOrNumber(f.Name) {
		f.ErrName = "Escreva o nome público, com 2 a 80 caracteres."
	}
	if n := utf8.RuneCountInString(f.Tagline); n > 140 || hasControl(f.Tagline) {
		f.ErrTagline = "A frase de impacto tem no máximo 140 caracteres, numa linha."
	}
	addr, err := mail.ParseAddress(f.Email)
	domainOK := false
	if err == nil {
		host := addr.Address
		if at := strings.LastIndex(host, "@"); at > 0 && at < len(host)-1 {
			domainOK = strings.Contains(host[at+1:], ".")
		}
	}
	if err != nil || !strings.EqualFold(addr.Address, f.Email) || !domainOK || len(f.Email) > 254 {
		f.ErrEmail = "Informe um e-mail válido."
	} else {
		f.Email = strings.ToLower(addr.Address)
	}
	switch {
	case utf8.RuneCountInString(f.Password) < auth.MinPasswordRunes:
		f.ErrPassword = "Use uma senha com pelo menos 12 caracteres."
	case len(f.Password) > auth.MaxPasswordBytes:
		f.ErrPassword = "A senha passa de 128 bytes."
	case f.Password != f.PasswordConfirm:
		f.ErrPassword = "A confirmação não é igual à senha."
	}
	if !f.Adult {
		f.ErrAdult = "Confirme que você tem 18 anos ou mais."
	}
	if !f.Terms {
		f.ErrTerms = "Aceite os termos de uso."
	}
	if !f.Privacy {
		f.ErrPrivacy = "Aceite a política de privacidade."
	}
	if !f.Content {
		f.ErrContent = "Aceite a política de conteúdo e remoção."
	}
}

func hasControl(s string) bool {
	for _, r := range s {
		if unicode.IsControl(r) {
			return true
		}
	}
	return false
}

// hasDangerousControl rejeita controles, mas permite quebra de linha e tab no corpo do artigo.
func hasDangerousControl(s string) bool {
	for _, r := range s {
		if r == '\n' || r == '\r' || r == '\t' {
			continue
		}
		if unicode.IsControl(r) {
			return true
		}
	}
	return false
}

func hasLetterOrNumber(s string) bool {
	for _, r := range s {
		if unicode.IsLetter(r) || unicode.IsNumber(r) {
			return true
		}
	}
	return false
}

func (s *Server) handleSignup(w http.ResponseWriter, r *http.Request) {
	noStore(w)
	if s.journalistID(r.Context()) != "" {
		http.Redirect(w, r, "/conta", http.StatusSeeOther)
		return
	}
	s.rd.render(w, r, http.StatusOK, "signup.html", "Criar conta", "Criar conta de jornalista no Jornalismo com Fonte.", signupForm{})
}

func (s *Server) handleSignupPost(w http.ResponseWriter, r *http.Request) {
	noStore(w)
	if s.journalistID(r.Context()) != "" {
		http.Redirect(w, r, "/conta", http.StatusSeeOther)
		return
	}
	if !signupAttempts.allow("ip:" + httpx.IPHash(r.Context())) {
		s.rd.renderError(w, r, http.StatusTooManyRequests, "Muitas tentativas a partir desta rede. Tente mais tarde.")
		return
	}
	form, err := parseSignup(r)
	if err != nil {
		s.rd.renderError(w, r, http.StatusBadRequest, "Não foi possível ler o formulário")
		return
	}
	if !form.ok() {
		form.Password, form.PasswordConfirm = "", ""
		s.rd.render(w, r, http.StatusUnprocessableEntity, "signup.html", "Criar conta", "Criar conta de jornalista no Jornalismo com Fonte.", form)
		return
	}
	hash, err := auth.HashPassword(form.Password)
	form.Password, form.PasswordConfirm = "", ""
	if err != nil {
		s.fail(w, r, err)
		return
	}
	if err := s.sessions.RenewToken(r.Context()); err != nil {
		s.fail(w, r, err)
		return
	}
	s.sessions.RememberMe(r.Context(), form.Remember)
	token := s.sessions.Token(r.Context())
	if token == "" {
		if _, _, err = s.sessions.Commit(r.Context()); err != nil {
			s.fail(w, r, err)
			return
		}
		token = s.sessions.Token(r.Context())
	}
	if token == "" {
		s.fail(w, r, errors.New("sessão sem token"))
		return
	}
	id, err := s.createAccount(r.Context(), form, hash, auth.SessionHash(token), httpx.IPHash(r.Context()))
	if isUniqueViolation(err) {
		_ = s.sessions.Destroy(r.Context())
		form.ErrEmail = "Já existe uma conta com este e-mail."
		s.rd.render(w, r, http.StatusUnprocessableEntity, "signup.html", "Criar conta", "Criar conta de jornalista no Jornalismo com Fonte.", form)
		return
	}
	if err != nil {
		_ = s.sessions.Destroy(r.Context())
		s.fail(w, r, err)
		return
	}
	s.sessions.Put(r.Context(), sessionJournalistID, id)
	s.sessions.Put(r.Context(), sessionFlash, "Conta criada.")
	http.Redirect(w, r, "/conta", http.StatusSeeOther)
}

func (s *Server) createAccount(ctx context.Context, form signupForm, passwordHash, sessionHash, ipHash string) (string, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, `SELECT set_config('app.session_hash', $1, true), set_config('app.ip_hash', $2, true)`, sessionHash, ipHash); err != nil {
		return "", err
	}
	q := s.q.WithTx(tx)
	id, err := q.CreateJournalist(ctx, db.CreateJournalistParams{
		Email:        form.Email,
		PasswordHash: passwordHash,
		DisplayName:  form.Name,
		Tagline:      form.Tagline,
	})
	if err != nil {
		return "", err
	}
	if _, err = tx.Exec(ctx, `SELECT set_config('app.actor_id', $1, true)`, id); err != nil {
		return "", err
	}
	for _, doc := range []db.LegalDocument{db.LegalDocumentTerms, db.LegalDocumentPrivacy, db.LegalDocumentContentPolicy} {
		if err = q.InsertLegalAcceptance(ctx, db.InsertLegalAcceptanceParams{
			JournalistID: id,
			Document:     doc,
			Version:      legalVersion,
			SessionHash:  sessionHash,
		}); err != nil {
			return "", err
		}
	}
	if err = q.AuditJournalistCreated(ctx, db.AuditJournalistCreatedParams{
		ActorID:     id,
		SessionHash: sessionHash,
		IpHash:      ipHash,
	}); err != nil {
		return "", err
	}
	if err = tx.Commit(ctx); err != nil {
		return "", err
	}
	return id, nil
}

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

type loginView struct {
	Email    string
	Remember bool
	ErrForm  string
}

func (loginView) Robots() string { return "noindex, follow" }

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	noStore(w)
	if s.journalistID(r.Context()) != "" {
		http.Redirect(w, r, "/conta", http.StatusSeeOther)
		return
	}
	s.rd.render(w, r, http.StatusOK, "login.html", "Entrar", "Entrar na conta de jornalista.", loginView{})
}

func (s *Server) handleLoginPost(w http.ResponseWriter, r *http.Request) {
	noStore(w)
	if err := r.ParseForm(); err != nil {
		s.rd.renderError(w, r, http.StatusBadRequest, "Não foi possível ler o formulário")
		return
	}
	view := loginView{
		Email:    strings.TrimSpace(r.PostForm.Get("email")),
		Remember: r.PostForm.Get("remember") == "on",
	}
	ipKey := "ip:" + httpx.IPHash(r.Context())
	mailKey := "mail:" + auth.SessionHash(strings.ToLower(view.Email))
	if !loginAttempts.allow(ipKey) || !loginAttempts.allow(mailKey) {
		s.rd.renderError(w, r, http.StatusTooManyRequests, "Muitas tentativas a partir desta rede. Tente mais tarde.")
		return
	}
	password := r.PostForm.Get("password")
	addr, err := mail.ParseAddress(view.Email)
	if err != nil || !strings.EqualFold(addr.Address, view.Email) || password == "" || len(password) > auth.MaxPasswordBytes {
		view.ErrForm = "E-mail ou senha não conferem."
		s.rd.render(w, r, http.StatusUnprocessableEntity, "login.html", "Entrar", "Entrar na conta de jornalista.", view)
		return
	}
	email := strings.ToLower(addr.Address)
	row, err := s.q.GetJournalistForLogin(r.Context(), email)
	if errors.Is(err, pgx.ErrNoRows) {
		_, _ = auth.CheckPassword("", password)
		view.ErrForm = "E-mail ou senha não conferem."
		s.rd.render(w, r, http.StatusUnprocessableEntity, "login.html", "Entrar", "Entrar na conta de jornalista.", view)
		return
	}
	if err != nil {
		s.fail(w, r, err)
		return
	}
	ok, err := auth.CheckPassword(row.PasswordHash, password)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	if !ok {
		view.ErrForm = "E-mail ou senha não conferem."
		s.rd.render(w, r, http.StatusUnprocessableEntity, "login.html", "Entrar", "Entrar na conta de jornalista.", view)
		return
	}
	switch row.Status {
	case db.JournalistStatusPendingVerification, db.JournalistStatusVerified:
	case db.JournalistStatusSuspended:
		view.ErrForm = "Esta conta está suspensa."
		s.rd.render(w, r, http.StatusUnprocessableEntity, "login.html", "Entrar", "Entrar na conta de jornalista.", view)
		return
	default:
		view.ErrForm = "Esta conta está encerrada."
		s.rd.render(w, r, http.StatusUnprocessableEntity, "login.html", "Entrar", "Entrar na conta de jornalista.", view)
		return
	}
	if err := s.sessions.RenewToken(r.Context()); err != nil {
		s.fail(w, r, err)
		return
	}
	s.sessions.RememberMe(r.Context(), view.Remember)
	s.sessions.Put(r.Context(), sessionJournalistID, row.ID)
	http.Redirect(w, r, "/conta", http.StatusSeeOther)
}

type accountView struct {
	Name, Email, Tagline, Avatar, Status, Flash string
	Pending, ProofPending, Verified, Staff      bool
}

func (accountView) Robots() string { return "noindex, follow" }

func (s *Server) handleAccount(w http.ResponseWriter, r *http.Request) {
	noStore(w)
	id := s.journalistID(r.Context())
	if id == "" {
		http.Redirect(w, r, "/entrar", http.StatusSeeOther)
		return
	}
	row, err := s.q.GetJournalistAccount(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		_ = s.sessions.Destroy(r.Context())
		http.Redirect(w, r, "/entrar", http.StatusSeeOther)
		return
	}
	if err != nil {
		s.fail(w, r, err)
		return
	}
	proofPending := false
	if row.Status == db.JournalistStatusPendingVerification {
		proofPending, err = s.q.HasPendingVerification(r.Context(), id)
		if err != nil {
			s.fail(w, r, err)
			return
		}
	}
	s.rd.render(w, r, http.StatusOK, "account.html", "Sua conta", "Conta de jornalista no Jornalismo com Fonte.", accountView{
		Name:         row.DisplayName,
		Email:        row.Email,
		Tagline:      row.Tagline,
		Avatar:       row.AvatarUrl,
		Status:       accountStatus(row.Status),
		Flash:        s.sessions.PopString(r.Context(), sessionFlash),
		Pending:      row.Status == db.JournalistStatusPendingVerification,
		ProofPending: proofPending,
		Verified:     row.Status == db.JournalistStatusVerified,
		Staff:        s.isStaff(row.Email),
	})
}

func accountStatus(status db.JournalistStatus) string {
	switch status {
	case db.JournalistStatusPendingVerification:
		return "Aguardando revisão humana da identidade. Até lá, a conta não publica, não avalia e não comenta. Envie o comprovante nesta tela."
	case db.JournalistStatusVerified:
		return "Identidade de jornalista verificada. Isso é a pessoa, não o conteúdo que ela publicar."
	case db.JournalistStatusSuspended:
		return "Conta suspensa."
	default:
		return "Conta encerrada."
	}
}

func (s *Server) handleLogout(w http.ResponseWriter, r *http.Request) {
	noStore(w)
	if err := s.sessions.Destroy(r.Context()); err != nil {
		s.fail(w, r, err)
		return
	}
	http.Redirect(w, r, "/", http.StatusSeeOther)
}

func (s *Server) journalistID(ctx context.Context) string {
	return s.sessions.GetString(ctx, sessionJournalistID)
}

type windowLimit struct {
	mu     sync.Mutex
	limit  int
	window time.Duration
	hits   map[string][]time.Time
}

func newWindow(limit int, window time.Duration) *windowLimit {
	return &windowLimit{limit: limit, window: window, hits: map[string][]time.Time{}}
}

func (l *windowLimit) allow(key string) bool {
	now := time.Now()
	l.mu.Lock()
	defer l.mu.Unlock()
	cut := now.Add(-l.window)
	if len(l.hits) > 4096 {
		for k, ts := range l.hits {
			fresh := make([]time.Time, 0, len(ts))
			for _, t := range ts {
				if t.After(cut) {
					fresh = append(fresh, t)
				}
			}
			if len(fresh) == 0 {
				delete(l.hits, k)
			} else {
				l.hits[k] = fresh
			}
		}
	}
	kept := make([]time.Time, 0, len(l.hits[key]))
	for _, t := range l.hits[key] {
		if t.After(cut) {
			kept = append(kept, t)
		}
	}
	if len(kept) >= l.limit {
		l.hits[key] = kept
		return false
	}
	l.hits[key] = append(kept, now)
	return true
}
