import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req: Request) => {
  try {
    // SEC-05 FIX: Verify caller has service role key (this should be a cron, not public)
    const authHeader = req.headers.get('Authorization');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    if (!authHeader || !authHeader.startsWith('Bearer ') || 
        authHeader.replace('Bearer ', '') !== serviceRoleKey) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 })
    }

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      serviceRoleKey
    )

    // Fetch Indonesian public holidays with timeout
    const currentYear = new Date().getFullYear();
    
    // REL-14 FIX: Add timeout to prevent hanging requests
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 10000); // 10s timeout
    
    let response;
    try {
      response = await fetch(`https://dayoffapi.vercel.app/api?year=${currentYear}`, {
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timeoutId);
    }
    
    if (!response.ok) throw new Error("Failed to retrieve Indonesian holiday metadata.");
    
    const holidaysData = await response.json();
    
    // SEC-05 FIX: Validate response shape before writing to DB
    if (!Array.isArray(holidaysData)) {
      throw new Error("Invalid holiday API response: expected array");
    }

    // Extract dates formatted as YYYY-MM-DD with validation
    const holidayDates: string[] = holidaysData
      .map((h: any) => h.tanggal ?? h.date)
      .filter((d: any): d is string => {
        if (typeof d !== 'string') return false;
        // Validate date format YYYY-MM-DD
        return /^\d{4}-\d{2}-\d{2}$/.test(d);
      });

    if (holidayDates.length === 0) throw new Error("Holiday array payload empty after validation.");

    // Update the automated_holidays array for all active partner profiles globally
    const { error } = await supabaseClient
      .from('partner_schedules')
      .update({ automated_holidays: holidayDates })
      .not('id', 'is', null); // Target all rows safely

    if (error) throw error;

    return new Response(JSON.stringify({ success: true, synchronized_dates: holidayDates.length }), {
      headers: { 'Content-Type': 'application/json' },
      status: 200,
    })

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500 })
  }
})
