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

Incluídos após checagem das quatro evidências públicas. Domínios e paths de opinião ficam no SQL (`db/seeds/cadastro_veiculos.sql`).

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

## Lote 2 — 2026-10-28

Seed: `db/seeds/cadastro_veiculos_lote2.sql`. Mesmos 4 critérios; BBC News e AP não se repetem (já no lote 1; `bbc.com/portuguese` cobre-se pelo domínio BBC).

### Brasil

| Veículo | País | Domínios | Sinais |
|---|---|---|---|
| UOL | BR | uol.com.br, noticias.uol.com.br | IFCN (Confere) |
| Nexo Jornal | BR | nexojornal.com.br | Trust Project |
| CNN Brasil | BR | cnnbrasil.com.br | — |
| Poder360 | BR | poder360.com.br | Trust Project |
| O Povo | BR | opovo.com.br | Trust Project |
| Gazeta do Povo | BR | gazetadopovo.com.br | — |
| GZH (Zero Hora) | BR | gauchazh.clicrbs.com.br, clicrbs.com.br | — |

### Portugal e mundo

| Veículo | País | Domínios | Sinais |
|---|---|---|---|
| PÚBLICO | PT | publico.pt | — |
| CNN | US | cnn.com, edition.cnn.com | — |
| The Wall Street Journal | US | wsj.com | — |
| Bloomberg News | US | bloomberg.com | — |
| ProPublica | US | propublica.org | Trust Project |
| USA TODAY | US | usatoday.com | IFCN |
| CBS News | US | cbsnews.com | — |
| TIME | US | time.com | — |
| Al Jazeera English | QA | aljazeera.com | — |
| The Economist | GB | economist.com | — |
| CBC News | CA | cbc.ca | — |
| ABC News (Australia) | AU | abc.net.au | — |
| The Globe and Mail | CA | theglobeandmail.com | — |
| DER SPIEGEL | DE | spiegel.de | — |

Nota CNN Brasil: política de correções documentada pela prática pública “ERRAMOS” e pelo manifesto “Fatos Primeiro”; canal `erro@cnnbrasil.com.br` também é citado em páginas institucionais (algumas só em subdomínios de staging).

## Checagem das evidências (2026-10-28)

HTTP nas URLs de `criteria` do lote 1 (GET com follow-redirect):

| Resultado | O que |
|---|---|
| **200** | 39 de 41 URLs únicas após correção |
| **Corrigido** | AFP `newsroom_url` (`/en/agency/about` → `/en/about-us`); Guardian `corrections_policy_url` (404 antigo → `/info/complaints-and-corrections`) |
| **403 / timeout automatizado** | Financial Times e New York Times (bloqueio de bot); Washington Post às vezes timeout. Conteúdo das páginas de correções/padrões já confirmado por consulta pública; as URLs permanecem. |

Histórico: `outlet_changes` com ação `criteria_updated` para AFP e Guardian.

## Como aplicar

```sh
MSYS_NO_PATHCONV=1 docker exec jcf-db psql -U jcf -d jcf -v ON_ERROR_STOP=1 -f /seeds/cadastro_veiculos.sql
MSYS_NO_PATHCONV=1 docker exec jcf-db psql -U jcf -d jcf -v ON_ERROR_STOP=1 -f /seeds/cadastro_veiculos_lote2.sql
```

Os scripts são idempotentes (`ON CONFLICT DO NOTHING`). Novos lotes entram em arquivos
`cadastro_veiculos_*.sql` ou em nova seção deste documento, com justificativa
pública em `outlet_changes`.

## Fora destes lotes (ainda)

Veículos entram quando os quatro critérios estiverem documentados com URL estável.
Exemplos a avaliar: The Hindu, Asahi Shimbun, Clarín, The Intercept Brasil,
Politico, South China Morning Post, NBC News (página nacional pública de padrões).
