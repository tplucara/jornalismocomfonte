-- Seed de desenvolvimento. Re-executável: limpa tudo e recria.
-- Uso: docker exec jcf-db sh -c 'psql -q -U jcf -d jcf -v ON_ERROR_STOP=1 -f /seeds/dev_seed.sql'
--
-- Veículos, domínios e URLs usam o TLD reservado .example (RFC 2606): nada aqui afirma
-- algo sobre veículos reais. Senha de todos os jornalistas: jcf-dev-123
--
-- IDs determinísticos por prefixo:
--   1… jornalistas   2… veículos   21… domínios   3… artigos   31… versões   32… fontes
--   4… gates         41… votos     42… comentários   5… notificações / processos

\set ON_ERROR_STOP on
BEGIN;

SET LOCAL app.actor_id = '10000000-0000-4000-8000-000000000009';   -- staff
SET LOCAL app.session_hash = 'seed';
SET LOCAL app.ip_hash = 'seed';

TRUNCATE
  appeals, counter_notices, takedown_notices, right_of_reply_requests, distortion_reports,
  reputation_snapshots, reviewer_daily_credits,
  comments, fidelity_votes, quiz_attempts, quiz_questions, reading_gates,
  article_sources, article_versions, articles,
  outlet_changes, outlet_domains, outlets,
  verifications, legal_acceptances, journalists,
  audit_log, access_logs
RESTART IDENTITY CASCADE;

-- ---------------------------------------------------------------------------
-- Jornalistas
-- ---------------------------------------------------------------------------
INSERT INTO journalists (id, email, password_hash, display_name, avatar_url, tagline, status) VALUES
  ('10000000-0000-4000-8000-000000000001', 'ana.ribeiro@jcf.example',    crypt('jcf-dev-123', gen_salt('bf', 10)), 'Ana Ribeiro',     '/static/avatars/ana.svg',    'Economia explicada sem jargão',                 'verified'),
  ('10000000-0000-4000-8000-000000000002', 'bruno.castro@jcf.example',   crypt('jcf-dev-123', gen_salt('bf', 10)), 'Bruno Castro',    '/static/avatars/bruno.svg',  'Política é sobre quem paga a conta',            'verified'),
  ('10000000-0000-4000-8000-000000000003', 'carla.mendes@jcf.example',   crypt('jcf-dev-123', gen_salt('bf', 10)), 'Carla Mendes',    '/static/avatars/carla.svg',  'Ciência e clima, com fonte',                    'verified'),
  ('10000000-0000-4000-8000-000000000004', 'diego.alves@jcf.example',    crypt('jcf-dev-123', gen_salt('bf', 10)), 'Diego Alves',     '/static/avatars/diego.svg',  'Cidades, transporte e o cotidiano',             'verified'),
  ('10000000-0000-4000-8000-000000000005', 'elisa.moura@jcf.example',    crypt('jcf-dev-123', gen_salt('bf', 10)), 'Elisa Moura',     '/static/avatars/elisa.svg',  'Cultura e mídia',                               'verified'),
  ('10000000-0000-4000-8000-000000000006', 'fabio.nunes@jcf.example',    crypt('jcf-dev-123', gen_salt('bf', 10)), 'Fábio Nunes',     NULL,                                 'Conta ativa; selo de jornalista opcional',       'pending_verification'),
  -- Gustavo começa verified para que seus votos/comentários rejeitados existam; é suspenso ao final do seed.
  ('10000000-0000-4000-8000-000000000007', 'gustavo.lima@jcf.example',   crypt('jcf-dev-123', gen_salt('bf', 10)), 'Gustavo Lima',    '/static/avatars/gustavo.svg',        'Suspenso por manipulação de votos',             'verified'),
  ('10000000-0000-4000-8000-000000000009', 'staff@jcf.example',          crypt('jcf-dev-123', gen_salt('bf', 10)), 'Equipe JCF',      NULL,                                 'Revisão humana e governança do cadastro de veículos', 'verified');

INSERT INTO legal_acceptances (journalist_id, document, version, adult_declaration, session_hash)
SELECT id, d, '1.0', true, 'seed'
FROM journalists, unnest(ARRAY['terms','privacy','content_policy']::legal_document[]) AS d;

INSERT INTO verifications (journalist_id, method, document_hash, evidence_meta, status, reviewer_id, decision_reason, decided_at, raw_purged_at) VALUES
  ('10000000-0000-4000-8000-000000000001', 'professional_registry', encode(digest('mtb-sp-0001','sha256'),'hex'), '{"registry":"MTb","uf":"SP"}', 'approved', '10000000-0000-4000-8000-000000000009', 'Registro MTb confere', now() - interval '40 days', now() - interval '40 days'),
  ('10000000-0000-4000-8000-000000000002', 'outlet_affiliation',    encode(digest('vinculo-bruno','sha256'),'hex'), '{"outlet":"Gazeta do Planalto"}', 'approved', '10000000-0000-4000-8000-000000000009', 'Expediente do veículo lista o nome', now() - interval '38 days', now() - interval '38 days'),
  ('10000000-0000-4000-8000-000000000003', 'portfolio',             encode(digest('portfolio-carla','sha256'),'hex'), '{"links":3}', 'approved', '10000000-0000-4000-8000-000000000009', '3 reportagens em veículos da lista', now() - interval '35 days', now() - interval '35 days'),
  ('10000000-0000-4000-8000-000000000004', 'professional_registry', encode(digest('mtb-rj-0442','sha256'),'hex'), '{"registry":"MTb","uf":"RJ"}', 'approved', '10000000-0000-4000-8000-000000000009', 'Registro MTb confere', now() - interval '30 days', now() - interval '30 days'),
  ('10000000-0000-4000-8000-000000000005', 'portfolio',             encode(digest('portfolio-elisa','sha256'),'hex'), '{"links":5}', 'approved', '10000000-0000-4000-8000-000000000009', '5 reportagens em veículos da lista', now() - interval '28 days', now() - interval '28 days'),
  ('10000000-0000-4000-8000-000000000007', 'professional_registry', encode(digest('mtb-mg-0910','sha256'),'hex'), '{"registry":"MTb","uf":"MG"}', 'approved', '10000000-0000-4000-8000-000000000009', 'Registro confere', now() - interval '25 days', now() - interval '25 days'),
  ('10000000-0000-4000-8000-000000000009', 'outlet_affiliation',    encode(digest('staff','sha256'),'hex'), '{}', 'approved', '10000000-0000-4000-8000-000000000001', 'Equipe fundadora', now() - interval '60 days', now() - interval '60 days'),
  ('10000000-0000-4000-8000-000000000006', 'portfolio',             encode(digest('portfolio-fabio','sha256'),'hex'), '{"links":1}', 'pending', NULL, NULL, NULL, NULL);

