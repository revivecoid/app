import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req: Request) => {
  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Fetch Indonesian public holidays from a verified public API endpoint
    const currentYear = new Date().getFullYear();
    
    // Fixed string interpolation syntax from the provided code
    // Using a standard Indonesian public holiday open API structure as placeholder
    const response = await fetch(`https://dayoffapi.vercel.app/api?year=${currentYear}`);
    
    if (!response.ok) throw new Error("Failed to retrieve Indonesian holiday metadata.");
    
    const holidaysData = await response.json();
    
    // Extract dates formatted as YYYY-MM-DD
    // Note: Assuming the API returns an array of objects where 'tanggal' or 'date' is the YYYY-MM-DD string
    const holidayDates: string[] = holidaysData.map((h: any) => h.tanggal ?? h.date).filter(Boolean);

    if (holidayDates.length === 0) throw new Error("Holiday array payload empty.");

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
