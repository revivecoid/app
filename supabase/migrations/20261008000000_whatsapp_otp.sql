-- Add table for WhatsApp OTP verifications
CREATE TABLE IF NOT EXISTS public.wa_otp_verifications (
    phone text PRIMARY KEY,
    code text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    attempts int NOT NULL DEFAULT 0,
    verified boolean NOT NULL DEFAULT false
);

ALTER TABLE public.wa_otp_verifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Service role manages WA OTP" ON public.wa_otp_verifications
    FOR ALL TO service_role USING (true) WITH CHECK (true);
