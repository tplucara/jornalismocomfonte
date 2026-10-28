-- Cadastro de veículos — lote inicial (2026-10-28).
-- Artefato versionado e reexecutável. Cada inclusão aponta evidência pública dos
-- 4 critérios (redação, política editorial, política de correções, responsável legal).
-- Sinais IFCN / Trust Project / JTI são positivos, não requisitos.
-- UUIDs estáveis em 2200… / 2210… (fora da faixa .example do dev_seed).
-- Não remove nem altera veículos já presentes; só acrescenta os que faltam.

BEGIN;
SET CONSTRAINTS ALL DEFERRED;

-- ---------------------------------------------------------------------------
-- Brasil
-- ---------------------------------------------------------------------------
INSERT INTO outlets (id, name, country, language, criteria, signals, status) VALUES
  ('22000000-0000-4000-8000-000000000001', 'Folha de S.Paulo', 'BR', 'pt-BR',
   '{"newsroom_url":"https://www1.folha.uol.com.br/institucional/expediente.shtml","editorial_policy_url":"https://www1.folha.uol.com.br/credibilidade/folha-no-projeto-credibilidade.shtml","corrections_policy_url":"https://www1.folha.uol.com.br/erramos/","legal_entity":"Empresa Folha da Manhã S.A."}',
   '{"trust_project": true}', 'active'),
  ('22000000-0000-4000-8000-000000000002', 'O Estado de S. Paulo', 'BR', 'pt-BR',
   '{"newsroom_url":"https://www.estadao.com.br/estadao-verifica/recebeu-algum-boato-envie-para-checagem-do-estadao-verifica/","editorial_policy_url":"https://www.estadao.com.br/codigo-etica/codigo-de-etica.pdf","corrections_policy_url":"https://www.estadao.com.br/correcoes/enviar","legal_entity":"S.A. O Estado de S. Paulo"}',
   '{"ifcn": true}', 'active'),
  ('22000000-0000-4000-8000-000000000003', 'O Globo', 'BR', 'pt-BR',
   '{"newsroom_url":"https://oglobo.globo.com/principios-editoriais/","editorial_policy_url":"https://oglobo.globo.com/principios-editoriais/","corrections_policy_url":"https://g1.globo.com/principios-editoriais-das-organizacoes-globo.pdf","legal_entity":"Infoglobo Comunicação e Participações S.A."}',
   '{}', 'active'),
  ('22000000-0000-4000-8000-000000000004', 'G1', 'BR', 'pt-BR',
   '{"newsroom_url":"https://g1.globo.com/principios-editoriais-das-organizacoes-globo.html","editorial_policy_url":"https://g1.globo.com/principios-editoriais-das-organizacoes-globo.pdf","corrections_policy_url":"https://g1.globo.com/principios-editoriais-das-organizacoes-globo.pdf","legal_entity":"Globo Comunicação e Participações S.A."}',
   '{}', 'active'),
  ('22000000-0000-4000-8000-000000000005', 'Valor Econômico', 'BR', 'pt-BR',
   '{"newsroom_url":"https://valor.globo.com/principios-editoriais-do-grupo-globo/","editorial_policy_url":"https://valor.globo.com/principios-editoriais-do-grupo-globo/","corrections_policy_url":"https://g1.globo.com/principios-editoriais-das-organizacoes-globo.pdf","legal_entity":"Valor Econômico S.A."}',
   '{}', 'active'),
  ('22000000-0000-4000-8000-000000000006', 'Aos Fatos', 'BR', 'pt-BR',
   '{"newsroom_url":"https://www.aosfatos.org/politica-editorial/","editorial_policy_url":"https://www.aosfatos.org/politica-editorial/","corrections_policy_url":"https://www.aosfatos.org/politica-editorial/","legal_entity":"Aos Fatos Jornalismo Independente Ltda."}',
   '{"ifcn": true}', 'active'),
  ('22000000-0000-4000-8000-000000000007', 'Agência Lupa', 'BR', 'pt-BR',
   '{"newsroom_url":"https://lupa.uol.com.br/","editorial_policy_url":"https://www.agencialupa.org/","corrections_policy_url":"https://www.agencialupa.org/noticias/2015/10/15/na-lupa-ha-espaco-para-contestacoes-e-correcoes/","legal_entity":"Lupa News Comunicação e Conteúdo Ltda."}',
   '{"ifcn": true}', 'active'),
  ('22000000-0000-4000-8000-000000000008', 'Agência Pública', 'BR', 'pt-BR',
   '{"newsroom_url":"https://apublica.org/quem-somos/","editorial_policy_url":"https://apublica.org/quem-somos/","corrections_policy_url":"https://apublica.org/politica-de-correcoes/","legal_entity":"Associação Agência Pública de Jornalismo Investigativo"}',
   '{}', 'active')
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Mundo
-- ---------------------------------------------------------------------------
INSERT INTO outlets (id, name, country, language, criteria, signals, status) VALUES
  ('22000000-0000-4000-8000-000000000020', 'The New York Times', 'US', 'en',
   '{"newsroom_url":"https://www.nytimes.com/explain/2022/new-york-times-journalism","editorial_policy_url":"https://www.nytimes.com/editorial-standards/ethical-journalism.html","corrections_policy_url":"https://www.nytimes.com/article/new-york-times-corrections.html","legal_entity":"The New York Times Company"}',
   '{"trust_project": true}', 'active'),
  ('22000000-0000-4000-8000-000000000021', 'The Washington Post', 'US', 'en',
   '{"newsroom_url":"https://www.washingtonpost.com/policies-and-standards/","editorial_policy_url":"https://www.washingtonpost.com/policies-and-standards/","corrections_policy_url":"https://www.washingtonpost.com/policies-and-standards/","legal_entity":"WP Company LLC"}',
   '{"trust_project": true}', 'active'),
  ('22000000-0000-4000-8000-000000000022', 'Associated Press', 'US', 'en',
   '{"newsroom_url":"https://apnews.com/projects/news-values-and-principles/","editorial_policy_url":"https://apnews.com/projects/news-values-and-principles/","corrections_policy_url":"https://apnews.com/projects/news-values-and-principles/","legal_entity":"The Associated Press"}',
   '{"trust_project": true}', 'active'),
  ('22000000-0000-4000-8000-000000000023', 'NPR', 'US', 'en',
   '{"newsroom_url":"https://www.npr.org/ethics","editorial_policy_url":"https://www.npr.org/ethics","corrections_policy_url":"https://www.npr.org/about-npr/688414106/accountability","legal_entity":"National Public Radio, Inc."}',
   '{"trust_project": true}', 'active'),
  ('22000000-0000-4000-8000-000000000024', 'Reuters', 'GB', 'en',
   '{"newsroom_url":"https://www.reutersagency.com/en/about/about-us/","editorial_policy_url":"https://www.reutersagency.com/about/standards-values/","corrections_policy_url":"https://www.reutersagency.com/about/standards-values/","legal_entity":"Reuters News & Media Limited"}',
   '{"trust_project": true, "ifcn": true}', 'active'),
  ('22000000-0000-4000-8000-000000000025', 'BBC News', 'GB', 'en',
   '{"newsroom_url":"https://www.bbc.com/editorialguidelines/guidelines/","editorial_policy_url":"https://www.bbc.com/editorialguidelines/guidelines/","corrections_policy_url":"https://www.bbc.com/editorialguidelines/guidelines/accuracy/","legal_entity":"British Broadcasting Corporation"}',
   '{"trust_project": true}', 'active'),
  ('22000000-0000-4000-8000-000000000026', 'The Guardian', 'GB', 'en',
   '{"newsroom_url":"https://www.theguardian.com/about","editorial_policy_url":"https://www.theguardian.com/about/2023/jul/07/guardian-editorial-code-of-practice-and-guidance-2023","corrections_policy_url":"https://www.theguardian.com/info/complaints-and-corrections","legal_entity":"Guardian News & Media Limited"}',
   '{"trust_project": true}', 'active'),
  ('22000000-0000-4000-8000-000000000027', 'Financial Times', 'GB', 'en',
   '{"newsroom_url":"https://www.ft.com/editorialcode","editorial_policy_url":"https://www.ft.com/editorialcode","corrections_policy_url":"https://www.ft.com/corrections","legal_entity":"The Financial Times Limited"}',
   '{}', 'active'),
  ('22000000-0000-4000-8000-000000000028', 'El País', 'ES', 'es',
   '{"newsroom_url":"https://elpais.com/info/codigo-etico/","editorial_policy_url":"https://elpais.com/info/codigo-etico/","corrections_policy_url":"https://elpais.com/info/codigo-etico/","legal_entity":"Ediciones El País, S.L."}',
   '{"trust_project": true}', 'active'),
  ('22000000-0000-4000-8000-000000000029', 'Le Monde', 'FR', 'fr',
   '{"newsroom_url":"https://www.lemonde.fr/actualite-medias/article/2010/11/03/la-charte-d-ethique-et-de-deontologie-du-groupe-le-monde_1434737_3236.html","editorial_policy_url":"https://www.lemonde.fr/actualite-medias/article/2010/11/03/la-charte-d-ethique-et-de-deontologie-du-groupe-le-monde_1434737_3236.html","corrections_policy_url":"https://www.lemonde.fr/actualite-medias/article/2019/11/07/le-monde-adopte-une-charte-sur-les-corrections_6018371_3236.html","legal_entity":"Société Éditrice du Monde S.A."}',
   '{"trust_project": true}', 'active'),
  ('22000000-0000-4000-8000-000000000030', 'Agence France-Presse', 'FR', 'fr',
   '{"newsroom_url":"https://www.afp.com/en/about-us","editorial_policy_url":"https://www.afp.com/en/editorial-standards-and-best-practices","corrections_policy_url":"https://www.afp.com/sites/default/files/2025-11/EN-Editorial-standards-and-best-practices.pdf","legal_entity":"Agence France-Presse"}',
   '{"ifcn": true}', 'active'),
  ('22000000-0000-4000-8000-000000000031', 'Deutsche Welle', 'DE', 'en',
   '{"newsroom_url":"https://corporate.dw.com/en/editor-in-chiefs-council/s-68340021","editorial_policy_url":"https://corporate.dw.com/en/dws-commitment-to-unbiased-information/a-57623728","corrections_policy_url":"https://corporate.dw.com/en/professional-and-transparent-dw-guidelines-for-dealing-with-errors/a-52066383","legal_entity":"Deutsche Welle"}',
   '{}', 'active')
