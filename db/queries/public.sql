-- Queries do site público (leitores sem conta). Só leitura.
-- Vocabulário (responsabilidade-legal.mdc): nada aqui "verifica" conteúdo; expomos contagens
-- de avaliação entre pares e conformidade estrutural (fontes no cadastro).

-- name: SearchArticles :many
-- Filtros vazios são NULL e não restringem. Texto casa com título, corpo,
-- nome do jornalista, veículo citado, título da fonte e trecho.
SELECT
  a.id,
  a.kind,
  a.published_at,
  v.title,
  j.id            AS author_id,
  j.display_name  AS author_name,
  j.avatar_url    AS author_avatar_url,
  (SELECT count(*) FROM article_sources s WHERE s.version_id = v.id)::int AS source_count,
  coalesce(f.faithful_count, 0)::int AS faithful_count,
  coalesce(f.valid_count, 0)::int    AS valid_count,
  count(*) OVER()::int               AS match_count
FROM articles a
JOIN article_versions v ON v.id = a.current_version_id
JOIN journalists j ON j.id = a.author_id
LEFT JOIN article_fidelity_summary f ON f.article_id = a.id
WHERE a.status = 'published'
  AND (sqlc.narg('kind')::text IS NULL OR a.kind::text = sqlc.narg('kind'))
  AND (sqlc.narg('author_id')::text IS NULL OR a.author_id::text = sqlc.narg('author_id'))
  AND (
    sqlc.narg('outlet_id')::text IS NULL
    OR EXISTS (
      SELECT 1
      FROM article_sources s
      JOIN outlet_domains d ON d.id = s.outlet_domain_id
      WHERE s.version_id = v.id
        AND d.outlet_id::text = sqlc.narg('outlet_id')
    )
  )
  AND (sqlc.narg('published_from')::timestamptz IS NULL OR a.published_at >= sqlc.narg('published_from'))
  AND (sqlc.narg('published_to')::timestamptz IS NULL OR a.published_at < sqlc.narg('published_to'))
  AND (
    sqlc.narg('q')::text IS NULL
    OR to_tsvector('portuguese', article_plain_text(v.title, v.body))
         @@ websearch_to_tsquery('portuguese', sqlc.narg('q'))
    OR j.display_name ILIKE sqlc.narg('like_q')::text ESCAPE E'\\'
    OR EXISTS (
      SELECT 1
      FROM article_sources s
      JOIN outlet_domains d ON d.id = s.outlet_domain_id
      JOIN outlets o ON o.id = d.outlet_id
      WHERE s.version_id = v.id
        AND (
          o.name ILIKE sqlc.narg('like_q')::text ESCAPE E'\\'
          OR s.excerpt ILIKE sqlc.narg('like_q')::text ESCAPE E'\\'
          OR coalesce(s.meta->>'title', '') ILIKE sqlc.narg('like_q')::text ESCAPE E'\\'
        )
    )
  )
ORDER BY a.published_at DESC, a.id DESC
LIMIT sqlc.arg('page_size')::int OFFSET sqlc.arg('page_offset')::int;

-- name: ListPublishedAuthors :many
SELECT DISTINCT j.id, j.display_name
FROM journalists j
JOIN articles a ON a.author_id = j.id
WHERE a.status = 'published'
ORDER BY j.display_name;

-- name: ListCitedOutlets :many
SELECT DISTINCT o.id, o.name
FROM outlets o
JOIN outlet_domains d ON d.outlet_id = o.id
JOIN article_sources s ON s.outlet_domain_id = d.id
JOIN article_versions v ON v.id = s.version_id
JOIN articles a ON a.current_version_id = v.id
WHERE a.status = 'published'
ORDER BY o.name;

-- name: ListFeed :many
SELECT
  a.id,
  a.kind,
  a.published_at,
  v.version_no,
  v.title,
  j.id            AS author_id,
  j.display_name  AS author_name,
  j.avatar_url    AS author_avatar_url,
  (SELECT count(*) FROM article_sources s WHERE s.version_id = v.id)::int AS source_count,
  coalesce(f.faithful_count, 0)::int AS faithful_count,
  coalesce(f.distorts_count, 0)::int AS distorts_count,
  coalesce(f.valid_count, 0)::int    AS valid_count
