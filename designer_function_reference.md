# re-V.co.id — Designer Function Reference
**Purpose:** Complete map of every implemented function per page, with responsive layout notes.
**Breakpoint:** `< 900px` = Mobile layout · `≥ 900px` = Desktop/Web layout

---

## Legend
| Symbol | Meaning |
|---|---|
| 📱 | Mobile only |
| 🖥️ | Desktop/Web only |
| 📱🖥️ | Available on both (responsive) |
| 🔴 | Requires login / role-gated |

---

## PAGE 1 — Login Gate
**Route:** `/login` · **Roles:** All  
**Layout:** Single centered card — same on mobile and desktop (no responsive split)

| # | Function | Layout | Notes |
|---|---|---|---|
| 1 | Email input field | 📱🖥️ | Labeled "Secure ID (Email)" |
| 2 | Password input field | 📱🖥️ | Obscured text |
| 3 | **AUTHORIZE** button | 📱🖥️ | Shows loading spinner while awaiting Supabase response |
| 4 | Error message banner | 📱🖥️ | Renders inline above the button with red background on auth failure |
| 5 | Auto-role redirect | 📱🖥️ | After login: `customer → /` · `partner_mechanic → /partner-dashboard` · `master_admin → /admin-central` |

---

## PAGE 2 — AI Estimator (Customer Home)
**Route:** `/` · **Role:** `customer` 🔴  
**Layout:** Single column stepper — same on mobile and desktop

| # | Function | Layout | Notes |
|---|---|---|---|
| 1 | **Step 1 — Contact Details** | 📱🖥️ | Full Name + WhatsApp Number text fields |
| 2 | **Step 2 — Vehicle Demographics** | 📱🖥️ | Car Brand dropdown (Toyota/Honda/Mitsubishi) + Year of Production field |
| 3 | **Step 3 — Capture Damage Photo** | 📱🖥️ | Opens device camera via `ImagePicker` |
| 4 | Image confirmation indicator | 📱🖥️ | Shows "Image Selected: [filename]" in green when photo is captured |
| 5 | **Submit to Vision AI** | 📱🖥️ | Compresses image (<300KB) → uploads to Supabase Storage → calls `vision-estimation` Edge Function |
| 6 | AI processing spinner | 📱🖥️ | Circular progress indicator during analysis |
| 7 | AI Assessment result panel | 📱🖥️ | Dark panel showing estimation result text from AI engine |
| 8 | Stepper navigation (Continue / Back) | 📱🖥️ | Steps forward/backward through the 3-step intake form |

> ⚠️ **Designer Note:** Car Brand dropdown currently has only 3 static options (Toyota, Honda, Mitsubishi). Needs expansion to full brand list.

---

## PAGE 3 — Checkout & Booking
**Route:** `/checkout/:jobId` · **Role:** `customer` 🔴  
**Layout:** Responsive split

| # | Function | Layout | Notes |
|---|---|---|---|
| 1 | **Delivery method selector** | 📱🖥️ | Segmented button: "Self Delivery" vs "Valet Pickup" |
| 2 | Pickup address field | 📱🖥️ | Appears only when "Valet Pickup" selected — requires min 10 chars |
| 3 | Latitude / Longitude fields | 📱🖥️ | Appears only when "Valet Pickup" selected — validated as decimal numbers |
| 4 | **Calendar date picker** | 📱🖥️ | Selectable dates from tomorrow up to 60 days ahead; checks workshop capacity async |
| 5 | Verified Intake Date confirmation | 📱🖥️ | Green text showing confirmed date after async capacity check passes |
| 6 | AI Estimate cost display | 📱🖥️ | Shows `IDR [amount]` from AI assessment |
| 7 | Valet fee notice | 📱🖥️ | Orange text shown conditionally when Valet Pickup is selected |
| 8 | **PAY NOW button** | 📱🖥️ | Triggers `executePaymentAndBooking()` — disabled while loading or awaiting webhook |
| 9 | Awaiting webhook state | 📱🖥️ | Button label changes to "Awaiting Gateway Webhook..." during payment processing |
| 10 | **Payment Success dialog** | 📱🖥️ | Non-dismissable modal confirming transaction — has "View Live Tracker" action button |
| 11 | Error snackbar | 📱🖥️ | Red snackbar for any validation or network failure |

