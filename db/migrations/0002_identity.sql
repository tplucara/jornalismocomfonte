-- 0002: identidade (perfil-identidade.mdc)
-- Superfície pública: display_name, avatar_url, tagline. Nada mais.
-- Proibido adicionar: localização, nascimento, telefone, redes pessoais, empregador.
-- O teste de invariantes verifica o information_schema para impedir regressão.

CREATE TABLE journalists (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email          citext NOT NULL UNIQUE,
  password_hash  text NOT NULL,
  display_name   varchar(80) NOT NULL,
  avatar_url     text,
  tagline        varchar(140),
  status         journalist_status NOT NULL DEFAULT 'pending_verification',
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  closed_at      timestamptz,
  CONSTRAINT journalists_closed_consistency
    CHECK ((status = 'closed') = (closed_at IS NOT NULL))
);

CREATE TRIGGER journalists_set_updated_at
  BEFORE UPDATE ON journalists
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Aceite de documentos legais: versionado, append-only, com identificador de sessão.
CREATE TABLE legal_acceptances (
  id                 bigserial PRIMARY KEY,
  journalist_id      uuid NOT NULL REFERENCES journalists(id),
  document           legal_document NOT NULL,
  version            varchar(20) NOT NULL,
  adult_declaration  boolean NOT NULL,
  session_hash       text NOT NULL,
  accepted_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT legal_acceptances_adult_required CHECK (adult_declaration = true)
);

CREATE INDEX legal_acceptances_journalist_idx ON legal_acceptances (journalist_id, document, accepted_at DESC);

CREATE TRIGGER legal_acceptances_append_only
  BEFORE UPDATE OR DELETE ON legal_acceptances
  FOR EACH ROW EXECUTE FUNCTION forbid_update_delete();

-- Verificação de jornalista. O arquivo bruto NÃO fica no banco: só hash e metadados.
-- raw_purged_at registra quando o arquivo foi apagado do object storage.
CREATE TABLE verifications (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journalist_id    uuid NOT NULL REFERENCES journalists(id),
  method           verification_method NOT NULL,
  document_hash    text NOT NULL,
  evidence_meta    jsonb NOT NULL DEFAULT '{}'::jsonb,
  status           verification_status NOT NULL DEFAULT 'pending',
  reviewer_id      uuid REFERENCES journalists(id),
  decision_reason  text,
  submitted_at     timestamptz NOT NULL DEFAULT now(),
  decided_at       timestamptz,
  raw_purged_at    timestamptz,
  CONSTRAINT verifications_decision_consistency
    CHECK ((status = 'pending') = (decided_at IS NULL)),
  CONSTRAINT verifications_decided_has_reason
    CHECK (status = 'pending' OR decision_reason IS NOT NULL),
  CONSTRAINT verifications_decided_has_reviewer
    CHECK (status = 'pending' OR reviewer_id IS NOT NULL),
  CONSTRAINT verifications_no_self_review
    CHECK (reviewer_id IS NULL OR reviewer_id <> journalist_id)
);

-- 1 pessoa = 1 conta: o mesmo documento só pode estar aprovado uma vez.
CREATE UNIQUE INDEX verifications_one_person_one_account
  ON verifications (document_hash) WHERE status = 'approved';

CREATE INDEX verifications_journalist_idx ON verifications (journalist_id, submitted_at DESC);

-- Ao aprovar, promover o jornalista para 'verified'.
CREATE OR REPLACE FUNCTION promote_on_verification() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'approved' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'approved') THEN
    UPDATE journalists SET status = 'verified'
      WHERE id = NEW.journalist_id AND status = 'pending_verification';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER verifications_promote
  AFTER INSERT OR UPDATE OF status ON verifications
  FOR EACH ROW EXECUTE FUNCTION promote_on_verification();
