-- 0005: avaliação (avaliacao-fidelidade.mdc)
-- Sem like. Voto Fiel/Distorce e comentários com flag, ambos só após gate de leitura
-- (abrir fonte + 2 perguntas geradas a partir da fonte). Filtro de qualidade registra motivo.

-- Gate de leitura: um por (jornalista, artigo). quiz_passed_at NULL = ainda não liberado.
CREATE TABLE reading_gates (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journalist_id    uuid NOT NULL REFERENCES journalists(id),
  article_id       uuid NOT NULL REFERENCES articles(id),
  source_id        uuid NOT NULL REFERENCES article_sources(id),  -- fonte efetivamente aberta
  opened_at        timestamptz NOT NULL DEFAULT now(),
  quiz_passed_at   timestamptz,
  attempts         smallint NOT NULL DEFAULT 0,
  next_attempt_at  timestamptz,                                    -- bloqueio após erro
  CONSTRAINT reading_gates_unique UNIQUE (journalist_id, article_id),
  CONSTRAINT reading_gates_attempts_nonneg CHECK (attempts >= 0)
);

-- Banco rotativo de perguntas por fonte, geradas por IA a partir do texto da fonte.
-- Nunca escritas pelo autor do artigo.
CREATE TABLE quiz_questions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_id        uuid NOT NULL REFERENCES article_sources(id),
  prompt           text NOT NULL,
  options          jsonb NOT NULL,                                 -- ["A", "B", "C", "D"]
  answer_hash      text NOT NULL,                                  -- sha256(índice correto + salt)
  generator_model  varchar(80) NOT NULL,
  active           boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT quiz_questions_min_options CHECK (jsonb_array_length(options) BETWEEN 2 AND 6)
);

CREATE INDEX quiz_questions_source_active_idx ON quiz_questions (source_id) WHERE active;

CREATE TABLE quiz_attempts (
  id            bigserial PRIMARY KEY,
  gate_id       uuid NOT NULL REFERENCES reading_gates(id),
  question_ids  uuid[] NOT NULL,
  correct       smallint NOT NULL,
  attempted_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT quiz_attempts_two_questions CHECK (array_length(question_ids, 1) = 2),
  CONSTRAINT quiz_attempts_correct_range CHECK (correct BETWEEN 0 AND 2)
);

CREATE INDEX quiz_attempts_gate_idx ON quiz_attempts (gate_id, attempted_at DESC);

-- Função compartilhada: o gate precisa estar aprovado, pertencer ao mesmo jornalista e artigo,
-- o jornalista precisa estar verificado e não pode ser o autor do artigo.
CREATE OR REPLACE FUNCTION enforce_reading_gate() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  g reading_gates%ROWTYPE;
  j_status journalist_status;
  a_author uuid;
  a_status article_status;
BEGIN
  SELECT * INTO g FROM reading_gates WHERE id = NEW.gate_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'gate_not_found: %', NEW.gate_id USING ERRCODE = 'P0001';
  END IF;
  IF g.journalist_id <> NEW.journalist_id OR g.article_id <> NEW.article_id THEN
    RAISE EXCEPTION 'gate_mismatch: gate % does not belong to journalist %/article %', NEW.gate_id, NEW.journalist_id, NEW.article_id
      USING ERRCODE = 'P0001';
  END IF;
  IF g.quiz_passed_at IS NULL THEN
    RAISE EXCEPTION 'gate_not_passed: journalist % has not passed the reading quiz for article %', NEW.journalist_id, NEW.article_id
      USING ERRCODE = 'P0001';
  END IF;

  SELECT status INTO j_status FROM journalists WHERE id = NEW.journalist_id;
  IF j_status IS DISTINCT FROM 'verified' THEN
    RAISE EXCEPTION 'evaluator_not_verified: journalist % has status %', NEW.journalist_id, j_status
      USING ERRCODE = 'P0001';
  END IF;

  SELECT author_id, status INTO a_author, a_status FROM articles WHERE id = NEW.article_id;
  IF a_author = NEW.journalist_id THEN
    RAISE EXCEPTION 'self_evaluation_forbidden: author cannot evaluate own article %', NEW.article_id
      USING ERRCODE = 'P0001';
  END IF;
  IF a_status <> 'published' THEN
    RAISE EXCEPTION 'article_not_published: cannot evaluate article % with status %', NEW.article_id, a_status
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END $$;

-- Voto de fidelidade: um por (artigo, jornalista). Pergunta: "O artigo é fiel às fontes citadas?"
CREATE TABLE fidelity_votes (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  article_id     uuid NOT NULL REFERENCES articles(id),
  journalist_id  uuid NOT NULL REFERENCES journalists(id),
  gate_id        uuid NOT NULL REFERENCES reading_gates(id),
  verdict        fidelity_verdict NOT NULL,
  note           varchar(200),                                     -- justificativa opcional, uma linha
  filter_status  filter_status NOT NULL DEFAULT 'pending',
  filter_reason  text,                                             -- motivo legível, exibido ao avaliador
  filter_model   varchar(80),
  filtered_at    timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT fidelity_votes_unique UNIQUE (article_id, journalist_id),
  CONSTRAINT fidelity_votes_filter_consistency
    CHECK ((filter_status = 'pending') = (filtered_at IS NULL)),
  CONSTRAINT fidelity_votes_rejected_has_reason
    CHECK (filter_status <> 'rejected' OR (filter_reason IS NOT NULL AND length(trim(filter_reason)) > 0))
);

CREATE INDEX fidelity_votes_article_valid_idx ON fidelity_votes (article_id, verdict) WHERE filter_status = 'valid';
CREATE INDEX fidelity_votes_journalist_idx ON fidelity_votes (journalist_id, created_at DESC);

CREATE TRIGGER fidelity_votes_require_gate
  BEFORE INSERT ON fidelity_votes
  FOR EACH ROW EXECUTE FUNCTION enforce_reading_gate();

-- Comentários: flag obrigatória (Concordo / Concordo parcialmente / Discordo) + texto curto.
-- A flag é posição sobre o conteúdo; NÃO entra no score de fidelidade.
CREATE TABLE comments (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  article_id     uuid NOT NULL REFERENCES articles(id),
  journalist_id  uuid NOT NULL REFERENCES journalists(id),
  gate_id        uuid NOT NULL REFERENCES reading_gates(id),
  stance         comment_stance NOT NULL,
  body           varchar(1000) NOT NULL,
  filter_status  filter_status NOT NULL DEFAULT 'pending',
  filter_reason  text,
  filter_model   varchar(80),
  filtered_at    timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT comments_body_not_blank CHECK (length(trim(body)) > 0),
  CONSTRAINT comments_filter_consistency
    CHECK ((filter_status = 'pending') = (filtered_at IS NULL)),
  CONSTRAINT comments_rejected_has_reason
    CHECK (filter_status <> 'rejected' OR (filter_reason IS NOT NULL AND length(trim(filter_reason)) > 0))
);

CREATE INDEX comments_article_visible_idx ON comments (article_id, created_at) WHERE filter_status = 'valid';
CREATE INDEX comments_journalist_idx ON comments (journalist_id, created_at DESC);

CREATE TRIGGER comments_require_gate
  BEFORE INSERT ON comments
  FOR EACH ROW EXECUTE FUNCTION enforce_reading_gate();
