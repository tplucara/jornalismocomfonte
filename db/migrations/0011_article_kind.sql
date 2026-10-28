-- 0011: a tag do artigo (reportagem, análise, opinião) sai da classificação do texto.
-- Uma decisão por versão, append-only, com método, modelo e motivo legível.
-- A tag exibida é articles.kind, atualizada para a decisão da versão corrente.
-- Isto não julga se o texto é verdadeiro.

CREATE TABLE article_kind_decisions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  article_id  uuid NOT NULL REFERENCES articles(id),
  version_id  uuid NOT NULL REFERENCES article_versions(id),
  kind        article_kind NOT NULL,
  method      varchar(40) NOT NULL,
  model       varchar(80) NOT NULL,
  reason      text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT article_kind_decisions_reason_len CHECK (char_length(reason) BETWEEN 20 AND 500),
  CONSTRAINT article_kind_decisions_method_len CHECK (char_length(trim(method)) BETWEEN 3 AND 40),
  CONSTRAINT article_kind_decisions_model_len CHECK (char_length(trim(model)) BETWEEN 3 AND 80)
);

CREATE INDEX article_kind_decisions_version_idx
  ON article_kind_decisions (version_id, created_at DESC);

CREATE TRIGGER article_kind_decisions_append_only
  BEFORE UPDATE OR DELETE ON article_kind_decisions
  FOR EACH ROW EXECUTE FUNCTION forbid_update_delete();

GRANT SELECT ON article_kind_decisions TO jcf_web_role, jcf_worker_role;
GRANT INSERT ON article_kind_decisions TO jcf_worker_role;
