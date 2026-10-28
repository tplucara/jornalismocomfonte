package web

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"jornalismocomfonte/internal/auth"
	"jornalismocomfonte/internal/db"
	"jornalismocomfonte/internal/httpx"
)

type publishForm struct {
	Title, Body, Kind                         string
	URL1, URL2, URL3                          string
	Excerpt1, Excerpt2, Excerpt3              string
	ErrTitle, ErrBody, ErrKind, ErrSources    string
	ErrForm                                   string
	Status                                    db.JournalistStatus
}

func (publishForm) Robots() string { return "noindex, follow" }

func (s *Server) handlePublishGet(w http.ResponseWriter, r *http.Request) {
	noStore(w)
	id := s.journalistID(r.Context())
	if id == "" {
		http.Redirect(w, r, "/entrar", http.StatusSeeOther)
		return
	}
	st, err := s.q.GetJournalistStatus(r.Context(), id)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	if st.Status != db.JournalistStatusVerified {
		s.rd.renderError(w, r, http.StatusForbidden, "Só contas com identidade verificada publicam. Envie o comprovante em Conta.")
		return
	}
	s.rd.render(w, r, http.StatusOK, "publish.html", "Escrever", "Publicar com 1 a 3 fontes do cadastro.", publishForm{
		Kind:   string(db.ArticleKindReport),
		Status: st.Status,
	})
}

func (s *Server) handlePublishPost(w http.ResponseWriter, r *http.Request) {
	noStore(w)
	id := s.journalistID(r.Context())
	if id == "" {
		http.Redirect(w, r, "/entrar", http.StatusSeeOther)
		return
	}
	st, err := s.q.GetJournalistStatus(r.Context(), id)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	if st.Status != db.JournalistStatusVerified {
		s.rd.renderError(w, r, http.StatusForbidden, "Só contas com identidade verificada publicam.")
		return
	}
	if err := r.ParseForm(); err != nil {
		s.rd.renderError(w, r, http.StatusBadRequest, "Pedido inválido.")
		return
	}
	f := publishForm{
		Title:    strings.TrimSpace(r.PostForm.Get("title")),
		Body:     strings.TrimSpace(r.PostForm.Get("body")),
		Kind:     strings.TrimSpace(r.PostForm.Get("kind")),
		URL1:     strings.TrimSpace(r.PostForm.Get("source_url_1")),
		URL2:     strings.TrimSpace(r.PostForm.Get("source_url_2")),
		URL3:     strings.TrimSpace(r.PostForm.Get("source_url_3")),
		Excerpt1: strings.TrimSpace(r.PostForm.Get("source_excerpt_1")),
		Excerpt2: strings.TrimSpace(r.PostForm.Get("source_excerpt_2")),
		Excerpt3: strings.TrimSpace(r.PostForm.Get("source_excerpt_3")),
		Status:   st.Status,
	}
	srcs, verr := validatePublish(r.Context(), s.q, f)
	if verr != "" {
		f.ErrForm = verr
		s.rd.render(w, r, http.StatusUnprocessableEntity, "publish.html", "Escrever", "", f)
		return
	}
	articleID, err := s.publishArticle(r.Context(), id, f, srcs, auth.SessionHash(s.sessions.Token(r.Context())), httpx.IPHash(r.Context()))
	if err != nil {
		s.log.Error("publish", "err", err)
		f.ErrForm = "Não foi possível publicar. Confira as fontes e tente de novo."
		s.rd.render(w, r, http.StatusUnprocessableEntity, "publish.html", "Escrever", "", f)
		return
	}
	http.Redirect(w, r, "/a/"+articleID, http.StatusSeeOther)
}

type preparedSource struct {
	URL, Excerpt, DomainID, Hash, Reason string
	Meta                                 []byte
}

func validatePublish(ctx context.Context, q *db.Queries, f publishForm) ([]preparedSource, string) {
	if n := utf8.RuneCountInString(f.Title); n < 8 || n > 200 || hasControl(f.Title) {
		return nil, "O título precisa ter entre 8 e 200 caracteres."
	}
	if n := utf8.RuneCountInString(f.Body); n < 80 || n > 50000 || hasDangerousControl(f.Body) {
		return nil, "O texto precisa ter entre 80 e 50.000 caracteres."
	}
	kind := db.ArticleKind(f.Kind)
	if !kind.Valid() {
		return nil, "Escolha Reportagem, Análise ou Opinião."
	}
	type pair struct{ u, e string }
	raw := []pair{{f.URL1, f.Excerpt1}, {f.URL2, f.Excerpt2}, {f.URL3, f.Excerpt3}}
	var out []preparedSource
	seen := map[string]bool{}
	for _, p := range raw {
		if p.u == "" && p.e == "" {
			continue
		}
		if p.u == "" || p.e == "" {
			return nil, "Cada fonte precisa de URL e trecho citado."
		}
		if utf8.RuneCountInString(p.e) > 300 {
			return nil, "O trecho citado tem no máximo 300 caracteres."
		}
		u, err := url.Parse(p.u)
		if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
			return nil, "A URL da fonte precisa ser http(s) completa."
		}
		host := strings.ToLower(u.Hostname())
		host = strings.TrimPrefix(host, "www.")
		key := strings.ToLower(u.String())
		if seen[key] {
			return nil, "Não repita a mesma URL como duas fontes."
		}
		seen[key] = true
		dom, err := q.FindOutletDomainByHost(ctx, host)
		if errors.Is(err, pgx.ErrNoRows) {
			// try full hostname with www
			dom, err = q.FindOutletDomainByHost(ctx, strings.ToLower(u.Hostname()))
		}
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, "A fonte " + host + " não está no cadastro de veículos."
		}
		if err != nil {
			return nil, "Erro ao conferir o veículo da fonte."
		}
		if dom.OutletStatus != db.OutletStatusActive {
			return nil, "O veículo " + dom.OutletName + " não está ativo no cadastro."
		}
		path := u.EscapedPath()
		for _, pat := range dom.OpinionPathPatterns {
			if pat != "" && strings.Contains(strings.ToLower(path), strings.ToLower(pat)) {
				return nil, "A URL parece opinião/coluna/editorial (" + pat + "), não reportagem."
			}
		}
		hash, meta, ferr := fetchSourceIntegrity(p.u, p.e)
		if ferr != nil {
			return nil, ferr.Error()
		}
		out = append(out, preparedSource{
			URL: p.u, Excerpt: p.e, DomainID: dom.DomainID, Hash: hash, Meta: meta,
			Reason: "path_pattern: não casa com paths de opinião do veículo",
		})
	}
	if len(out) < 1 || len(out) > 3 {
		return nil, "Informe de 1 a 3 fontes de reportagem do cadastro."
	}
	return out, ""
}

