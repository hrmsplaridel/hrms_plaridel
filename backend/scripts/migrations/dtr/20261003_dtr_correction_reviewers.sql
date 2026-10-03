CREATE TABLE IF NOT EXISTS dtr_correction_reviewer_configs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  effective_from DATE NOT NULL,
  reviewer_ids UUID[] NOT NULL,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (cardinality(reviewer_ids) BETWEEN 1 AND 6)
);

CREATE INDEX IF NOT EXISTS idx_dtr_correction_reviewer_configs_date
  ON dtr_correction_reviewer_configs(effective_from DESC, created_at DESC, id DESC);
