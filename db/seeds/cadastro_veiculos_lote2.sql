-- Cadastro de veículos — lote 2 (2026-10-28).
-- Idempotente. Só acrescenta IDs/domínios novos.
-- Cada linha aponta evidência pública dos 4 critérios.
-- BBC News (bbc.com) e Associated Press (apnews.com) já estão no lote 1.

BEGIN;
SET CONSTRAINTS ALL DEFERRED;

-- ---------------------------------------------------------------------------
-- Brasil
-- ---------------------------------------------------------------------------
INSERT INTO outlets (id, name, country, language, criteria, signals, status) VALUES
  ('22000000-0000-4000-8000-000000000040', 'UOL', 'BR', 'pt-BR',
   '{"newsroom_url":"https://noticias.uol.com.br/missao-e-compromisso/","editorial_policy_url":"https://noticias.uol.com.br/missao-e-compromisso/","corrections_policy_url":"https://noticias.uol.com.br/erratas/","legal_entity":"Universo Online S.A."}',
   '{"ifcn": true}', 'active'),
  ('22000000-0000-4000-8000-000000000041', 'Nexo Jornal', 'BR', 'pt-BR',
   '{"newsroom_url":"https://www.nexojornal.com.br/sobre/nossa-equipe","editorial_policy_url":"https://network.thetrustproject.org/partner/nexo","corrections_policy_url":"https://network.thetrustproject.org/partner/nexo","legal_entity":"Instituto Nexo de Jornalismo"}',
   '{"trust_project": true}', 'active'),
  ('22000000-0000-4000-8000-000000000042', 'CNN Brasil', 'BR', 'pt-BR',
   '{"newsroom_url":"https://www.cnnbrasil.com.br/nacional/fatos-primeiro-manifesto-em-defesa-da-credibilidade-da-cnn/","editorial_policy_url":"https://www.cnnbrasil.com.br/nacional/fatos-primeiro-manifesto-em-defesa-da-credibilidade-da-cnn/","corrections_policy_url":"https://www.cnnbrasil.com.br/nacional/erramos-nome-de-bolsonaro-aparece-em-redacao-de-post-sobre-explosao-de-hotel-em-cuba/","legal_entity":"CNN Brasil Serviços de Notícias Ltda. (licença CNN International Commercial)"}',
   '{}', 'active'),
  ('22000000-0000-4000-8000-000000000043', 'Poder360', 'BR', 'pt-BR',
   '{"newsroom_url":"https://www.poder360.com.br/equipe/","editorial_policy_url":"https://www.poder360.com.br/politica-editorial/","corrections_policy_url":"https://www.poder360.com.br/contato/","legal_entity":"Poder360 Jornalismo Ltda."}',
   '{"trust_project": true}', 'active'),
  ('22000000-0000-4000-8000-000000000044', 'O Povo', 'BR', 'pt-BR',
   '{"newsroom_url":"https://www.opovo.com.br/conhecaopovo/compromissoseditoriais","editorial_policy_url":"https://www.opovo.com.br/conhecaopovo/compromissoseditoriais","corrections_policy_url":"https://www.opovo.com.br/conhecaopovo/compromissoseditoriais","legal_entity":"O Povo Comunicação S.A."}',
   '{"trust_project": true}', 'active'),
  ('22000000-0000-4000-8000-000000000045', 'Gazeta do Povo', 'BR', 'pt-BR',
   '{"newsroom_url":"https://www.gazetadopovo.com.br/principios-editoriais/","editorial_policy_url":"https://www.gazetadopovo.com.br/principios-editoriais/","corrections_policy_url":"https://www.gazetadopovo.com.br/politica-de-correcoes-e-atualizacoes-de-conteudos/","legal_entity":"GRPCom – Grupo Paranaense de Comunicação"}',
   '{}', 'active'),
  ('22000000-0000-4000-8000-000000000046', 'GZH (Zero Hora)', 'BR', 'pt-BR',
   '{"newsroom_url":"https://gauchazh.clicrbs.com.br/praticas-editoriais","editorial_policy_url":"https://gauchazh.clicrbs.com.br/praticas-editoriais","corrections_policy_url":"https://gauchazh.clicrbs.com.br/praticas-editoriais","legal_entity":"Rede Brasil Sul de Comunicação S.A. (Grupo RBS)"}',
   '{}', 'active')
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Portugal
-- ---------------------------------------------------------------------------
INSERT INTO outlets (id, name, country, language, criteria, signals, status) VALUES
  ('22000000-0000-4000-8000-000000000050', 'PÚBLICO', 'PT', 'pt-PT',
   '{"newsroom_url":"https://www.publico.pt/nos/ficha-tecnica","editorial_policy_url":"https://www.publico.pt/nos/estatuto-editorial","corrections_policy_url":"https://static.publico.pt/files/provadosfactos/livro-de-estilo.pdf","legal_entity":"PÚBLICO – Comunicação Social, S.A."}',
   '{}', 'active')
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Mundo
-- ---------------------------------------------------------------------------
INSERT INTO outlets (id, name, country, language, criteria, signals, status) VALUES
  ('22000000-0000-4000-8000-000000000060', 'CNN', 'US', 'en',
   '{"newsroom_url":"https://edition.cnn.com/about","editorial_policy_url":"https://edition.cnn.com/about","corrections_policy_url":"https://edition.cnn.com/tips","legal_entity":"Cable News Network, Inc. (Warner Bros. Discovery)"}',
   '{}', 'active'),
  ('22000000-0000-4000-8000-000000000061', 'The Wall Street Journal', 'US', 'en',
   '{"newsroom_url":"https://www.wsj.com/about-us","editorial_policy_url":"https://www.wsj.com/about-us","corrections_policy_url":"https://www.wsj.com/news/types/corrections","legal_entity":"Dow Jones & Company, Inc."}',
   '{}', 'active'),
  ('22000000-0000-4000-8000-000000000062', 'Bloomberg News', 'US', 'en',
   '{"newsroom_url":"https://www.bloomberg.com/company/press/the-bloomberg-way-guide-for-reporters-and-editors-now-available-to-the-public/","editorial_policy_url":"https://www.bloomberg.com/company/press/the-bloomberg-way-guide-for-reporters-and-editors-now-available-to-the-public/","corrections_policy_url":"https://www.bloomberg.com/help/question/submit-feedback-news-coverage/","legal_entity":"Bloomberg L.P."}',
   '{}', 'active'),
  ('22000000-0000-4000-8000-000000000063', 'ProPublica', 'US', 'en',
   '{"newsroom_url":"https://www.propublica.org/about/","editorial_policy_url":"https://www.propublica.org/code-of-ethics","corrections_policy_url":"https://www.propublica.org/corrections","legal_entity":"Pro Publica, Inc."}',
   '{"trust_project": true}', 'active'),
  ('22000000-0000-4000-8000-000000000064', 'USA TODAY', 'US', 'en',
   '{"newsroom_url":"https://cm.usatoday.com/ethical-conduct","editorial_policy_url":"https://cm.usatoday.com/ethical-conduct","corrections_policy_url":"https://www.usatoday.com/story/news/2026/01/11/corrections-clarifications-2026/88134660007/","legal_entity":"Gannett Co., Inc."}',
   '{"ifcn": true}', 'active'),
  ('22000000-0000-4000-8000-000000000065', 'CBS News', 'US', 'en',
   '{"newsroom_url":"https://www.cbsnews.com/news/cbs-news-publishing-principles/","editorial_policy_url":"https://www.cbsnews.com/news/cbs-news-publishing-principles/","corrections_policy_url":"https://www.cbsnews.com/news/cbs-news-publishing-principles/","legal_entity":"CBS News, a division of Paramount Global"}',
   '{}', 'active'),
  ('22000000-0000-4000-8000-000000000066', 'TIME', 'US', 'en',
   '{"newsroom_url":"https://time.com/about-time/","editorial_policy_url":"https://time.com/about-time/","corrections_policy_url":"https://time.com/about-time/","legal_entity":"Time USA, LLC"}',
   '{}', 'active'),
  ('22000000-0000-4000-8000-000000000067', 'Al Jazeera English', 'QA', 'en',
   '{"newsroom_url":"https://network.aljazeera.net/en/our-values/standards","editorial_policy_url":"https://www.aljazeera.com/code-of-ethics","corrections_policy_url":"https://network.aljazeera.net/en/our-values/standards","legal_entity":"Al Jazeera Media Network"}',
   '{}', 'active'),
  ('22000000-0000-4000-8000-000000000068', 'The Economist', 'GB', 'en',
   '{"newsroom_url":"https://www.economist.com/about-the-economist","editorial_policy_url":"https://www.economist.com/about-the-economist","corrections_policy_url":"https://www.economist.com/help/contact-us","legal_entity":"The Economist Newspaper Limited"}',
   '{}', 'active'),
  ('22000000-0000-4000-8000-000000000069', 'CBC News', 'CA', 'en',
   '{"newsroom_url":"https://cbc.radio-canada.ca/en/vision/governance","editorial_policy_url":"https://cbc.radio-canada.ca/en/vision/journalistic-standards-and-practices","corrections_policy_url":"https://cbc.radio-canada.ca/en/ombudsman","legal_entity":"Canadian Broadcasting Corporation"}',
   '{}', 'active'),
  ('22000000-0000-4000-8000-000000000070', 'ABC News (Australia)', 'AU', 'en',
   '{"newsroom_url":"https://www.abc.net.au/news/about/","editorial_policy_url":"https://www.abc.net.au/edpols","corrections_policy_url":"https://www.abc.net.au/corrections","legal_entity":"Australian Broadcasting Corporation"}',
   '{}', 'active'),
  ('22000000-0000-4000-8000-000000000071', 'The Globe and Mail', 'CA', 'en',
   '{"newsroom_url":"https://www.theglobeandmail.com/about/","editorial_policy_url":"https://www.theglobeandmail.com/about/","corrections_policy_url":"https://www.theglobeandmail.com/contact/","legal_entity":"The Globe and Mail Inc."}',
   '{}', 'active'),
  ('22000000-0000-4000-8000-000000000072', 'DER SPIEGEL', 'DE', 'de',
   '{"newsroom_url":"https://gruppe.spiegel.de/verantwortung-und-nachhaltigkeit-in-der-spiegel-gruppe/verantwortung-fuer-unsere-demokratische-gesellschaft","editorial_policy_url":"https://cdn.prod.www.spiegel.de/media/cd89f133-34e3-49e0-a7bc-0f5cc6cab8d9/Spiegel_Standards_Juli2021.pdf","corrections_policy_url":"https://cdn.prod.www.spiegel.de/media/cd89f133-34e3-49e0-a7bc-0f5cc6cab8d9/Spiegel_Standards_Juli2021.pdf","legal_entity":"SPIEGEL-Verlag Rudolf Augstein GmbH & Co. KG"}',
   '{}', 'active')