func fetchSourceIntegrity(rawURL, excerpt string) (hash string, meta []byte, err error) {
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return "", nil, fmt.Errorf("URL da fonte inválida.")
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (compatible; JornalismoComFonte/1.0; +https://jornalismocomfonte.example; source-integrity)")
	req.Header.Set("Accept", "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8")
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", nil, fmt.Errorf("Não foi possível abrir a fonte. Confira o link.")
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return "", nil, fmt.Errorf("A fonte respondeu com erro HTTP %d.", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return "", nil, fmt.Errorf("Não foi possível ler a fonte.")
	}
	sum := sha256.Sum256(body)
	hash = "sha256:" + hex.EncodeToString(sum[:])
	meta, _ = json.Marshal(map[string]string{
		"fetched_content_type": resp.Header.Get("Content-Type"),
		"excerpt_note":         "trecho informado pelo autor",
	})
	_ = excerpt
	return hash, meta, nil
}

func (s *Server) publishArticle(ctx context.Context, authorID string, f publishForm, srcs []preparedSource, sessionHash, ipHash string) (string, error) {
	body, err := bodyJSONFromText(f.Body)
	if err != nil {
		return "", err
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)
	q := s.q.WithTx(tx)

	if _, err := tx.Exec(ctx, `SELECT set_config('app.actor_id', $1, true), set_config('app.session_hash', $2, true), set_config('app.ip_hash', $3, true)`,
		authorID, sessionHash, ipHash); err != nil {
		return "", err
	}

	articleID, err := q.InsertArticle(ctx, db.InsertArticleParams{
		AuthorID: authorID,
		Kind:     db.ArticleKind(f.Kind),
	})
	if err != nil {
		return "", err
	}
	versionID, err := q.InsertArticleVersion(ctx, db.InsertArticleVersionParams{
		ArticleID: articleID,
		Title:     f.Title,
		Body:      body,
		CreatedBy: authorID,
	})
	if err != nil {
		return "", err
	}
	for i, src := range srcs {
		if err := q.InsertArticleSource(ctx, db.InsertArticleSourceParams{
			VersionID:            versionID,
			Position:             int16(i + 1),
			Url:                  src.URL,
			OutletDomainID:       src.DomainID,
			Classification:       db.SourceClassificationReport,
			ClassificationMethod: pgtype.Text{String: "path_pattern", Valid: true},
			ClassificationReason: src.Reason,
			ContentHash:          src.Hash,
			Meta:                 src.Meta,
			Excerpt:              src.Excerpt,
			ArchiveUrl:           "",
		}); err != nil {
			return "", err
		}
	}
	if err := q.PublishArticle(ctx, db.PublishArticleParams{ID: articleID, VersionID: versionID}); err != nil {
		return "", err
	}
	payload, _ := json.Marshal(map[string]any{"version_id": versionID, "sources": len(srcs)})
	if err := q.AuditArticlePublished(ctx, db.AuditArticlePublishedParams{
		ActorID: authorID, EntityID: articleID, SessionHash: sessionHash, IpHash: ipHash, Payload: payload,
	}); err != nil {
		return "", err
	}
	if err := tx.Commit(ctx); err != nil {
		return "", err
	}
	return articleID, nil
}

func bodyJSONFromText(text string) ([]byte, error) {
	paras := strings.Split(text, "\n")
	type block struct {
		Type string `json:"type"`
		Text string `json:"text"`
	}
	var blocks []block
	var buf []string
	flush := func() {
		p := strings.TrimSpace(strings.Join(buf, " "))
		buf = nil
		if p != "" {
			blocks = append(blocks, block{Type: "p", Text: p})
		}
	}
	for _, line := range paras {
		if strings.TrimSpace(line) == "" {
			flush()
			continue
		}
		buf = append(buf, strings.TrimSpace(line))
	}
	flush()
	if len(blocks) == 0 {
		return nil, errors.New("empty body")
	}
	return json.Marshal(map[string]any{"blocks": blocks})
}
