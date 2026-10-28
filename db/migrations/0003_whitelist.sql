-- 0003: cadastro de veículos (cadastro-de-veiculos.mdc)
-- Pública, auditável, versionada. Critérios objetivos em jsonb com URLs de evidência.

CREATE TABLE outlets (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        varchar(200) NOT NULL,
  country     char(2) NOT NULL,          -- ISO 3166-1 alpha-2
  language    varchar(10) NOT NULL,      -- BCP 47 (pt-BR, en, es...)
  -- Critérios de entrada: { "newsroom_url", "editorial_policy_url", "corrections_policy_url", "legal_entity" }
  criteria    jsonb NOT NULL,
  -- Sinais positivos (não requisitos): { "ifcn": true, "trust_project": true, "jti": false }
  signals     jsonb NOT NULL DEFAULT '{}'::jsonb,
  status      outlet_status NOT NULL DEFAULT 'active',
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT outlets_criteria_complete CHECK (
    criteria ? 'newsroom_url' AND
    criteria ? 'editorial_policy_url' AND
    criteria ? 'corrections_policy_url' AND
    criteria ? 'legal_entity'
  )
);

CREATE TRIGGER outlets_set_updated_at
  BEFORE UPDATE ON outlets
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Domínios do veículo e padrões de path que indicam opinião/editorial/coluna.
CREATE TABLE outlet_domains (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  outlet_id              uuid NOT NULL REFERENCES outlets(id),
  domain                 citext NOT NULL UNIQUE,
  opinion_path_patterns  text[] NOT NULL DEFAULT '{}',
  created_at             timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT outlet_domains_domain_format CHECK (domain ~ '^[a-z0-9.-]+\.[a-z]{2,}$')
);

CREATE INDEX outlet_domains_outlet_idx ON outlet_domains (outlet_id);

-- Histórico público e append-only de toda mudança na lista.
CREATE TABLE outlet_changes (
  id          bigserial PRIMARY KEY,
  outlet_id   uuid NOT NULL REFERENCES outlets(id),
  action      outlet_change_action NOT NULL,
  reason      text NOT NULL,
  actor_id    uuid REFERENCES journalists(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT outlet_changes_reason_not_blank CHECK (length(trim(reason)) > 0)
);

CREATE INDEX outlet_changes_outlet_idx ON outlet_changes (outlet_id, created_at DESC);

CREATE TRIGGER outlet_changes_append_only
  BEFORE UPDATE OR DELETE ON outlet_changes
  FOR EACH ROW EXECUTE FUNCTION forbid_update_delete();

-- Toda mudança de status em outlets exige entrada em outlet_changes na mesma transação.
-- Implementado como constraint trigger deferrable para checar no COMMIT.
CREATE OR REPLACE FUNCTION require_outlet_change_entry() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  -- age(xmin) = 0: a linha foi inserida na transação corrente (independe de created_at,
  -- que pode ser retrodatado em importações e seeds).
  IF NOT EXISTS (
    SELECT 1 FROM outlet_changes
    WHERE outlet_id = NEW.id AND age(xmin) = 0
  ) THEN
    RAISE EXCEPTION 'whitelist_change_without_history: outlet % changed without outlet_changes entry', NEW.id
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END $$;

CREATE CONSTRAINT TRIGGER outlets_require_history
  AFTER INSERT OR UPDATE OF status, criteria ON outlets
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION require_outlet_change_entry();
