CREATE TABLE IF NOT EXISTS picture_word_recognition_confirmations_daily (
  metric_date date NOT NULL,
  original_english text NOT NULL,
  original_chinese text NOT NULL,
  selected_english text NOT NULL,
  selected_chinese text NOT NULL,
  selection text NOT NULL CHECK (selection IN ('first', 'second', 'third', 'other')),
  confirmation_count bigint NOT NULL DEFAULT 0 CHECK (confirmation_count >= 0),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (
    metric_date,
    original_english,
    original_chinese,
    selected_english,
    selected_chinese,
    selection
  )
);

CREATE TABLE IF NOT EXISTS picture_word_recognition_corrections_daily (
  metric_date date NOT NULL,
  original_english text NOT NULL,
  original_chinese text NOT NULL,
  corrected_english text NOT NULL,
  corrected_chinese text NOT NULL,
  correction_count bigint NOT NULL DEFAULT 0 CHECK (correction_count >= 0),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (
    metric_date,
    original_english,
    original_chinese,
    corrected_english,
    corrected_chinese
  )
);
