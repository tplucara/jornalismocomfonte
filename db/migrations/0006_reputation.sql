-- 0006: reputação (reputacao-jornalista.mdc)
-- Dois componentes separados: author e reviewer. Calculados por job, nunca em leitura.
-- Rotulagem na UI: "avaliação entre pares". Nunca "índice de veracidade".

-- Snapshot periódico. Cada componente: { score, ci_low, ci_high, n_valid, insufficient }
-- score e CI em [0,1]; insufficient = true quando n_valid < limiar (UI mostra "amostra insuficiente").
CREATE TABLE reputation_snapshots (
  id             bigserial PRIMARY KEY,
  journalist_id  uuid NOT NULL REFERENCES journalists(id),
  computed_at    timestamptz NOT NULL DEFAULT now(),
  author         jsonb NOT NULL,
  reviewer       jsonb NOT NULL,
  algorithm      varchar(40) NOT NULL,                      -- versão do cálculo, para auditoria
  CONSTRAINT reputation_author_shape CHECK (
    author ? 'n_valid' AND author ? 'insufficient' AND
    ((author->>'insufficient')::boolean OR (author ? 'score' AND author ? 'ci_low' AND author ? 'ci_high'))
  ),
  CONSTRAINT reputation_reviewer_shape CHECK (
    reviewer ? 'n_valid' AND reviewer ? 'insufficient' AND
    ((reviewer->>'insufficient')::boolean OR (reviewer ? 'score' AND reviewer ? 'ci_low' AND reviewer ? 'ci_high'))
  )
);

CREATE INDEX reputation_snapshots_latest_idx ON reputation_snapshots (journalist_id, computed_at DESC);

-- Visão da reputação corrente de cada jornalista (último snapshot).
CREATE VIEW current_reputation AS
SELECT DISTINCT ON (journalist_id)
  journalist_id, computed_at, author, reviewer, algorithm
FROM reputation_snapshots
ORDER BY journalist_id, computed_at DESC;

-- Créditos diários do avaliador: base do retorno decrescente e do desconto por rejeição.
CREATE TABLE reviewer_daily_credits (
  journalist_id   uuid NOT NULL REFERENCES journalists(id),
  day             date NOT NULL,
  credited_count  integer NOT NULL DEFAULT 0,               -- votos/comentários válidos no dia
  rejected_count  integer NOT NULL DEFAULT 0,               -- rejeitados por fã/hater no dia
  PRIMARY KEY (journalist_id, day),
  CONSTRAINT reviewer_daily_credits_nonneg CHECK (credited_count >= 0 AND rejected_count >= 0)
);

-- Mantém reviewer_daily_credits a partir das decisões do filtro em votos e comentários.
CREATE OR REPLACE FUNCTION bump_reviewer_credits() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.filter_status = 'pending' OR NEW.filter_status IS NOT DISTINCT FROM OLD.filter_status THEN
    RETURN NEW;
  END IF;
  INSERT INTO reviewer_daily_credits (journalist_id, day, credited_count, rejected_count)
  VALUES (
    NEW.journalist_id,
    (NEW.filtered_at AT TIME ZONE 'UTC')::date,
    CASE WHEN NEW.filter_status = 'valid' THEN 1 ELSE 0 END,
    CASE WHEN NEW.filter_status = 'rejected' THEN 1 ELSE 0 END
  )
  ON CONFLICT (journalist_id, day) DO UPDATE SET
    credited_count = reviewer_daily_credits.credited_count + EXCLUDED.credited_count,
    rejected_count = reviewer_daily_credits.rejected_count + EXCLUDED.rejected_count;
  RETURN NEW;
END $$;

CREATE TRIGGER fidelity_votes_bump_credits
  AFTER UPDATE OF filter_status ON fidelity_votes
  FOR EACH ROW EXECUTE FUNCTION bump_reviewer_credits();

CREATE TRIGGER comments_bump_credits
  AFTER UPDATE OF filter_status ON comments
  FOR EACH ROW EXECUTE FUNCTION bump_reviewer_credits();

-- Agregado por artigo usado pelo job de reputação e pela UI
-- ("avaliado por N jornalistas: X fiel"). Só votos válidos; rejeitados ficam fora.
CREATE VIEW article_fidelity_summary AS
SELECT
  article_id,
  count(*) FILTER (WHERE verdict = 'faithful')  AS faithful_count,
  count(*) FILTER (WHERE verdict = 'distorts')  AS distorts_count,
  count(*)                                       AS valid_count
FROM fidelity_votes
WHERE filter_status = 'valid'
GROUP BY article_id;

-- Taxa de rejeição por artigo: usada para normalizar tema polêmico
-- (brigada hater não derruba o autor se os votos válidos o sustentam).
CREATE VIEW article_rejection_rate AS
SELECT
  article_id,
  count(*) FILTER (WHERE filter_status = 'rejected')::numeric
    / NULLIF(count(*) FILTER (WHERE filter_status <> 'pending'), 0) AS rejection_rate,
  count(*) FILTER (WHERE filter_status <> 'pending') AS decided_count
FROM fidelity_votes
GROUP BY article_id;
