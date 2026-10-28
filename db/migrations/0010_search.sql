-- 0010: busca pública (algoritmos-transparentes.mdc)
-- O texto pesquisável é título + parágrafos da versão. A ordem dos resultados
-- é cronológica; esta migração não cria ranking por voto, clique ou comentário.

CREATE OR REPLACE FUNCTION article_plain_text(title text, body jsonb)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT coalesce(title, '') || ' ' || coalesce((
    SELECT string_agg(coalesce(b->>'text', ''), ' ')
    FROM jsonb_array_elements(
      CASE
        WHEN jsonb_typeof(body -> 'blocks') = 'array' THEN body -> 'blocks'
        ELSE '[]'::jsonb
      END
    ) AS b
  ), '')
$$;

COMMENT ON FUNCTION article_plain_text(text, jsonb) IS
  'Texto plano de uma versão para a busca. Não inclui cópia de fonte de terceiros além do que o autor escreveu.';

CREATE INDEX article_versions_search_idx
  ON article_versions
  USING gin (to_tsvector('portuguese', article_plain_text(title, body)));

REVOKE EXECUTE ON FUNCTION article_plain_text(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION article_plain_text(text, jsonb) TO jcf_web_role, jcf_worker_role;
