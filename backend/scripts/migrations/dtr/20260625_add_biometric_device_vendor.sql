-- Add vendor column to biometric_devices for multi-brand support.
-- Default 'zkteco' keeps all existing devices working unchanged.
ALTER TABLE biometric_devices
  ADD COLUMN IF NOT EXISTS vendor TEXT NOT NULL DEFAULT 'zkteco';
