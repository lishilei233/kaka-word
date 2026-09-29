CREATE TABLE IF NOT EXISTS picture_word_installation_metrics_daily (
  installation_id uuid NOT NULL REFERENCES picture_word_installations(id) ON DELETE CASCADE,
  metric_date date NOT NULL,
  recognition_attempt_count bigint NOT NULL DEFAULT 0 CHECK (recognition_attempt_count >= 0),
  recognition_success_count bigint NOT NULL DEFAULT 0 CHECK (recognition_success_count >= 0),
  confirmation_count bigint NOT NULL DEFAULT 0 CHECK (confirmation_count >= 0),
  reselection_count bigint NOT NULL DEFAULT 0 CHECK (reselection_count >= 0),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (installation_id, metric_date),
  CHECK (reselection_count <= confirmation_count)
);

CREATE INDEX IF NOT EXISTS picture_word_installation_metrics_daily_date_idx
  ON picture_word_installation_metrics_daily (metric_date, installation_id);
