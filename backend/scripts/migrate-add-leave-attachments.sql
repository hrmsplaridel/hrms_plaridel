-- Add attachment columns to leave_requests for supporting documents
-- Run: psql -d hrms_plaridel -f backend/scripts/migrate-add-leave-attachments.sql

ALTER TABLE leave_requests
  ADD COLUMN IF NOT EXISTS attachment_name TEXT,
  ADD COLUMN IF NOT EXISTS attachment_path TEXT,
  ADD COLUMN IF NOT EXISTS attachment_mime_type TEXT,
  ADD COLUMN IF NOT EXISTS attachment_uploaded_at TIMESTAMPTZ;
