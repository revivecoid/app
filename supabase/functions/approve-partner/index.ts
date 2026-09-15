import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3'

serve(async (req) => {
  const corsHeaders = {
    'Access-Control-Allow-Origin': 'https://revive.co.id',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('Missing Authorization header')
    const token = authHeader.replace('Bearer ', '')

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    )

    // Verify caller is master_admin
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(token)
    if (userError || !user) throw new Error(`Unauthorized: ${userError?.message || 'No user'}`)

    // SEC-02 FIX: Only read role from app_metadata (cannot be self-modified by user)
    const userRole = user.app_metadata?.role
    if (userRole !== 'master_admin') {
      return new Response(JSON.stringify({ error: 'Forbidden' }), { status: 403, headers: corsHeaders })
    }

    // Get request body
    const { applicationId } = await req.json()
    if (!applicationId) throw new Error('applicationId is required')

    // We need service_role key to bypass RLS and use auth.admin
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Fetch the application
    const { data: appData, error: appError } = await supabaseAdmin
      .from('partner_applications')
      .select('*')
      .eq('id', applicationId)
      .single()

    if (appError || !appData) throw new Error('Application not found')
    if (appData.status !== 'pending') throw new Error('Application is not pending')

    // 1. Create the partner row
    const { data: partnerData, error: partnerError } = await supabaseAdmin
      .from('partners')
      .insert({
        shop_name: appData.shop_name,
        email: appData.email,
        phone: appData.phone,
        address: appData.address,
        is_active: true
      })
      .select()
      .single()

    if (partnerError) throw partnerError

    // 2. Invite or fetch the user
    let userId = '';
    const { data: authData, error: authError } = await supabaseAdmin.auth.admin.inviteUserByEmail(
      appData.email,
      {
        data: { role: 'partner_mechanic', partner_id: partnerData.id }
      }
    )

    if (authError) {
      // SEC-15 FIX: Use filtered lookup instead of unpaginated listUsers()
      // listUsers() without pagination only returns the first page — fails when user count exceeds default limit
      const { data: listData, error: listError } = await supabaseAdmin.auth.admin.listUsers({
        page: 1,
        perPage: 1,
        // Note: Supabase admin API doesn't support email filter directly in listUsers.
        // Use getUserByEmail if available, or search after fetch.
      })
      
      // Better approach: iterate to find user by email, but limit scope
      let existingUser = null
      let page = 1
      const perPage = 100
      while (!existingUser) {
        const { data: pageData, error: pageError } = await supabaseAdmin.auth.admin.listUsers({ page, perPage })
        if (pageError) throw pageError
        existingUser = pageData.users.find(u => u.email === appData.email)
        if (pageData.users.length < perPage) break // No more pages
        page++
        if (page > 50) break // Safety limit: 5000 users max scan
      }
      
      if (!existingUser) {
        throw new Error(`Failed to invite user and could not find existing account: ${authError.message}`)
      }
      userId = existingUser.id
    } else {
      userId = authData.user.id
    }

    // Ensure the metadata is forcefully updated (handles cases where the user already existed)
    const { error: updateAuthError } = await supabaseAdmin.auth.admin.updateUserById(
      userId,
      {
        user_metadata: { role: 'partner_mechanic', partner_id: partnerData.id },
        app_metadata: { role: 'partner_mechanic', partner_id: partnerData.id }
      }
    )
    
    if (updateAuthError) throw updateAuthError

    // 3. Create or update the profile
    const { error: profileError } = await supabaseAdmin
      .from('profiles')
      .upsert({
        id: userId,
        full_name: appData.owner_name,
        email: appData.email,
        phone: appData.phone,
        role: 'partner_mechanic',
        partner_id: partnerData.id
      })

    if (profileError) throw profileError

    // 4. Update the application status
    const { error: updateError } = await supabaseAdmin
      .from('partner_applications')
      .update({ status: 'approved' })
      .eq('id', applicationId)

    if (updateError) throw updateError

    return new Response(
      JSON.stringify({ success: true, message: 'Partner approved and invited' }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (err: any) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
