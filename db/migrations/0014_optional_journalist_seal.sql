-- Selo de jornalista verificado passa a ser opcional.
-- Contas ativas (pending_verification ou verified) publicam e avaliam;
-- suspensas, banidas ou encerradas continuam bloqueadas.
-- A invariante dura continua sendo: 1–3 fontes reportagem de veículo ativo.

CREATE OR REPLACE FUNCTION enforce_publication_rules() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  n_total   integer;
  n_report  integer;
  n_active  integer;
  v_article uuid;
  a_status  journalist_status;
BEGIN
  IF NEW.status <> 'published' THEN
    RETURN NEW;
  END IF;

  SELECT status INTO a_status FROM journalists WHERE id = NEW.author_id;
  IF a_status IS NULL OR a_status NOT IN ('pending_verification', 'verified') THEN
    RAISE EXCEPTION 'publication_requires_active_author: author % has status %', NEW.author_id, a_status
      USING ERRCODE = 'P0001';
  END IF;

  SELECT article_id INTO v_article FROM article_versions WHERE id = NEW.current_version_id;
  IF v_article IS DISTINCT FROM NEW.id THEN
    RAISE EXCEPTION 'publication_version_mismatch: version % does not belong to article %', NEW.current_version_id, NEW.id
      USING ERRCODE = 'P0001';
  END IF;

  SELECT
    count(*),
    count(*) FILTER (WHERE s.classification = 'report'),
    count(*) FILTER (WHERE o.status = 'active')
  INTO n_total, n_report, n_active
  FROM article_sources s
  JOIN outlet_domains d ON d.id = s.outlet_domain_id
  JOIN outlets o ON o.id = d.outlet_id
  WHERE s.version_id = NEW.current_version_id;

  IF n_total < 1 OR n_total > 3 THEN
    RAISE EXCEPTION 'publication_requires_1_to_3_sources: version % has % sources', NEW.current_version_id, n_total
      USING ERRCODE = 'P0001';
  END IF;
  IF n_report <> n_total THEN
    RAISE EXCEPTION 'publication_requires_report_sources: % of % sources are not classified as report', n_total - n_report, n_total
      USING ERRCODE = 'P0001';
  END IF;
  IF n_active <> n_total THEN
    RAISE EXCEPTION 'publication_requires_active_outlets: % of % sources cite inactive outlets', n_total - n_active, n_total
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION enforce_reading_gate() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  g reading_gates%ROWTYPE;
  j_status journalist_status;
  a_author uuid;
  a_status article_status;
BEGIN
  SELECT * INTO g FROM reading_gates WHERE id = NEW.gate_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'gate_not_found: %', NEW.gate_id USING ERRCODE = 'P0001';
  END IF;
  IF g.journalist_id <> NEW.journalist_id OR g.article_id <> NEW.article_id THEN
    RAISE EXCEPTION 'gate_mismatch: gate % does not belong to journalist %/article %', NEW.gate_id, NEW.journalist_id, NEW.article_id
      USING ERRCODE = 'P0001';
  END IF;
  IF g.quiz_passed_at IS NULL THEN
    RAISE EXCEPTION 'gate_not_passed: journalist % has not passed the reading quiz for article %', NEW.journalist_id, NEW.article_id
      USING ERRCODE = 'P0001';
  END IF;

  SELECT status INTO j_status FROM journalists WHERE id = NEW.journalist_id;
  IF j_status IS NULL OR j_status NOT IN ('pending_verification', 'verified') THEN
    RAISE EXCEPTION 'evaluator_not_active: journalist % has status %', NEW.journalist_id, j_status
      USING ERRCODE = 'P0001';
  END IF;

  SELECT author_id, status INTO a_author, a_status FROM articles WHERE id = NEW.article_id;
  IF a_author = NEW.journalist_id THEN
    RAISE EXCEPTION 'self_evaluation_forbidden: author cannot evaluate own article %', NEW.article_id
      USING ERRCODE = 'P0001';
  END IF;
  IF a_status <> 'published' THEN
    RAISE EXCEPTION 'article_not_published: cannot evaluate article % with status %', NEW.article_id, a_status
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END $$;
