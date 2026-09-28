// sync-holidays/index.ts
// C-68 fix: fetch current + next year, upsert (not overwrite)
// REL-16 fix: single source — dayoffapi → public.holidays table
// REL-14 fix: timeout + fail-open (old data retained)
// C-41 fix: writes to public.holidays, not partner_schedules.automated_holidays

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const HOLIDAY_API = "https://dayoffapi.vercel.app/api";
const FETCH_TIMEOUT_MS = 15_000;

async function fetchYear(year: number): Promise<{ date: string; name: string }[]> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(`${HOLIDAY_API}?year=${year}`, { signal: ctrl.signal });
    if (!res.ok) throw new Error(`HTTP ${res.status} for year ${year}`);
    const data = await res.json();
    if (!Array.isArray(data)) throw new Error(`Invalid response shape for year ${year}`);

    return data
      .filter((h: any) => {
        const d = h.tanggal ?? h.date ?? h.holiday_date;
        return typeof d === "string" && /^\d{4}-\d{2}-\d{2}$/.test(d);
      })
      .map((h: any) => ({
        date: h.tanggal ?? h.date ?? h.holiday_date,
        name: String(h.keterangan ?? h.name ?? h.holiday_name ?? "Hari Libur Nasional"),
      }));
  } finally {
    clearTimeout(timer);
  }
}

serve(async (req: Request) => {
  try {
    // Only callable via service_role key (cron or manual admin trigger)
    const authHeader = req.headers.get("Authorization") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!authHeader.startsWith("Bearer ") ||
        authHeader.replace("Bearer ", "") !== serviceRoleKey) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      serviceRoleKey
    );

    const now = new Date();
    const thisYear = now.getFullYear();
    const nextYear = thisYear + 1;

    // Fetch both years; if one fails, log but continue with the other
    const results: { date: string; name: string; source: string }[] = [];
    for (const year of [thisYear, nextYear]) {
      try {
        const rows = await fetchYear(year);
        rows.forEach(r => results.push({ ...r, source: "sync-holidays" }));
        console.log(`[sync-holidays] year=${year} fetched=${rows.length} holidays`);
      } catch (err: any) {
        // Fail-open: old data stays, just skip this year
        console.error(`[sync-holidays] year=${year} fetch failed: ${err.message}`);
      }
    }

    if (results.length === 0) {
      return new Response(JSON.stringify({
        warning: "No holidays fetched — existing data retained"
      }), { status: 200 });
    }

    // Upsert (not overwrite) so existing manual entries survive
    const { error } = await supabase
      .from("holidays")
      .upsert(results, { onConflict: "date" });

    if (error) throw error;

    return new Response(JSON.stringify({
      success: true,
      upserted: results.length,
      years: [thisYear, nextYear],
    }), { headers: { "Content-Type": "application/json" }, status: 200 });

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});