ON CONFLICT (id) DO NOTHING;

-- Histórico público
INSERT INTO outlet_changes (outlet_id, action, reason, actor_id, created_at)
SELECT o.id, 'included',
       'Atende aos 4 critérios; inclusão no lote 2 do cadastro (2026-10-28). Evidências nas URLs de criteria.',
       (SELECT id FROM journalists WHERE email = 'staff@jcf.example' LIMIT 1),
       now()
FROM outlets o
WHERE o.id IN (
  '22000000-0000-4000-8000-000000000040',
  '22000000-0000-4000-8000-000000000041',
  '22000000-0000-4000-8000-000000000042',
  '22000000-0000-4000-8000-000000000043',
  '22000000-0000-4000-8000-000000000044',
  '22000000-0000-4000-8000-000000000045',
  '22000000-0000-4000-8000-000000000046',
  '22000000-0000-4000-8000-000000000050',
  '22000000-0000-4000-8000-000000000060',
  '22000000-0000-4000-8000-000000000061',
  '22000000-0000-4000-8000-000000000062',
  '22000000-0000-4000-8000-000000000063',
  '22000000-0000-4000-8000-000000000064',
  '22000000-0000-4000-8000-000000000065',
  '22000000-0000-4000-8000-000000000066',
  '22000000-0000-4000-8000-000000000067',
  '22000000-0000-4000-8000-000000000068',
  '22000000-0000-4000-8000-000000000069',
  '22000000-0000-4000-8000-000000000070',
  '22000000-0000-4000-8000-000000000071',
  '22000000-0000-4000-8000-000000000072'
)
AND NOT EXISTS (
  SELECT 1 FROM outlet_changes c WHERE c.outlet_id = o.id AND c.action = 'included'
);

