CREATE TABLE IF NOT EXISTS picture_word_activity_events (
  event_id uuid PRIMARY KEY,
  installation_id uuid NOT NULL REFERENCES picture_word_installations(id) ON DELETE CASCADE,
  occurred_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  environment text NOT NULL,
  event_name text NOT NULL CHECK (event_name IN ('app_foreground', 'app_open', 'listening_enter', 'listening_start', 'listening_answer', 'listening_complete', 'history_view', 'word_play')),
  outcome text NOT NULL DEFAULT '' CHECK (outcome IN ('', 'found', 'revealed')),
  session_id uuid,
  app_version varchar(64),
  app_build varchar(64)
);
CREATE INDEX IF NOT EXISTS picture_word_activity_events_device_time_idx
  ON picture_word_activity_events (installation_id, occurred_at DESC, event_id DESC);
CREATE INDEX IF NOT EXISTS picture_word_activity_events_time_idx ON picture_word_activity_events (occurred_at);
CREATE TABLE IF NOT EXISTS picture_word_activity_daily (
  installation_id uuid NOT NULL REFERENCES picture_word_installations(id) ON DELETE CASCADE,
  metric_date date NOT NULL,
  environment text NOT NULL,
  event_name text NOT NULL,
  outcome text NOT NULL DEFAULT '',
  event_count bigint NOT NULL DEFAULT 0 CHECK (event_count >= 0),
  first_at timestamptz NOT NULL,
  last_at timestamptz NOT NULL,
  PRIMARY KEY (installation_id, metric_date, environment, event_name, outcome)
);
CREATE INDEX IF NOT EXISTS picture_word_activity_daily_date_idx
  ON picture_word_activity_daily (metric_date, environment, installation_id);
INSERT INTO picture_word_stats_metadata (name) VALUES ('activity_events_started') ON CONFLICT (name) DO NOTHING;
