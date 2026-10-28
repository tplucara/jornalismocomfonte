-- 0004: conteúdo (fonte-validada.mdc, integridade-editorial.mdc)
-- Artigo = cabeçalho mutável (status, versão corrente) + versões append-only + fontes por versão.
-- Invariante 1 do produto: nenhuma publicação sem 1 a 3 reportagens de veículos do cadastro.

CREATE TABLE articles (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id           uuid NOT NULL REFERENCES journalists(id),
  kind                article_kind NOT NULL,                -- tag obrigatória: report | analysis | opinion
  status              article_status NOT NULL DEFAULT 'draft',
  current_version_id  uuid,                                 -- FK adicionada abaixo (referência circular)
  published_at        timestamptz,
  removed_at          timestamptz,
  removal_reason      removal_reason,
  removal_ref         text,                                 -- protocolo da notificação ou nº do processo
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT articles_published_has_version
    CHECK (status <> 'published' OR current_version_id IS NOT NULL),
  CONSTRAINT articles_published_has_date
    CHECK (status <> 'published' OR published_at IS NOT NULL),
  CONSTRAINT articles_removed_consistency
    CHECK ((status IN ('removed', 'author_deleted')) = (removed_at IS NOT NULL)),
  CONSTRAINT articles_removed_has_reason
    CHECK (status NOT IN ('removed', 'author_deleted') OR removal_reason IS NOT NULL),
  CONSTRAINT articles_author_deleted_reason
    CHECK (status <> 'author_deleted' OR removal_reason = 'author')
);

CREATE INDEX articles_feed_idx ON articles (published_at DESC) WHERE status = 'published';
CREATE INDEX articles_author_idx ON articles (author_id, created_at DESC);

CREATE TRIGGER articles_set_updated_at
  BEFORE UPDATE ON articles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Versões: append-only. Toda edição pós-publicação é uma nova linha. Nunca edição silenciosa.
