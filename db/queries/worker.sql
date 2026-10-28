-- Queries do worker (manutenção e jobs).

-- name: EnsureMonthPartition :exec
SELECT ensure_month_partition(sqlc.arg(parent)::regclass, sqlc.arg(month)::date);

-- name: DropExpiredAccessLogPartitions :one
SELECT drop_expired_access_log_partitions()::int AS dropped;

-- name: ListSourcesForHashRecheck :many
SELECT id, url, content_hash
FROM article_sources
WHERE hash_compared_at IS NULL OR hash_compared_at < now() - interval '7 days'
ORDER BY hash_compared_at NULLS FIRST
LIMIT sqlc.arg(batch)::int;

-- name: UpdateSourceHashStatus :exec
UPDATE article_sources
SET hash_status = $2, hash_compared_at = now()
WHERE id = $1;

-- name: ListPendingVotes :many
SELECT id, article_id, journalist_id, verdict, note, created_at
FROM fidelity_votes
WHERE filter_status = 'pending'
ORDER BY created_at
LIMIT sqlc.arg(batch)::int
FOR UPDATE SKIP LOCKED;

-- name: ListPendingComments :many
SELECT id, article_id, journalist_id, stance, body, created_at
FROM comments
WHERE filter_status = 'pending'
ORDER BY created_at
LIMIT sqlc.arg(batch)::int
FOR UPDATE SKIP LOCKED;

-- name: ListVersionsWithoutKindDecision :many
-- Versões publicadas ainda sem decisão. A tag do leitor sai daqui, não de um rótulo fixo.
SELECT
  a.id AS article_id,
  v.id AS version_id,
  article_plain_text(v.title, v.body) AS plain
FROM articles a
JOIN article_versions v ON v.id = a.current_version_id
WHERE a.status = 'published'
  AND NOT EXISTS (
    SELECT 1 FROM article_kind_decisions d WHERE d.version_id = v.id
  )
ORDER BY a.published_at DESC
LIMIT sqlc.arg(batch)::int;

-- name: InsertKindDecision :exec
INSERT INTO article_kind_decisions (article_id, version_id, kind, method, model, reason)
VALUES ($1, $2, $3, $4, $5, $6);

-- name: SetArticleKind :exec
UPDATE articles
SET kind = $2
WHERE id = $1 AND kind IS DISTINCT FROM $2;

-- name: ListSourcesWithoutQuiz :many
SELECT s.id, s.url, s.excerpt, s.meta
FROM article_sources s
WHERE NOT EXISTS (SELECT 1 FROM quiz_questions q WHERE q.source_id = s.id AND q.active)
LIMIT sqlc.arg(batch)::int;