-- ---------------------------------------------------------------------------
-- Cadastro de veículos
-- ---------------------------------------------------------------------------
INSERT INTO outlets (id, name, country, language, criteria, signals, status) VALUES
  ('20000000-0000-4000-8000-000000000001', 'Gazeta do Planalto', 'BR', 'pt-BR',
   '{"newsroom_url":"https://gazetadoplanalto.example/expediente","editorial_policy_url":"https://gazetadoplanalto.example/principios","corrections_policy_url":"https://gazetadoplanalto.example/erramos","legal_entity":"Gazeta do Planalto Comunicação S.A."}',
   '{"trust_project": true}', 'active'),
  ('20000000-0000-4000-8000-000000000002', 'Diário do Litoral', 'BR', 'pt-BR',
   '{"newsroom_url":"https://diariodolitoral.example/quem-somos","editorial_policy_url":"https://diariodolitoral.example/politica-editorial","corrections_policy_url":"https://diariodolitoral.example/correcoes","legal_entity":"Litoral Editora Ltda."}',
   '{}', 'active'),
  ('20000000-0000-4000-8000-000000000003', 'Agência Fato', 'BR', 'pt-BR',
   '{"newsroom_url":"https://agenciafato.example/equipe","editorial_policy_url":"https://agenciafato.example/metodo","corrections_policy_url":"https://agenciafato.example/correcoes","legal_entity":"Associação Agência Fato"}',
   '{"ifcn": true}', 'active'),
  ('20000000-0000-4000-8000-000000000004', 'O Correio de Lisboa', 'PT', 'pt-PT',
   '{"newsroom_url":"https://correiodelisboa.example/ficha-tecnica","editorial_policy_url":"https://correiodelisboa.example/estatuto-editorial","corrections_policy_url":"https://correiodelisboa.example/provedor","legal_entity":"Correio de Lisboa, S.A."}',
   '{}', 'active'),
  ('20000000-0000-4000-8000-000000000005', 'El Austral', 'AR', 'es',
   '{"newsroom_url":"https://elaustral.example/staff","editorial_policy_url":"https://elaustral.example/manual-de-estilo","corrections_policy_url":"https://elaustral.example/fe-de-erratas","legal_entity":"Editorial Austral S.R.L."}',
   '{}', 'active'),
  ('20000000-0000-4000-8000-000000000006', 'The Northern Ledger', 'GB', 'en',
   '{"newsroom_url":"https://northernledger.example/about/staff","editorial_policy_url":"https://northernledger.example/about/editorial-code","corrections_policy_url":"https://northernledger.example/about/corrections","legal_entity":"Northern Ledger Media Ltd"}',
   '{"trust_project": true, "jti": true}', 'active'),
  ('20000000-0000-4000-8000-000000000007', 'Le Quotidien du Rhône', 'FR', 'fr',
   '{"newsroom_url":"https://quotidiendurhone.example/redaction","editorial_policy_url":"https://quotidiendurhone.example/charte","corrections_policy_url":"https://quotidiendurhone.example/rectificatifs","legal_entity":"SAS Quotidien du Rhône"}',
   '{}', 'active'),
  ('20000000-0000-4000-8000-000000000008', 'Dainik Samachar', 'IN', 'hi',
   '{"newsroom_url":"https://dainiksamachar.example/team","editorial_policy_url":"https://dainiksamachar.example/editorial-policy","corrections_policy_url":"https://dainiksamachar.example/corrections","legal_entity":"Samachar Prakashan Pvt Ltd"}',
   '{}', 'active'),
  ('20000000-0000-4000-8000-000000000009', 'Portal Veloz', 'BR', 'pt-BR',
   '{"newsroom_url":"https://portalveloz.example/sobre","editorial_policy_url":"https://portalveloz.example/editorial","corrections_policy_url":"https://portalveloz.example/correcoes","legal_entity":"Veloz Mídia Digital ME"}',
   '{}', 'suspended');

INSERT INTO outlet_changes (outlet_id, action, reason, actor_id, created_at) VALUES
  ('20000000-0000-4000-8000-000000000001', 'included', 'Atende aos 4 critérios; política de correções pública desde 2019', '10000000-0000-4000-8000-000000000009', now() - interval '60 days'),
  ('20000000-0000-4000-8000-000000000002', 'included', 'Atende aos 4 critérios; veículo regional com redação identificada', '10000000-0000-4000-8000-000000000009', now() - interval '59 days'),
  ('20000000-0000-4000-8000-000000000003', 'included', 'Atende aos 4 critérios; signatária IFCN', '10000000-0000-4000-8000-000000000009', now() - interval '58 days'),
  ('20000000-0000-4000-8000-000000000004', 'included', 'Atende aos 4 critérios; estatuto editorial publicado', '10000000-0000-4000-8000-000000000009', now() - interval '50 days'),
  ('20000000-0000-4000-8000-000000000005', 'included', 'Atende aos 4 critérios', '10000000-0000-4000-8000-000000000009', now() - interval '45 days'),
  ('20000000-0000-4000-8000-000000000006', 'included', 'Atende aos 4 critérios; Trust Project e JTI', '10000000-0000-4000-8000-000000000009', now() - interval '44 days'),
  ('20000000-0000-4000-8000-000000000007', 'included', 'Atende aos 4 critérios', '10000000-0000-4000-8000-000000000009', now() - interval '40 days'),
  ('20000000-0000-4000-8000-000000000008', 'included', 'Atende aos 4 critérios; pedido feito por jornalista da plataforma', '10000000-0000-4000-8000-000000000009', now() - interval '20 days'),
  ('20000000-0000-4000-8000-000000000009', 'included', 'Atendia aos 4 critérios na inclusão', '10000000-0000-4000-8000-000000000009', now() - interval '30 days'),
  ('20000000-0000-4000-8000-000000000009', 'suspended', 'Página de política de correções removida do site; padrão de manchetes sem lastro em 3 casos documentados', '10000000-0000-4000-8000-000000000009', now() - interval '5 days');

