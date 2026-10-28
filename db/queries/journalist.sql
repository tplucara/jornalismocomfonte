-- Área do jornalista: perfil, verificação e publicação.

-- name: UpdateJournalistAvatar :exec
UPDATE journalists
SET avatar_url = sqlc.arg('avatar_url')
WHERE id = sqlc.arg('id');

-- name: GetJournalistStatus :one
SELECT id, status, email, display_name
FROM journalists
WHERE id = sqlc.arg('id');

-- name: InsertVerificationPending :one
INSERT INTO verifications (journalist_id, method, document_hash, evidence_meta, status)
VALUES (
  sqlc.arg('journalist_id'),
  sqlc.arg('method'),
  sqlc.arg('document_hash'),
  sqlc.arg('evidence_meta'),
  'pending'
)
RETURNING id;

-- name: ListPendingVerifications :many
SELECT
  v.id,
  v.journalist_id,
  j.display_name,
  j.email,
  v.method,
  v.evidence_meta,
  v.submitted_at
FROM verifications v
JOIN journalists j ON j.id = v.journalist_id
WHERE v.status = 'pending'
ORDER BY v.submitted_at;

-- name: GetVerification :one
SELECT
  v.id,
  v.journalist_id,
  v.method,
  v.document_hash,
  v.evidence_meta,
  v.status,
  v.submitted_at
FROM verifications v
WHERE v.id = sqlc.arg('id');

-- name: DecideVerification :exec
UPDATE verifications
SET
  status = sqlc.arg('status'),
  reviewer_id = sqlc.arg('reviewer_id'),
  decision_reason = sqlc.arg('decision_reason'),
  decided_at = now(),
  raw_purged_at = CASE WHEN sqlc.arg('purge_raw')::boolean THEN now() ELSE raw_purged_at END
WHERE id = sqlc.arg('id') AND status = 'pending';

-- name: FindOutletDomainByHost :one
SELECT
  d.id AS domain_id,
  d.domain,
  d.opinion_path_patterns,
  o.id AS outlet_id,
  o.name AS outlet_name,
  o.status AS outlet_status
FROM outlet_domains d
JOIN outlets o ON o.id = d.outlet_id
WHERE lower(sqlc.arg('host')::text) = d.domain::text
   OR lower(sqlc.arg('host')::text) LIKE ('%.' || d.domain::text)
ORDER BY length(d.domain::text) DESC
LIMIT 1;

-- name: InsertArticle :one
INSERT INTO articles (author_id, kind, status)
VALUES (sqlc.arg('author_id'), sqlc.arg('kind'), 'draft')
RETURNING id;

-- name: InsertArticleVersion :one
INSERT INTO article_versions (article_id, version_no, title, body, created_by)
VALUES (
  sqlc.arg('article_id'),
  1,
  sqlc.arg('title'),
  sqlc.arg('body'),
  sqlc.arg('created_by')
)
RETURNING id;

-- name: InsertArticleSource :exec
INSERT INTO article_sources (
  version_id, position, url, outlet_domain_id,
  classification, classification_method, classification_reason,
  content_hash, meta, excerpt, archive_url, hash_status, hash_compared_at
) VALUES (
  sqlc.arg('version_id'),
  sqlc.arg('position'),
  sqlc.arg('url'),
  sqlc.arg('outlet_domain_id'),
  sqlc.arg('classification'),
  sqlc.arg('classification_method'),
  NULLIF(sqlc.arg('classification_reason'), ''),
  sqlc.arg('content_hash'),
  sqlc.arg('meta')::jsonb,
  sqlc.arg('excerpt'),
  NULLIF(sqlc.arg('archive_url'), ''),
  'ok',
  now()
);

-- name: PublishArticle :exec
UPDATE articles
SET
  status = 'published',
  published_at = now(),
  current_version_id = sqlc.arg('version_id')
WHERE id = sqlc.arg('id') AND status = 'draft';

-- name: AuditArticlePublished :exec
INSERT INTO audit_log (actor_id, action, entity_type, entity_id, session_hash, ip_hash, payload)
VALUES (
  sqlc.arg('actor_id'),
  'article.publish',
  'articles',
  sqlc.arg('entity_id'),
  NULLIF(sqlc.arg('session_hash'), ''),
  NULLIF(sqlc.arg('ip_hash'), ''),
  sqlc.arg('payload')::jsonb
);

-- name: HasPendingVerification :one
SELECT EXISTS (
  SELECT 1 FROM verifications
  WHERE journalist_id = sqlc.arg('journalist_id') AND status = 'pending'
)::boolean AS pending;
