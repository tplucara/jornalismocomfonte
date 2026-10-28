package web

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"regexp"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"

	"jornalismocomfonte/internal/db"
)

// uuidRe valida IDs de rota antes de qualquer consulta. Entrada inválida vira 404, não erro de banco.
var uuidRe = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

const feedPageSize = 20

func (s *Server) handleFeed(w http.ResponseWriter, r *http.Request) {
	pageNum := 1
	if p := r.URL.Query().Get("p"); p != "" {
		n, err := strconv.Atoi(p)
		if err != nil || n < 1 || n > 10000 {
			s.rd.renderError(w, r, http.StatusBadRequest, "Página inválida")
			return
		}
		pageNum = n
	}
	rows, err := s.q.ListFeed(r.Context(), db.ListFeedParams{
		PageSize:   feedPageSize + 1,
		PageOffset: int32((pageNum - 1) * feedPageSize),
	})
	if err != nil {
		s.fail(w, r, err)
		return
	}
	hasNext := len(rows) > feedPageSize
	if hasNext {
		rows = rows[:feedPageSize]
	}
	cachePublic(w)
	s.rd.render(w, r, http.StatusOK, "feed.html",
		"",
		"Toda notícia aponta sua fonte. Publicações ancoradas em reportagens de veículos de comunicação cadastrados.",
		map[string]any{
			"Articles": rows,
			"Page":     pageNum,
			"HasNext":  hasNext,
			"HasPrev":  pageNum > 1,
		})
}

type articleView struct {
	db.GetArticleRow
	Body       articleBody
	Sources    []db.ListArticleSourcesRow
	Versions   []db.ListArticleVersionsRow
	Comments   []db.ListValidCommentsRow
	Replies    []db.ListPublishedRepliesRow
	Distortion []db.ListUpheldDistortionReportsRow
}

func (s *Server) handleArticle(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !uuidRe.MatchString(id) {
		s.rd.renderError(w, r, http.StatusNotFound, "Artigo não encontrado")
		return
	}
	ctx := r.Context()
	a, err := s.q.GetArticle(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) || (err == nil && a.Status == db.ArticleStatusDraft) {
		s.rd.renderError(w, r, http.StatusNotFound, "Artigo não encontrado")
		return
	}
	if err != nil {
		s.fail(w, r, err)
		return
	}

	v := articleView{GetArticleRow: a}

	// Artigo removido: placeholder com motivo e data. O rastro nunca é apagado (responsabilidade-legal.mdc).
	if a.Status == db.ArticleStatusRemoved || a.Status == db.ArticleStatusAuthorDeleted {
		cachePublic(w)
		s.rd.render(w, r, http.StatusGone, "article_removed.html", "Conteúdo removido", "", v)
		return
	}

	if err := s.loadArticleDetails(ctx, &v); err != nil {
		s.fail(w, r, err)
		return
	}
	cachePublic(w)
	s.rd.render(w, r, http.StatusOK, "article.html", a.Title.String, firstParagraph(v.Body), v)
}

func (v articleView) jsonLD() string {
	citations := make([]string, 0, len(v.Sources))
	for _, src := range v.Sources {
		citations = append(citations, src.Url)
	}
	doc := map[string]any{
		"@context":       "https://schema.org",
		"@type":          "NewsArticle",
		"headline":       v.Title.String,
		"author":         map[string]string{"@type": "Person", "name": v.AuthorName},
		"articleSection": kindLabel(v.Kind),
	}
	if v.PublishedAt.Valid {
		doc["datePublished"] = v.PublishedAt.Time.UTC().Format(time.RFC3339)
	}
	if len(citations) > 0 {
		doc["citation"] = citations
	}
	b, err := json.Marshal(doc)
	if err != nil {
		return ""
	}
	return string(b)
}

// EvaluationsOpen é falso quando toda fonte da versão corrente está indisponível.
// Avaliações já válidas continuam na página e na ordem do início.
func (v articleView) EvaluationsOpen() bool {
	if len(v.Sources) == 0 {
		return false
	}
	for _, src := range v.Sources {
		if src.HashStatus != db.SourceHashStatusUnavailable {
			return true
		}
	}
	return false
}

func (s *Server) loadArticleDetails(ctx context.Context, v *articleView) error {
	var err error
	v.Body = parseBody(v.GetArticleRow.Body)
	if v.Sources, err = s.q.ListArticleSources(ctx, v.CurrentVersionID); err != nil {
		return err
	}
	if v.Versions, err = s.q.ListArticleVersions(ctx, v.ID); err != nil {
		return err
	}
	if v.Comments, err = s.q.ListValidComments(ctx, v.ID); err != nil {
		return err
	}
	if v.Replies, err = s.q.ListPublishedReplies(ctx, v.ID); err != nil {
		return err
	}
	if v.Distortion, err = s.q.ListUpheldDistortionReports(ctx, v.ID); err != nil {
		return err
	}
	return nil
}

func firstParagraph(b articleBody) string {
	for _, blk := range b.Blocks {
		if blk.Type == "p" && blk.Text != "" {
			if len(blk.Text) > 160 {
				return blk.Text[:157] + "…"
			}
			return blk.Text
		}
	}
	return ""
}

