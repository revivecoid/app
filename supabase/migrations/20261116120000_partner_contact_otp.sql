-- Contact verification for partner applications.
--
-- The previous flow sent an OTP *before* submit and dispatched it through
-- public.notify(). That could never work: notify() has signature
-- (p_kind, p_title, p_body, p_job_id, p_to, p_payload, p_user_id, p_channel),
-- the call site passed p_to_address/p_purpose and p_channel='whatsapp' (only
-- system|marketing|chatbot are accepted), and even a correct call writes outbox
-- rows only for recipients derived from users/memberships plus an explicit
-- notification_preferences consent row. An applicant who has not registered yet
-- is none of those, so nothing was ever enqueued.
--
-- Challenges now live here, one row per channel, created by
-- submit-partner-application (i.e. only after the user presses Submit) and
-- delivered by inserting straight into notification_outbox.

CREATE TABLE IF NOT EXISTS public.partner_contact_otps (
  application_id uuid        NOT NULL REFERENCES public.partner_applications(id) ON DELETE CASCADE,
  channel        text        NOT NULL CHECK (channel IN ('whatsapp','email')),
  code_hash      text        NOT NULL,
  to_address     text        NOT NULL,
  expires_at     timestamptz NOT NULL,
  attempts       int         NOT NULL DEFAULT 0,
  resend_count   int         NOT NULL DEFAULT 0,
  last_sent_at   timestamptz NOT NULL DEFAULT now(),
  verified_at    timestamptz,
  last_error     text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (application_id, channel)
);

-- Only the edge functions (service role) read/write these rows.
ALTER TABLE public.partner_contact_otps ENABLE ROW LEVEL SECURITY;

-- Throttling looks up "how many codes has this address been sent recently".
CREATE INDEX IF NOT EXISTS idx_partner_contact_otps_to
  ON public.partner_contact_otps (to_address, last_sent_at DESC);

-- Per-channel verification flags on the application itself.
ALTER TABLE public.partner_applications
  ADD COLUMN IF NOT EXISTS email_verified       boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS contacts_verified_at timestamptz;

-- Superseded: keyed by phone, written before the application existed.
DROP TABLE IF EXISTS public.partner_otp_tokens;