**Responsive layout difference:**
- 📱 **Mobile:** Checkout form stacked above pricing panel (vertical column)
- 🖥️ **Desktop:** Checkout form (left 60%) + Pricing panel (right 40%) side by side

---

## PAGE 4 — Live Tracker Timeline
**Route:** `/track/:jobId` · **Role:** `customer` 🔴  
**Layout:** Responsive dual-pane

| # | Function | Layout | Notes |
|---|---|---|---|
| 1 | **9-stage vertical timeline stepper** | 📱🖥️ | Displays all stages: Intake → Handover. Completed = green ✓, Active = pulsating red dot, Pending = grey |
| 2 | Pulsating active stage indicator | 📱🖥️ | Animated scale pulse on the currently active stage node |
| 3 | **Live progress photo gallery** | 📱🖥️ | 2-column grid of photos uploaded by the workshop mechanic team |
| 4 | Photo label overlay | 📱🖥️ | Each photo card shows a context label (e.g. "IN_PROGRESS") at the bottom |
| 5 | **Photo lightbox viewer** | 📱🖥️ | Tap any photo to open full-screen with pinch-to-zoom (0.5× to 4×) + close button |
| 6 | "Awaiting photo updates" empty state | 📱🖥️ | Shown when no progress photos exist yet |
| 7 | **Disconnection warning banner** | 📱🖥️ | Orange full-width banner shown at top when WebSocket stream loses connection |
| 8 | Real-time auto-update | 📱🖥️ | Supabase `.stream()` listener — page updates automatically without refresh |

**Responsive layout difference:**
- 📱 **Mobile:** Timeline (top 60%) + Photo gallery (bottom 40%) in a single scroll column
- 🖥️ **Desktop:** Timeline (left pane) + Photo gallery (right pane) side by side

---

## PAGE 5 — Partner Dashboard
**Route:** `/partner-dashboard` · **Role:** `partner_mechanic` 🔴  
**⚠️ This page has TWO completely different layouts for mobile vs desktop**

### 5A — Desktop: Workshop Command Matrix
| # | Function | Layout | Notes |
|---|---|---|---|
| 1 | **4-column Kanban board** | 🖥️ | Columns: "Admitted Queue" / "Active Body & Paint" / "Quality Control" / "Ready For Dispatch" |
| 2 | Job count badge per column | 🖥️ | Red circle showing number of active jobs in each column |
| 3 | Job card: Car identity + license plate | 🖥️ | Make/model bold, license plate in orange |
| 4 | Job card: Customer name + admitted date | 🖥️ | Secondary info below the car identity |
| 5 | **ADVANCE button** | 🖥️ | Moves the job to the next repair stage in the 9-stage model |
| 6 | **DISPUTE button** | 🖥️ | Raises a dispute ticket notification to Master Admin |
| 7 | Offline sync indicator | 🖥️ | "Syncing Cache..." spinner in app bar when background queue is processing |
| 8 | Real-time Supabase stream | 🖥️ | Board auto-refreshes when job status changes in the database |

### 5B — Mobile: Garage Floor Mechanic View
| # | Function | Layout | Notes |
|---|---|---|---|
| 1 | **Job list** (scrollable cards) | 📱 | Shows car make/model, license plate, and current status |
| 2 | License plate display | 📱 | Formatted in bold caps with border — designed for quick garage ID |
| 3 | Status label | 📱 | Shows current stage in red (e.g. "IN_PROGRESS") |
| 4 | **Camera upload button** | 📱 | Red circle camera icon per job card — triggers native camera |
| 5 | Image compress + upload pipeline | 📱 | Captured photo is compressed (<300KB) then uploaded to Cloudflare R2 |
| 6 | Upload loading overlay | 📱 | Bottom bar shows "Compressing & Uploading..." with spinner during upload |
| 7 | Offline sync icon | 📱 | Sync icon in app bar when offline queue is retrying failed uploads |
| 8 | Offline fallback queue | 📱 | If upload fails (no network), photo is saved locally and retried automatically |

