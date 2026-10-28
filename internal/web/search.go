package web

import (
	"errors"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5/pgtype"

	"jornalismocomfonte/internal/db"
)

const searchQueryMax = 120

var errBadSearch = errors.New("filtro inválido")

type searchFilters struct {
	Q, Kind, AuthorID, OutletID, From, To string
	Page                                  int
	FromTime, ToTime                      time.Time
	HasFrom, HasTo                        bool
}

type searchView struct {
	searchFilters
	Authors    []db.ListPublishedAuthorsRow
	Outlets    []db.ListCitedOutletsRow
	Articles   []db.SearchArticlesRow
	MatchCount int32
	HasNext    bool
	HasPrev    bool
}

// Robots: a busca não é uma página de conteúdo. Os artigos encontrados têm URL própria.
func (searchView) Robots() string { return "noindex, follow" }

// Advanced é verdadeiro quando algum filtro além do texto está preenchido.
func (v searchView) Advanced() bool {
	return v.Kind != "" || v.AuthorID != "" || v.OutletID != "" || v.From != "" || v.To != ""
}

// ClearAdvancedHref tira os filtros e conserva o texto da busca ampla.
func (v searchView) ClearAdvancedHref() string {
	if v.Q == "" {
		return "/busca"
	}
	return "/busca?q=" + url.QueryEscape(v.Q)
}

func (v searchView) PageHref(page int) string {
	vals := url.Values{}
	if v.Q != "" {
		vals.Set("q", v.Q)
	}
	if v.Kind != "" {
		vals.Set("tipo", v.Kind)
	}
	if v.AuthorID != "" {
		vals.Set("jornalista", v.AuthorID)
	}
	if v.OutletID != "" {
		vals.Set("veiculo", v.OutletID)
	}
	if v.From != "" {
		vals.Set("de", v.From)
	}
	if v.To != "" {
		vals.Set("ate", v.To)
	}
	if page > 1 {
		vals.Set("p", strconv.Itoa(page))
	}
	if len(vals) == 0 {
		return "/busca"
	}
	return "/busca?" + vals.Encode()
}

func (s *Server) handleSearch(w http.ResponseWriter, r *http.Request) {
	f, err := parseSearch(r)
	if err != nil {
		s.rd.renderError(w, r, http.StatusBadRequest, "Filtro inválido")
		return
	}
	ctx := r.Context()
	authors, err := s.q.ListPublishedAuthors(ctx)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	outlets, err := s.q.ListCitedOutlets(ctx)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	rows, err := s.q.SearchArticles(ctx, searchParams(f))
	if err != nil {
		s.fail(w, r, err)
		return
	}
	v := searchView{
		searchFilters: f,
		Authors:       authors,
		Outlets:       outlets,
		Articles:      rows,
		HasPrev:       f.Page > 1,
	}
	if len(rows) > 0 {
		v.MatchCount = rows[0].MatchCount
		v.HasNext = int(v.MatchCount) > f.Page*feedPageSize
	}
	cachePublic(w)
	s.rd.render(w, r, http.StatusOK, "search.html",
		"Busca",
		"Busca ampla por título, texto, jornalista ou veículo. A busca avançada restringe por tipo, período, jornalista e veículo. Resultados em ordem cronológica.",
		v)
}

func searchParams(f searchFilters) db.SearchArticlesParams {
	p := db.SearchArticlesParams{
		Kind:       textOpt(f.Kind),
		AuthorID:   textOpt(f.AuthorID),
		OutletID:   textOpt(f.OutletID),
		PageOffset: int32((f.Page - 1) * feedPageSize),
		PageSize:   feedPageSize,
	}
	if f.Q != "" {
		p.Q = textOpt(f.Q)
		p.LikeQ = textOpt(likeContains(f.Q))
	}
	if f.HasFrom {
		p.PublishedFrom = pgtype.Timestamptz{Time: f.FromTime, Valid: true}
	}
	if f.HasTo {
		p.PublishedTo = pgtype.Timestamptz{Time: f.ToTime.AddDate(0, 0, 1), Valid: true}
	}
	return p
}

func parseSearch(r *http.Request) (searchFilters, error) {
	var f searchFilters
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if utf8.RuneCountInString(q) > searchQueryMax || strings.ContainsRune(q, 0) {
		return f, errBadSearch
	}
	f.Q = q
	f.Kind = r.URL.Query().Get("tipo")
	switch f.Kind {
	case "", "report", "analysis", "opinion":
	default:
		return f, errBadSearch
	}
	f.AuthorID = r.URL.Query().Get("jornalista")
	if f.AuthorID != "" && !uuidRe.MatchString(f.AuthorID) {
		return f, errBadSearch
	}
	f.OutletID = r.URL.Query().Get("veiculo")
	if f.OutletID != "" && !uuidRe.MatchString(f.OutletID) {
		return f, errBadSearch
	}
	var err error
	if f.FromTime, f.HasFrom, err = parseDay(r.URL.Query().Get("de")); err != nil {
		return f, err
	}
	if f.ToTime, f.HasTo, err = parseDay(r.URL.Query().Get("ate")); err != nil {
		return f, err
	}
	if f.HasFrom {
		f.From = f.FromTime.Format("2006-01-02")
	}
	if f.HasTo {
		f.To = f.ToTime.Format("2006-01-02")
	}
	if f.HasFrom && f.HasTo && f.ToTime.Before(f.FromTime) {
		return f, errBadSearch
	}
	f.Page = 1
	if p := r.URL.Query().Get("p"); p != "" {
		n, err := strconv.Atoi(p)
		if err != nil || n < 1 || n > 10000 {
			return f, errBadSearch
		}
		f.Page = n
	}
	return f, nil
}

func parseDay(s string) (time.Time, bool, error) {
	if s == "" {
		return time.Time{}, false, nil
	}
	t, err := time.ParseInLocation("2006-01-02", s, saoPaulo)
	if err != nil {
		return time.Time{}, false, errBadSearch
	}
	return t, true, nil
}

func textOpt(s string) pgtype.Text {
	if s == "" {
		return pgtype.Text{}
	}
	return pgtype.Text{String: s, Valid: true}
}

// likeContains escapa curingas para que o texto digitado seja literal.
func likeContains(s string) string {
	var b strings.Builder
	b.Grow(len(s) + 2)
	b.WriteByte('%')
	for _, r := range s {
		if r == '%' || r == '_' || r == '\\' {
			b.WriteByte('\\')
		}
		b.WriteRune(r)
	}
	b.WriteByte('%')
	return b.String()
}
