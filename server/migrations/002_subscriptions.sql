CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS picture_word_installations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  installation_hash char(64) NOT NULL UNIQUE,
  free_used smallint NOT NULL DEFAULT 0 CHECK (free_used BETWEEN 0 AND 3),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS picture_word_subscriptions (
  environment text NOT NULL,
  original_transaction_id text NOT NULL,
  latest_transaction_id text NOT NULL,
  product_id text NOT NULL,
  state text NOT NULL CHECK (state IN ('active', 'grace', 'expired', 'revoked')),
  original_purchase_at timestamptz NOT NULL,
  purchase_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  grace_expires_at timestamptz,
  revoked_at timestamptz,
  auto_renew_enabled boolean,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (environment, original_transaction_id)
);

CREATE TABLE IF NOT EXISTS picture_word_access_tokens (
  token_hash char(64) PRIMARY KEY,
  installation_id uuid NOT NULL REFERENCES picture_word_installations(id) ON DELETE CASCADE,
  subscription_environment text,
  original_transaction_id text,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  last_used_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK (
    (subscription_environment IS NULL AND original_transaction_id IS NULL)
    OR (subscription_environment IS NOT NULL AND original_transaction_id IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS picture_word_access_tokens_installation_idx
  ON picture_word_access_tokens (installation_id);
CREATE INDEX IF NOT EXISTS picture_word_access_tokens_subscription_idx
  ON picture_word_access_tokens (subscription_environment, original_transaction_id);

CREATE TABLE IF NOT EXISTS picture_word_quota_periods (
  subject_type text NOT NULL CHECK (subject_type IN ('subscription')),
  subject_id text NOT NULL,
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  quota_limit integer NOT NULL CHECK (quota_limit > 0),
  used_count integer NOT NULL DEFAULT 0 CHECK (used_count >= 0),
  reserved_count integer NOT NULL DEFAULT 0 CHECK (reserved_count >= 0),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (subject_type, subject_id, period_start)
);

CREATE TABLE IF NOT EXISTS picture_word_quota_operations (
  operation_id uuid PRIMARY KEY,
  reservation_id uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  installation_id uuid NOT NULL REFERENCES picture_word_installations(id) ON DELETE CASCADE,
  subject_type text NOT NULL CHECK (subject_type IN ('free', 'subscription')),
  subject_id text NOT NULL,
  period_start timestamptz,
  state text NOT NULL CHECK (state IN ('reserved', 'committed', 'released')),
  lease_expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  committed_at timestamptz
);

CREATE INDEX IF NOT EXISTS picture_word_quota_operations_lease_idx
  ON picture_word_quota_operations (state, lease_expires_at);

CREATE TABLE IF NOT EXISTS picture_word_store_notifications (
  environment text NOT NULL,
  notification_uuid uuid NOT NULL,
  notification_type text NOT NULL,
  subtype text,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (environment, notification_uuid)
);

-- DeviceCheck tokens are intentionally not persisted. A failed two-bit update is
-- recorded as a durable task and retried when that installation next supplies a
-- fresh token.
CREATE TABLE IF NOT EXISTS picture_word_devicecheck_sync_tasks (
  installation_id uuid PRIMARY KEY REFERENCES picture_word_installations(id) ON DELETE CASCADE,
  target_used smallint NOT NULL CHECK (target_used BETWEEN 0 AND 3),
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  last_error text,
  next_attempt_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS picture_word_aggregate_metrics_daily (
  metric_date date NOT NULL,
  event_name text NOT NULL,
  product_id text NOT NULL DEFAULT '',
  outcome text NOT NULL DEFAULT '',
  event_count bigint NOT NULL DEFAULT 0 CHECK (event_count >= 0),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (metric_date, event_name, product_id, outcome)
);
