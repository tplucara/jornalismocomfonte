// Package web implementa o site público e, futuramente, a área do jornalista.
// Toda saída HTML passa por html/template (escape contextual). Nunca template.HTML com dado de usuário.
package web

import (
	"embed"
	"encoding/json"
	"fmt"
	"html/template"
	"io/fs"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgtype"

	"jornalismocomfonte/internal/db"
	"jornalismocomfonte/internal/httpx"
)

//go:embed templates/*.html
var templateFS embed.FS

//go:embed all:static
var staticFS embed.FS

// StaticFS expõe os arquivos estáticos (CSS próprio, sem terceiros).
func StaticFS() fs.FS {
	sub, err := fs.Sub(staticFS, "static")
	if err != nil {
		panic(err)
	}
	return sub
}

type renderer struct {
	tpl *template.Template
	log *slog.Logger
}

func newRenderer(log *slog.Logger) *renderer {
	funcs := template.FuncMap{
		"kindLabel":             kindLabel,
		"stanceLabel":           stanceLabel,
		"statusLabel":           outletStatusLabel,
		"actionLabel":           outletActionLabel,
		"hashStatusLabel":       hashStatusLabel,
		"removalReasonLabel":    removalReasonLabel,
		"journalistStatusLabel": journalistStatusLabel,
		"fmtDate":               fmtDate,
		"fmtDateTime":           fmtDateTime,
		"pct":                   pct,
		"hostOf":                hostOf,
		"metaTitle":             metaTitle,
		"criterion":             criterion,
		"signalOn":              signalOn,
		"text":                  textOf,
		"initials":              initials,
		"portrait":              portrait,
		"add":                   func(a, b int) int { return a + b },
		"sub":                   func(a, b int) int { return a - b },
	}
	tpl := template.Must(template.New("").Funcs(funcs).ParseFS(templateFS, "templates/*.html"))
	return &renderer{tpl: tpl, log: log}
}

// page é o envelope comum a toda página.
type page struct {
	Title       string
	Description string
	Nonce       string
	Path        string
	JSONLD      template.JS
	Robots      string
	Data        any
}

type jsonLDProvider interface {
	jsonLD() string
}

func (rd *renderer) render(w http.ResponseWriter, r *http.Request, status int, name, title, description string, data any) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(status)
	p := page{
		Title:       title,
		Description: description,
		Nonce:       httpx.Nonce(r.Context()),
		Path:        r.URL.Path,
		Data:        data,
	}
	if j, ok := data.(jsonLDProvider); ok {
		// json.Marshal já escapa <, > e &; template.JS evita o html/template
		// citar o JSON como string JavaScript dentro de <script>.
		p.JSONLD = template.JS(j.jsonLD())
	}
	if rbt, ok := data.(interface{ Robots() string }); ok {
		p.Robots = rbt.Robots()
	}
	err := rd.tpl.ExecuteTemplate(w, name, p)
	if err != nil {
		rd.log.Error("render", "template", name, "err", err)
	}
}

func (rd *renderer) renderError(w http.ResponseWriter, r *http.Request, status int, msg string) {
	rd.render(w, r, status, "error.html", msg, "", map[string]any{"Status": status, "Message": msg})
}

// ---- rótulos (enum → português). Vocabulário conforme responsabilidade-legal.mdc.

func kindLabel(k db.ArticleKind) string {
	switch k {
	case db.ArticleKindReport:
		return "Reportagem"
	case db.ArticleKindAnalysis:
		return "Análise"
	case db.ArticleKindOpinion:
		return "Opinião"
	}
	return string(k)
}

func stanceLabel(s db.CommentStance) string {
	switch s {
	case db.CommentStanceAgree:
		return "Concordo"
	case db.CommentStancePartiallyAgree:
		return "Concordo parcialmente"
	case db.CommentStanceDisagree:
		return "Discordo"
	}
	return string(s)
}

func outletStatusLabel(s db.OutletStatus) string {
	switch s {
	case db.OutletStatusActive:
		return "Ativo"
	case db.OutletStatusSuspended:
		return "Suspenso"
	case db.OutletStatusRemoved:
		return "Removido"
	}
	return string(s)
}

func outletActionLabel(a db.OutletChangeAction) string {
	switch a {
	case db.OutletChangeActionIncluded:
		return "Incluído"
	case db.OutletChangeActionSuspended:
		return "Suspenso"
	case db.OutletChangeActionReinstated:
		return "Reativado"
	case db.OutletChangeActionRemoved:
		return "Removido"
	case db.OutletChangeActionCriteriaUpdated:
		return "Critérios atualizados"
	}
	return string(a)
}

func fmtDate(t pgtype.Timestamptz) string {
	if !t.Valid {
		return ""
	}
	return t.Time.In(saoPaulo).Format("02/01/2006")
}

func fmtDateTime(t pgtype.Timestamptz) string {
	if !t.Valid {
		return ""
	}
	return t.Time.In(saoPaulo).Format("02/01/2006 15:04")
}