ON CONFLICT (id) DO NOTHING;

-- Histórico público: uma entrada "included" por veículo, se ainda não houver.
INSERT INTO outlet_changes (outlet_id, action, reason, actor_id, created_at)
SELECT o.id, 'included',
       'Atende aos 4 critérios; inclusão no lote inicial do cadastro (2026-10-28). Evidências nas URLs de criteria.',
       (SELECT id FROM journalists WHERE email = 'staff@jcf.example' LIMIT 1),
       timestamptz '2026-10-28 12:00:00+00'
FROM outlets o
WHERE o.id BETWEEN '22000000-0000-4000-8000-000000000001' AND '22000000-0000-4000-8000-000000000031'
  AND NOT EXISTS (
    SELECT 1 FROM outlet_changes c WHERE c.outlet_id = o.id AND c.action = 'included'
  );

-- Domínios e paths típicos de opinião/coluna/editorial (rejeitados como fonte).
INSERT INTO outlet_domains (id, outlet_id, domain, opinion_path_patterns) VALUES
  ('22100000-0000-4000-8000-000000000001', '22000000-0000-4000-8000-000000000001', 'folha.uol.com.br', '{/colunas/,/opiniao/,/paineldoleitor/,/ombudsman/}'),
  ('22100000-0000-4000-8000-000000000002', '22000000-0000-4000-8000-000000000002', 'estadao.com.br', '{/opiniao/,/colunas/,/blog/}'),
  ('22100000-0000-4000-8000-000000000003', '22000000-0000-4000-8000-000000000003', 'oglobo.globo.com', '{/opiniao/,/colunas/,/blogs/}'),
  ('22100000-0000-4000-8000-000000000004', '22000000-0000-4000-8000-000000000004', 'g1.globo.com', '{/blog/,/opiniao/}'),
  ('22100000-0000-4000-8000-000000000005', '22000000-0000-4000-8000-000000000005', 'valor.globo.com', '{/opiniao/,/eu-e/,/blog/}'),
  ('22100000-0000-4000-8000-000000000006', '22000000-0000-4000-8000-000000000006', 'aosfatos.org', '{}'),
  ('22100000-0000-4000-8000-000000000007', '22000000-0000-4000-8000-000000000007', 'lupa.uol.com.br', '{}'),
  ('22100000-0000-4000-8000-000000000008', '22000000-0000-4000-8000-000000000007', 'agencialupa.org', '{}'),
  ('22100000-0000-4000-8000-000000000009', '22000000-0000-4000-8000-000000000008', 'apublica.org', '{}'),
  ('22100000-0000-4000-8000-000000000020', '22000000-0000-4000-8000-000000000020', 'nytimes.com', '{/opinion/,/column/,/editorial/}'),
  ('22100000-0000-4000-8000-000000000021', '22000000-0000-4000-8000-000000000021', 'washingtonpost.com', '{/opinions/,/outlook/,/editorial/}'),
  ('22100000-0000-4000-8000-000000000022', '22000000-0000-4000-8000-000000000022', 'apnews.com', '{}'),
  ('22100000-0000-4000-8000-000000000023', '22000000-0000-4000-8000-000000000023', 'npr.org', '{/sections/opinion/,/series/npr-opinion/}'),
  ('22100000-0000-4000-8000-000000000024', '22000000-0000-4000-8000-000000000024', 'reuters.com', '{/breakingviews/}'),
  ('22100000-0000-4000-8000-000000000025', '22000000-0000-4000-8000-000000000025', 'bbc.com', '{/news/blogs-,/news/have_your_say/}'),
  ('22100000-0000-4000-8000-000000000026', '22000000-0000-4000-8000-000000000025', 'bbc.co.uk', '{/news/blogs-,/news/have_your_say/}'),
  ('22100000-0000-4000-8000-000000000027', '22000000-0000-4000-8000-000000000026', 'theguardian.com', '{/commentisfree/,/tone/comment/,/tone/editorials/}'),
  ('22100000-0000-4000-8000-000000000028', '22000000-0000-4000-8000-000000000027', 'ft.com', '{/opinion/,/ft-view/}'),
  ('22100000-0000-4000-8000-000000000029', '22000000-0000-4000-8000-000000000028', 'elpais.com', '{/opinion/,/ideas/}'),
  ('22100000-0000-4000-8000-000000000030', '22000000-0000-4000-8000-000000000029', 'lemonde.fr', '{/idees/,/campus/,/blog/}'),
  ('22100000-0000-4000-8000-000000000031', '22000000-0000-4000-8000-000000000030', 'afp.com', '{}'),
  ('22100000-0000-4000-8000-000000000032', '22000000-0000-4000-8000-000000000031', 'dw.com', '{/opinion/}')
ON CONFLICT (domain) DO NOTHING;

COMMIT;

SELECT o.country, o.name, o.status,
       (SELECT string_agg(d.domain::text, ', ' ORDER BY d.domain) FROM outlet_domains d WHERE d.outlet_id = o.id) AS domains
FROM outlets o
WHERE o.id::text LIKE '22000000%'
ORDER BY o.country, o.name;
