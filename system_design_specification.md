# 📑 SYSTEM DESIGN SPECIFICATION: AUTOMOTIVE BODY REPAIR PLATFORM

## 1. High-Level Architecture
* **Frontend:** Single Responsive Flutter Repository (iOS, Android, Responsive Web).
* **Database & Auth:** Supabase (PostgreSQL with Row-Level Security enforced).
* **File Storage:** Cloudflare R2 (S3-compatible API via `minio` or `amazon_s3_cognito` Flutter packages).
* **Web Hosting:** Cloudflare Pages (Connected to GitHub branch).
* **AI Orchestration Layer:** Edge-ready API functions (Supabase Edge Functions / Node.js) mediating multi-model Vision LLM queries, failure fallback switching, and prompt context appending.

---

## 2. Updated Database Schema (Supabase PostgreSQL)
Copy and enforce this relational schema. All tables require strict constraints.

### `profiles` (User Management)
* `id`: uuid (references auth.users, primary key)
* `full_name`: text
* `email`: text (strictly managed and sync'd from auth.users)
* `phone`: text
* `role`: text (enum constraint: `'customer'`, `'partner_mechanic'`, `'master_admin'`)
* `partner_id`: uuid (nullable, references partners.id)
* `created_at`: timestamp with time zone

### `partners` (Body Repair Shops)
* `id`: uuid (primary key, default: uuid_generate_v4())
* `shop_name`: text
* `email`: text (business contact email)
* `address`: text
* `phone`: text
* `is_active`: boolean (default: true)

### `vehicles` (Car Data)
* `id`: uuid (primary key)
* `customer_id`: uuid (references profiles.id)
* `make`: text (e.g., Toyota)
* `model`: text (e.g., Camry)
* `year`: integer
* `license_plate`: text

### `repair_jobs` (The 9-Step Business Flow Engine)
* `id`: uuid (primary key)
* `customer_id`: uuid (references profiles.id)
* `partner_id`: uuid (nullable, references partners.id)
* `vehicle_id`: uuid (references vehicles.id)
* `initial_estimation_cost`: numeric
* `final_cost`: numeric
* `status`: text (enum constraint strictly matching your workflow):
  * `'1_intake'` (Form filled, photos uploaded)
  * `'2_estimated'` (Cost and schedule calculated)
  * `'3_booked'` (User confirmed schedule, picked delivery type)
  * `'4_paid'` (Payment downpayment/full settled)
  * `'5_admitted'` (Car arrived at workshop)
  * `'6_in_progress'` (Active body work / painting)
  * `'7_finished'` (Repair complete, report ready)
  * `'8_awaiting_delivery'` (Notification sent for pickup/delivery)
  * `'9_done'` (Car handed over, closed to CRM)
* `delivery_type`: text (enum: `'self_deliver'`, `'pickup'`)
* `scheduled_date`: timestamp with time zone
* `created_at`: timestamp with time zone

### `repair_photos` (Cloudflare R2 Meta Links)
* `id`: uuid (primary key)
* `job_id`: uuid (references repair_jobs.id)
* `step_context`: text (enum: `'intake'`, `'progress'`, `'finished'`)
* `r2_file_key`: text (The unique file path inside your Cloudflare R2 bucket)
* `uploaded_at`: timestamp with time zone

### `ai_config` (Admin Settings for Multi-Model Fallbacks)
* `id`: integer (primary key, single row configuration)
* `primary_model_provider`: text (e.g., `'google'`, `'groq'`, `'openrouter'`)
* `primary_model_name`: text (e.g., `'gemini-2.5-flash'`)
* `fallback_model_provider`: text
* `fallback_model_name`: text
* `system_instruction_context`: text (The master domain-knowledge prompt text)
* `updated_at`: timestamp with time zone

### `ai_training_context` (Few-Shot Fine-Tuning Storage)
* `id`: uuid (primary key)
* `car_make_model`: text
* `damage_description`: text
* `resolved_actual_cost`: numeric
* `is_active_context`: boolean (default: true, allows admin to opt-in rows to be injected into the LLM system prompt context dynamically)

---

## 3. Vision AI Model Strategy (2026 Competitive Landscape)

### Best "Free Tier" Vision Models For Automotive Analysis
To achieve the best results without cost while mitigating quota lockouts or framework failures, use the following API targets:

1. **Google Gemini 2.5 Flash (via Google AI Studio):**
   * **The Verdict:** The absolute premier choice for a free tier. It offers a massive rate limit allowance on its free plan (up to 15 RPM / 1,500 RPD) and processes images natively with brilliant spatial understanding of dents, cracks, and structural car alignments.
2. **Groq (Llama-3.2-11b-Vision-Preview / Llama-3.3-70b-Spec):**
   * **The Verdict:** Incredibly fast execution speeds. Free tier limits are strictly based on token counts per minute, functioning as an exceptional immediate failover engine.
3. **OpenRouter (Aggregator Fallback):**
   * **The Verdict:** A single unified endpoint API. Allows your app to fall back to several low-cost or free vision open-source alternatives if individual direct provider keys crash.

### How to Make the AI Model "Smarter" Without Fine-Tuning Costs
Training or fine-tuning vision architectures directly is complex and expensive. The best approach for a solo developer is **Dynamic Few-Shot In-Context Learning**:
* Every time a body repair mechanic completes a job and logs the **actual invoice cost**, that data saves into `ai_training_context`.
* When a new customer uploads a photo, your backend runs a vector search or relational query for highly successful historical cases (e.g., *“Find 3 items matching Toyota Camry bumper scratch with complete repair invoices”*).
* The backend appends these historical image URLs and cost text pairs straight into the LLM system prompt context dynamically. This teaches the vision model exactly how your specific partner shops price their work, instantly upgrading its predictive intelligence.

---

## 4. Master Engineering Prompt for Antigravity

```text
CONTEXT: 
We are building a multi-sided Automotive Body Repair Platform using Flutter, Supabase, and Cloudflare R2. The system handles 3 roles: Customer (Mobile App/Web), Partner Repair Shop (Desktop Portal), and Master Admin (Desktop Portal).

STRICT ARCHITECTURAL DIRECTIVES:
1. Do not write placeholder code, "TODOs", or mock data arrays. Write complete, production-ready modules.
2. We are using a single Flutter codebase. Implement responsive layout guards checking `MediaQuery.of(context).size.width`. If width > 900, render a wide-screen dashboard layout with a persistent sidebar navigation drawer. If width <= 900, render a mobile layout with bottom navigation bars.
3. Every image upload MUST run through a client-side image compression function utilizing the 'flutter_image_compress' package. Max dimensions: 1080p, quality: 70%, target output size < 300KB.
4. Do not use Supabase Storage for photos. Image uploads must communicate directly with our Cloudflare R2 bucket via an S3-compatible client wrapper. Save only the generated R2 storage key back into the Supabase database.
5. Use Riverpod or Bloc for state management to handle the 9-stage 'repair_jobs' status transitions sequentially. State mutation triggers must be explicit and validate database responses.
6. The app requires a multi-model Vision LLM estimation system. Admin must be able to switch primary and secondary fallback engines (Gemini-2.5-Flash via Google AI Studio, or Llama Vision via Groq) dynamically through the UI. Provide an automated try/catch middleware handler that executes the primary model, catches quota errors or timeouts, and switches to the fallback engine automatically while saving logs to the DB.

TASK FOR THIS STEP:
Generate the SQL migration schema matching our updated database profile/partner structure along with the multi-model AI configuration schema. Provide the Supabase Edge Function script written in TypeScript/Deno that handles the multi-model vision estimation fallback mechanism and appends dynamic historical context records.
```