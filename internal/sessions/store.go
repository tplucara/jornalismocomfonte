// Package sessions implementa o armazenamento server-side exigido pelo scs, via sqlc.
package sessions

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"jornalismocomfonte/internal/db"
)

// Store fala com a tabela sessions. O token vencido ou ausente não é erro.
type Store struct {
	q *db.Queries
}

func New(q *db.Queries) *Store {
	return &Store{q: q}
}

func (s *Store) Delete(token string) error {
	return s.DeleteCtx(context.Background(), token)
}

func (s *Store) Find(token string) ([]byte, bool, error) {
	return s.FindCtx(context.Background(), token)
}

func (s *Store) Commit(token string, b []byte, expiry time.Time) error {
	return s.CommitCtx(context.Background(), token, b, expiry)
}

func (s *Store) DeleteCtx(ctx context.Context, token string) error {
	if s.q == nil {
		return errors.New("sessão sem banco")
	}
	return s.q.DeleteSession(ctx, token)
}

func (s *Store) FindCtx(ctx context.Context, token string) ([]byte, bool, error) {
	if s.q == nil {
		return nil, false, errors.New("sessão sem banco")
	}
	row, err := s.q.GetSession(ctx, token)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	if !row.Expiry.Valid || !row.Expiry.Time.After(time.Now()) {
		_ = s.q.DeleteSession(ctx, token)
		return nil, false, nil
	}
	return row.Data, true, nil
}

func (s *Store) CommitCtx(ctx context.Context, token string, b []byte, expiry time.Time) error {
	if s.q == nil {
		return errors.New("sessão sem banco")
	}
	if err := s.q.DeleteExpiredSessions(ctx); err != nil {
		return err
	}
	return s.q.UpsertSession(ctx, db.UpsertSessionParams{
		Token:  token,
		Data:   b,
		Expiry: pgtype.Timestamptz{Time: expiry, Valid: true},
	})
}
