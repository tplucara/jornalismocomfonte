package main

import (
	"context"
	"log/slog"

	"github.com/jackc/pgx/v5/pgxpool"

	"jornalismocomfonte/internal/config"
	"jornalismocomfonte/internal/db"
	"jornalismocomfonte/internal/kindclass"
)

// classifyPublished grava a tag da versão corrente que ainda não tem decisão.
// Modelo externo quando configurado; senão a rubrica versionada. Falha de um
// artigo não impede os demais. O texto não vai para o log.
func classifyPublished(ctx context.Context, pool *pgxpool.Pool, q *db.Queries, cfg config.Config, log *slog.Logger) {
	rows, err := q.ListVersionsWithoutKindDecision(ctx, 20)
	if err != nil {
		log.Error("kind_list", "err", err.Error())
		return
	}
	for _, row := range rows {
		result := kindclass.Classify(row.Plain)
		method := kindclass.RubricMethod
		model := kindclass.RubricModel
		if cfg.AIBaseURL != "" && cfg.AIAPIKey != "" && cfg.AIModel != "" {
			remote, err := kindclass.ClassifyRemote(ctx, cfg.AIBaseURL, cfg.AIAPIKey, cfg.AIModel, row.Plain, !cfg.IsProd())
			if err != nil {
				log.Warn("kind_model", "err", err.Error())
			} else {
				result = remote
				method = kindclass.PromptMethod
				model = cfg.AIModel
				if len(model) > 80 {
					model = model[:80]
				}
			}
		}
		tx, err := pool.Begin(ctx)
		if err != nil {
			log.Error("kind_tx", "err", err.Error())
			return
		}
		qtx := q.WithTx(tx)
		err = qtx.InsertKindDecision(ctx, db.InsertKindDecisionParams{
			ArticleID: row.ArticleID,
			VersionID: row.VersionID,
			Kind:      db.ArticleKind(result.Kind),
			Method:    method,
			Model:     model,
			Reason:    result.Reason,
		})
		if err == nil {
			err = qtx.SetArticleKind(ctx, db.SetArticleKindParams{
				ID:   row.ArticleID,
				Kind: db.ArticleKind(result.Kind),
			})
		}
		if err != nil {
			_ = tx.Rollback(ctx)
			log.Error("kind_save", "article_id", row.ArticleID, "err", err.Error())
			continue
		}
		if err := tx.Commit(ctx); err != nil {
			log.Error("kind_commit", "article_id", row.ArticleID, "err", err.Error())
			continue
		}
		log.Info("kind_decision", "article_id", row.ArticleID, "kind", result.Kind, "method", method)
	}
}
