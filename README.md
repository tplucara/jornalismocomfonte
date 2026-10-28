# Jornalismo com Fonte

Site de notícias em formato de feed: toda publicação aponta 1 a 3 reportagens de veículos de comunicação cadastrados. Contas ativas publicam e avaliam fidelidade às fontes; o selo **jornalista verificado** é opcional (identidade, não conteúdo). O público lê sem conta.

A plataforma é intermediária técnica. **Não certifica verdade.** O conteúdo é responsabilidade exclusiva do autor.

Arquitetura: [docs/adr/0001-arquitetura-e-stack.md](docs/adr/0001-arquitetura-e-stack.md). Modelo de dados: [docs/data-model.md](docs/data-model.md). Documentos legais: [docs/legal/](docs/legal/) (versão 1.1).

## Ambiente local

Nada é instalado na máquina. Tudo corre em Docker, isolado de outros projetos (`jcf-*`, portas altas).

| Serviço | Host |
|---|---|
| Site (Caddy → web) | http://localhost:8843 |
| Postgres | localhost:5433 |

```sh
docker compose up --build
```

Na primeira subida o serviço `jcf-migrate` aplica as migrações, cria os papéis `jcf_web` e `jcf_worker` e carrega o seed se o banco estiver vazio.

Abrir http://localhost:8843 — feed com as publicações do seed, artigos com fontes no topo, perfis, cadastro de veículos.

Para só o banco: `docker compose up -d db migrate`. Detalhes em [db/README.md](db/README.md).

Encerrar só este projeto, neste diretório:

```sh
docker compose down
```

(`down -v` apaga o volume `jcf_pgdata` deste projeto. Nunca use `docker system prune`.)

## O que este protótipo já faz

- Páginas públicas em HTML no servidor: feed, artigo, perfil, cadastro de veículos, busca, termos.
- Conta: cadastro com aceite versionado (docs legais 1.1), entrada, foto de perfil. Publicação com fontes sem exigir selo de jornalista. Selo opcional via comprovante + revisão em `/equipe/verificacoes` (`staff@jcf.example` / `jcf-dev-123` no seed).
- Publicação em `/escrever`: 1 a 3 fontes do cadastro, com hash de integridade.
- CSP estrita com nonce, cabeçalhos de segurança, CSRF, rate limit por hash de IP, log sem PII.
- Queries sqlc; papéis de banco com privilégio mínimo; worker de partições de auditoria.
- Distroless, não-root, FS somente leitura; mídia em volume local (`MEDIA_DIR`).

## Ainda não neste protótipo

Avaliação ancorada (quiz) na UI, comentários, filtro de qualidade, segundo fator (passkey/TOTP), publicidade, MinIO.
