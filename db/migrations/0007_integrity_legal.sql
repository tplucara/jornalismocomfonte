-- 0007: integridade editorial e processos legais
-- (integridade-editorial.mdc, responsabilidade-legal.mdc, docs/legal/politica-de-conteudo-e-remocao.md)
-- PII de terceiros (notificante, solicitante de resposta) fica cifrada com pgcrypto (bytea).
-- A chave vive fora do banco (variável de ambiente da aplicação).

-- Denúncia de distorção de fonte, entre jornalistas. Procedente => aviso no artigo; nunca remoção.
CREATE TABLE distortion_reports (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  article_id       uuid NOT NULL REFERENCES articles(id),
  version_id       uuid NOT NULL REFERENCES article_versions(id),
  source_id        uuid NOT NULL REFERENCES article_sources(id),
  reporter_id      uuid NOT NULL REFERENCES journalists(id),
  excerpt          varchar(500) NOT NULL,                    -- trecho do artigo apontado
  argument         text NOT NULL,                            -- por que a fonte não sustenta
  status           review_status NOT NULL DEFAULT 'open',
  reviewer_id      uuid REFERENCES journalists(id),
  decision_reason  text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  decided_at       timestamptz,
  CONSTRAINT distortion_reports_decision_consistency
    CHECK ((status = 'open') = (decided_at IS NULL)),
  CONSTRAINT distortion_reports_decided_has_reason
    CHECK (status = 'open' OR decision_reason IS NOT NULL)
);

CREATE INDEX distortion_reports_article_idx ON distortion_reports (article_id, status);

-- Autor não denuncia o próprio artigo; revisor não é o autor nem o denunciante.
CREATE OR REPLACE FUNCTION check_distortion_report_parties() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE a_author uuid;
BEGIN
  SELECT author_id INTO a_author FROM articles WHERE id = NEW.article_id;
  IF NEW.reporter_id = a_author THEN
    RAISE EXCEPTION 'self_report_forbidden' USING ERRCODE = 'P0001';
  END IF;
  IF NEW.reviewer_id IS NOT NULL AND NEW.reviewer_id IN (a_author, NEW.reporter_id) THEN
    RAISE EXCEPTION 'reviewer_conflict_of_interest' USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER distortion_reports_parties
  BEFORE INSERT OR UPDATE OF reviewer_id ON distortion_reports
  FOR EACH ROW EXECUTE FUNCTION check_distortion_report_parties();

-- Direito de resposta (Lei 13.188/2015 por analogia). Publicado junto ao artigo.
CREATE TABLE right_of_reply_requests (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  article_id       uuid NOT NULL REFERENCES articles(id),
  version_id       uuid NOT NULL REFERENCES article_versions(id),
  requester_pii    bytea NOT NULL,                           -- pgp_sym_encrypt(json{name, doc, email})
  requester_hash   text NOT NULL,                            -- para deduplicar sem decifrar
  excerpt          varchar(500) NOT NULL,                    -- trecho que motiva a resposta
  reply_text       text NOT NULL,
  status           reply_status NOT NULL DEFAULT 'requested',
  reviewer_id      uuid REFERENCES journalists(id),
  decision_reason  text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  decided_at       timestamptz,
  published_at     timestamptz,
  CONSTRAINT reply_published_consistency
    CHECK ((status = 'published') = (published_at IS NOT NULL)),
  CONSTRAINT reply_decided_consistency
    CHECK ((status = 'requested') = (decided_at IS NULL)),
  CONSTRAINT reply_declined_has_reason
    CHECK (status <> 'declined' OR decision_reason IS NOT NULL)
);

CREATE INDEX right_of_reply_article_idx ON right_of_reply_requests (article_id) WHERE status = 'published';

