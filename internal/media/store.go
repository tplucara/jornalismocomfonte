// Package media guarda avatares e comprovantes em disco.
// MinIO/S3 é o alvo de produção (ADR 0001); a imagem MinIO não puxa neste
// ambiente, então o desenvolvimento usa um volume Docker em MEDIA_DIR.
package media

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

var (
	ErrNotFound = errors.New("media: not found")
	ErrDenied   = errors.New("media: path denied")
)

// Store é um diretório raiz. Sem symlink escape: tudo sob Root.
type Store struct {
	Root string
}

func Open(root string) (*Store, error) {
	root = strings.TrimSpace(root)
	if root == "" {
		return nil, errors.New("MEDIA_DIR vazio")
	}
	if err := os.MkdirAll(filepath.Join(root, "avatars"), 0o750); err != nil {
		return nil, err
	}
	if err := os.MkdirAll(filepath.Join(root, "proofs"), 0o750); err != nil {
		return nil, err
	}
	return &Store{Root: root}, nil
}

func (s *Store) put(rel string, r io.Reader) error {
	full, err := s.resolve(rel)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(full), 0o750); err != nil {
		return err
	}
	tmp := full + ".tmp"
	f, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o640)
	if err != nil {
		return err
	}
	_, copyErr := io.Copy(f, r)
	closeErr := f.Close()
	if copyErr != nil {
		_ = os.Remove(tmp)
		return copyErr
	}
	if closeErr != nil {
		_ = os.Remove(tmp)
		return closeErr
	}
	return os.Rename(tmp, full)
}

func (s *Store) PutAvatar(journalistID string, r io.Reader) (string, error) {
	rel := filepath.Join("avatars", journalistID+".jpg")
	if err := s.put(rel, r); err != nil {
		return "", err
	}
	return "/media/a/" + journalistID + ".jpg", nil
}

func (s *Store) PutProof(verificationID string, ext string, r io.Reader) (string, error) {
	ext = strings.TrimPrefix(strings.ToLower(ext), ".")
	if ext != "pdf" && ext != "jpg" && ext != "jpeg" && ext != "png" {
		return "", fmt.Errorf("extensão não permitida: %s", ext)
	}
	if ext == "jpeg" {
		ext = "jpg"
	}
	rel := filepath.Join("proofs", verificationID+"."+ext)
	if err := s.put(rel, r); err != nil {
		return "", err
	}
	return rel, nil
}

func (s *Store) Open(rel string) (*os.File, error) {
	full, err := s.resolve(rel)
	if err != nil {
		return nil, err
	}
	f, err := os.Open(full)
	if errors.Is(err, os.ErrNotExist) {
		return nil, ErrNotFound
	}
	return f, err
}

func (s *Store) Remove(rel string) error {
	full, err := s.resolve(rel)
	if err != nil {
		return err
	}
	err = os.Remove(full)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	return err
}

func (s *Store) resolve(rel string) (string, error) {
	rel = filepath.Clean("/" + strings.ReplaceAll(rel, "\\", "/"))
	rel = strings.TrimPrefix(rel, string(filepath.Separator))
	if rel == "." || rel == "" || strings.HasPrefix(rel, "..") {
		return "", ErrDenied
	}
	full := filepath.Join(s.Root, rel)
	root := filepath.Clean(s.Root) + string(filepath.Separator)
	if full != filepath.Clean(s.Root) && !strings.HasPrefix(full, root) {
		return "", ErrDenied
	}
	return full, nil
}