var saoPaulo = func() *time.Location {
	loc, err := time.LoadLocation("America/Sao_Paulo")
	if err != nil {
		return time.FixedZone("BRT", -3*3600)
	}
	return loc
}()

func pct(part, total int32) string {
	if total == 0 {
		return "—"
	}
	return fmt.Sprintf("%d%%", int(float64(part)*100/float64(total)+0.5))
}

func hostOf(u string) string {
	u = strings.TrimPrefix(strings.TrimPrefix(u, "https://"), "http://")
	if i := strings.IndexAny(u, "/?#"); i >= 0 {
		u = u[:i]
	}
	return strings.TrimPrefix(u, "www.")
}

// metaTitle extrai o título da reportagem do jsonb `meta` da fonte.
func metaTitle(meta []byte) string {
	var m struct {
		Title string `json:"title"`
	}
	_ = json.Unmarshal(meta, &m)
	return m.Title
}

// criterion lê uma chave do jsonb `criteria` do veículo.
func hashStatusLabel(s db.SourceHashStatus) string {
	switch s {
	case db.SourceHashStatusChanged:
		return "Fonte alterada desde a publicação"
	case db.SourceHashStatusUnavailable:
		return "Fonte indisponível"
	default:
		return ""
	}
}

func removalReasonLabel(r db.NullRemovalReason) string {
	if !r.Valid {
		return ""
	}
	switch r.RemovalReason {
	case db.RemovalReasonCourtOrder:
		return "ordem judicial"
	case db.RemovalReasonValidNotice:
		return "notificação válida"
	case db.RemovalReasonTermsViolation:
		return "violação dos Termos"
	case db.RemovalReasonAuthor:
		return "decisão do autor"
	}
	return string(r.RemovalReason)
}

func journalistStatusLabel(s db.JournalistStatus) string {
	switch s {
	case db.JournalistStatusSuspended:
		return "Conta suspensa"
	default:
		return ""
	}
}

func signalOn(signals []byte, key string) bool {
	var m map[string]any
	_ = json.Unmarshal(signals, &m)
	b, _ := m[key].(bool)
	return b
}

func textOf(t pgtype.Text) string {
	if !t.Valid {
		return ""
	}
	return t.String
}

// portrait é a miniatura da foto. Só aceita arquivo do próprio site:
// img-src da CSP é 'self', e a plataforma não faz hotlink de mídia.
type portraitData struct {
	URL      string
	Class    string
	Initials string
}

func portrait(name, url, class string) portraitData {
	return portraitData{URL: sameOriginAvatar(url), Class: class, Initials: initials(name)}
}

func sameOriginAvatar(raw string) string {
	raw = strings.TrimSpace(raw)
	if strings.Contains(raw, "..") || strings.ContainsAny(raw, "\\?#") {
		return ""
	}
	if strings.HasPrefix(raw, "/static/avatars/") {
		name := strings.TrimPrefix(raw, "/static/avatars/")
		if name == "" || strings.Contains(name, "/") {
			return ""
		}
		return raw
	}
	// Upload do jornalista: /media/a/{uuid}.jpg
	if strings.HasPrefix(raw, "/media/a/") {
		name := strings.TrimPrefix(raw, "/media/a/")
		if name == "" || strings.Contains(name, "/") || !strings.HasSuffix(strings.ToLower(name), ".jpg") {
			return ""
		}
		return raw
	}
	return ""
}

func initials(name string) string {
	parts := strings.Fields(name)
	if len(parts) == 0 {
		return "?"
	}
	r := []rune(parts[0])
	out := string(r[0:1])
	if len(parts) > 1 {
		r2 := []rune(parts[len(parts)-1])
		out += string(r2[0:1])
	}
	return strings.ToUpper(out)
}

func criterion(criteria []byte, key string) string {
	var m map[string]any
	_ = json.Unmarshal(criteria, &m)
	if v, ok := m[key].(string); ok {
		return v
	}
	return ""
}

// ---- modelos de visualização

type articleBody struct {
	Blocks []struct {
		Type string `json:"type"`
		Text string `json:"text"`
	} `json:"blocks"`
}

func parseBody(raw []byte) articleBody {
	var b articleBody
	_ = json.Unmarshal(raw, &b)
	return b
}

type reputationComponent struct {
	Score        float64 `json:"score"`
	CILow        float64 `json:"ci_low"`
	CIHigh       float64 `json:"ci_high"`
	NValid       int     `json:"n_valid"`
	Insufficient bool    `json:"insufficient"`
}

func (c reputationComponent) ScorePct() int  { return int(c.Score*100 + 0.5) }
func (c reputationComponent) CILowPct() int  { return int(c.CILow*100 + 0.5) }
func (c reputationComponent) CIHighPct() int { return int(c.CIHigh*100 + 0.5) }

func parseReputation(raw []byte) reputationComponent {
	var c reputationComponent
	_ = json.Unmarshal(raw, &c)
	return c
}
