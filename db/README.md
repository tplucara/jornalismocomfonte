# Banco de dados — PostgreSQL 16

Schema do Jornalismo com Fonte em migrações SQL puras. Cada invariante das rules de produto
(`.cursor/rules/`) vira constraint, trigger ou índice; o mapeamento completo está em
[`docs/data-model.md`](../docs/data-model.md).

## Subir o ambiente local

Isolado de outros projetos Docker da máquina (ver `.cursor/rules/ambiente-local.mdc`):
projeto `jcf`, containers `jcf-*`, volumes `jcf_*`, rede `jcf_net`.

| Serviço | Porta no host |
|---|---|
| Site (Caddy) | **8843** |
| Postgres | **5433** |

```sh
docker compose up -d
docker compose ps          # jcf-db deve aparecer como healthy
```

Conexão: `postgres://jcf:jcf_dev_only@localhost:5433/jcf` (credenciais só para desenvolvimento).

## Aplicar migrações

Não há `psql` instalado na máquina; use o do container. As migrações são montadas em `/migrations`.

```sh
docker exec jcf-db sh -c 'for f in /migrations/*.sql; do psql -q -U jcf -d jcf -v ON_ERROR_STOP=1 -f "$f" || exit 1; done'
```

As migrações não são idempotentes. Para recomeçar do zero sem derrubar o container:

```sh
docker exec jcf-db psql -q -U jcf -d jcf -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
```

## Popular com dados de desenvolvimento

`db/seeds/dev_seed.sql` é re-executável (faz `TRUNCATE` de tudo e recria) e passa por todos os
triggers — é também um exemplo de como a aplicação deve escrever no banco.

```sh
docker exec jcf-db sh -c 'psql -q -U jcf -d jcf -v ON_ERROR_STOP=1 -f /seeds/dev_seed.sql'
```

O que ele cria:

- 8 jornalistas (5 verificados, 1 pendente, 1 suspenso, 1 equipe). Senha de todos: `jcf-dev-123`.
  E-mails: `ana.ribeiro@`, `bruno.castro@`, `carla.mendes@`, `diego.alves@`, `elisa.moura@`,
  `fabio.nunes@` (pendente), `gustavo.lima@` (suspenso), `staff@` — todos `@jcf.example`.
- 9 veículos de demonstração (8 ativos em 7 países, 1 suspenso), domínios `.example`.
- Cadastro real em `cadastro_veiculos.sql` (jornais e agências do Brasil e do mundo; ver `docs/cadastro-de-veiculos.md`).
- 9 artigos: 7 publicados (Reportagem, Análise e Opinião), 1 rascunho, 1 removido por notificação válida.
  Um deles tem correção publicada (versão 2 com nota).
- 16 fontes com registro de integridade; 32 perguntas de quiz (2 por fonte).
- 20 votos (17 válidos, 1 rejeitado por ataque ao autor, 2 pendentes de filtro) e 6 comentários com flag.
- 1 denúncia de distorção procedente e 1 aberta; 1 direito de resposta publicado.
- 2 notificações: uma removeu artigo (com contranotificação aberta), outra foi redirecionada a direito
  de resposta por ser alegação de honra (só ordem judicial remove).
- 1 apelação aberta; snapshots de reputação para todos.

Os veículos de demonstração usam o TLD reservado `.example` (RFC 2606). O cadastro real
(`cadastro_veiculos.sql`) usa domínios e URLs públicos; a migrate aplica o arquivo sempre
que ele existir (idempotente).

A chave de cifra da PII de terceiros no seed é `dev-only-key`.

## Rodar os testes de invariantes

`db/tests/invariants.sql` tenta violar cada regra e exige erro; termina com `ROLLBACK`, então
não deixa dados no banco.

```sh
docker exec jcf-db sh -c 'psql -q -U jcf -d jcf -v ON_ERROR_STOP=1 -f /tests/invariants.sql' 2>&1 | grep -E 'PASS|FAIL|ERROR'
```

Qualquer linha `TEST FAILED` ou `ERROR` indica regressão.

## Convenções

- Arquivos `NNNN_nome.sql`, aplicados em ordem lexicográfica. Nunca editar migração já aplicada em
  ambiente compartilhado; criar a próxima.
- Identificadores em inglês `snake_case`. Enums em inglês; rótulos em português ficam na UI
  (tabela de mapeamento em `docs/data-model.md`).
- Tabelas append-only (`article_versions`, `legal_acceptances`, `outlet_changes`, `audit_log`,
  `access_logs`) têm trigger `forbid_update_delete()`. Correção = nova linha, nunca UPDATE.
- Constraint triggers `DEFERRABLE INITIALLY DEFERRED` checam no `COMMIT`. A aplicação deve
  inserir versão, fontes e atualizar o artigo **na mesma transação**.
- Contexto de auditoria: a aplicação define por transação
  `SET LOCAL app.actor_id = '<uuid>'`, `SET LOCAL app.session_hash = '...'`, `SET LOCAL app.ip_hash = '...'`.
  O trigger `audit_row_change()` lê esses valores.
- PII de terceiros (`notifier_pii`, `requester_pii`) é `bytea` cifrado com `pgp_sym_encrypt`;
  a chave vive na aplicação, nunca no banco.

## Manutenção periódica (jobs da aplicação)

| Função | Quando | O que faz |
|---|---|---|
| `ensure_month_partition('audit_log', date)` e `('access_logs', date)` | Início de cada mês, para o mês seguinte | Cria partição mensal com trigger append-only |
| `drop_expired_access_log_partitions()` | Diário | Remove partições de `access_logs` com mais de 6 meses (Marco Civil art. 15) |
| Recalcular `reputation_snapshots` | Periódico | Job da aplicação; grava snapshot, nunca calcula em leitura |
| Recheque de `article_sources.content_hash` | Periódico | Atualiza `hash_status` e `hash_compared_at` |

## Derrubar

Só este projeto, dentro deste diretório:

```sh
docker compose down -v
```
