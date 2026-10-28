-- 0009: papéis de aplicação com privilégio mínimo (stack-e-seguranca.mdc)
--   jcf_web_role    : site e área do jornalista. Sem DDL, sem DELETE, sem acesso à PII cifrada de terceiros.
--   jcf_worker_role : jobs. Pode ler PII cifrada (precisa decifrar para notificar), executar manutenção.
-- São papéis de grupo (NOLOGIN). Usuários de login são criados fora das migrações
-- (db/dev/create_dev_users.sql em desenvolvimento; secret manager em produção) e recebem GRANT do grupo.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'jcf_web_role') THEN
    CREATE ROLE jcf_web_role NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'jcf_worker_role') THEN
    CREATE ROLE jcf_worker_role NOLOGIN;
  END IF;
END $$;

GRANT USAGE ON SCHEMA public TO jcf_web_role, jcf_worker_role;

-- Leitura geral
GRANT SELECT ON ALL TABLES IN SCHEMA public TO jcf_web_role, jcf_worker_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO jcf_web_role, jcf_worker_role;

-- Web: escrita apenas onde o produto escreve a partir de uma requisição. Nunca DELETE.
GRANT INSERT ON journalists, legal_acceptances, verifications, articles, article_versions, article_sources,
                reading_gates, quiz_attempts, fidelity_votes, comments, distortion_reports,
                right_of_reply_requests, takedown_notices, counter_notices, appeals,
                outlets, outlet_domains, outlet_changes, audit_log, access_logs
  TO jcf_web_role;
GRANT UPDATE ON journalists, verifications, articles, article_sources, reading_gates,
                distortion_reports, right_of_reply_requests, takedown_notices, counter_notices, appeals,
                outlets, outlet_domains
  TO jcf_web_role;

-- Web NÃO lê PII cifrada de terceiros: revoga a tabela inteira e concede coluna a coluna.
REVOKE SELECT ON takedown_notices, right_of_reply_requests FROM jcf_web_role;
GRANT SELECT (id, protocol, category, article_id, url, grounds, notifier_hash, good_faith, urgent,
              status, reviewer_id, decision, received_at, decided_at)
  ON takedown_notices TO jcf_web_role;
GRANT SELECT (id, article_id, version_id, requester_hash, excerpt, reply_text, status, reviewer_id,
              decision_reason, created_at, decided_at, published_at)
  ON right_of_reply_requests TO jcf_web_role;
-- INSERT das colunas cifradas continua permitido (o web cifra ao receber a notificação).

-- Worker: escreve resultados de jobs e lê PII cifrada.
GRANT INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO jcf_worker_role;
GRANT UPDATE ON reviewer_daily_credits TO jcf_worker_role;
GRANT INSERT ON reputation_snapshots TO jcf_worker_role;

-- Manutenção de partições exige ser dono das tabelas: funções viram SECURITY DEFINER
-- e só o worker pode executá-las.
ALTER FUNCTION ensure_month_partition(regclass, date) SECURITY DEFINER SET search_path = public;
ALTER FUNCTION drop_expired_access_log_partitions() SECURITY DEFINER SET search_path = public;
REVOKE EXECUTE ON FUNCTION ensure_month_partition(regclass, date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION drop_expired_access_log_partitions() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION ensure_month_partition(regclass, date) TO jcf_worker_role;
GRANT EXECUTE ON FUNCTION drop_expired_access_log_partitions() TO jcf_worker_role;

-- Partições futuras herdam os privilégios do pai; tabelas novas em migrações futuras
-- recebem SELECT automaticamente (escrita deve ser concedida explicitamente na migração).
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO jcf_web_role, jcf_worker_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO jcf_web_role, jcf_worker_role;
