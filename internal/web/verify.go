package web

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"path"
	"strings"

	"github.com/jackc/pgx/v5/pgtype"

	"jornalismocomfonte/internal/db"
)

const maxProofBytes = 2 << 20 // 2 MiB
const staffEmail = "staff@jcf.example"

func (s *Server) isStaff(email string) bool {
	return strings.EqualFold(email, staffEmail)
}

func (s *Server) handleProofUpload(w http.ResponseWriter, r *http.Request) {
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
	if st.Status != db.JournalistStatusPendingVerification {
		s.sessions.Put(r.Context(), sessionFlash, "Esta conta não aguarda comprovante.")
		http.Redirect(w, r, "/conta", http.StatusSeeOther)
		return
	}
	pending, err := s.q.HasPendingVerification(r.Context(), id)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	if pending {
		s.sessions.Put(r.Context(), sessionFlash, "Já há um comprovante em análise.")
		http.Redirect(w, r, "/conta", http.StatusSeeOther)
		return
	}
	if s.media == nil {
		s.rd.renderError(w, r, http.StatusServiceUnavailable, "Upload indisponível neste ambiente.")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxProofBytes+64<<10)
	if err := r.ParseMultipartForm(maxProofBytes + 64<<10); err != nil {
		s.sessions.Put(r.Context(), sessionFlash, "O arquivo precisa ter no máximo 2 MiB.")
		http.Redirect(w, r, "/conta", http.StatusSeeOther)
		return
	}
	method := db.VerificationMethod(r.PostForm.Get("method"))
	if !method.Valid() {
		s.sessions.Put(r.Context(), sessionFlash, "Escolha o tipo de comprovante.")
		http.Redirect(w, r, "/conta", http.StatusSeeOther)
		return
	}
	file, hdr, err := r.FormFile("proof")
	if err != nil {
		s.sessions.Put(r.Context(), sessionFlash, "Anexe o comprovante (PDF, JPEG ou PNG).")
		http.Redirect(w, r, "/conta", http.StatusSeeOther)
		return
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, maxProofBytes+1))
	if err != nil || len(data) == 0 || len(data) > maxProofBytes {
		s.sessions.Put(r.Context(), sessionFlash, "Não foi possível ler o arquivo.")
		http.Redirect(w, r, "/conta", http.StatusSeeOther)
		return
	}
	sum := sha256.Sum256(data)
	docHash := hex.EncodeToString(sum[:])
	ext := strings.ToLower(strings.TrimPrefix(path.Ext(hdr.Filename), "."))
	if ext == "" {
		ct := hdr.Header.Get("Content-Type")
		switch {
		case strings.Contains(ct, "pdf"):
			ext = "pdf"
		case strings.Contains(ct, "png"):
			ext = "png"
		default:
			ext = "jpg"
		}
	}
	meta, _ := json.Marshal(map[string]string{
		"filename":     path.Base(hdr.Filename),
		"content_type": hdr.Header.Get("Content-Type"),
		"note":         strings.TrimSpace(r.PostForm.Get("note")),
	})
	vid, err := s.q.InsertVerificationPending(r.Context(), db.InsertVerificationPendingParams{
		JournalistID: id,
		Method:       method,
		DocumentHash: docHash,
		EvidenceMeta: meta,
	})
	if err != nil {
		s.fail(w, r, err)
		return
	}
	if _, err := s.media.PutProof(vid, ext, bytes.NewReader(data)); err != nil {
		s.fail(w, r, err)
		return
	}
	s.sessions.Put(r.Context(), sessionFlash, "Comprovante enviado. A equipe analisa e responde por aqui.")
	http.Redirect(w, r, "/conta", http.StatusSeeOther)
}

func (s *Server) handleStaffVerifications(w http.ResponseWriter, r *http.Request) {
	noStore(w)
	id := s.journalistID(r.Context())
	if id == "" {
		http.Redirect(w, r, "/entrar", http.StatusSeeOther)
		return
	}
	st, err := s.q.GetJournalistStatus(r.Context(), id)
	if err != nil || !s.isStaff(st.Email) {
		s.rd.renderError(w, r, http.StatusForbidden, "Área restrita à equipe.")
		return
	}
	if r.Method == http.MethodPost {
		s.decideVerification(w, r, id)
		return
	}
	rows, err := s.q.ListPendingVerifications(r.Context())
	if err != nil {
		s.fail(w, r, err)
		return
	}
	s.rd.render(w, r, http.StatusOK, "staff_verifications.html", "Verificações", "Revisão humana de identidade.", staffVerificationsView{
		Rows:  rows,
		Flash: s.sessions.PopString(r.Context(), sessionFlash),
	})
}

type staffVerificationsView struct {
	Rows  []db.ListPendingVerificationsRow
	Flash string
}

func (staffVerificationsView) Robots() string { return "noindex, follow" }

func (s *Server) decideVerification(w http.ResponseWriter, r *http.Request, reviewerID string) {
	if err := r.ParseForm(); err != nil {
		s.rd.renderError(w, r, http.StatusBadRequest, "Pedido inválido.")
		return
	}
	vid := r.PostForm.Get("id")
	decision := r.PostForm.Get("decision")
	reason := strings.TrimSpace(r.PostForm.Get("reason"))
	if reason == "" {
		s.sessions.Put(r.Context(), sessionFlash, "Informe o motivo da decisão.")
		http.Redirect(w, r, "/equipe/verificacoes", http.StatusSeeOther)
		return
	}
	var status db.VerificationStatus
	switch decision {
	case "approved":
		status = db.VerificationStatusApproved
	case "rejected":
		status = db.VerificationStatusRejected
	default:
		s.sessions.Put(r.Context(), sessionFlash, "Decisão inválida.")
		http.Redirect(w, r, "/equipe/verificacoes", http.StatusSeeOther)
		return
	}
	v, err := s.q.GetVerification(r.Context(), vid)
	if err != nil || v.Status != db.VerificationStatusPending {
		s.sessions.Put(r.Context(), sessionFlash, "Pedido não encontrado ou já decidido.")
		http.Redirect(w, r, "/equipe/verificacoes", http.StatusSeeOther)
		return
	}
	if err := s.q.DecideVerification(r.Context(), db.DecideVerificationParams{
		Status:         status,
		ReviewerID:     reviewerID,
		DecisionReason: pgtype.Text{String: reason, Valid: true},
		PurgeRaw:       true,
		ID:             vid,
	}); err != nil {
		s.fail(w, r, err)
		return
	}
	// Apaga arquivo bruto após a decisão (perfil-identidade.mdc).
	if s.media != nil {
		for _, ext := range []string{"pdf", "jpg", "png"} {
			_ = s.media.Remove("proofs/" + vid + "." + ext)
		}
	}
	s.sessions.Put(r.Context(), sessionFlash, "Decisão registrada.")
	http.Redirect(w, r, "/equipe/verificacoes", http.StatusSeeOther)
}
