-- Adds SMS OTP storage for /auth/forgot-password and /auth/reset-password.
-- Run manually if needed:
--   psql "$DATABASE_URL" -f scripts/migrate-auth-password-reset-otps.sql

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS auth_password_reset_otps (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL,
  sent_to TEXT,
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  failed_attempts INT NOT NULL DEFAULT 0,
  ip_address INET,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_auth_password_reset_otps_user_active
  ON auth_password_reset_otps(user_id, expires_at DESC)
  WHERE consumed_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_auth_password_reset_otps_expires_at
  ON auth_password_reset_otps(expires_at);