FROM articles a
JOIN article_versions v ON v.id = a.current_version_id
JOIN journalists j ON j.id = a.author_id
LEFT JOIN article_fidelity_summary f ON f.article_id = a.id
WHERE a.status = 'published'
ORDER BY
  (a.published_at AT TIME ZONE 'America/Sao_Paulo')::date DESC,
  coalesce(f.valid_count, 0) DESC,
  a.published_at DESC,
  a.id DESC
LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int;

-- name: GetArticle :one
SELECT
  a.id,
  a.kind,
  a.status,
  a.published_at,
  a.removed_at,
  a.removal_reason,
  a.current_version_id,
  v.version_no,
  v.title,
  v.body,
  v.change_note,
  v.created_at AS version_created_at,
  j.id            AS author_id,
  j.display_name  AS author_name,
  j.avatar_url    AS author_avatar_url,
  j.tagline       AS author_tagline,
  coalesce(f.faithful_count, 0)::int AS faithful_count,
  coalesce(f.distorts_count, 0)::int AS distorts_count,
  coalesce(f.valid_count, 0)::int    AS valid_count,
  coalesce((
    SELECT d.reason
    FROM article_kind_decisions d
    WHERE d.version_id = a.current_version_id
    ORDER BY d.created_at DESC
    LIMIT 1
  ), '') AS kind_reason
FROM articles a
LEFT JOIN article_versions v ON v.id = a.current_version_id
JOIN journalists j ON j.id = a.author_id
LEFT JOIN article_fidelity_summary f ON f.article_id = a.id
WHERE a.id = $1;

-- name: ListArticleSources :many
SELECT
  s.id, s.position, s.url, s.excerpt, s.archive_url, s.hash_status, s.hash_compared_at,
  s.meta,
  d.domain,
  o.name  AS outlet_name,
  o.country AS outlet_country,
  o.status  AS outlet_status
FROM article_sources s
JOIN outlet_domains d ON d.id = s.outlet_domain_id
JOIN outlets o ON o.id = d.outlet_id
WHERE s.version_id = $1
ORDER BY s.position;

-- name: ListArticleVersions :many
SELECT id, version_no, title, change_note, created_at
FROM article_versions
WHERE article_id = $1
ORDER BY version_no DESC;

-- name: ListValidComments :many
SELECT
  c.id, c.stance, c.body, c.created_at,
  j.id AS author_id, j.display_name AS author_name, j.avatar_url AS author_avatar_url
FROM comments c
JOIN journalists j ON j.id = c.journalist_id
WHERE c.article_id = $1 AND c.filter_status = 'valid'
ORDER BY c.created_at;

-- name: ListPublishedReplies :many
SELECT id, excerpt, reply_text, published_at
FROM right_of_reply_requests
WHERE article_id = $1 AND status = 'published'
ORDER BY published_at;

-- name: ListUpheldDistortionReports :many
SELECT id, excerpt, decision_reason, decided_at
FROM distortion_reports
WHERE article_id = $1 AND status = 'upheld'
ORDER BY decided_at;

-- name: GetJournalistPublic :one
SELECT id, display_name, avatar_url, tagline, status, created_at
FROM journalists
WHERE id = $1 AND status IN ('pending_verification', 'verified', 'suspended');

-- name: GetCurrentReputation :one
SELECT journalist_id, computed_at, author, reviewer, algorithm
FROM current_reputation
WHERE journalist_id = $1;

-- name: ListArticlesByAuthor :many
SELECT
  a.id, a.kind, a.published_at, v.title,
  coalesce(f.faithful_count, 0)::int AS faithful_count,
  coalesce(f.valid_count, 0)::int    AS valid_count
FROM articles a
JOIN article_versions v ON v.id = a.current_version_id
LEFT JOIN article_fidelity_summary f ON f.article_id = a.id
WHERE a.author_id = $1 AND a.status = 'published'
ORDER BY a.published_at DESC;

-- name: ListOutlets :many
SELECT
  o.id, o.name, o.country, o.language, o.status, o.criteria, o.signals,
  (SELECT array_agg(d.domain::text ORDER BY d.domain) FROM outlet_domains d WHERE d.outlet_id = o.id)::text[] AS domains
FROM outlets o
ORDER BY o.status, o.country, o.name;

-- name: ListOutletChanges :many
SELECT c.id, c.outlet_id, o.name AS outlet_name, c.action, c.reason, c.created_at
FROM outlet_changes c
JOIN outlets o ON o.id = c.outlet_id
ORDER BY c.created_at DESC
LIMIT 200;
