-- 0008: trilha de auditoria e logs de acesso (responsabilidade-legal.mdc, Marco Civil arts. 10, 15, 22)
-- Ambas append-only e particionadas por mês. Nunca expostas publicamente.
-- access_logs: retenção de 6 meses por drop de partição (Marco Civil art. 15).
-- audit_log: retenção pelo prazo prescricional; partições antigas podem ir para armazenamento frio.

CREATE TABLE audit_log (
  id            bigint GENERATED ALWAYS AS IDENTITY,
  actor_id      uuid,                                        -- NULL para ações do sistema
  action        varchar(60) NOT NULL,                        -- article.publish, vote.create, notice.decide...
  entity_type   varchar(40) NOT NULL,
  entity_id     uuid,
  session_hash  text,
  ip_hash       text,
  payload       jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

CREATE INDEX audit_log_entity_idx ON audit_log (entity_type, entity_id, created_at DESC);
CREATE INDEX audit_log_actor_idx ON audit_log (actor_id, created_at DESC);

CREATE TABLE access_logs (
  id           bigint GENERATED ALWAYS AS IDENTITY,
  ip_hash      text NOT NULL,                                -- hash com salt rotativo; nunca IP em claro
  occurred_at  timestamptz NOT NULL DEFAULT now(),
  path         text NOT NULL,
  PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);

-- Cria partição mensal se não existir. Chamar por job no início de cada mês (e para o mês seguinte).
CREATE OR REPLACE FUNCTION ensure_month_partition(parent regclass, month date) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  start_d date := date_trunc('month', month)::date;
  end_d   date := (date_trunc('month', month) + interval '1 month')::date;
  pname   text := format('%s_%s', parent::text, to_char(start_d, 'YYYY_MM'));
BEGIN
  IF to_regclass(pname) IS NULL THEN
    EXECUTE format('CREATE TABLE %I PARTITION OF %s FOR VALUES FROM (%L) TO (%L)', pname, parent, start_d, end_d);
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION forbid_update_delete()',
                   pname || '_append_only', pname);
  END IF;
END $$;

-- Remove partições de access_logs com mais de 6 meses (Marco Civil art. 15).
CREATE OR REPLACE FUNCTION drop_expired_access_log_partitions() RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  r record;
  dropped integer := 0;
  cutoff date := (date_trunc('month', now()) - interval '6 months')::date;
BEGIN
  FOR r IN
    SELECT c.relname
    FROM pg_inherits i
    JOIN pg_class c ON c.oid = i.inhrelid
    WHERE i.inhparent = 'access_logs'::regclass
  LOOP
    IF to_date(substring(r.relname from '\d{4}_\d{2}$'), 'YYYY_MM') < cutoff THEN
      EXECUTE format('DROP TABLE %I', r.relname);
      dropped := dropped + 1;
    END IF;
  END LOOP;
  RETURN dropped;
END $$;

-- Partições do mês corrente e do próximo.
SELECT ensure_month_partition('audit_log',   now()::date);
SELECT ensure_month_partition('audit_log',   (now() + interval '1 month')::date);
SELECT ensure_month_partition('access_logs', now()::date);
SELECT ensure_month_partition('access_logs', (now() + interval '1 month')::date);

-- Auditoria automática de eventos críticos. A aplicação complementa com session_hash/ip_hash
-- via SET LOCAL app.session_hash / app.ip_hash na transação.
CREATE OR REPLACE FUNCTION audit_row_change() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  actor uuid;
  ent_id uuid;
BEGIN
  BEGIN
    actor := nullif(current_setting('app.actor_id', true), '')::uuid;
  EXCEPTION WHEN others THEN actor := NULL;
  END;
  ent_id := CASE WHEN TG_OP = 'DELETE' THEN (to_jsonb(OLD)->>'id')::uuid ELSE (to_jsonb(NEW)->>'id')::uuid END;

  INSERT INTO audit_log (actor_id, action, entity_type, entity_id, session_hash, ip_hash, payload)
  VALUES (
    actor,
    lower(TG_TABLE_NAME || '.' || TG_OP),
    TG_TABLE_NAME,
    ent_id,
    nullif(current_setting('app.session_hash', true), ''),
    nullif(current_setting('app.ip_hash', true), ''),
    CASE WHEN TG_OP = 'INSERT' THEN jsonb_build_object('new', to_jsonb(NEW))
         WHEN TG_OP = 'UPDATE' THEN jsonb_build_object('old', to_jsonb(OLD), 'new', to_jsonb(NEW))
         ELSE jsonb_build_object('old', to_jsonb(OLD)) END
  );
  RETURN COALESCE(NEW, OLD);
END $$;

CREATE TRIGGER articles_audit          AFTER INSERT OR UPDATE ON articles          FOR EACH ROW EXECUTE FUNCTION audit_row_change();
CREATE TRIGGER article_versions_audit  AFTER INSERT ON article_versions            FOR EACH ROW EXECUTE FUNCTION audit_row_change();
CREATE TRIGGER fidelity_votes_audit    AFTER INSERT OR UPDATE ON fidelity_votes    FOR EACH ROW EXECUTE FUNCTION audit_row_change();
CREATE TRIGGER comments_audit          AFTER INSERT OR UPDATE ON comments          FOR EACH ROW EXECUTE FUNCTION audit_row_change();
CREATE TRIGGER verifications_audit     AFTER INSERT OR UPDATE ON verifications     FOR EACH ROW EXECUTE FUNCTION audit_row_change();
CREATE TRIGGER takedown_notices_audit  AFTER INSERT OR UPDATE ON takedown_notices  FOR EACH ROW EXECUTE FUNCTION audit_row_change();
CREATE TRIGGER counter_notices_audit   AFTER INSERT OR UPDATE ON counter_notices   FOR EACH ROW EXECUTE FUNCTION audit_row_change();
CREATE TRIGGER appeals_audit           AFTER INSERT OR UPDATE ON appeals           FOR EACH ROW EXECUTE FUNCTION audit_row_change();
CREATE TRIGGER outlets_audit           AFTER INSERT OR UPDATE ON outlets           FOR EACH ROW EXECUTE FUNCTION audit_row_change();
