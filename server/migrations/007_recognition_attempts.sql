CREATE TABLE IF NOT EXISTS picture_word_recognition_attempts (
  operation_id uuid PRIMARY KEY,
  installation_id uuid NOT NULL REFERENCES picture_word_installations(id) ON DELETE CASCADE,
  request_id text NOT NULL,
  started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  finished_at timestamptz,
  environment text NOT NULL DEFAULT 'Unknown',
  outcome text NOT NULL DEFAULT 'processing' CHECK (outcome IN
    ('processing', 'success', 'empty', 'failure', 'cancelled', 'quota_exhausted', 'rate_limited', 'unfinished')),
  reason_code text,
  stage text,
  duration_ms integer CHECK (duration_ms >= 0),
  app_version varchar(64),
  app_build varchar(64),
  quota_before jsonb NOT NULL,
  quota_after jsonb
);
CREATE INDEX IF NOT EXISTS picture_word_recognition_attempts_device_time_idx
  ON picture_word_recognition_attempts (installation_id, started_at DESC, operation_id DESC);
CREATE INDEX IF NOT EXISTS picture_word_recognition_attempts_time_idx
  ON picture_word_recognition_attempts (started_at);
CREATE TABLE IF NOT EXISTS picture_word_stats_metadata (
  name text PRIMARY KEY,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO picture_word_stats_metadata (name) VALUES ('recognition_attempts_started')
  ON CONFLICT (name) DO NOTHING;
