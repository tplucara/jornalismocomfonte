-- Conta do jornalista: criação, entrada e sessão.
-- A senha já chega como hash Argon2id. O e-mail não entra na auditoria.

-- name: CreateJournalist :one
INSERT INTO journalists (email, password_hash, display_name, tagline)
VALUES (
  sqlc.arg('email'),
  sqlc.arg('password_hash'),
  sqlc.arg('display_name'),
  NULLIF(sqlc.arg('tagline'), '')
)
RETURNING id;

-- name: InsertLegalAcceptance :exec
INSERT INTO legal_acceptances (journalist_id, document, version, adult_declaration, session_hash)
VALUES (
  sqlc.arg('journalist_id'),
  sqlc.arg('document'),
  sqlc.arg('version'),
  true,
  sqlc.arg('session_hash')
);

-- name: AuditJournalistCreated :exec
INSERT INTO audit_log (actor_id, action, entity_type, entity_id, session_hash, ip_hash, payload)
VALUES (
  sqlc.arg('actor_id'),
  'journalist.create',
  'journalists',
  sqlc.arg('actor_id'),
  NULLIF(sqlc.arg('session_hash'), ''),
  NULLIF(sqlc.arg('ip_hash'), ''),
  '{"status":"pending_verification"}'::jsonb
);

-- name: GetJournalistForLogin :one
SELECT id, password_hash, status
FROM journalists
WHERE email = sqlc.arg('email');

-- name: GetJournalistAccount :one
SELECT id, email, display_name, coalesce(tagline, '')::text AS tagline,
       coalesce(avatar_url, '')::text AS avatar_url, status
FROM journalists
WHERE id = sqlc.arg('id');

-- name: UpsertSession :exec
INSERT INTO sessions (token, data, expiry)
VALUES ($1, $2, $3)
ON CONFLICT (token) DO UPDATE
SET data = EXCLUDED.data, expiry = EXCLUDED.expiry;

-- name: GetSession :one
SELECT data, expiry
FROM sessions
WHERE token = $1;

-- name: DeleteSession :exec
DELETE FROM sessions WHERE token = $1;

-- name: DeleteExpiredSessions :exec
DELETE FROM sessions WHERE expiry <= now();
