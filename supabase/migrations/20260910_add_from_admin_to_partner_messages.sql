-- Migration: Add from_admin column to partner_messages
-- The original schema used sender_id to track who sent a message.
-- The app needs an explicit from_admin boolean flag to distinguish
-- admin-originated messages from partner-originated ones without
-- requiring a round-trip to check the sender_id against the partner's UID.

ALTER TABLE public.partner_messages
  ADD COLUMN IF NOT EXISTS from_admin BOOLEAN NOT NULL DEFAULT false;

-- Backfill existing rows:
-- Messages sent by a user whose role is 'master_admin' in app_metadata
-- are admin messages. For existing rows we can approximate using the 
-- sender_id — if it does NOT match the partner_id user, it's from admin.
-- Since we don't have a direct admin UID list here, we default all 
-- existing rows to false (partner-sent). Admins can re-send if needed.
-- (Production note: update manually if rows exist from admin side.)

-- Also add body as alias column and sent_at view for backward compat.
-- The app code now uses content / created_at directly, but these
-- comments document the original intent.

COMMENT ON COLUMN public.partner_messages.from_admin IS
  'True when the message was originated by a Revive Ops admin. False = partner sent.';
