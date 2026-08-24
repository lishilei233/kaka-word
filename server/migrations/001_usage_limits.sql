CREATE TABLE IF NOT EXISTS picture_word_rate_limit_buckets (
  scope text NOT NULL,
  subject_hash char(64) NOT NULL,
  tokens double precision NOT NULL CHECK (tokens >= 0),
  updated_at timestamptz NOT NULL,
  PRIMARY KEY (scope, subject_hash)
);

CREATE INDEX IF NOT EXISTS picture_word_rate_limit_buckets_updated_at_idx
  ON picture_word_rate_limit_buckets (updated_at);

CREATE TABLE IF NOT EXISTS picture_word_daily_usage (
  scope text NOT NULL,
  usage_date date NOT NULL,
  request_count integer NOT NULL CHECK (request_count >= 0),
  updated_at timestamptz NOT NULL,
  PRIMARY KEY (scope, usage_date)
);
