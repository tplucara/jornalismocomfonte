-- 0013: ordem do início e fonte fora do ar (algoritmos-transparentes, avaliacao-fidelidade).
-- O dia de publicação em America/Sao_Paulo manda. Dentro do dia, mais avaliações
-- válidas vêm antes. Leitura anônima, comentário e voto rejeitado não entram.
-- Se toda fonte da versão corrente está indisponível, não há avaliação nova.
-- As já válidas permanecem no resumo e, portanto, na ordem.

CREATE INDEX articles_feed_day_idx
  ON articles (((published_at AT TIME ZONE 'America/Sao_Paulo')::date) DESC, published_at DESC)
  WHERE status = 'published';

-- Voto novo exige ao menos uma fonte da versão corrente ainda alcançável.
-- UPDATE de um voto já enviado (o filtro) continua permitido.
CREATE OR REPLACE FUNCTION reject_vote_without_reachable_source() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM articles a
    JOIN article_sources s ON s.version_id = a.current_version_id
    WHERE a.id = NEW.article_id
      AND s.hash_status <> 'unavailable'
  ) THEN
    RAISE EXCEPTION 'sources_unavailable: article % cannot receive a new evaluation because every cited source is unreachable', NEW.article_id
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER fidelity_votes_require_reachable_source
  BEFORE INSERT ON fidelity_votes
  FOR EACH ROW EXECUTE FUNCTION reject_vote_without_reachable_source();

-- Abrir o gate numa fonte já indisponível não prova leitura.
CREATE OR REPLACE FUNCTION reject_gate_on_unavailable_source() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  st source_hash_status;
BEGIN
  SELECT hash_status INTO st FROM article_sources WHERE id = NEW.source_id;
  IF st = 'unavailable' THEN
    RAISE EXCEPTION 'source_unavailable: source % is unreachable, so it cannot open a reading gate', NEW.source_id
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER reading_gates_require_reachable_source
  BEFORE INSERT OR UPDATE OF source_id ON reading_gates
  FOR EACH ROW EXECUTE FUNCTION reject_gate_on_unavailable_source();
