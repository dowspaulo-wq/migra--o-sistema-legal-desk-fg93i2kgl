import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    // We use the ANON KEY to trigger the standard signUp process which sends the confirmation email
    const supabaseKey = Deno.env.get('SUPABASE_ANON_KEY');

    if (!supabaseUrl || !supabaseKey) {
      throw new Error('Missing Supabase environment variables');
    }

    const supabase = createClient(supabaseUrl, supabaseKey);
    const { email, password, name, role } = await req.json();

    if (!email || !password) {
      throw new Error('Email and password are required');
    }

    // Using signUp instead of admin.createUser to trigger standard confirmation email
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { 
          name: name || email.split('@')[0],
          role: role || 'user'
        }
      }
    });

    if (error) {
      throw error;
    }

    return new Response(JSON.stringify({ user: data.user }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    });
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    });
  }
});
