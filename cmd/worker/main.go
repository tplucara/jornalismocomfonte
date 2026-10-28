package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"jornalismocomfonte/internal/config"
	"jornalismocomfonte/internal/db"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if err := run(log); err != nil {
		log.Error("worker", "err", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()
	q := db.New(pool)

	if err := ensurePartitions(ctx, q, log); err != nil {
		return err
	}
	classifyPublished(ctx, pool, q, cfg, log)
	log.Info("worker started")

	tick := time.NewTicker(time.Hour)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			log.Info("worker stopped")
			return nil
		case <-tick.C:
			if err := ensurePartitions(ctx, q, log); err != nil {
				log.Error("partitions", "err", err)
			}
			classifyPublished(ctx, pool, q, cfg, log)
			dropped, err := q.DropExpiredAccessLogPartitions(ctx)
			if err != nil {
				log.Error("drop_access_logs", "err", err)
			} else if dropped > 0 {
				log.Info("dropped_access_log_partitions", "n", dropped)
			}
			// Filtro de qualidade, quiz e recheque de hash entram em iterações seguintes.
			// O worker não marca voto como válido sozinho (algoritmos-transparentes.mdc).
		}
	}
}

func ensurePartitions(ctx context.Context, q *db.Queries, log *slog.Logger) error {
	now := time.Now().UTC()
	this := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	next := this.AddDate(0, 1, 0)
	for _, parent := range []string{"audit_log", "access_logs"} {
		for _, month := range []time.Time{this, next} {
			if err := q.EnsureMonthPartition(ctx, db.EnsureMonthPartitionParams{
				Parent: parent,
				Month:  pgtype.Date{Time: month, Valid: true},
			}); err != nil {
				return err
			}
		}
	}
	log.Info("partitions_ok", "month", this.Format("2006-01"))
	return nil
}
