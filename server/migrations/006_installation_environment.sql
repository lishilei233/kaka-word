ALTER TABLE picture_word_installations
  ADD COLUMN IF NOT EXISTS store_environment text;

ALTER TABLE picture_word_installation_metrics_daily
  ADD COLUMN IF NOT EXISTS environment text NOT NULL DEFAULT 'Unknown';

DO $$
DECLARE
  existing_primary_key text;
BEGIN
  SELECT conname INTO existing_primary_key
  FROM pg_constraint
  WHERE conrelid = 'picture_word_installation_metrics_daily'::regclass
    AND contype = 'p';
  IF existing_primary_key IS NOT NULL THEN
    EXECUTE format('ALTER TABLE picture_word_installation_metrics_daily DROP CONSTRAINT %I', existing_primary_key);
  END IF;
  ALTER TABLE picture_word_installation_metrics_daily
    ADD CONSTRAINT picture_word_installation_metrics_daily_pkey PRIMARY KEY (installation_id, metric_date, environment);
END $$;

CREATE INDEX IF NOT EXISTS picture_word_installation_metrics_daily_environment_date_idx
  ON picture_word_installation_metrics_daily (environment, metric_date, installation_id);