---

## PAGE 6 — Master Admin Central Command
**Route:** `/admin-central` · **Role:** `master_admin` 🔴  
**Layout:** Desktop-first only (persistent sidebar + content area). No mobile layout currently built.

### Navigation Sidebar (persistent)
| # | Item | Notes |
|---|---|---|
| 1 | Live Matrix | View A |
| 2 | CRM Portal | View B |
| 3 | Breach Alerts | View C |
| 4 | Vision AI Core | View D |

### View A — Live Operational Matrix
| # | Function | Layout | Notes |
|---|---|---|---|
| 1 | **Search bar** | 🖥️ | Filters by Customer Name, Vehicle, or Job UUID |
| 2 | **Jobs data table** | 🖥️ | Columns: Job UUID · Customer · Vehicle · Active Stage · Time Elapsed · Partner Shop |
| 3 | Stage badge | 🖥️ | Stage shown as red pill badge in the Active Stage column |
| 4 | **Override Job Status dialog** | 🖥️ | Click any row → dropdown to select a new stage → "FORCE UPDATE" |
| 5 | Real-time auto-refresh | 🖥️ | Table updates automatically via Supabase Realtime channel |
| 6 | Late-schedule breach toast | 🖥️ | Orange snackbar (8s duration) appears when polling detects a time overrun |

### View B — CRM Portal
| # | Function | Layout | Notes |
|---|---|---|---|
| 1 | **Customer Network tab** | 🖥️ | List of all customers: Name, Email, Phone, Active Jobs count, Lifetime Value (IDR) |
| 2 | **Partner Workshops tab** | 🖥️ | List of partners: Shop Name, Avg Cycle Velocity (days), Active Volume (cars) |
| 3 | **Partner active/inactive toggle** | 🖥️ | Switch to enable/disable a partner workshop on the platform |

### View C — Global Breach Alerts
| # | Function | Layout | Notes |
|---|---|---|---|
| 1 | Breach count badge | 🖥️ | Red circle showing number of active breaches next to the title |
| 2 | **Breach alert cards** | 🖥️ | Each card: Job ID, Customer name, Trigger reason, Detection timestamp |
| 3 | Nominal state message | 🖥️ | Green text "Zero criteria breaches detected" when list is empty |

### View D — Vision AI Core
| # | Function | Layout | Notes |
|---|---|---|---|
| 1 | **AI model cards grid** | 🖥️ | 2-column grid of configured AI engines (Gemini, OpenAI, etc.) |
| 2 | Model name + provider label | 🖥️ | Name in large bold white, provider in grey |
| 3 | Token price display | 🖥️ | Cost per query shown in green |
| 4 | **Active model toggle (Switch)** | 🖥️ | Enables a model — only one can be active at a time (primary engine) |
| 5 | Active model highlight | 🖥️ | Active model card gets red border + red tinted background |

---

## Summary: Responsive Coverage Map

| Page | Mobile View | Desktop/Web View |
|---|---|---|
| Login Gate | ✅ Fully responsive (same layout) | ✅ Fully responsive (same layout) |
| AI Estimator (`/`) | ✅ Single column stepper | ✅ Single column stepper |
| Checkout & Booking | ✅ Stacked vertical layout | ✅ Side-by-side split layout |
| Live Tracker | ✅ Stacked (timeline top, gallery bottom) | ✅ Dual-pane (timeline left, gallery right) |
| Partner Dashboard | ✅ **Unique mobile view** (Camera-first job list) | ✅ **Unique desktop view** (Kanban matrix) |
| Admin Central | ❌ **No mobile layout built** | ✅ Full 4-view sidebar dashboard |