INSERT INTO outlet_domains (id, outlet_id, domain, opinion_path_patterns) VALUES
  ('22100000-0000-4000-8000-000000000040', '22000000-0000-4000-8000-000000000040', 'uol.com.br', '{/colunas/,/opiniao/,/blog/}'),
  ('22100000-0000-4000-8000-000000000041', '22000000-0000-4000-8000-000000000040', 'noticias.uol.com.br', '{/colunas/,/opiniao/}'),
  ('22100000-0000-4000-8000-000000000042', '22000000-0000-4000-8000-000000000041', 'nexojornal.com.br', '{/coluna/,/opiniao/}'),
  ('22100000-0000-4000-8000-000000000043', '22000000-0000-4000-8000-000000000042', 'cnnbrasil.com.br', '{/opiniao/,/colunas/}'),
  ('22100000-0000-4000-8000-000000000044', '22000000-0000-4000-8000-000000000043', 'poder360.com.br', '{/opiniao/}'),
  ('22100000-0000-4000-8000-000000000045', '22000000-0000-4000-8000-000000000044', 'opovo.com.br', '{/opiniao/,/colunas/}'),
  ('22100000-0000-4000-8000-000000000046', '22000000-0000-4000-8000-000000000045', 'gazetadopovo.com.br', '{/opiniao/,/colunas/,/vozes/}'),
  ('22100000-0000-4000-8000-000000000047', '22000000-0000-4000-8000-000000000046', 'gauchazh.clicrbs.com.br', '{/colunistas/,/opiniao/}'),
  ('22100000-0000-4000-8000-000000000048', '22000000-0000-4000-8000-000000000046', 'clicrbs.com.br', '{/colunistas/,/opiniao/}'),
  ('22100000-0000-4000-8000-000000000050', '22000000-0000-4000-8000-000000000050', 'publico.pt', '{/espaco-publico/,/editorial/}'),
  ('22100000-0000-4000-8000-000000000060', '22000000-0000-4000-8000-000000000060', 'cnn.com', '{/opinions/,/opinion/}'),
  ('22100000-0000-4000-8000-000000000061', '22000000-0000-4000-8000-000000000060', 'edition.cnn.com', '{/opinions/,/opinion/}'),
  ('22100000-0000-4000-8000-000000000062', '22000000-0000-4000-8000-000000000061', 'wsj.com', '{/opinion/,/articles/opinion}'),
  ('22100000-0000-4000-8000-000000000063', '22000000-0000-4000-8000-000000000062', 'bloomberg.com', '{/opinion/}'),
  ('22100000-0000-4000-8000-000000000064', '22000000-0000-4000-8000-000000000063', 'propublica.org', '{}'),
  ('22100000-0000-4000-8000-000000000065', '22000000-0000-4000-8000-000000000064', 'usatoday.com', '{/opinion/}'),
  ('22100000-0000-4000-8000-000000000066', '22000000-0000-4000-8000-000000000065', 'cbsnews.com', '{/opinion/}'),
  ('22100000-0000-4000-8000-000000000067', '22000000-0000-4000-8000-000000000066', 'time.com', '{/ideas/,/vault/}'),
  ('22100000-0000-4000-8000-000000000068', '22000000-0000-4000-8000-000000000067', 'aljazeera.com', '{/opinions/}'),
  ('22100000-0000-4000-8000-000000000069', '22000000-0000-4000-8000-000000000068', 'economist.com', '{/the-world-this-week/,/letters/}'),
  ('22100000-0000-4000-8000-000000000070', '22000000-0000-4000-8000-000000000069', 'cbc.ca', '{/opinion/}'),
  ('22100000-0000-4000-8000-000000000071', '22000000-0000-4000-8000-000000000070', 'abc.net.au', '{/news/opinion/}'),
  ('22100000-0000-4000-8000-000000000072', '22000000-0000-4000-8000-000000000071', 'theglobeandmail.com', '{/opinion/}'),
  ('22100000-0000-4000-8000-000000000073', '22000000-0000-4000-8000-000000000072', 'spiegel.de', '{/meinung/,/debatte/}')
ON CONFLICT (domain) DO NOTHING;

COMMIT;

SELECT count(*) AS outlets_cadastrados FROM outlets WHERE id::text LIKE '22000000%';
SELECT o.country, o.name,
       (SELECT string_agg(d.domain::text, ', ' ORDER BY d.domain) FROM outlet_domains d WHERE d.outlet_id = o.id) AS domains
FROM outlets o
WHERE o.id::text LIKE '22000000%'
ORDER BY o.country, o.name;
