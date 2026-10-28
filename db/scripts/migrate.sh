#!/bin/sh
# Aplica migrações pendentes, cria papéis de login de desenvolvimento e, se o banco
# estiver vazio, carrega o seed. Idempotente. Roda como o superusuário jcf.
set -eu
export PGHOST="${PGHOST:-jcf-db}"
export PGUSER="${PGUSER:-jcf}"
export PGDATABASE="${PGDATABASE:-jcf}"

echo "aguardando postgres..."
i=0
until pg_isready >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -gt 30 ]; then
    echo "postgres indisponível" >&2
    exit 1
  fi
  sleep 1
done

psql -v ON_ERROR_STOP=1 -q -c "CREATE TABLE IF NOT EXISTS schema_migrations (
  filename text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);"

# Banco já populado por execuções anteriores a esta tabela: marca 0001–0008.
if [ "$(psql -tAc "SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='journalists'")" = "1" ]; then
  for f in /migrations/0001_*.sql /migrations/0002_*.sql /migrations/0003_*.sql /migrations/0004_*.sql \
           /migrations/0005_*.sql /migrations/0006_*.sql /migrations/0007_*.sql /migrations/0008_*.sql; do
    [ -f "$f" ] || continue
    b=$(basename "$f")
    psql -q -c "INSERT INTO schema_migrations(filename) VALUES ('$b') ON CONFLICT DO NOTHING;"
  done
fi

for f in /migrations/*.sql; do
  b=$(basename "$f")
  if [ "$(psql -tAc "SELECT 1 FROM schema_migrations WHERE filename='$b'")" = "1" ]; then
    continue
  fi
  echo "aplicando $b"
  psql -v ON_ERROR_STOP=1 -q -f "$f"
  psql -q -c "INSERT INTO schema_migrations(filename) VALUES ('$b');"
done

psql -v ON_ERROR_STOP=1 -q -f /devsql/create_dev_users.sql

if [ "$(psql -tAc "SELECT count(*) FROM journalists")" = "0" ]; then
  echo "banco vazio: carregando seed"
  psql -v ON_ERROR_STOP=1 -q -f /seeds/dev_seed.sql
fi

# Cadastro real de veículos: idempotente; roda sempre após o seed de demo.
if [ -f /seeds/cadastro_veiculos.sql ]; then
  echo "atualizando cadastro de veículos"
  psql -v ON_ERROR_STOP=1 -q -f /seeds/cadastro_veiculos.sql
fi

echo "migrate ok"
