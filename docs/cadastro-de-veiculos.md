# Cadastro de veículos

Artefato público e versionado. Critérios e processo estão em `.cursor/rules/cadastro-de-veiculos.mdc`.
O seed executável está em `db/seeds/cadastro_veiculos.sql`.

O cadastro **habilita a citação** como fonte. Não atesta veracidade do veículo nem do conteúdo.

## Critérios (todos obrigatórios)

1. Redação identificável (equipe editorial nomeada).
2. Política editorial pública.
3. Política de correções pública.
4. Responsável legal identificável.

Sinais positivos (não requisitos): IFCN, Trust Project, JTI.

## Lote inicial — 2026-10-28

Incluídos após checagem das quatro evidências públicas. Domínios e paths de opinião ficam no SQL.

### Brasil

| Veículo | País | Domínios | Sinais |
|---|---|---|---|
| Folha de S.Paulo | BR | folha.uol.com.br | Trust Project |
| O Estado de S. Paulo | BR | estadao.com.br | IFCN (Verifica) |
| O Globo | BR | oglobo.globo.com | — |
| G1 | BR | g1.globo.com | — |
| Valor Econômico | BR | valor.globo.com | — |
| Aos Fatos | BR | aosfatos.org | IFCN |
| Agência Lupa | BR | lupa.uol.com.br, agencialupa.org | IFCN |
| Agência Pública | BR | apublica.org | — |

### Mundo

| Veículo | País | Domínios | Sinais |
|---|---|---|---|
| The New York Times | US | nytimes.com | Trust Project |
| The Washington Post | US | washingtonpost.com | Trust Project |
| Associated Press | US | apnews.com | Trust Project |
| NPR | US | npr.org | Trust Project |
| Reuters | GB | reuters.com | Trust Project, IFCN |
| BBC News | GB | bbc.com, bbc.co.uk | Trust Project |
| The Guardian | GB | theguardian.com | Trust Project |
| Financial Times | GB | ft.com | — |
| El País | ES | elpais.com | Trust Project |
| Le Monde | FR | lemonde.fr | Trust Project |
| Agence France-Presse | FR | afp.com | IFCN (Fact Check) |
| Deutsche Welle | DE | dw.com | — |

## Checagem das evidências (2026-10-28)

HTTP nas URLs de `criteria` (GET com follow-redirect):

| Resultado | O que |
|---|---|
| **200** | 39 de 41 URLs únicas após correção |
| **Corrigido** | AFP `newsroom_url` (`/en/agency/about` → `/en/about-us`); Guardian `corrections_policy_url` (404 antigo → `/info/complaints-and-corrections`) |
| **403 / timeout automatizado** | Financial Times e New York Times (bloqueio de bot); Washington Post às vezes timeout. Conteúdo das páginas de correções/padrões já confirmado por consulta pública; as URLs permanecem. |

Histórico: `outlet_changes` com ação `criteria_updated` para AFP e Guardian.

## Como aplicar

```sh
MSYS_NO_PATHCONV=1 docker exec jcf-db psql -U jcf -d jcf -v ON_ERROR_STOP=1 -f /seeds/cadastro_veiculos.sql
```

O script é idempotente (`ON CONFLICT DO NOTHING`). Novos lotes entram em arquivos
`cadastro_veiculos_YYYY-MM-DD.sql` ou em nova seção deste documento, com justificativa
pública em `outlet_changes`.

## Fora deste lote (ainda)

Veículos regionais e de outros idiomas entram quando os quatro critérios estiverem
documentados. Exemplos a avaliar: The Hindu, Asahi Shimbun, Clarín, Folha de Portugal /
Público, The Globe and Mail, Al Jazeera English, Bloomberg, Wall Street Journal, Nexo Jornal.
