-- Removes the unused WNS/provider preparation after switching Windows desktop
-- notifications to the system-tray + WebSocket approach.
-- Safe to run whether or not the provider column/constraint was added.

ALTER TABLE IF EXISTS user_push_tokens
  DROP CONSTRAINT IF EXISTS user_push_tokens_provider_check;

ALTER TABLE IF EXISTS user_push_tokens
  DROP COLUMN IF EXISTS provider;
