-- Testes de invariantes do schema. Roda inteiro em uma transação e termina com ROLLBACK.
-- Uso: psql -v ON_ERROR_STOP=1 -f db/tests/invariants.sql
-- Cada expect_fail tenta violar uma regra e exige erro; cada expect_ok exige sucesso.

\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.expect_fail(label text, sql text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    SET CONSTRAINTS ALL DEFERRED;
    EXECUTE sql;
    SET CONSTRAINTS ALL IMMEDIATE;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS (rejeitado)  % -> %', label, left(SQLERRM, 90);
    RETURN;
  END;
  RAISE EXCEPTION 'TEST FAILED: "%" deveria ter sido rejeitado mas passou', label;
END $$;

CREATE FUNCTION pg_temp.expect_ok(label text, sql text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  SET CONSTRAINTS ALL DEFERRED;
  EXECUTE sql;
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PASS (aceito)     %', label;
END $$;

-- ---------------------------------------------------------------------------
-- Seed mínimo
-- ---------------------------------------------------------------------------
SELECT pg_temp.expect_ok('seed: jornalistas', $q$
  INSERT INTO journalists (id, email, password_hash, display_name, status) VALUES
    ('00000000-0000-0000-0000-000000000001', 'autor@jcf.test',    'x', 'Autor',    'verified'),
    ('00000000-0000-0000-0000-000000000002', 'revisor@jcf.test',  'x', 'Revisor',  'verified'),
    ('00000000-0000-0000-0000-000000000003', 'pendente@jcf.test', 'x', 'Pendente', 'pending_verification'),
    ('00000000-0000-0000-0000-000000000004', 'staff@jcf.test',    'x', 'Staff',    'verified');
$q$);

SELECT pg_temp.expect_ok('seed: cadastro de veículos (ativo + suspenso)', $q$
  INSERT INTO outlets (id, name, country, language, criteria, status) VALUES
    ('00000000-0000-0000-0000-000000000010', 'Diário Exemplo', 'BR', 'pt-BR',
     '{"newsroom_url":"https://exemplo.com.br/expediente","editorial_policy_url":"https://exemplo.com.br/politica","corrections_policy_url":"https://exemplo.com.br/correcoes","legal_entity":"Exemplo S.A."}', 'active'),
    ('00000000-0000-0000-0000-000000000020', 'Jornal Suspenso', 'AR', 'es',
     '{"newsroom_url":"https://suspenso.com/x","editorial_policy_url":"https://suspenso.com/y","corrections_policy_url":"https://suspenso.com/z","legal_entity":"Suspenso SRL"}', 'suspended');
  INSERT INTO outlet_changes (outlet_id, action, reason, actor_id) VALUES
    ('00000000-0000-0000-0000-000000000010', 'included',  'Atende aos 4 critérios', '00000000-0000-0000-0000-000000000004'),
    ('00000000-0000-0000-0000-000000000020', 'suspended', 'Política de correções removida do site', '00000000-0000-0000-0000-000000000004');
  INSERT INTO outlet_domains (id, outlet_id, domain, opinion_path_patterns) VALUES
    ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000010', 'exemplo.com.br', '{/opiniao/,/colunas/}'),
    ('00000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000020', 'suspenso.com', '{}');
$q$);

-- ---------------------------------------------------------------------------
-- perfil-identidade.mdc
-- ---------------------------------------------------------------------------
SELECT pg_temp.expect_fail('aceite legal sem declaração de maioridade', $q$
  INSERT INTO legal_acceptances (journalist_id, document, version, adult_declaration, session_hash)
  VALUES ('00000000-0000-0000-0000-000000000003', 'terms', '1.0', false, 'h');
$q$);

SELECT pg_temp.expect_ok('aceite legal válido', $q$
  INSERT INTO legal_acceptances (journalist_id, document, version, adult_declaration, session_hash)
  VALUES ('00000000-0000-0000-0000-000000000003', 'terms', '1.0', true, 'h');
$q$);

SELECT pg_temp.expect_fail('append-only: UPDATE em legal_acceptances', $q$
  UPDATE legal_acceptances SET version = '9.9';
$q$);

SELECT pg_temp.expect_fail('append-only: DELETE em legal_acceptances', $q$
  DELETE FROM legal_acceptances;
$q$);

SELECT pg_temp.expect_ok('verificação aprovada promove jornalista', $q$
  INSERT INTO verifications (journalist_id, method, document_hash, status, reviewer_id, decision_reason, decided_at)
  VALUES ('00000000-0000-0000-0000-000000000003', 'professional_registry', 'DOC-HASH-1', 'approved',
          '00000000-0000-0000-0000-000000000004', 'Registro confere', now());
  DO $d$ BEGIN
    IF (SELECT status FROM journalists WHERE id = '00000000-0000-0000-0000-000000000003') <> 'verified' THEN
      RAISE EXCEPTION 'jornalista não foi promovido a verified';
    END IF;
  END $d$;
$q$);

SELECT pg_temp.expect_fail('1 pessoa = 1 conta: mesmo documento aprovado duas vezes', $q$
  INSERT INTO journalists (id, email, password_hash, display_name) VALUES
    ('00000000-0000-0000-0000-000000000005', 'clone@jcf.test', 'x', 'Clone');
  INSERT INTO verifications (journalist_id, method, document_hash, status, reviewer_id, decision_reason, decided_at)
  VALUES ('00000000-0000-0000-0000-000000000005', 'professional_registry', 'DOC-HASH-1', 'approved',
          '00000000-0000-0000-0000-000000000004', 'ok', now());
$q$);

SELECT pg_temp.expect_fail('verificação: revisor não pode ser o próprio jornalista', $q$
  INSERT INTO verifications (journalist_id, method, document_hash, status, reviewer_id, decision_reason, decided_at)
  VALUES ('00000000-0000-0000-0000-000000000001', 'portfolio', 'DOC-HASH-2', 'approved',
          '00000000-0000-0000-0000-000000000001', 'eu mesmo', now());
$q$);

SELECT pg_temp.expect_fail('verificação decidida sem motivo', $q$
  INSERT INTO verifications (journalist_id, method, document_hash, status, reviewer_id, decided_at)
  VALUES ('00000000-0000-0000-0000-000000000001', 'portfolio', 'DOC-HASH-3', 'rejected',
          '00000000-0000-0000-0000-000000000004', now());
$q$);

SELECT pg_temp.expect_fail('e-mail duplicado (case-insensitive)', $q$
  INSERT INTO journalists (email, password_hash, display_name) VALUES ('AUTOR@JCF.TEST', 'x', 'Dup');
$q$);

-- Sem PII extra: nenhuma coluna de localização, nascimento, telefone, etc.
DO $$
DECLARE bad text;
BEGIN
  SELECT string_agg(column_name, ', ') INTO bad
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'journalists'
    AND column_name ~* '(phone|telefone|birth|nascimento|address|endereco|city|cidade|location|localiza|cpf|rg|gender|genero|employer|empregador|instagram|twitter|linkedin)';
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'TEST FAILED: journalists tem colunas de PII proibidas: %', bad;
  END IF;
  RAISE NOTICE 'PASS (schema)     journalists sem colunas de PII além do mínimo';
END $$;

-- ---------------------------------------------------------------------------
-- cadastro-de-veiculos.mdc
-- ---------------------------------------------------------------------------
SELECT pg_temp.expect_fail('outlet sem política de correções', $q$
  INSERT INTO outlets (id, name, country, language, criteria) VALUES
    ('00000000-0000-0000-0000-000000000030', 'Sem Correções', 'US', 'en',
     '{"newsroom_url":"https://x.com/a","editorial_policy_url":"https://x.com/b","legal_entity":"X Inc"}');
  INSERT INTO outlet_changes (outlet_id, action, reason) VALUES ('00000000-0000-0000-0000-000000000030', 'included', 'r');
$q$);

SELECT pg_temp.expect_fail('outlet incluído sem entrada no histórico público', $q$
  INSERT INTO outlets (id, name, country, language, criteria) VALUES
    ('00000000-0000-0000-0000-000000000031', 'Sem Histórico', 'FR', 'fr',
     '{"newsroom_url":"https://x.fr/a","editorial_policy_url":"https://x.fr/b","corrections_policy_url":"https://x.fr/c","legal_entity":"X SAS"}');
$q$);

SELECT pg_temp.expect_fail('append-only: UPDATE em outlet_changes', $q$
  UPDATE outlet_changes SET reason = 'alterado';
$q$);

SELECT pg_temp.expect_fail('domínio de veículo duplicado', $q$
  INSERT INTO outlet_domains (outlet_id, domain) VALUES ('00000000-0000-0000-0000-000000000020', 'EXEMPLO.COM.BR');
$q$);

-- ---------------------------------------------------------------------------
-- fonte-validada.mdc + integridade-editorial.mdc
-- ---------------------------------------------------------------------------
SELECT pg_temp.expect_fail('artigo sem tag de tipo (kind NULL)', $q$
  INSERT INTO articles (author_id, kind) VALUES ('00000000-0000-0000-0000-000000000001', NULL);
$q$);

SELECT pg_temp.expect_ok('rascunho + versão 1', $q$
  INSERT INTO articles (id, author_id, kind) VALUES
    ('00000000-0000-0000-0000-000000000100', '00000000-0000-0000-0000-000000000001', 'analysis');
  INSERT INTO article_versions (id, article_id, version_no, title, body, created_by) VALUES
    ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000100', 1, 'Título', '{"blocks":[]}',
     '00000000-0000-0000-0000-000000000001');
$q$);

SELECT pg_temp.expect_fail('publicar com 0 fontes', $q$
  UPDATE articles SET status = 'published', published_at = now(),
    current_version_id = '00000000-0000-0000-0000-000000000101'
  WHERE id = '00000000-0000-0000-0000-000000000100';
$q$);

SELECT pg_temp.expect_fail('fonte com URL fora do domínio declarado', $q$
  INSERT INTO article_sources (version_id, position, url, outlet_domain_id, classification, classification_method, content_hash, excerpt)
  VALUES ('00000000-0000-0000-0000-000000000101', 1, 'https://outrosite.com/noticia', '00000000-0000-0000-0000-000000000011',
          'report', 'path_pattern', 'h', 'trecho');
$q$);

SELECT pg_temp.expect_fail('fonte com position 4', $q$
  INSERT INTO article_sources (version_id, position, url, outlet_domain_id, classification, classification_method, content_hash, excerpt)
  VALUES ('00000000-0000-0000-0000-000000000101', 4, 'https://exemplo.com.br/n4', '00000000-0000-0000-0000-000000000011',
          'report', 'path_pattern', 'h', 'trecho');
$q$);

SELECT pg_temp.expect_fail('fonte classificada sem método', $q$
  INSERT INTO article_sources (version_id, position, url, outlet_domain_id, classification, content_hash, excerpt)
  VALUES ('00000000-0000-0000-0000-000000000101', 1, 'https://exemplo.com.br/n1', '00000000-0000-0000-0000-000000000011',
          'report', 'h', 'trecho');
$q$);

SELECT pg_temp.expect_fail('publicar com fonte de opinião', $q$
  INSERT INTO article_sources (version_id, position, url, outlet_domain_id, classification, classification_method, classification_reason, content_hash, excerpt)
  VALUES ('00000000-0000-0000-0000-000000000101', 1, 'https://exemplo.com.br/opiniao/coluna', '00000000-0000-0000-0000-000000000011',
          'opinion', 'path_pattern', 'path /opiniao/', 'h', 'trecho');
  UPDATE articles SET status = 'published', published_at = now(),
    current_version_id = '00000000-0000-0000-0000-000000000101'
  WHERE id = '00000000-0000-0000-0000-000000000100';
$q$);

SELECT pg_temp.expect_fail('publicar com fonte de veículo suspenso', $q$
  INSERT INTO article_sources (version_id, position, url, outlet_domain_id, classification, classification_method, content_hash, excerpt)
  VALUES ('00000000-0000-0000-0000-000000000101', 1, 'https://suspenso.com/nota', '00000000-0000-0000-0000-000000000021',
          'report', 'path_pattern', 'h', 'trecho');
  UPDATE articles SET status = 'published', published_at = now(),
    current_version_id = '00000000-0000-0000-0000-000000000101'
  WHERE id = '00000000-0000-0000-0000-000000000100';
$q$);

SELECT pg_temp.expect_ok('publicar com 2 reportagens de veículos cadastrados', $q$
  INSERT INTO article_sources (id, version_id, position, url, outlet_domain_id, classification, classification_method, content_hash, excerpt, archive_url) VALUES
    ('00000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-000000000101', 1, 'https://exemplo.com.br/economia/n1',
     '00000000-0000-0000-0000-000000000011', 'report', 'path_pattern', 'sha256-a', 'trecho da reportagem 1', 'https://web.archive.org/x'),
    ('00000000-0000-0000-0000-000000000112', '00000000-0000-0000-0000-000000000101', 2, 'https://www.exemplo.com.br/politica/n2',
     '00000000-0000-0000-0000-000000000011', 'report', 'ai_model:test', 'sha256-b', 'trecho da reportagem 2', NULL);
  UPDATE articles SET status = 'published', published_at = now(),
    current_version_id = '00000000-0000-0000-0000-000000000101'
  WHERE id = '00000000-0000-0000-0000-000000000100';
$q$);

SELECT pg_temp.expect_fail('publicar por autor não verificado', $q$
  INSERT INTO journalists (id, email, password_hash, display_name, status) VALUES
    ('00000000-0000-0000-0000-000000000006', 'novato@jcf.test', 'x', 'Novato', 'pending_verification');
  INSERT INTO articles (id, author_id, kind) VALUES
    ('00000000-0000-0000-0000-000000000120', '00000000-0000-0000-0000-000000000006', 'report');
  INSERT INTO article_versions (id, article_id, version_no, title, body, created_by) VALUES
    ('00000000-0000-0000-0000-000000000121', '00000000-0000-0000-0000-000000000120', 1, 'T', '{}', '00000000-0000-0000-0000-000000000006');
  INSERT INTO article_sources (version_id, position, url, outlet_domain_id, classification, classification_method, content_hash, excerpt) VALUES
    ('00000000-0000-0000-0000-000000000121', 1, 'https://exemplo.com.br/n9', '00000000-0000-0000-0000-000000000011', 'report', 'path_pattern', 'h', 't');
  UPDATE articles SET status = 'published', published_at = now(), current_version_id = '00000000-0000-0000-0000-000000000121'
  WHERE id = '00000000-0000-0000-0000-000000000120';
$q$);

SELECT pg_temp.expect_fail('append-only: editar versão publicada in-place', $q$
  UPDATE article_versions SET title = 'Título alterado em silêncio' WHERE id = '00000000-0000-0000-0000-000000000101';
$q$);

SELECT pg_temp.expect_fail('versão 2 sem nota de correção', $q$
  INSERT INTO article_versions (article_id, version_no, title, body, created_by)
  VALUES ('00000000-0000-0000-0000-000000000100', 2, 'v2', '{}', '00000000-0000-0000-0000-000000000001');
$q$);

SELECT pg_temp.expect_ok('correção = versão 2 com nota e fontes', $q$
  INSERT INTO article_versions (id, article_id, version_no, title, body, change_note, created_by) VALUES
    ('00000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000100', 2, 'Título corrigido', '{}',
     'Corrigido valor citado no 3º parágrafo', '00000000-0000-0000-0000-000000000001');
  INSERT INTO article_sources (version_id, position, url, outlet_domain_id, classification, classification_method, content_hash, excerpt) VALUES
    ('00000000-0000-0000-0000-000000000102', 1, 'https://exemplo.com.br/economia/n1', '00000000-0000-0000-0000-000000000011',
     'report', 'path_pattern', 'sha256-a', 'trecho');
  UPDATE articles SET current_version_id = '00000000-0000-0000-0000-000000000102' WHERE id = '00000000-0000-0000-0000-000000000100';
$q$);

SELECT pg_temp.expect_fail('voltar versão corrente para a anterior', $q$
  UPDATE articles SET current_version_id = '00000000-0000-0000-0000-000000000101' WHERE id = '00000000-0000-0000-0000-000000000100';
$q$);

-- ---------------------------------------------------------------------------
-- avaliacao-fidelidade.mdc
-- ---------------------------------------------------------------------------
SELECT pg_temp.expect_ok('gate aberto (quiz ainda não passado)', $q$
  INSERT INTO reading_gates (id, journalist_id, article_id, source_id) VALUES
    ('00000000-0000-0000-0000-000000000200', '00000000-0000-0000-0000-000000000002',
     '00000000-0000-0000-0000-000000000100', '00000000-0000-0000-0000-000000000111');
$q$);

SELECT pg_temp.expect_fail('voto sem passar no quiz', $q$
  INSERT INTO fidelity_votes (article_id, journalist_id, gate_id, verdict) VALUES
    ('00000000-0000-0000-0000-000000000100', '00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000200', 'faithful');
$q$);

SELECT pg_temp.expect_fail('comentário sem passar no quiz', $q$
  INSERT INTO comments (article_id, journalist_id, gate_id, stance, body) VALUES
    ('00000000-0000-0000-0000-000000000100', '00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000200', 'agree', 'ok');
$q$);

SELECT pg_temp.expect_ok('quiz passado', $q$
  INSERT INTO quiz_attempts (gate_id, question_ids, correct) VALUES
    ('00000000-0000-0000-0000-000000000200', ARRAY[gen_random_uuid(), gen_random_uuid()], 2);
  UPDATE reading_gates SET quiz_passed_at = now(), attempts = 1 WHERE id = '00000000-0000-0000-0000-000000000200';
$q$);

SELECT pg_temp.expect_fail('comentário sem flag de posição', $q$
  INSERT INTO comments (article_id, journalist_id, gate_id, stance, body) VALUES
    ('00000000-0000-0000-0000-000000000100', '00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000200', NULL, 'texto');
$q$);

SELECT pg_temp.expect_ok('voto Fiel após gate', $q$
  INSERT INTO fidelity_votes (id, article_id, journalist_id, gate_id, verdict, note) VALUES
    ('00000000-0000-0000-0000-000000000300', '00000000-0000-0000-0000-000000000100', '00000000-0000-0000-0000-000000000002',
     '00000000-0000-0000-0000-000000000200', 'faithful', 'Dados batem com a fonte 1');
$q$);

SELECT pg_temp.expect_ok('comentário Discordo após gate', $q$
  INSERT INTO comments (article_id, journalist_id, gate_id, stance, body) VALUES
    ('00000000-0000-0000-0000-000000000100', '00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000200',
     'disagree', 'Discordo: a conclusão ignora o dado X da fonte 2');
$q$);

SELECT pg_temp.expect_fail('voto duplicado no mesmo artigo', $q$
  INSERT INTO fidelity_votes (article_id, journalist_id, gate_id, verdict) VALUES
    ('00000000-0000-0000-0000-000000000100', '00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000200', 'distorts');
$q$);

SELECT pg_temp.expect_fail('autor avaliando o próprio artigo', $q$
  INSERT INTO reading_gates (id, journalist_id, article_id, source_id, quiz_passed_at) VALUES
    ('00000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-000000000100', '00000000-0000-0000-0000-000000000111', now());
  INSERT INTO fidelity_votes (article_id, journalist_id, gate_id, verdict) VALUES
    ('00000000-0000-0000-0000-000000000100', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000201', 'faithful');
$q$);

SELECT pg_temp.expect_fail('gate de outro jornalista usado no voto', $q$
  INSERT INTO fidelity_votes (article_id, journalist_id, gate_id, verdict) VALUES
    ('00000000-0000-0000-0000-000000000100', '00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000200', 'faithful');
$q$);

SELECT pg_temp.expect_fail('voto rejeitado sem motivo legível', $q$
  UPDATE fidelity_votes SET filter_status = 'rejected', filtered_at = now() WHERE id = '00000000-0000-0000-0000-000000000300';
$q$);

SELECT pg_temp.expect_ok('voto validado pelo filtro alimenta créditos do avaliador', $q$
  UPDATE fidelity_votes SET filter_status = 'valid', filtered_at = now(), filter_model = 'test'
  WHERE id = '00000000-0000-0000-0000-000000000300';
  DO $d$ BEGIN
    IF (SELECT credited_count FROM reviewer_daily_credits WHERE journalist_id = '00000000-0000-0000-0000-000000000002') <> 1 THEN
      RAISE EXCEPTION 'reviewer_daily_credits não incrementou';
    END IF;
    IF (SELECT faithful_count FROM article_fidelity_summary WHERE article_id = '00000000-0000-0000-0000-000000000100') <> 1 THEN
      RAISE EXCEPTION 'article_fidelity_summary não reflete voto válido';
    END IF;
  END $d$;
$q$);

SELECT pg_temp.expect_ok('versão corrente ganha uma segunda fonte e a primeira sai do ar', $q$
  INSERT INTO article_sources (id, version_id, position, url, outlet_domain_id, classification, classification_method, content_hash, excerpt) VALUES
    ('00000000-0000-0000-0000-000000000113', '00000000-0000-0000-0000-000000000102', 2,
     'https://exemplo.com.br/economia/n2', '00000000-0000-0000-0000-000000000011',
     'report', 'path_pattern', 'sha256-c', 'trecho da reportagem corrente 2');
  UPDATE article_sources SET hash_status = 'unavailable'
  WHERE version_id = '00000000-0000-0000-0000-000000000102' AND position = 1;
$q$);

SELECT pg_temp.expect_fail('gate numa fonte indisponível', $q$
  INSERT INTO reading_gates (journalist_id, article_id, source_id, quiz_passed_at)
  SELECT '00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000100', id, now()
  FROM article_sources
  WHERE version_id = '00000000-0000-0000-0000-000000000102' AND position = 1;
$q$);

SELECT pg_temp.expect_ok('a fonte que segue no ar recebe avaliação', $q$
  INSERT INTO reading_gates (id, journalist_id, article_id, source_id, quiz_passed_at)
  SELECT '00000000-0000-0000-0000-000000000202', '00000000-0000-0000-0000-000000000004',
         '00000000-0000-0000-0000-000000000100', id, now()
  FROM article_sources
  WHERE version_id = '00000000-0000-0000-0000-000000000102' AND position = 2;
  INSERT INTO fidelity_votes (id, article_id, journalist_id, gate_id, verdict) VALUES
    ('00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000100',
     '00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000202', 'faithful');
  INSERT INTO journalists (id, email, password_hash, display_name, status) VALUES
    ('00000000-0000-0000-0000-000000000005', 'outra@jcf.test', 'x', 'Outra', 'verified');
  INSERT INTO reading_gates (id, journalist_id, article_id, source_id, quiz_passed_at)
  SELECT '00000000-0000-0000-0000-000000000203', '00000000-0000-0000-0000-000000000005',
         '00000000-0000-0000-0000-000000000100', id, now()
  FROM article_sources
  WHERE version_id = '00000000-0000-0000-0000-000000000102' AND position = 2;
$q$);

SELECT pg_temp.expect_ok('a última fonte também sai do ar', $q$
  UPDATE article_sources SET hash_status = 'unavailable'
  WHERE version_id = '00000000-0000-0000-0000-000000000102' AND position = 2;
$q$);

SELECT pg_temp.expect_fail('voto novo quando todas as fontes estão indisponíveis', $q$
  INSERT INTO fidelity_votes (article_id, journalist_id, gate_id, verdict) VALUES
    ('00000000-0000-0000-0000-000000000100', '00000000-0000-0000-0000-000000000005',
     '00000000-0000-0000-0000-000000000203', 'distorts');
$q$);

SELECT pg_temp.expect_ok('avaliações já feitas permanecem e o filtro ainda conclui a que estava em aberto', $q$
  UPDATE fidelity_votes SET filter_status = 'valid', filtered_at = now(), filter_model = 'test'
  WHERE id = '00000000-0000-0000-0000-000000000301';
  DO $d$ BEGIN
    IF (SELECT valid_count FROM article_fidelity_summary WHERE article_id = '00000000-0000-0000-0000-000000000100') <> 2 THEN
      RAISE EXCEPTION 'resumo perdeu avaliação já feita com as fontes fora do ar';
    END IF;
  END $d$;
  UPDATE article_sources SET hash_status = 'ok'
  WHERE version_id = '00000000-0000-0000-0000-000000000102';
$q$);

-- ---------------------------------------------------------------------------
-- reputacao-jornalista.mdc
-- ---------------------------------------------------------------------------
SELECT pg_temp.expect_fail('snapshot de reputação sem intervalo de confiança', $q$
  INSERT INTO reputation_snapshots (journalist_id, author, reviewer, algorithm) VALUES
    ('00000000-0000-0000-0000-000000000001', '{"score":0.9,"n_valid":50,"insufficient":false}',
     '{"n_valid":0,"insufficient":true}', 'v1');
$q$);

SELECT pg_temp.expect_ok('snapshot de reputação válido', $q$
  INSERT INTO reputation_snapshots (journalist_id, author, reviewer, algorithm) VALUES
    ('00000000-0000-0000-0000-000000000001', '{"score":0.87,"ci_low":0.80,"ci_high":0.92,"n_valid":54,"insufficient":false}',
     '{"n_valid":3,"insufficient":true}', 'v1');
$q$);

-- ---------------------------------------------------------------------------
-- responsabilidade-legal.mdc
-- ---------------------------------------------------------------------------
SELECT pg_temp.expect_fail('notificação sem declaração de boa-fé', $q$
  INSERT INTO takedown_notices (protocol, category, article_id, url, grounds, notifier_pii, notifier_hash, good_faith)
  VALUES ('P-001', 'evident_illicit', '00000000-0000-0000-0000-000000000100', 'https://jcf/a/1', 'x', '\x00', 'h', false);
$q$);

SELECT pg_temp.expect_fail('remover artigo com removal_ref inexistente', $q$
  UPDATE articles SET status = 'removed', removed_at = now(), removal_reason = 'valid_notice', removal_ref = 'P-NAO-EXISTE'
  WHERE id = '00000000-0000-0000-0000-000000000100';
$q$);

SELECT pg_temp.expect_ok('notificação válida decidida com remoção e rastro', $q$
  INSERT INTO takedown_notices (id, protocol, category, article_id, url, grounds, notifier_pii, notifier_hash, good_faith,
                                status, reviewer_id, decision, decided_at)
  VALUES ('00000000-0000-0000-0000-000000000400', 'P-002', 'evident_illicit', '00000000-0000-0000-0000-000000000100',
          'https://jcf/a/1', 'violação autoral com comprovação', pgp_sym_encrypt('{"name":"N"}', 'k'), 'h', true,
          'removed', '00000000-0000-0000-0000-000000000004', 'Titularidade comprovada; conteúdo removido', now());
  UPDATE articles SET status = 'removed', removed_at = now(), removal_reason = 'valid_notice', removal_ref = 'P-002'
  WHERE id = '00000000-0000-0000-0000-000000000100';
$q$);

SELECT pg_temp.expect_fail('contranotificação revisada pelo mesmo revisor da remoção', $q$
  INSERT INTO counter_notices (notice_id, author_id, argument, reviewer_id) VALUES
    ('00000000-0000-0000-0000-000000000400', '00000000-0000-0000-0000-000000000001', 'uso justo', '00000000-0000-0000-0000-000000000004');
$q$);

SELECT pg_temp.expect_ok('contranotificação com revisor diferente', $q$
  INSERT INTO counter_notices (notice_id, author_id, argument, reviewer_id) VALUES
    ('00000000-0000-0000-0000-000000000400', '00000000-0000-0000-0000-000000000001', 'uso justo', '00000000-0000-0000-0000-000000000002');
$q$);

SELECT pg_temp.expect_fail('apelação revisada pelo próprio apelante', $q$
  INSERT INTO appeals (subject_type, subject_id, journalist_id, argument, reviewer_id) VALUES
    ('vote', '00000000-0000-0000-0000-000000000300', '00000000-0000-0000-0000-000000000002', 'x', '00000000-0000-0000-0000-000000000002');
$q$);

SELECT pg_temp.expect_fail('append-only: UPDATE em audit_log', $q$
  UPDATE audit_log SET action = 'x' WHERE id = (SELECT min(id) FROM audit_log);
$q$);

SELECT pg_temp.expect_fail('append-only: DELETE em audit_log', $q$
  DELETE FROM audit_log WHERE id = (SELECT min(id) FROM audit_log);
$q$);

DO $$
DECLARE n bigint;
BEGIN
  SELECT count(*) INTO n FROM audit_log WHERE entity_type = 'articles' AND entity_id = '00000000-0000-0000-0000-000000000100';
  IF n < 3 THEN
    RAISE EXCEPTION 'TEST FAILED: esperado >= 3 eventos de auditoria para o artigo, encontrado %', n;
  END IF;
  RAISE NOTICE 'PASS (auditoria)  % eventos registrados para o artigo (insert, publish, nova versão, remoção)', n;
END $$;

-- Vocabulário: nenhuma coluna de conteúdo sugere que a plataforma certifica verdade.
DO $$
DECLARE bad text;
BEGIN
  SELECT string_agg(table_name || '.' || column_name, ', ') INTO bad
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name IN ('articles', 'article_versions', 'article_sources', 'fidelity_votes', 'reputation_snapshots')
    AND column_name ~* '(verified|truth|veracity|approved|fact_check|checked)';
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'TEST FAILED: vocabulário proibido em colunas de conteúdo: %', bad;
  END IF;
  RAISE NOTICE 'PASS (schema)     vocabulário: nenhuma coluna de conteúdo sugere certificação de verdade';
END $$;

ROLLBACK;
