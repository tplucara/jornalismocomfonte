# Jornalismo com Fonte

Site de notícias em formato de feed: toda publicação aponta 1 a 3 reportagens de veículos de comunicação cadastrados. Só jornalistas verificados escrevem, avaliam e comentam. O público lê sem conta.

A plataforma é intermediária técnica. **Não certifica verdade.** O conteúdo é responsabilidade exclusiva do autor.

Arquitetura: [docs/adr/0001-arquitetura-e-stack.md](docs/adr/0001-arquitetura-e-stack.md). Modelo de dados: [docs/data-model.md](docs/data-model.md).

## Ambiente local

Nada é instalado na máquina. Tudo corre em Docker, isolado de outros projetos (`jcf-*`, portas altas). Ver `.cursor/rules/ambiente-local.mdc`.

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

## O que este esqueleto já faz

- Páginas públicas em HTML no servidor: feed, artigo, perfil, cadastro de veículos, busca, termos.
- Conta de jornalista: cadastro com aceite versionado, entrada, foto de perfil e envio de comprovante. A conta nasce aguardando revisão humana; staff aprova em `/equipe/verificacoes` (`staff@jcf.example` / `jcf-dev-123` no seed).
- Publicação em `/escrever`: 1 a 3 fontes de veículos do cadastro, com hash de integridade no momento da publicação.
- CSP estrita com nonce, demais cabeçalhos de segurança, CSRF da stdlib, rate limit por hash de IP, log sem PII.
- Queries geradas por sqlc; papéis de banco com privilégio mínimo.
- Worker que cria partições mensais de auditoria (filtro de qualidade e quiz ficam para a próxima iteração).
- Imagens distroless, não-root, sistema de arquivos somente leitura. Avatares e comprovantes em volume local (`MEDIA_DIR`); MinIO entra quando a imagem estiver acessível neste ambiente.

## O que ainda não está neste esqueleto

Avaliação ancorada (quiz), comentários, filtro de qualidade, segundo fator (passkey/TOTP), publicidade, upload para MinIO.
