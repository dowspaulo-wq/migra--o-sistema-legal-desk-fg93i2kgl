import 'jsr:@supabase/functions-js/edge-runtime.d.ts'

Deno.serve(async (req: Request) => {
  if (req.method !== 'GET') {
    return new Response(JSON.stringify({ error: 'method_not_allowed' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json' },
    })
  }
  const url = new URL(req.url)
  const provided = url.searchParams.get('key') ?? ''
  const { data: cfg, error: cfgErr } = (await (globalThis as any).SupabaseClient)
    ? { data: null, error: null }
    : { data: null, error: null }
  // Read secret via service-role client created by the runtime
  const { createClient } = await import('jsr:@supabase/supabase-js@2')
  const SUPABASE_URL =
    (globalThis as any).Deno?.env?.get('SUPABASE_URL') ?? 'https://cpcafthwnqazopqftemj.supabase.co'
  const SERVICE_ROLE = (globalThis as any).Deno?.env?.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } })
  const { data, error } = await admin
    .from('backup_export_config')
    .select('value')
    .eq('id', 1)
    .single()
  if (error || !data) {
    return new Response(JSON.stringify({ error: 'config_unavailable' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
  const expected = data.value
  if (!provided || provided.length !== expected.length) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    })
  }
  let diff = 0
  for (let i = 0; i < provided.length; i++) diff |= provided.charCodeAt(i) ^ expected.charCodeAt(i)
  if (diff !== 0) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    })
  }
  const { data: backup, error: bkErr } = await admin.rpc('export_database_backup_json')
  if (bkErr || !backup) {
    return new Response(JSON.stringify({ error: 'export_failed', detail: String(bkErr) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
  const body = JSON.stringify(backup)
  return new Response(body, {
    status: 200,
    headers: {
      'Content-Type': 'application/json',
      'Content-Disposition': 'attachment; filename="sbjur-export.json"',
      'Cache-Control': 'no-store',
    },
  })
})