type profileView struct {
	db.GetJournalistPublicRow
	HasReputation bool
	Author        reputationComponent
	Reviewer      reputationComponent
	Articles      []db.ListArticlesByAuthorRow
}

func (s *Server) handleProfile(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !uuidRe.MatchString(id) {
		s.rd.renderError(w, r, http.StatusNotFound, "Perfil não encontrado")
		return
	}
	ctx := r.Context()
	j, err := s.q.GetJournalistPublic(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		s.rd.renderError(w, r, http.StatusNotFound, "Perfil não encontrado")
		return
	}
	if err != nil {
		s.fail(w, r, err)
		return
	}
	v := profileView{GetJournalistPublicRow: j}
	rep, err := s.q.GetCurrentReputation(ctx, id)
	switch {
	case err == nil:
		v.HasReputation = true
		v.Author = parseReputation(rep.Author)
		v.Reviewer = parseReputation(rep.Reviewer)
	case errors.Is(err, pgx.ErrNoRows):
	default:
		s.fail(w, r, err)
		return
	}
	if v.Articles, err = s.q.ListArticlesByAuthor(ctx, id); err != nil {
		s.fail(w, r, err)
		return
	}
	cachePublic(w)
	s.rd.render(w, r, http.StatusOK, "profile.html", j.DisplayName, j.Tagline.String, v)
}

func (s *Server) handleOutlets(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	outlets, err := s.q.ListOutlets(ctx)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	changes, err := s.q.ListOutletChanges(ctx)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	cachePublic(w)
	s.rd.render(w, r, http.StatusOK, "outlets.html",
		"Cadastro de veículos",
		"Veículos jornalísticos que podem ser citados como fonte, com critérios objetivos e histórico público de todas as mudanças.",
		map[string]any{"Outlets": outlets, "Changes": changes})
}

func (s *Server) handleHealthz(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = w.Write([]byte("ok\n"))
}

func (s *Server) handleReadyz(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	if s.pool == nil {
		http.Error(w, "not ready", http.StatusServiceUnavailable)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := s.pool.Ping(ctx); err != nil {
		s.log.Error("readyz", "err", err)
		http.Error(w, "not ready", http.StatusServiceUnavailable)
		return
	}
	_, _ = w.Write([]byte("ok\n"))
}

func (s *Server) handleNotFound(w http.ResponseWriter, r *http.Request) {
	s.rd.renderError(w, r, http.StatusNotFound, "Página não encontrada")
}

func (s *Server) handleAbout(w http.ResponseWriter, r *http.Request) {
	cachePublic(w)
	s.rd.render(w, r, http.StatusOK, "about.html",
		"Sobre o Jornalismo com Fonte",
		"Toda notícia aponta sua fonte. A plataforma reduz o risco de desinformação; não certifica verdade.",
		nil)
}

func (s *Server) handleTerms(w http.ResponseWriter, r *http.Request) {
	cachePublic(w)
	s.rd.render(w, r, http.StatusOK, "legal_terms.html", "Termos de Uso", "Termos de uso da plataforma Jornalismo com Fonte, operada pela Anvil Software LTDA.", nil)
}

func (s *Server) handlePrivacy(w http.ResponseWriter, r *http.Request) {
	cachePublic(w)
	s.rd.render(w, r, http.StatusOK, "legal_privacy.html", "Política de Privacidade", "Como a Anvil Software LTDA trata dados no Jornalismo com Fonte.", nil)
}

func (s *Server) handleContentPolicy(w http.ResponseWriter, r *http.Request) {
	cachePublic(w)
	s.rd.render(w, r, http.StatusOK, "legal_content.html", "Política de Conteúdo e Remoção", "Como notificar conteúdo ilícito, pedir resposta e acompanhar remoções.", nil)
}

func (s *Server) handleSecurity(w http.ResponseWriter, r *http.Request) {
	cachePublic(w)
	s.rd.render(w, r, http.StatusOK, "legal_security.html", "Divulgação responsável de vulnerabilidades", "Como reportar uma vulnerabilidade de segurança no Jornalismo com Fonte.", nil)
}

func (s *Server) handleSecurityTxt(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	cachePublic(w)
	_, _ = w.Write([]byte(
		"Contact: mailto:security@jornalismocomfonte.example\n" +
			"Preferred-Languages: pt-BR, en\n" +
			"Policy: /seguranca\n" +
			"Expires: 2027-12-31T23:59:59.000Z\n"))
}

func (s *Server) handleRobots(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	cachePublic(w)
	_, _ = w.Write([]byte("User-agent: *\nAllow: /\nDisallow: /healthz\nDisallow: /cadastro\nDisallow: /entrar\nDisallow: /conta\nDisallow: /escrever\nDisallow: /equipe\n"))
}

// fail: 500 genérico ao usuário, detalhe só no log.
func (s *Server) fail(w http.ResponseWriter, r *http.Request, err error) {
	s.log.Error("handler", "path", r.URL.Path, "err", err)
	s.rd.renderError(w, r, http.StatusInternalServerError, "Não foi possível carregar esta página")
}