INSERT INTO outlet_domains (id, outlet_id, domain, opinion_path_patterns) VALUES
  ('21000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'gazetadoplanalto.example', '{/opiniao/,/colunas/,/editorial/}'),
  ('21000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002', 'diariodolitoral.example',  '{/opiniao/,/colunistas/}'),
  ('21000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000003', 'agenciafato.example',      '{}'),
  ('21000000-0000-4000-8000-000000000004', '20000000-0000-4000-8000-000000000004', 'correiodelisboa.example',  '{/opiniao/,/cronicas/}'),
  ('21000000-0000-4000-8000-000000000005', '20000000-0000-4000-8000-000000000005', 'elaustral.example',        '{/opinion/,/columnistas/}'),
  ('21000000-0000-4000-8000-000000000006', '20000000-0000-4000-8000-000000000006', 'northernledger.example',   '{/opinion/,/comment/,/editorial/}'),
  ('21000000-0000-4000-8000-000000000007', '20000000-0000-4000-8000-000000000007', 'quotidiendurhone.example', '{/opinion/,/tribunes/,/editorial/}'),
  ('21000000-0000-4000-8000-000000000008', '20000000-0000-4000-8000-000000000008', 'dainiksamachar.example',   '{/opinion/,/vichar/}'),
  ('21000000-0000-4000-8000-000000000009', '20000000-0000-4000-8000-000000000009', 'portalveloz.example',      '{/opiniao/}');

-- ---------------------------------------------------------------------------
-- Helpers temporários
-- ---------------------------------------------------------------------------
CREATE FUNCTION pg_temp.src(
  p_version uuid, p_pos int, p_url text, p_domain uuid, p_title text, p_excerpt text, p_days_ago int
) RETURNS void LANGUAGE sql AS $$
  INSERT INTO article_sources (id, version_id, position, url, outlet_domain_id, classification, classification_method,
                               classification_reason, content_hash, meta, excerpt, archive_url, hash_status, hash_compared_at)
  VALUES (gen_random_uuid(), p_version, p_pos, p_url, p_domain, 'report', 'path_pattern',
          'path não corresponde a padrão de opinião do veículo',
          encode(digest(p_url || p_title, 'sha256'), 'hex'),
          jsonb_build_object('title', p_title, 'published_at', (now() - make_interval(days => p_days_ago))::date),
          p_excerpt, 'https://web.archive.org/web/2026/' || p_url, 'ok', now() - interval '1 day');
$$;

CREATE FUNCTION pg_temp.publish(p_article uuid, p_version uuid, p_days_ago int) RETURNS void LANGUAGE sql AS $$
  UPDATE articles SET status = 'published', published_at = now() - make_interval(days => p_days_ago), current_version_id = p_version
  WHERE id = p_article;
$$;

CREATE FUNCTION pg_temp.gate(p_journalist uuid, p_article uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE g uuid := gen_random_uuid(); s uuid;
BEGIN
  SELECT s2.id INTO s FROM article_sources s2 JOIN articles a ON a.current_version_id = s2.version_id
  WHERE a.id = p_article ORDER BY s2.position LIMIT 1;
  INSERT INTO reading_gates (id, journalist_id, article_id, source_id, opened_at, quiz_passed_at, attempts)
  VALUES (g, p_journalist, p_article, s, now() - interval '2 hours', now() - interval '110 minutes', 1);
  INSERT INTO quiz_attempts (gate_id, question_ids, correct)
  SELECT g, ARRAY(SELECT id FROM quiz_questions WHERE source_id = s AND active LIMIT 2), 2;
  RETURN g;
END $$;

CREATE FUNCTION pg_temp.vote(p_journalist uuid, p_article uuid, p_verdict fidelity_verdict, p_note text,
                             p_filter filter_status, p_reason text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE g uuid; v uuid := gen_random_uuid();
BEGIN
  SELECT id INTO g FROM reading_gates WHERE journalist_id = p_journalist AND article_id = p_article;
  IF g IS NULL THEN g := pg_temp.gate(p_journalist, p_article); END IF;
  INSERT INTO fidelity_votes (id, article_id, journalist_id, gate_id, verdict, note) VALUES (v, p_article, p_journalist, g, p_verdict, p_note);
  IF p_filter <> 'pending' THEN
    UPDATE fidelity_votes SET filter_status = p_filter, filter_reason = p_reason, filter_model = 'seed-filter-v0', filtered_at = now() - interval '90 minutes'
    WHERE id = v;
  END IF;
END $$;

CREATE FUNCTION pg_temp.comment(p_journalist uuid, p_article uuid, p_stance comment_stance, p_body text,
                                p_filter filter_status, p_reason text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE g uuid; c uuid := gen_random_uuid();
BEGIN
  SELECT id INTO g FROM reading_gates WHERE journalist_id = p_journalist AND article_id = p_article;
  IF g IS NULL THEN g := pg_temp.gate(p_journalist, p_article); END IF;
  INSERT INTO comments (id, article_id, journalist_id, gate_id, stance, body) VALUES (c, p_article, p_journalist, g, p_stance, p_body);
  IF p_filter <> 'pending' THEN
    UPDATE comments SET filter_status = p_filter, filter_reason = p_reason, filter_model = 'seed-filter-v0', filtered_at = now() - interval '80 minutes'
    WHERE id = c;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Artigos
-- ---------------------------------------------------------------------------

-- A1 (Ana, análise, 3 fontes) — o mais avaliado
INSERT INTO articles (id, author_id, kind) VALUES ('30000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'analysis');
INSERT INTO article_versions (id, article_id, version_no, title, body, created_by) VALUES
  ('31000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 1,
   'Por que a inflação de alimentos caiu mais rápido que o previsto',
   '{"blocks":[{"type":"p","text":"Três fatores explicam a queda de 2,1 pontos no índice de alimentos no último trimestre: safra recorde de grãos, câmbio estável e redução do frete rodoviário."},{"type":"p","text":"A Gazeta do Planalto reportou a safra de 318 milhões de toneladas, 6% acima do ciclo anterior. O Diário do Litoral apurou a queda de 11% no frete entre os portos de Santos e Paranaguá."},{"type":"p","text":"Minha leitura: o efeito do frete é subestimado nas projeções oficiais e deve sustentar a desaceleração por mais um trimestre."}]}',
   '10000000-0000-4000-8000-000000000001');
SELECT pg_temp.src('31000000-0000-4000-8000-000000000001', 1, 'https://gazetadoplanalto.example/economia/safra-recorde-318-milhoes', '21000000-0000-4000-8000-000000000001', 'Safra de grãos atinge 318 milhões de toneladas', 'A produção nacional de grãos alcançou 318 milhões de toneladas no ciclo 2025/26, alta de 6% sobre o anterior, segundo levantamento divulgado nesta terça.', 12);
SELECT pg_temp.src('31000000-0000-4000-8000-000000000001', 2, 'https://diariodolitoral.example/portos/frete-cai-11-por-cento', '21000000-0000-4000-8000-000000000002', 'Frete rodoviário entre Santos e Paranaguá cai 11%', 'O custo médio do frete entre os dois maiores portos do Sul e Sudeste recuou 11% em doze meses, apurou a reportagem junto a transportadoras.', 10);
SELECT pg_temp.src('31000000-0000-4000-8000-000000000001', 3, 'https://agenciafato.example/checagem/indice-alimentos-trimestre', '21000000-0000-4000-8000-000000000003', 'Índice de alimentos recua 2,1 pontos no trimestre', 'O subíndice de alimentação no domicílio caiu 2,1 pontos percentuais no trimestre encerrado em setembro.', 9);
SELECT pg_temp.publish('30000000-0000-4000-8000-000000000001', '31000000-0000-4000-8000-000000000001', 8);

-- A2 (Bruno, reportagem, 2 fontes) — terá correção (v2)
INSERT INTO articles (id, author_id, kind) VALUES ('30000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', 'report');
INSERT INTO article_versions (id, article_id, version_no, title, body, created_by) VALUES
  ('31000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000002', 1,
   'Câmara aprova novo marco das concessões rodoviárias',
   '{"blocks":[{"type":"p","text":"O plenário aprovou por 312 votos a 140 o texto-base do novo marco das concessões rodoviárias, que muda o cálculo de reajuste de pedágio."},{"type":"p","text":"O texto segue para o Senado. A relatoria estima R$ 48 bilhões em novos investimentos em dez anos."}]}',
   '10000000-0000-4000-8000-000000000002');
SELECT pg_temp.src('31000000-0000-4000-8000-000000000002', 1, 'https://gazetadoplanalto.example/politica/camara-aprova-marco-concessoes', '21000000-0000-4000-8000-000000000001', 'Câmara aprova marco das concessões por 312 a 140', 'O texto-base foi aprovado por 312 votos favoráveis e 140 contrários; destaques serão votados na próxima semana.', 7);
SELECT pg_temp.src('31000000-0000-4000-8000-000000000002', 2, 'https://diariodolitoral.example/economia/concessoes-48-bilhoes', '21000000-0000-4000-8000-000000000002', 'Relator projeta R$ 48 bi em investimentos', 'Segundo o relator, o novo marco pode atrair R$ 48 bilhões em investimentos privados em uma década.', 7);
SELECT pg_temp.publish('30000000-0000-4000-8000-000000000002', '31000000-0000-4000-8000-000000000002', 6);
-- correção: versão 2
INSERT INTO article_versions (id, article_id, version_no, title, body, change_note, created_by) VALUES
  ('31000000-0000-4000-8000-000000000022', '30000000-0000-4000-8000-000000000002', 2,
   'Câmara aprova novo marco das concessões rodoviárias',
   '{"blocks":[{"type":"p","text":"O plenário aprovou por 312 votos a 140 o texto-base do novo marco das concessões rodoviárias, que muda o cálculo de reajuste de pedágio."},{"type":"p","text":"O texto segue para o Senado. A relatoria estima R$ 48 bilhões em novos investimentos em dez anos, segundo nota técnica da consultoria legislativa."}]}',
   'Corrigida a atribuição da estimativa de R$ 48 bi: é da consultoria legislativa, não do relator, como mostra a fonte 2.',
   '10000000-0000-4000-8000-000000000002');
SELECT pg_temp.src('31000000-0000-4000-8000-000000000022', 1, 'https://gazetadoplanalto.example/politica/camara-aprova-marco-concessoes', '21000000-0000-4000-8000-000000000001', 'Câmara aprova marco das concessões por 312 a 140', 'O texto-base foi aprovado por 312 votos favoráveis e 140 contrários; destaques serão votados na próxima semana.', 7);
SELECT pg_temp.src('31000000-0000-4000-8000-000000000022', 2, 'https://diariodolitoral.example/economia/concessoes-48-bilhoes', '21000000-0000-4000-8000-000000000002', 'Consultoria projeta R$ 48 bi em investimentos', 'Nota técnica da consultoria legislativa projeta R$ 48 bilhões em investimentos privados em uma década.', 7);
UPDATE articles SET current_version_id = '31000000-0000-4000-8000-000000000022' WHERE id = '30000000-0000-4000-8000-000000000002';

-- A3 (Carla, reportagem, 2 fontes internacionais)
INSERT INTO articles (id, author_id, kind) VALUES ('30000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000003', 'report');
INSERT INTO article_versions (id, article_id, version_no, title, body, created_by) VALUES
  ('31000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000003', 1,
   'Estudo europeu liga onda de calor de 2025 a 40 mil mortes adicionais',
   '{"blocks":[{"type":"p","text":"Pesquisadores de 12 países estimaram em 40 mil o excesso de mortes atribuível às ondas de calor do verão europeu de 2025."},{"type":"p","text":"A metodologia compara a mortalidade observada com a esperada para o período, controlando por idade e região."}]}',
   '10000000-0000-4000-8000-000000000003');
SELECT pg_temp.src('31000000-0000-4000-8000-000000000003', 1, 'https://northernledger.example/science/heatwave-excess-deaths-2025', '21000000-0000-4000-8000-000000000006', 'Heatwaves linked to 40,000 excess deaths across Europe', 'A multi-country study estimates 40,000 excess deaths attributable to the summer 2025 heatwaves, using age- and region-adjusted baselines.', 15);
SELECT pg_temp.src('31000000-0000-4000-8000-000000000003', 2, 'https://quotidiendurhone.example/sciences/canicule-2025-surmortalite', '21000000-0000-4000-8000-000000000007', 'Canicule 2025 : une surmortalité estimée à 40 000 décès', 'L étude, menée dans douze pays, attribue 40 000 décès supplémentaires aux vagues de chaleur de l été 2025.', 14);
SELECT pg_temp.publish('30000000-0000-4000-8000-000000000003', '31000000-0000-4000-8000-000000000003', 13);

-- A4 (Diego, opinião, 1 fonte)
INSERT INTO articles (id, author_id, kind) VALUES ('30000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000004', 'opinion');
INSERT INTO article_versions (id, article_id, version_no, title, body, created_by) VALUES
  ('31000000-0000-4000-8000-000000000004', '30000000-0000-4000-8000-000000000004', 1,
   'A tarifa zero no ônibus é cara, mas o congestionamento é mais',
   '{"blocks":[{"type":"p","text":"A cidade que zerou a tarifa viu a demanda crescer 23% em um ano, segundo levantamento publicado pelo Diário do Litoral."},{"type":"p","text":"Defendo que o custo fiscal, embora alto, é menor que o custo difuso de horas perdidas no trânsito. É uma posição, não um dado."}]}',
   '10000000-0000-4000-8000-000000000004');
SELECT pg_temp.src('31000000-0000-4000-8000-000000000004', 1, 'https://diariodolitoral.example/cidades/tarifa-zero-demanda-cresce-23', '21000000-0000-4000-8000-000000000002', 'Tarifa zero: demanda por ônibus cresce 23% em um ano', 'Um ano após zerar a tarifa, o município registrou alta de 23% no número de passageiros transportados, segundo dados da secretaria de mobilidade.', 20);
SELECT pg_temp.publish('30000000-0000-4000-8000-000000000004', '31000000-0000-4000-8000-000000000004', 18);

-- A5 (Elisa, análise, 2 fontes) — receberá denúncia de distorção procedente
INSERT INTO articles (id, author_id, kind) VALUES ('30000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000005', 'analysis');
INSERT INTO article_versions (id, article_id, version_no, title, body, created_by) VALUES
  ('31000000-0000-4000-8000-000000000005', '30000000-0000-4000-8000-000000000005', 1,
   'Streaming já responde por metade da receita da música no país',
   '{"blocks":[{"type":"p","text":"O streaming ultrapassou 50% da receita da indústria fonográfica nacional, segundo balanço anual."},{"type":"p","text":"Isso significa que shows perderam relevância na renda dos artistas."}]}',
   '10000000-0000-4000-8000-000000000005');
SELECT pg_temp.src('31000000-0000-4000-8000-000000000005', 1, 'https://gazetadoplanalto.example/cultura/streaming-metade-receita-musica', '21000000-0000-4000-8000-000000000001', 'Streaming chega a 52% da receita fonográfica', 'O streaming respondeu por 52% da receita da indústria fonográfica em 2025, segundo o balanço anual da entidade do setor. O dado não inclui receita de shows.', 11);
SELECT pg_temp.src('31000000-0000-4000-8000-000000000005', 2, 'https://correiodelisboa.example/cultura/streaming-portugal-2025', '21000000-0000-4000-8000-000000000004', 'Streaming domina receita da música em Portugal', 'Em Portugal, o streaming representou 61% da receita da indústria fonográfica em 2025.', 11);
SELECT pg_temp.publish('30000000-0000-4000-8000-000000000005', '31000000-0000-4000-8000-000000000005', 10);

-- A6 (Ana, reportagem, 1 fonte) — recente, sem avaliações ainda
INSERT INTO articles (id, author_id, kind) VALUES ('30000000-0000-4000-8000-000000000006', '10000000-0000-4000-8000-000000000001', 'report');
INSERT INTO article_versions (id, article_id, version_no, title, body, created_by) VALUES
  ('31000000-0000-4000-8000-000000000006', '30000000-0000-4000-8000-000000000006', 1,
   'Banco central argentino mantém taxa e sinaliza pausa',
   '{"blocks":[{"type":"p","text":"A autoridade monetária argentina manteve a taxa básica em 29% e indicou pausa no ciclo de cortes até a divulgação da inflação de outubro."}]}',
   '10000000-0000-4000-8000-000000000001');
SELECT pg_temp.src('31000000-0000-4000-8000-000000000006', 1, 'https://elaustral.example/economia/bcra-mantiene-tasa-29', '21000000-0000-4000-8000-000000000005', 'El BCRA mantiene la tasa en 29% y señala pausa', 'El Banco Central mantuvo la tasa de política monetaria en 29% y anticipó una pausa hasta conocer la inflación de octubre.', 1);
SELECT pg_temp.publish('30000000-0000-4000-8000-000000000006', '31000000-0000-4000-8000-000000000006', 0);

-- A7 (Carla, reportagem, 1 fonte) — será removido por notificação válida
INSERT INTO articles (id, author_id, kind) VALUES ('30000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000003', 'report');
INSERT INTO article_versions (id, article_id, version_no, title, body, created_by) VALUES
  ('31000000-0000-4000-8000-000000000007', '30000000-0000-4000-8000-000000000007', 1,
   'Nova vacina contra dengue chega à rede pública em março',
   '{"blocks":[{"type":"p","text":"Texto removido após notificação por violação de direito autoral em imagem anexa."}]}',
   '10000000-0000-4000-8000-000000000003');
SELECT pg_temp.src('31000000-0000-4000-8000-000000000007', 1, 'https://agenciafato.example/saude/vacina-dengue-rede-publica-marco', '21000000-0000-4000-8000-000000000003', 'Vacina contra dengue chega ao SUS em março', 'A nova vacina contra dengue começa a ser aplicada na rede pública em março, inicialmente para a faixa de 10 a 14 anos.', 25);
SELECT pg_temp.publish('30000000-0000-4000-8000-000000000007', '31000000-0000-4000-8000-000000000007', 24);

-- A8 (Bruno, rascunho) — não publicado, sem fontes ainda
INSERT INTO articles (id, author_id, kind) VALUES ('30000000-0000-4000-8000-000000000008', '10000000-0000-4000-8000-000000000002', 'analysis');
INSERT INTO article_versions (id, article_id, version_no, title, body, created_by) VALUES
  ('31000000-0000-4000-8000-000000000008', '30000000-0000-4000-8000-000000000008', 1,
   'Rascunho: o que muda com o novo marco no Senado',
   '{"blocks":[{"type":"p","text":"Em elaboração."}]}',
   '10000000-0000-4000-8000-000000000002');

-- A9 (Diego, reportagem, 2 fontes) — avaliações mistas
INSERT INTO articles (id, author_id, kind) VALUES ('30000000-0000-4000-8000-000000000009', '10000000-0000-4000-8000-000000000004', 'report');
INSERT INTO article_versions (id, article_id, version_no, title, body, created_by) VALUES
  ('31000000-0000-4000-8000-000000000009', '30000000-0000-4000-8000-000000000009', 1,
   'Metrô de Lisboa amplia horário noturno em caráter experimental',
   '{"blocks":[{"type":"p","text":"O metrô de Lisboa passa a operar até as 2h nas sextas e sábados por seis meses, em teste anunciado pela operadora."},{"type":"p","text":"A medida atende a pedido antigo do setor de hotelaria e restauração."}]}',
   '10000000-0000-4000-8000-000000000004');
SELECT pg_temp.src('31000000-0000-4000-8000-000000000009', 1, 'https://correiodelisboa.example/lisboa/metro-horario-noturno-teste', '21000000-0000-4000-8000-000000000004', 'Metro de Lisboa alarga horário até às 2h em teste de seis meses', 'O Metropolitano de Lisboa vai operar até às 2h às sextas e sábados durante seis meses, anunciou a empresa.', 5);
SELECT pg_temp.src('31000000-0000-4000-8000-000000000009', 2, 'https://dainiksamachar.example/world/lisbon-metro-night-service', '21000000-0000-4000-8000-000000000008', 'Lisbon metro extends night service in six-month trial', 'Lisbon metro will run until 2 a.m. on Fridays and Saturdays for six months, the operator said.', 5);
SELECT pg_temp.publish('30000000-0000-4000-8000-000000000009', '31000000-0000-4000-8000-000000000009', 4);

-- ---------------------------------------------------------------------------
-- Perguntas do quiz (2 por fonte, geradas "por IA")
-- ---------------------------------------------------------------------------
INSERT INTO quiz_questions (source_id, prompt, options, answer_hash, generator_model)
SELECT s.id,
       'Segundo a fonte, qual é o dado central da reportagem?',
       jsonb_build_array(left(s.excerpt, 60) || '…', 'Um dado diferente do citado', 'A fonte não traz números', 'O oposto do que o artigo afirma'),
       encode(digest('0' || s.id::text, 'sha256'), 'hex'),
       'seed-quizgen-v0'
FROM article_sources s;

INSERT INTO quiz_questions (source_id, prompt, options, answer_hash, generator_model)
SELECT s.id,
       'A reportagem foi publicada por qual veículo?',
       jsonb_build_array(o.name, 'Portal Veloz', 'Blog pessoal', 'Rede social'),
       encode(digest('0' || s.id::text, 'sha256'), 'hex'),
       'seed-quizgen-v0'
FROM article_sources s JOIN outlet_domains d ON d.id = s.outlet_domain_id JOIN outlets o ON o.id = d.outlet_id;

-- ---------------------------------------------------------------------------
-- Votos e comentários
-- ---------------------------------------------------------------------------
-- A1: amplamente avaliado como fiel; um voto hater rejeitado
SELECT pg_temp.vote('10000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001', 'faithful', 'Os três números batem com as fontes', 'valid', 'Voto referencia dados específicos das fontes');
SELECT pg_temp.vote('10000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000001', 'faithful', NULL, 'valid', 'Sem indícios de padrão pró/contra autor');
SELECT pg_temp.vote('10000000-0000-4000-8000-000000000004', '30000000-0000-4000-8000-000000000001', 'faithful', 'Frete de 11% confere na fonte 2', 'valid', 'Voto referencia dados específicos das fontes');
SELECT pg_temp.vote('10000000-0000-4000-8000-000000000005', '30000000-0000-4000-8000-000000000001', 'distorts', 'A conclusão sobre o frete é só opinião', 'valid', 'Divergência fundamentada sobre inferência do autor; voto aceito');
SELECT pg_temp.vote('10000000-0000-4000-8000-000000000007', '30000000-0000-4000-8000-000000000001', 'distorts', 'essa aí sempre inventa número', 'rejected', 'Voto ataca a autora e não referencia conteúdo ou fonte');
SELECT pg_temp.comment('10000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001', 'agree', 'Concordo com a leitura do frete. A fonte 2 mostra queda de 11%, consistente com o argumento.', 'valid', 'Comentário referencia a fonte');
SELECT pg_temp.comment('10000000-0000-4000-8000-000000000005', '30000000-0000-4000-8000-000000000001', 'partially_agree', 'Concordo parcialmente: os dados estão corretos, mas a projeção de mais um trimestre não tem lastro nas fontes citadas.', 'valid', 'Comentário distingue dado de inferência');
SELECT pg_temp.comment('10000000-0000-4000-8000-000000000007', '30000000-0000-4000-8000-000000000001', 'disagree', 'ridículo, como sempre', 'rejected', 'Comentário sem referência ao conteúdo; linguagem de ataque');

-- A2 (corrigido): votos antes e depois da correção
SELECT pg_temp.vote('10000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000002', 'distorts', 'A fonte 2 atribui a estimativa à consultoria, não ao relator', 'valid', 'Voto aponta divergência específica com a fonte');
SELECT pg_temp.vote('10000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000002', 'faithful', 'Após a correção, confere', 'valid', 'Sem indícios de padrão');
SELECT pg_temp.vote('10000000-0000-4000-8000-000000000004', '30000000-0000-4000-8000-000000000002', 'faithful', NULL, 'valid', 'Sem indícios de padrão');
SELECT pg_temp.comment('10000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000002', 'agree', 'Concordo com a correção publicada; a atribuição agora reflete a fonte 2.', 'valid', 'Comentário referencia a fonte');

-- A3: unanimidade
SELECT pg_temp.vote('10000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000003', 'faithful', NULL, 'valid', 'Sem indícios de padrão');
SELECT pg_temp.vote('10000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000003', 'faithful', 'Número e metodologia conferem nas duas fontes', 'valid', 'Voto referencia dados específicos');
SELECT pg_temp.vote('10000000-0000-4000-8000-000000000005', '30000000-0000-4000-8000-000000000003', 'faithful', NULL, 'valid', 'Sem indícios de padrão');

-- A4 (opinião): leitores discordam da opinião mas reconhecem fidelidade
SELECT pg_temp.vote('10000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000004', 'faithful', 'O dado de 23% está na fonte; o resto é opinião declarada', 'valid', 'Voto distingue dado de opinião');
SELECT pg_temp.vote('10000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000004', 'faithful', NULL, 'valid', 'Sem indícios de padrão');
SELECT pg_temp.comment('10000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000004', 'disagree', 'Discordo da conclusão: o custo fiscal recai sobre quem não usa o sistema. Mas o artigo é honesto ao marcar isso como posição.', 'valid', 'Discordância fundamentada');
SELECT pg_temp.comment('10000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000004', 'partially_agree', 'Concordo parcialmente. Faltou uma fonte sobre o custo das horas perdidas para sustentar a comparação.', 'valid', 'Comentário aponta lacuna de fonte');

-- A5: distorção apontada
SELECT pg_temp.vote('10000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000005', 'distorts', 'A fonte diz que o dado exclui shows; o artigo conclui o oposto', 'valid', 'Voto aponta divergência específica com a fonte');
SELECT pg_temp.vote('10000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000005', 'distorts', 'Conclusão sobre shows não está em nenhuma das fontes', 'valid', 'Voto aponta divergência específica com a fonte');
SELECT pg_temp.vote('10000000-0000-4000-8000-000000000004', '30000000-0000-4000-8000-000000000005', 'faithful', NULL, 'valid', 'Sem indícios de padrão');
SELECT pg_temp.vote('10000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000005', 'distorts', NULL, 'pending', NULL);

-- A9: misto, com um pendente
SELECT pg_temp.vote('10000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000009', 'faithful', NULL, 'valid', 'Sem indícios de padrão');
SELECT pg_temp.vote('10000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000009', 'faithful', 'Horário e duração conferem', 'valid', 'Voto referencia dados específicos');
SELECT pg_temp.vote('10000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000009', 'distorts', 'O pedido da hotelaria não aparece nas fontes', 'pending', NULL);

-- 006 e 009 saem no mesmo dia. 009 foi ao ar mais cedo e já tem avaliações válidas,
-- então aparece antes de 006. Os links de 009 quebram depois: o lugar permanece.
UPDATE articles SET published_at =
  date_trunc('day', now() AT TIME ZONE 'America/Sao_Paulo') AT TIME ZONE 'America/Sao_Paulo'
WHERE id = '30000000-0000-4000-8000-000000000009';
UPDATE articles SET published_at =
  (date_trunc('day', now() AT TIME ZONE 'America/Sao_Paulo') AT TIME ZONE 'America/Sao_Paulo') + interval '6 hours'
WHERE id = '30000000-0000-4000-8000-000000000006';
UPDATE article_sources
SET hash_status = 'unavailable', hash_compared_at = now()
WHERE version_id = '31000000-0000-4000-8000-000000000009';

-- ---------------------------------------------------------------------------
-- Integridade editorial e processos legais
-- ---------------------------------------------------------------------------
-- Denúncia de distorção procedente em A5
INSERT INTO distortion_reports (article_id, version_id, source_id, reporter_id, excerpt, argument, status, reviewer_id, decision_reason, created_at, decided_at)
SELECT '30000000-0000-4000-8000-000000000005', '31000000-0000-4000-8000-000000000005', s.id, '10000000-0000-4000-8000-000000000001',
       'Isso significa que shows perderam relevância na renda dos artistas.',
       'A fonte 1 afirma explicitamente que o dado de 52% não inclui receita de shows. A conclusão não é sustentada.',
       'upheld', '10000000-0000-4000-8000-000000000009',
       'Procedente: a fonte exclui shows do cálculo; a afirmação do artigo não decorre da fonte citada. Autor notificado para correção.',
       now() - interval '6 days', now() - interval '4 days'
FROM article_sources s WHERE s.version_id = '31000000-0000-4000-8000-000000000005' AND s.position = 1;

-- Denúncia aberta em A9
INSERT INTO distortion_reports (article_id, version_id, source_id, reporter_id, excerpt, argument, status, created_at)
SELECT '30000000-0000-4000-8000-000000000009', '31000000-0000-4000-8000-000000000009', s.id, '10000000-0000-4000-8000-000000000002',
       'A medida atende a pedido antigo do setor de hotelaria e restauração.',
       'Nenhuma das duas fontes menciona pedido do setor de hotelaria.',
       'open', now() - interval '1 day'
FROM article_sources s WHERE s.version_id = '31000000-0000-4000-8000-000000000009' AND s.position = 1;

-- Direito de resposta publicado em A4
INSERT INTO right_of_reply_requests (article_id, version_id, requester_pii, requester_hash, excerpt, reply_text, status, reviewer_id, created_at, decided_at, published_at) VALUES
  ('30000000-0000-4000-8000-000000000004', '31000000-0000-4000-8000-000000000004',
   pgp_sym_encrypt('{"name":"Secretaria Municipal de Mobilidade","doc":"00.000.000/0001-00","email":"imprensa@mobilidade.example"}', 'dev-only-key'),
   encode(digest('secretaria-mobilidade', 'sha256'), 'hex'),
   'o custo fiscal, embora alto',
   'A Secretaria esclarece que o custo da tarifa zero representa 3,1% do orçamento municipal e foi integralmente coberto pela redução de subsídios anteriores às concessionárias.',
   'published', '10000000-0000-4000-8000-000000000009', now() - interval '15 days', now() - interval '13 days', now() - interval '13 days');

-- Notificação válida e remoção de A7
INSERT INTO takedown_notices (id, protocol, category, article_id, url, grounds, notifier_pii, notifier_hash, good_faith, urgent, status, reviewer_id, decision, received_at, decided_at) VALUES
  ('50000000-0000-4000-8000-000000000001', 'JCF-2026-000001', 'evident_illicit', '30000000-0000-4000-8000-000000000007',
   'https://jornalismocomfonte.example/a/30000000-0000-4000-8000-000000000007',
   'Imagem anexa ao artigo é de titularidade do notificante, sem licença. Comprovação de registro anexada.',
   pgp_sym_encrypt('{"name":"Fotógrafo Exemplo","doc":"000.000.000-00","email":"foto@exemplo.example"}', 'dev-only-key'),
   encode(digest('fotografo-exemplo', 'sha256'), 'hex'), true, false,
   'removed', '10000000-0000-4000-8000-000000000009',
   'Titularidade comprovada por registro. Autora não apresentou licença. Conteúdo removido; autora notificada e orientada sobre contranotificação.',
   now() - interval '9 days', now() - interval '6 days');

UPDATE articles SET status = 'removed', removed_at = now() - interval '6 days', removal_reason = 'valid_notice', removal_ref = 'JCF-2026-000001'
WHERE id = '30000000-0000-4000-8000-000000000007';

INSERT INTO counter_notices (notice_id, author_id, argument, status, created_at) VALUES
  ('50000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000003',
   'A imagem foi obtida sob licença CC BY 4.0 no repositório da agência; anexo o link e a atribuição original.', 'open', now() - interval '2 days');

-- Notificação de honra redirecionada para direito de resposta (não removida)
INSERT INTO takedown_notices (protocol, category, article_id, url, grounds, notifier_pii, notifier_hash, good_faith, status, reviewer_id, decision, received_at, decided_at) VALUES
  ('JCF-2026-000002', 'evident_illicit', '30000000-0000-4000-8000-000000000002',
   'https://jornalismocomfonte.example/a/30000000-0000-4000-8000-000000000002',
   'O artigo me difama ao sugerir que inflei a estimativa de investimentos.',
   pgp_sym_encrypt('{"name":"Parlamentar Exemplo","doc":"000.000.000-00","email":"gabinete@exemplo.example"}', 'dev-only-key'),
   encode(digest('parlamentar-exemplo', 'sha256'), 'hex'), true,
   'redirected_to_reply', '10000000-0000-4000-8000-000000000009',
   'Alegação de crime contra a honra: remoção só por ordem judicial (Marco Civil, art. 19). Notificante orientado ao caminho judicial e ao direito de resposta. Autor já publicou correção da atribuição.',
   now() - interval '5 days', now() - interval '3 days');

-- Apelação aberta do voto rejeitado de Gustavo em A1
INSERT INTO appeals (subject_type, subject_id, journalist_id, argument, status, created_at)
SELECT 'vote', v.id, '10000000-0000-4000-8000-000000000007', 'Eu li a fonte, só me expressei mal.', 'open', now() - interval '1 day'
FROM fidelity_votes v WHERE v.journalist_id = '10000000-0000-4000-8000-000000000007' AND v.article_id = '30000000-0000-4000-8000-000000000001';

-- Suspensão de Gustavo após padrão de votos/comentários rejeitados (processo interno, Termos cláusula 8)
UPDATE journalists SET status = 'suspended' WHERE id = '10000000-0000-4000-8000-000000000007';

-- ---------------------------------------------------------------------------
-- Reputação (snapshots calculados "pelo job")
-- ---------------------------------------------------------------------------
INSERT INTO reputation_snapshots (journalist_id, author, reviewer, algorithm) VALUES
  ('10000000-0000-4000-8000-000000000001', '{"score":0.82,"ci_low":0.61,"ci_high":0.93,"n_valid":7,"insufficient":false}',  '{"score":0.91,"ci_low":0.72,"ci_high":0.98,"n_valid":6,"insufficient":false}', 'seed-v0'),
  ('10000000-0000-4000-8000-000000000002', '{"score":0.67,"ci_low":0.30,"ci_high":0.90,"n_valid":3,"insufficient":false}',  '{"score":0.88,"ci_low":0.65,"ci_high":0.97,"n_valid":6,"insufficient":false}', 'seed-v0'),
  ('10000000-0000-4000-8000-000000000003', '{"score":1.00,"ci_low":0.44,"ci_high":1.00,"n_valid":3,"insufficient":false}',  '{"score":0.85,"ci_low":0.55,"ci_high":0.97,"n_valid":4,"insufficient":false}', 'seed-v0'),
  ('10000000-0000-4000-8000-000000000004', '{"score":0.80,"ci_low":0.38,"ci_high":0.96,"n_valid":4,"insufficient":false}',  '{"score":0.80,"ci_low":0.38,"ci_high":0.96,"n_valid":3,"insufficient":false}', 'seed-v0'),
  ('10000000-0000-4000-8000-000000000005', '{"score":0.33,"ci_low":0.06,"ci_high":0.79,"n_valid":3,"insufficient":false}',  '{"score":0.90,"ci_low":0.60,"ci_high":0.98,"n_valid":3,"insufficient":false}', 'seed-v0'),
  ('10000000-0000-4000-8000-000000000006', '{"n_valid":0,"insufficient":true}', '{"n_valid":0,"insufficient":true}', 'seed-v0'),
  ('10000000-0000-4000-8000-000000000007', '{"n_valid":0,"insufficient":true}', '{"score":0.00,"ci_low":0.00,"ci_high":0.60,"n_valid":2,"insufficient":false}', 'seed-v0'),
  ('10000000-0000-4000-8000-000000000009', '{"n_valid":0,"insufficient":true}', '{"n_valid":0,"insufficient":true}', 'seed-v0');

COMMIT;

-- Resumo
SELECT 'journalists' AS tabela, count(*) FROM journalists
UNION ALL SELECT 'outlets', count(*) FROM outlets
UNION ALL SELECT 'articles (published)', count(*) FROM articles WHERE status = 'published'
UNION ALL SELECT 'articles (removed)', count(*) FROM articles WHERE status = 'removed'
UNION ALL SELECT 'articles (draft)', count(*) FROM articles WHERE status = 'draft'
UNION ALL SELECT 'article_versions', count(*) FROM article_versions
UNION ALL SELECT 'article_sources', count(*) FROM article_sources
UNION ALL SELECT 'quiz_questions', count(*) FROM quiz_questions
UNION ALL SELECT 'fidelity_votes (valid)', count(*) FROM fidelity_votes WHERE filter_status = 'valid'
UNION ALL SELECT 'fidelity_votes (rejected)', count(*) FROM fidelity_votes WHERE filter_status = 'rejected'
UNION ALL SELECT 'fidelity_votes (pending)', count(*) FROM fidelity_votes WHERE filter_status = 'pending'
UNION ALL SELECT 'comments', count(*) FROM comments
UNION ALL SELECT 'distortion_reports', count(*) FROM distortion_reports
UNION ALL SELECT 'takedown_notices', count(*) FROM takedown_notices
UNION ALL SELECT 'audit_log', count(*) FROM audit_log;
