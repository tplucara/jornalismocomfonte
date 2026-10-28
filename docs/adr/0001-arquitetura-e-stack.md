# ADR 0001 — Arquitetura e stack

**Status**: aceito · **Data**: 2026-10-27

## Contexto

O Jornalismo com Fonte é um site de notícias em feed onde o público só lê e apenas jornalistas verificados escrevem, avaliam e comentam. As rules exigem invariantes no servidor, white hat em tudo, zero rastreamento, acessibilidade AA, e o pedido explícito é "o mais anti-hacking possível". Já decidimos PostgreSQL 16 com migrações SQL puras e um schema que carrega as invariantes em constraints e triggers.

Restrições da máquina de desenvolvimento: nenhuma toolchain instalada (Go, .NET, Node, Python) e a rule `ambiente-local.mdc` proíbe instalação global. Tudo precisa compilar e rodar em Docker.

## Princípios que guiaram a escolha

1. **Menor superfície de ataque vence feature.** Cada dependência, cada byte de JavaScript, cada porta aberta é superfície.
2. **Segurança por padrão, não por disciplina.** O framework deve escapar HTML, proteger contra CSRF e parametrizar SQL sem que o desenvolvedor lembre de fazer.
3. **Linguagem memory-safe, tipada e compilada.** Classes inteiras de bugs desaparecem; o compilador pega o que o revisor não viu.
4. **Cadeia de suprimentos pequena e verificável.** Poucas dependências, de poucos autores, com checksums e varredura de vulnerabilidades no build.
5. **O banco já é a última linha de defesa.** O código da aplicação deve espelhar o schema, não reinventá-lo.

## Decisão

### Linguagem e servidor web: Go

- Memory-safe, compilado, tipado, binário estático único. Imagem final `distroless`, sem shell, rodando como não-root com sistema de arquivos somente leitura.
- `net/http` da biblioteca padrão como servidor. `html/template` com **escape contextual automático** (HTML, atributo, URL, JS) — a melhor defesa nativa contra XSS entre os ecossistemas avaliados.
- Go 1.25+ inclui `http.CrossOriginProtection` (CSRF via `Sec-Fetch-Site`/`Origin`) na biblioteca padrão.
- Cadeia de suprimentos: `go.sum` com checksum DB público (`sum.golang.org`), `govulncheck` no CI, `GOFLAGS=-mod=readonly`.
- Dependências de terceiros permitidas inicialmente (todas de autores estabelecidos, revisadas):
  `jackc/pgx` (driver Postgres), `sqlc` (gera Go tipado a partir de SQL — espelha o schema sem ORM),
  `alexedwards/scs` (sessões server-side), `golang.org/x/crypto` (Argon2id), `golang.org/x/time/rate`,
  `go-webauthn/webauthn` (passkeys para jornalistas). Qualquer outra exige justificativa em PR.

### Renderização: HTML no servidor, JavaScript mínimo

- Páginas renderizadas no servidor. Sem SPA, sem framework de frontend, **sem `npm`** (a maior fonte de risco de cadeia de suprimentos em aplicações web).
- Progressive enhancement: o site funciona 100% sem JavaScript. Onde interatividade ajudar (quiz, voto), um único arquivo JS próprio, pequeno, servido do mesmo domínio, com `nonce` de CSP.
- CSP estrita: `default-src 'none'; script-src 'nonce-…' 'strict-dynamic'; style-src 'self'; img-src 'self' <storage>; form-action 'self'; frame-ancestors 'none'; base-uri 'none'`.
- Resultado colateral alinhado às rules: SEO honesto (HTML completo para buscadores), acessibilidade AA mais fácil, zero trackers por construção.

### Dados: PostgreSQL 16 (já decidido) + sqlc

- Migrações SQL em `db/migrations/`; `sqlc` gera o código Go de acesso a partir de queries SQL versionadas em `db/queries/`. Sem ORM, sem SQL concatenado: toda query é parametrizada por construção.
- Dois papéis de banco com privilégio mínimo: `jcf_web` (sem DDL, sem `DELETE` em tabelas append-only, sem acesso a PII cifrada) e `jcf_worker` (jobs). Migrações rodam com papel separado.
- Contexto de auditoria via `SET LOCAL app.actor_id/session_hash/ip_hash` em toda transação (já previsto no schema).

### Processos

```text
caddy  ──►  web (Go)     ──►  postgres
             worker (Go) ──►  postgres, provedor de IA, object storage
```

