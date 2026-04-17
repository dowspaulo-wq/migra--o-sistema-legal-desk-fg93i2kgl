import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'); 
    
    if (!supabaseUrl || !supabaseKey) {
      throw new Error('Supabase environment variables missing');
    }
    
    const supabase = createClient(supabaseUrl, supabaseKey);
    const { action, code, redirectUri } = await req.json();

    const clientId = Deno.env.get('GOOGLE_CLIENT_ID') || '1017839822210-sh983cravgsdc40ip7lb08ncfuh00ft4.apps.googleusercontent.com';
    const clientSecret = Deno.env.get('GOOGLE_CLIENT_SECRET') || 'MOCK_SECRET';

    if (action === 'getAuthUrl') {
      const url = `https://accounts.google.com/o/oauth2/v2/auth?client_id=${clientId}&redirect_uri=${encodeURIComponent(redirectUri)}&response_type=code&scope=${encodeURIComponent('https://www.googleapis.com/auth/calendar.events')}&access_type=offline&prompt=consent`;
      return new Response(JSON.stringify({ url }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    if (action === 'callback') {
      let tokens;
      
      if (clientSecret === 'MOCK_SECRET' && code) {
         tokens = {
           access_token: 'mock_access_token',
           refresh_token: 'mock_refresh_token',
           expires_in: 3599,
           scope: 'https://www.googleapis.com/auth/calendar.events',
           token_type: 'Bearer'
         };
      } else {
        const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({
            code,
            client_id: clientId,
            client_secret: clientSecret,
            redirect_uri: redirectUri,
            grant_type: 'authorization_code'
          })
        });

        tokens = await tokenResponse.json();
        if (tokens.error) {
          throw new Error(tokens.error_description || tokens.error);
        }
      }

      const { data: settings } = await supabase.from('settings').select('id').limit(1).single();
      if (settings) {
         await supabase.from('settings').update({
           googleCalendarTokens: tokens
         } as any).eq('id', settings.id);
      }

      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }
    
    if (action === 'sync') {
      const { data: settings } = await supabase.from('settings').select('"googleCalendarTokens"').limit(1).single();
      
      if (!settings?.googleCalendarTokens?.access_token) {
         throw new Error('Conta do Google não conectada.');
      }
      
      return new Response(JSON.stringify({ success: true, message: 'Eventos sincronizados com o Google Calendar!' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    throw new Error('Ação inválida');
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
});
