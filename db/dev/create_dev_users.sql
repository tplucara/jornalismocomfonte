-- Usuários de login para desenvolvimento local. Idempotente.
-- Senhas correspondem a .env.example. Em produção, criar via secret manager, nunca por arquivo.
-- Uso: docker exec jcf-db sh -c 'psql -q -U jcf -d jcf -v ON_ERROR_STOP=1 -f /dev/create_dev_users.sql'

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'jcf_web') THEN
    CREATE ROLE jcf_web LOGIN PASSWORD 'jcf_web_dev_only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'jcf_worker') THEN
    CREATE ROLE jcf_worker LOGIN PASSWORD 'jcf_worker_dev_only';
  END IF;
END $$;

GRANT jcf_web_role TO jcf_web;
GRANT jcf_worker_role TO jcf_worker;
GRANT CONNECT ON DATABASE jcf TO jcf_web, jcf_worker;