-- Notificações de remoção. Categoria define o caminho:
--   court_order     -> cumprir no prazo
--   evident_illicit -> análise em até 5 dias úteis (24h para casos urgentes)
--   terms_violation -> processo interno
-- Honra e opinião NÃO são categorias: só ordem judicial (status redirected_to_reply como resposta padrão).
CREATE TABLE takedown_notices (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  protocol        varchar(30) NOT NULL UNIQUE,
  category        notice_category NOT NULL,
  article_id      uuid REFERENCES articles(id),
  url             text NOT NULL,                             -- URL específica exigida (Marco Civil art. 19 §1º)
  grounds         text NOT NULL,                             -- fundamento jurídico
  notifier_pii    bytea NOT NULL,                            -- cifrado
  notifier_hash   text NOT NULL,
  good_faith      boolean NOT NULL,
  urgent          boolean NOT NULL DEFAULT false,            -- abuso infantil, nudez não consentida, ameaça
  status          notice_status NOT NULL DEFAULT 'received',
  reviewer_id     uuid REFERENCES journalists(id),
  decision        text,
  received_at     timestamptz NOT NULL DEFAULT now(),
  decided_at      timestamptz,
  CONSTRAINT takedown_good_faith_required CHECK (good_faith = true),
  CONSTRAINT takedown_decided_consistency
    CHECK ((status IN ('removed', 'denied', 'redirected_to_reply')) = (decided_at IS NOT NULL)),
  CONSTRAINT takedown_decided_has_text
    CHECK (status NOT IN ('removed', 'denied', 'redirected_to_reply') OR decision IS NOT NULL)
);

CREATE INDEX takedown_notices_open_idx ON takedown_notices (received_at) WHERE decided_at IS NULL;
CREATE INDEX takedown_notices_article_idx ON takedown_notices (article_id);

-- Contranotificação: revisor obrigatoriamente diferente do que decidiu a remoção.
CREATE TABLE counter_notices (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notice_id        uuid NOT NULL UNIQUE REFERENCES takedown_notices(id),
  author_id        uuid NOT NULL REFERENCES journalists(id),
  argument         text NOT NULL,
  status           counter_notice_status NOT NULL DEFAULT 'open',
  reviewer_id      uuid REFERENCES journalists(id),
  decision_reason  text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  decided_at       timestamptz,
  CONSTRAINT counter_decided_consistency CHECK ((status = 'open') = (decided_at IS NULL)),
  CONSTRAINT counter_decided_has_reason CHECK (status = 'open' OR decision_reason IS NOT NULL)
);

CREATE OR REPLACE FUNCTION check_counter_notice_reviewer() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE original_reviewer uuid; original_status notice_status;
BEGIN
  SELECT reviewer_id, status INTO original_reviewer, original_status FROM takedown_notices WHERE id = NEW.notice_id;
  IF original_status <> 'removed' THEN
    RAISE EXCEPTION 'counter_notice_requires_removal: notice % has status %', NEW.notice_id, original_status
      USING ERRCODE = 'P0001';
  END IF;
  IF NEW.reviewer_id IS NOT NULL AND NEW.reviewer_id = original_reviewer THEN
    RAISE EXCEPTION 'counter_notice_same_reviewer: reviewer % decided the original notice', NEW.reviewer_id
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER counter_notices_reviewer
  BEFORE INSERT OR UPDATE OF reviewer_id ON counter_notices
  FOR EACH ROW EXECUTE FUNCTION check_counter_notice_reviewer();

-- Apelações de decisões automáticas ou de revisão. Toda rejeição tem caminho de apelação humana.
CREATE TABLE appeals (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_type     appeal_subject NOT NULL,
  subject_id       uuid NOT NULL,
  journalist_id    uuid NOT NULL REFERENCES journalists(id),
  argument         text NOT NULL,
  status           appeal_status NOT NULL DEFAULT 'open',
  reviewer_id      uuid REFERENCES journalists(id),
  decision         text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  decided_at       timestamptz,
  CONSTRAINT appeals_one_per_subject UNIQUE (subject_type, subject_id, journalist_id),
  CONSTRAINT appeals_decided_consistency CHECK ((status = 'open') = (decided_at IS NULL)),
  CONSTRAINT appeals_decided_has_text CHECK (status = 'open' OR decision IS NOT NULL),
  CONSTRAINT appeals_no_self_review CHECK (reviewer_id IS NULL OR reviewer_id <> journalist_id)
);

CREATE INDEX appeals_open_idx ON appeals (created_at) WHERE status = 'open';

-- Remoção de artigo exige referência: notificação, processo ou decisão do autor.
-- Placeholder público é responsabilidade da aplicação; o banco garante que o rastro existe.
CREATE OR REPLACE FUNCTION check_article_removal_ref() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status IN ('removed') AND NEW.removal_reason IN ('court_order', 'valid_notice')
     AND NOT EXISTS (SELECT 1 FROM takedown_notices WHERE protocol = NEW.removal_ref) THEN
    RAISE EXCEPTION 'removal_requires_notice: removal_ref % does not match a takedown notice', NEW.removal_ref
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER articles_removal_ref
  BEFORE UPDATE OF status ON articles
  FOR EACH ROW WHEN (NEW.status = 'removed')
  EXECUTE FUNCTION check_article_removal_ref();