- **`cmd/web`**: site público (feed, artigo, perfil, cadastro de veículos) e área do jornalista (publicar, avaliar, comentar, apelar), além de área administrativa restrita (verificação, cadastro de veículos, notificações).
- **`cmd/worker`**: jobs assíncronos — geração de perguntas do quiz, filtro de qualidade de votos/comentários, recheque de hash das fontes, cálculo de reputação, criação/expurgo de partições. Fila simples em Postgres (`SELECT … FOR UPDATE SKIP LOCKED`); sem broker adicional.
- **Caddy** como proxy reverso: TLS automático, HTTP/2 e 3, cabeçalhos de segurança, limite de tamanho de corpo. Memory-safe (Go), configuração de 20 linhas.
- **Object storage S3-compatível** para avatares e documentos de verificação (bucket privado, URLs assinadas de curta duração, expurgo após decisão). MinIO em desenvolvimento, em portas que não conflitem com outros projetos da máquina.
- **IA**: chamadas HTTP ao provedor a partir do worker, nunca do request do usuário. Entrada sempre tratada como não confiável; saída validada contra schema antes de persistir. Prompts versionados no repositório.

### Autenticação dos jornalistas

- Senha com **Argon2id** (parâmetros OWASP), ou **passkey (WebAuthn)** como primeira opção.
- **Segundo fator obrigatório** para publicar, avaliar e para a área administrativa (passkey ou TOTP).
- Sessão server-side (cookie `__Host-`, `HttpOnly`, `Secure`, `SameSite=Lax`), rotação de ID no login, expiração absoluta e por inatividade.
- Rate limit por IP e por conta em login, publicação, voto e comentário; bloqueio progressivo.
- Leitores não têm sessão: páginas públicas são cacheáveis e servidas sem cookie.

### Segurança operacional

- Imagens `distroless`, não-root, FS somente leitura, `cap_drop: ALL`, `no-new-privileges`.
- Segredos por variável de ambiente ou arquivo montado; nunca no repositório. `.env` no `.gitignore`.
- CI: `go vet`, `staticcheck`, `gosec`, `govulncheck`, testes, build da imagem, varredura da imagem (`trivy`). Build falha com vulnerabilidade crítica.
- Logs estruturados sem PII; IP só como hash com salt rotativo (já exigido pelo schema).
- `/.well-known/security.txt`, cabeçalhos `Strict-Transport-Security` (preload), `X-Content-Type-Options`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy` negando tudo.
- Backups cifrados do Postgres com teste de restauração periódico.

## Alternativas consideradas

| Opção | Por que não |
|---|---|
| **ASP.NET Core (Razor Pages)** | Segunda melhor opção: memory-safe, antiforgery e Identity maduros, Npgsql excelente. Perdeu por superfície maior (runtime, Kestrel, Identity traz muito que não usaremos), imagens maiores e menor sinergia com o schema SQL-first (EF Core empurra para ORM). |
| **Django** | Melhor conjunto de proteções "por padrão" entre frameworks dinâmicos. Perdeu por Python não ser compilado/tipado de verdade, cadeia `pip` ampla e difícil de auditar, e imagem com interpretador e shell. |
| **Rust (Axum)** | Máxima segurança de memória, mas custo de desenvolvimento alto para equipe pequena; Go entrega memory-safety suficiente para aplicação web com muito menos atrito. |
| **Node/TypeScript (Next.js, SvelteKit)** | Descartado pela cadeia `npm` (milhares de pacotes transitivos), histórico de incidentes de supply chain e tendência a SPA/JS pesado, que contraria white hat, acessibilidade e CSP estrita. |
| **Elixir/Phoenix** | Excelente, mas LiveView depende de WebSocket persistente (mais superfície) e o ecossistema é menor para WebAuthn e tooling de segurança. |

## Consequências

- Todo o desenvolvimento acontece em containers; `Dockerfile` multi-stage com `golang:1.25` para build e `gcr.io/distroless/static` para execução. Nenhuma instalação global na máquina.
- Sem build de frontend: não há `package.json`, bundler ou transpilação. CSS próprio, estático.
- Qualquer nova dependência Go, qualquer byte de JS de terceiro e qualquer nova porta exposta precisam de justificativa escrita em PR, avaliada contra o princípio 1.
- A rule `.cursor/rules/stack-e-seguranca.mdc` resume estas decisões para o dia a dia.

## Próximo passo

Esqueleto do repositório: `go.mod`, `cmd/web`, `cmd/worker`, `internal/`, `db/queries/` + `sqlc.yaml`, `Dockerfile`, `Caddyfile`, serviços `web`, `worker`, `caddy` e `minio` no `docker-compose.yml`, middleware de segurança (CSP com nonce, cabeçalhos, rate limit, sessão, CSRF), página pública do feed e do artigo lendo o seed, CI com as varreduras acima.