CREATE TABLE article_versions (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  article_id   uuid NOT NULL REFERENCES articles(id),
  version_no   integer NOT NULL,
  title        varchar(200) NOT NULL,
  body         jsonb NOT NULL,                              -- documento do editor (blocos, marcações)
  change_note  text,                                        -- obrigatório a partir da versão 2
  created_by   uuid NOT NULL REFERENCES journalists(id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT article_versions_unique_no UNIQUE (article_id, version_no),
  CONSTRAINT article_versions_positive_no CHECK (version_no >= 1),
  CONSTRAINT article_versions_change_note_after_first
    CHECK (version_no = 1 OR (change_note IS NOT NULL AND length(trim(change_note)) > 0))
);

CREATE TRIGGER article_versions_append_only
  BEFORE UPDATE OR DELETE ON article_versions
  FOR EACH ROW EXECUTE FUNCTION forbid_update_delete();

ALTER TABLE articles
  ADD CONSTRAINT articles_current_version_fk
  FOREIGN KEY (current_version_id) REFERENCES article_versions(id)
  DEFERRABLE INITIALLY DEFERRED;

-- Fontes por versão. position 1..3 + UNIQUE garante no máximo 3 por versão.
-- Registro de integridade: hash + metadados + trecho curto + link de arquivo externo.
-- NUNCA cópia integral do conteúdo de terceiros.
CREATE TABLE article_sources (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id              uuid NOT NULL REFERENCES article_versions(id),
  position                smallint NOT NULL,
  url                     text NOT NULL,
  outlet_domain_id        uuid NOT NULL REFERENCES outlet_domains(id),
  classification          source_classification NOT NULL DEFAULT 'unknown',
  classification_method   varchar(40),                      -- path_pattern | ai_model:<nome> | human_review
  classification_reason   text,
  content_hash            text NOT NULL,                     -- sha256 do texto principal no momento da publicação
  meta                    jsonb NOT NULL DEFAULT '{}'::jsonb, -- { title, outlet, published_at, author }
  excerpt                 varchar(300) NOT NULL,
  archive_url             text,                              -- ex.: Wayback Machine
  hash_status             source_hash_status NOT NULL DEFAULT 'ok',
  hash_compared_at        timestamptz,                       -- última comparação do hash com a fonte viva
  created_at              timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT article_sources_position_range CHECK (position BETWEEN 1 AND 3),
  CONSTRAINT article_sources_unique_position UNIQUE (version_id, position),
  CONSTRAINT article_sources_unique_url UNIQUE (version_id, url),
  CONSTRAINT article_sources_https CHECK (url ~* '^https?://'),
  CONSTRAINT article_sources_classified_has_method
    CHECK (classification = 'unknown' OR classification_method IS NOT NULL)
);

CREATE INDEX article_sources_version_idx ON article_sources (version_id);
CREATE INDEX article_sources_domain_idx ON article_sources (outlet_domain_id);
CREATE INDEX article_sources_recheck_idx ON article_sources (hash_compared_at NULLS FIRST);

-- A URL precisa pertencer ao domínio declarado (impede apontar outlet A e linkar site B).
CREATE OR REPLACE FUNCTION check_source_url_matches_domain() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  d text;
  host text;
BEGIN
  SELECT domain INTO d FROM outlet_domains WHERE id = NEW.outlet_domain_id;
  host := lower(substring(NEW.url from '^https?://([^/:?#]+)'));
  IF host IS NULL OR NOT (host = d OR host LIKE '%.' || d) THEN
    RAISE EXCEPTION 'source_url_domain_mismatch: url host % is not under whitelisted domain %', host, d
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER article_sources_domain_match
  BEFORE INSERT OR UPDATE OF url, outlet_domain_id ON article_sources
  FOR EACH ROW EXECUTE FUNCTION check_source_url_matches_domain();

-- INVARIANTE 1: ao publicar (ou trocar a versão corrente de um artigo publicado),
-- a versão precisa ter entre 1 e 3 fontes, todas classificadas como reportagem,
-- todas de domínios cujo veículo está ativo no cadastro. Autor precisa estar verificado.
-- Constraint trigger DEFERRED: a aplicação insere versão + fontes + atualiza o artigo
-- na mesma transação, e a checagem roda no COMMIT.
CREATE OR REPLACE FUNCTION enforce_publication_rules() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  n_total   integer;
  n_report  integer;
  n_active  integer;
  v_article uuid;
  a_status  journalist_status;
BEGIN
  IF NEW.status <> 'published' THEN
    RETURN NEW;
  END IF;

  SELECT status INTO a_status FROM journalists WHERE id = NEW.author_id;
  IF a_status IS DISTINCT FROM 'verified' THEN
    RAISE EXCEPTION 'publication_requires_verified_author: author % has status %', NEW.author_id, a_status
      USING ERRCODE = 'P0001';
  END IF;

  SELECT article_id INTO v_article FROM article_versions WHERE id = NEW.current_version_id;
  IF v_article IS DISTINCT FROM NEW.id THEN
    RAISE EXCEPTION 'publication_version_mismatch: version % does not belong to article %', NEW.current_version_id, NEW.id
      USING ERRCODE = 'P0001';
  END IF;

  SELECT
    count(*),
    count(*) FILTER (WHERE s.classification = 'report'),
    count(*) FILTER (WHERE o.status = 'active')
  INTO n_total, n_report, n_active
  FROM article_sources s
  JOIN outlet_domains d ON d.id = s.outlet_domain_id
  JOIN outlets o ON o.id = d.outlet_id
  WHERE s.version_id = NEW.current_version_id;

  IF n_total < 1 OR n_total > 3 THEN
    RAISE EXCEPTION 'publication_requires_1_to_3_sources: version % has % sources', NEW.current_version_id, n_total
      USING ERRCODE = 'P0001';
  END IF;
  IF n_report <> n_total THEN
    RAISE EXCEPTION 'publication_requires_report_sources: % of % sources are not classified as report', n_total - n_report, n_total
      USING ERRCODE = 'P0001';
  END IF;
  IF n_active <> n_total THEN
    RAISE EXCEPTION 'publication_requires_active_outlets: % of % sources are from inactive outlets', n_total - n_active, n_total
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END $$;

CREATE CONSTRAINT TRIGGER articles_enforce_publication
  AFTER INSERT OR UPDATE OF status, current_version_id ON articles
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION enforce_publication_rules();

-- Versão corrente só pode avançar, nunca voltar (histórico é só leitura; correção = nova versão).
CREATE OR REPLACE FUNCTION enforce_version_monotonic() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  old_no integer;
  new_no integer;
BEGIN
  IF OLD.current_version_id IS NULL OR NEW.current_version_id IS NOT DISTINCT FROM OLD.current_version_id THEN
    RETURN NEW;
  END IF;
  SELECT version_no INTO old_no FROM article_versions WHERE id = OLD.current_version_id;
  SELECT version_no INTO new_no FROM article_versions WHERE id = NEW.current_version_id;
  IF new_no <= old_no THEN
    RAISE EXCEPTION 'version_must_advance: cannot move article % from version % to %', NEW.id, old_no, new_no
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER articles_version_monotonic
  BEFORE UPDATE OF current_version_id ON articles
  FOR EACH ROW EXECUTE FUNCTION enforce_version_monotonic();
