package web

import (
	"bytes"
	"image"
	"image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"strings"

	"github.com/jackc/pgx/v5/pgtype"

	"jornalismocomfonte/internal/db"
)

const (
	maxAvatarUpload = 5 << 20 // 5 MiB de entrada (foto de celular)
	maxAvatarStored = 512 << 10
	avatarMaxSide   = 512
)

func (s *Server) handleAvatarUpload(w http.ResponseWriter, r *http.Request) {
	noStore(w)
	id := s.journalistID(r.Context())
	if id == "" {
		http.Redirect(w, r, "/entrar", http.StatusSeeOther)
		return
	}
	if s.media == nil {
		s.rd.renderError(w, r, http.StatusServiceUnavailable, "Upload de foto indisponível neste ambiente.")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxAvatarUpload+64<<10)
	if err := r.ParseMultipartForm(maxAvatarUpload + 64<<10); err != nil {
		s.sessions.Put(r.Context(), sessionFlash, "A foto precisa ter no máximo 5 MiB. No celular, escolha “tamanho médio” ou exporte como JPEG.")
		http.Redirect(w, r, "/conta", http.StatusSeeOther)
		return
	}
	file, hdr, err := r.FormFile("avatar")
	if err != nil {
		s.sessions.Put(r.Context(), sessionFlash, "Escolha um arquivo de imagem.")
		http.Redirect(w, r, "/conta", http.StatusSeeOther)
		return
	}
	defer file.Close()

	raw, err := io.ReadAll(io.LimitReader(file, maxAvatarUpload+1))
	if err != nil || len(raw) == 0 {
		s.sessions.Put(r.Context(), sessionFlash, "Não foi possível ler o arquivo.")
		http.Redirect(w, r, "/conta", http.StatusSeeOther)
		return
	}
	if len(raw) > maxAvatarUpload {
		s.sessions.Put(r.Context(), sessionFlash, "A foto precisa ter no máximo 5 MiB.")
		http.Redirect(w, r, "/conta", http.StatusSeeOther)
		return
	}

	ct := strings.ToLower(strings.TrimSpace(hdr.Header.Get("Content-Type")))
	if ct != "" && !avatarContentTypeOK(ct) && !sniffJPEGOrPNG(raw) {
		s.sessions.Put(r.Context(), sessionFlash, "Use JPEG ou PNG. Fotos HEIC/WebP do iPhone ou Android precisam ser exportadas como JPEG.")
		http.Redirect(w, r, "/conta", http.StatusSeeOther)
		return
	}
	if !sniffJPEGOrPNG(raw) {
		s.sessions.Put(r.Context(), sessionFlash, "Não foi possível ler a imagem. Use JPEG ou PNG (não HEIC nem WebP).")
		http.Redirect(w, r, "/conta", http.StatusSeeOther)
		return
	}

	img, _, err := image.Decode(bytes.NewReader(raw))
	if err != nil {
		s.sessions.Put(r.Context(), sessionFlash, "Não foi possível ler a imagem. Use JPEG ou PNG.")
		http.Redirect(w, r, "/conta", http.StatusSeeOther)
		return
	}
	b := img.Bounds()
	if b.Dx() < 64 || b.Dy() < 64 {
		s.sessions.Put(r.Context(), sessionFlash, "A imagem precisa ter pelo menos 64 pixels de lado.")
		http.Redirect(w, r, "/conta", http.StatusSeeOther)
		return
	}
	img = resizeMax(img, avatarMaxSide)

	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 85}); err != nil {
		s.fail(w, r, err)
		return
	}
	if buf.Len() > maxAvatarStored {
		buf.Reset()
		if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 70}); err != nil {
			s.fail(w, r, err)
			return
		}
	}
	if buf.Len() > maxAvatarStored {
		s.sessions.Put(r.Context(), sessionFlash, "A foto ficou grande demais depois do processamento. Tente outra.")
		http.Redirect(w, r, "/conta", http.StatusSeeOther)
		return
	}
	url, err := s.media.PutAvatar(id, bytes.NewReader(buf.Bytes()))
	if err != nil {
		s.fail(w, r, err)
		return
	}
	if err := s.q.UpdateJournalistAvatar(r.Context(), db.UpdateJournalistAvatarParams{
		ID:        id,
		AvatarUrl: pgtype.Text{String: url, Valid: true},
	}); err != nil {
		s.fail(w, r, err)
		return
	}
	s.sessions.Put(r.Context(), sessionFlash, "Foto de perfil atualizada.")
	http.Redirect(w, r, "/conta", http.StatusSeeOther)
}

func avatarContentTypeOK(ct string) bool {
	return strings.HasPrefix(ct, "image/jpeg") ||
		strings.HasPrefix(ct, "image/jpg") ||
		strings.HasPrefix(ct, "image/png") ||
		ct == "application/octet-stream" ||
		ct == "binary/octet-stream"
}

func sniffJPEGOrPNG(raw []byte) bool {
	if len(raw) >= 3 && raw[0] == 0xff && raw[1] == 0xd8 && raw[2] == 0xff {
		return true
	}
	if len(raw) >= 8 && raw[0] == 0x89 && raw[1] == 0x50 && raw[2] == 0x4e && raw[3] == 0x47 {
		return true
	}
	return false
}

func resizeMax(img image.Image, maxSide int) image.Image {
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	if w <= maxSide && h <= maxSide {
		return img
	}
	nw, nh := w, h
	if w >= h {
		nw = maxSide
		nh = h * maxSide / w
	} else {
		nh = maxSide
		nw = w * maxSide / h
	}
	if nw < 1 {
		nw = 1
	}
	if nh < 1 {
		nh = 1
	}
	dst := image.NewRGBA(image.Rect(0, 0, nw, nh))
	for y := 0; y < nh; y++ {
		sy := b.Min.Y + y*h/nh
		for x := 0; x < nw; x++ {
			sx := b.Min.X + x*w/nw
			dst.Set(x, y, img.At(sx, sy))
		}
	}
	return dst
}

func (s *Server) handleMediaAvatar(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	if name == "" || strings.Contains(name, "..") || strings.ContainsAny(name, "/\\") {
		http.NotFound(w, r)
		return
	}
	if !strings.HasSuffix(strings.ToLower(name), ".jpg") {
		http.NotFound(w, r)
		return
	}
	if s.media == nil {
		http.NotFound(w, r)
		return
	}
	f, err := s.media.Open("avatars/" + name)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "image/jpeg")
	w.Header().Set("Cache-Control", "public, max-age=3600")
	http.ServeContent(w, r, name, info.ModTime(), f)
}
