import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { corsHeaders } from '../_shared/cors.ts'

Deno.serve(async () => {
  return new Response(JSON.stringify({ message: 'Deprecated' }), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
})
