# Partner contact verification (OTP)

How a prospective partner proves that the phone number and email address on
their application are theirs — and what stops that mechanism from being used to
burn resources.

## Flow

1. The applicant fills the registration form. **No code is sent yet.** The
   "Kirim OTP" buttons are gone; the phone and email are plain fields.
2. Every file is uploaded **the moment it is picked** (`<uid>/partner-applications/<doc_type>/…`).
   A failed file is retried on its own; the rest of the form is unaffected.
3. `submit-partner-application` files the row, normalises the phone to MSISDN
   (`62…`), and creates one challenge per channel in `partner_contact_otps`.
   Each challenge gets a 6-digit code and a row in `notification_outbox`
   (`kind = 'partner_otp'`, `purpose = 'transactional'`).
4. The applicant opens `/partner/application-status` and enters the code per
   channel. Success sets `partner_applications.wa_verified` /
   `email_verified` and, when both pass, `contacts_verified_at`.

## Why not `public.notify()`

`notify(p_kind, p_title, p_body, p_job_id, p_to, p_payload, p_user_id, p_channel)`
fans out to users, partners and admins that it can resolve from memberships and
`notification_preferences` consent rows. An applicant has none of those yet, so
`notify()` cannot deliver a code to them — the old call site also passed
arguments the function does not have (`p_to_address`, `p_purpose`) and a channel
outside `system|marketing|chatbot`, so it failed outright. Delivery therefore
writes straight into `notification_outbox`, which the dispatcher already owns.

## Limits (per application, per channel)

| Limit | Value | Enforced in |
|---|---|---|
| Code lifetime | 10 minutes | `partner_contact_otps.expires_at` |
| Wrong-code attempts | 5, then the code is locked | `attempts` |
| Resends | 3 | `resend_count` |
| Resend cooldown | 60 s | `last_sent_at` |
| Applications per session | 3 / 24 h | `submit-partner-application` |

The server is the only authority on all of them: the client countdown is
cosmetic, the edge functions re-check every value.

## Functions

- `send-partner-otp` — issues or re-issues a code. 429 on cooldown
  (`retry_after_seconds`) and on an exhausted resend budget.
- `verify-partner-otp` — checks a code. Returns `attempts_left`, `locked` when
  the budget is gone, `both_verified` when both channels passed.
- `_shared/partner_otp.ts` — the pure policy (normalisation, code generation,
  hashing, resend/verify decisions) with unit tests in `partner_otp_test.ts`.

## Storage notes

- Phone numbers are stored as MSISDN without `+` (`628…`) so the WhatsApp JID and
  the outbox address agree.
- `r2-presign` gained a `delete` action (owner-only, performed server-side —
  a browser DELETE would need a CORS preflight the bucket does not answer).
  Replacing a file deletes the previous object instead of leaving an orphan.
- Uploads are capped at 6 MB per file in the client: the relay carries the file
  as base64 inside a ~8 MB request body.
