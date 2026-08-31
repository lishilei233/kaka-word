CREATE TABLE IF NOT EXISTS picture_word_subscription_transactions (
  environment text NOT NULL,
  transaction_id text NOT NULL,
  original_transaction_id text NOT NULL,
  product_id text NOT NULL,
  original_purchase_at timestamptz NOT NULL,
  purchase_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  first_seen_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  last_seen_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (environment, transaction_id)
);

CREATE INDEX IF NOT EXISTS picture_word_subscription_transactions_chain_idx
  ON picture_word_subscription_transactions (environment, original_transaction_id, purchase_at);

-- Existing releases only retained the latest transaction for each subscription
-- chain. Seed that known transaction without inventing older history.
INSERT INTO picture_word_subscription_transactions
  (environment, transaction_id, original_transaction_id, product_id,
   original_purchase_at, purchase_at, expires_at, revoked_at,
   first_seen_at, last_seen_at)
SELECT environment, latest_transaction_id, original_transaction_id, product_id,
       original_purchase_at, purchase_at, expires_at, revoked_at,
       updated_at, updated_at
FROM picture_word_subscriptions
ON CONFLICT (environment, transaction_id) DO NOTHING;
