import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-requested-with',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
}

interface GoogleTokens {
  access_token: string
  refresh_token?: string
  expires_in?: number
  scope?: string
  token_type?: string
  error?: string
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    let body: any = {}
    try {
      body = await req.json()
    } catch {
      body = {}
    }
    const { action, code, redirectUri, appointments, appointment } = body

    // 1. Carrega tokens e possíveis credenciais salvas no banco (tabela settings)
    const { data: settingsData, error: settingsError } = await supabaseClient
      .from('settings')
      .select('id, googleCalendarTokens, googleClientId, googleClientSecret')
      .limit(1)
      .maybeSingle()

    if (settingsError) {
      console.error('Erro ao ler settings:', settingsError)
    }

    // Prioriza env var do edge-runtime; se ausente, faz fallback para tabela settings
    const GOOGLE_CLIENT_ID = Deno.env.get('GOOGLE_CLIENT_ID') || settingsData?.googleClientId || ''
    const GOOGLE_CLIENT_SECRET =
      Deno.env.get('GOOGLE_CLIENT_SECRET') || settingsData?.googleClientSecret || ''

    // ----------------------------------------------------
    // ACTION: EXCHANGE CODE (OAuth Callback)
    // Suporta tanto 'exchange_code' quanto 'callback'
    // ----------------------------------------------------
    if (action === 'exchange_code' || action === 'callback') {
      if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET) {
        return new Response(
          JSON.stringify({
            success: false,
            error:
              'Credenciais do Google não configuradas. Preencha o Client ID e Client Secret em Configurações > Integrações ou defina GOOGLE_CLIENT_ID e GOOGLE_CLIENT_SECRET no servidor.',
            missingCredentials: true,
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200, // Retornamos 200 com success: false para que o frontend exiba a mensagem limpa
          },
        )
      }

      if (!code) {
        return new Response(
          JSON.stringify({
            success: false,
            error: 'Código de autorização não fornecido pelo Google.',
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
          },
        )
      }

      const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          code,
          client_id: GOOGLE_CLIENT_ID,
          client_secret: GOOGLE_CLIENT_SECRET,
          redirect_uri: redirectUri,
          grant_type: 'authorization_code',
        }),
      })

      const tokenData = await tokenResponse.json()

      if (!tokenResponse.ok || tokenData.error) {
        console.error('Google OAuth token error:', tokenData)
        return new Response(
          JSON.stringify({
            success: false,
            error:
              tokenData.error_description ||
              tokenData.error ||
              'Falha ao trocar código de autorização por tokens.',
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
          },
        )
      }

      // Preserva o refresh_token anterior caso o Google não tenha retornado um novo
      const prevTokens = (settingsData?.googleCalendarTokens as GoogleTokens) || {}
      const tokensToSave: GoogleTokens = {
        ...tokenData,
        refresh_token: tokenData.refresh_token || prevTokens.refresh_token,
      }

      if (settingsData?.id) {
        await supabaseClient
          .from('settings')
          .update({ googleCalendarTokens: tokensToSave })
          .eq('id', settingsData.id)
      }

      return new Response(
        JSON.stringify({
          success: true,
          message: 'Google Agenda conectado com sucesso!',
          tokens: tokensToSave,
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200,
        },
      )
    }

    // ----------------------------------------------------
    // DEMAIS ACTIONS: EXIGEM TOKENS SALVOS
    // ----------------------------------------------------
    const tokens = settingsData?.googleCalendarTokens as GoogleTokens | undefined

    if (!tokens || (!tokens.access_token && !tokens.refresh_token)) {
      return new Response(
        JSON.stringify({
          success: false,
          error:
            'A conta do Google Agenda não está conectada. Acesse Configurações > Integrações e conecte sua conta Google.',
          notConnected: true,
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200, // Retornamos 200 para que o frontend exiba a mensagem amigável sem estourar "non-2xx"
        },
      )
    }

    // Helper para renovar o access_token se tiver refresh_token
    let accessToken = tokens.access_token

    const refreshGoogleToken = async (): Promise<string | null> => {
      if (!tokens.refresh_token) {
        console.warn('Sem refresh_token para renovar access_token')
        return null
      }
      if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET) {
        console.warn('Faltam GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET para renovar token')
        return null
      }

      try {
        const res = await fetch('https://oauth2.googleapis.com/token', {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({
            client_id: GOOGLE_CLIENT_ID,
            client_secret: GOOGLE_CLIENT_SECRET,
            refresh_token: tokens.refresh_token,
            grant_type: 'refresh_token',
          }),
        })

        const data = await res.json()
        if (data.access_token) {
          const updatedTokens: GoogleTokens = {
            ...tokens,
            access_token: data.access_token,
            expires_in: data.expires_in,
          }
          if (settingsData?.id) {
            await supabaseClient
              .from('settings')
              .update({ googleCalendarTokens: updatedTokens })
              .eq('id', settingsData.id)
          }
          return data.access_token
        } else {
          console.error('Falha na renovação do token do Google:', data)
          return null
        }
      } catch (err) {
        console.error('Exceção ao renovar token:', err)
        return null
      }
    }

    // Função auxiliar com retry de 401
    const fetchGoogleApi = async (url: string, options: RequestInit = {}): Promise<Response> => {
      let headers = {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
        ...(options.headers || {}),
      }

      let res = await fetch(url, { ...options, headers })

      if (res.status === 401) {
        console.log('Access token expirado (401). Tentando renovar...')
        const newAccessToken = await refreshGoogleToken()
        if (newAccessToken) {
          accessToken = newAccessToken
          headers = {
            ...headers,
            Authorization: `Bearer ${newAccessToken}`,
          }
          res = await fetch(url, { ...options, headers })
        }
      }

      return res
    }

    // ----------------------------------------------------
    // ACTION: SYNC (Bidirecional / Importar + Exportar)
    // ----------------------------------------------------
    if (action === 'sync') {
      const now = new Date()
      // Busca eventos a partir do início do mês anterior até 1 ano à frente
      const timeMin = new Date(now.getFullYear(), now.getMonth() - 1, 1).toISOString()
      const timeMax = new Date(now.getFullYear() + 1, now.getMonth(), 1).toISOString()

      const googleEventsRes = await fetchGoogleApi(
        `https://www.googleapis.com/calendar/v3/calendars/primary/events?singleEvents=true&orderBy=startTime&timeMin=${encodeURIComponent(
          timeMin,
        )}&timeMax=${encodeURIComponent(timeMax)}&maxResults=2500`,
      )

      if (!googleEventsRes.ok) {
        const errJson = await googleEventsRes.json().catch(() => ({}))
        console.error('Erro na API do Google Calendar:', errJson)

        if (googleEventsRes.status === 401) {
          return new Response(
            JSON.stringify({
              success: false,
              error:
                'A autorização do Google Agenda expirou ou foi revogada. Por favor, reconecte sua conta em Configurações > Integrações.',
              needsReauth: true,
            }),
            {
              headers: { ...corsHeaders, 'Content-Type': 'application/json' },
              status: 200,
            },
          )
        }

        return new Response(
          JSON.stringify({
            success: false,
            error:
              errJson?.error?.message ||
              `Erro do Google Calendar (${googleEventsRes.status}): verifique se o serviço Google Agenda está ativo no Google Cloud Console.`,
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
          },
        )
      }

      const googleData = await googleEventsRes.json()
      const googleEvents = googleData.items || []

      // 1. Sincroniza eventos do Google -> DPSjur (cria ou atualiza)
      const syncedAppointments = []
      for (const gEvent of googleEvents) {
        if (!gEvent.start) continue

        const startDateTime = gEvent.start.dateTime || gEvent.start.date
        const dateStr = startDateTime ? startDateTime.split('T')[0] : ''
        const timeStr =
          gEvent.start.dateTime && gEvent.start.dateTime.includes('T')
            ? gEvent.start.dateTime.split('T')[1].substring(0, 5)
            : '09:00'

        // Procura se já temos um appointment com este googleEventId
        const { data: existing } = await supabaseClient
          .from('appointments')
          .select('id')
          .eq('googleEventId', gEvent.id)
          .maybeSingle()

        if (existing) {
          await supabaseClient
            .from('appointments')
            .update({
              title: gEvent.summary || 'Sem título',
              description: gEvent.description || '',
              date: dateStr,
              time: timeStr,
              location: gEvent.location || '',
            })
            .eq('id', existing.id)
          syncedAppointments.push({ id: existing.id, action: 'updated' })
        } else {
          // Cria novo compromisso vindo do Google
          const { data: newApp, error: insertErr } = await supabaseClient
            .from('appointments')
            .insert({
              title: gEvent.summary || 'Sem título',
              description: gEvent.description || '',
              date: dateStr,
              time: timeStr,
              location: gEvent.location || '',
              googleEventId: gEvent.id,
              type: 'Reunião',
              status: 'Confirmado',
            })
            .select('id')
            .maybeSingle()

          if (!insertErr && newApp) {
            syncedAppointments.push({ id: newApp.id, action: 'created' })
          }
        }
      }

      // 2. Envia compromissos locais para o Google Calendar caso ainda não tenham googleEventId
      const localAppsList: any[] = Array.isArray(appointments) ? appointments : []
      let exportedCount = 0

      for (const app of localAppsList) {
        if (!app.googleEventId && app.title && app.date) {
          try {
            const timePart = app.time ? `${app.time}:00` : '09:00:00'
            const startDateTime = `${app.date}T${timePart}`
            const endDate = new Date(new Date(startDateTime).getTime() + 60 * 60 * 1000)
            const endDateTime = endDate.toISOString().split('.')[0]

            const postRes = await fetchGoogleApi(
              'https://www.googleapis.com/calendar/v3/calendars/primary/events',
              {
                method: 'POST',
                body: JSON.stringify({
                  summary: app.title,
                  description: app.description || '',
                  location: app.location || '',
                  start: {
                    dateTime: `${startDateTime}-03:00`,
                    timeZone: 'America/Sao_Paulo',
                  },
                  end: {
                    dateTime: `${endDateTime}-03:00`,
                    timeZone: 'America/Sao_Paulo',
                  },
                }),
              },
            )

            if (postRes.ok) {
              const createdGEvent = await postRes.json()
              if (createdGEvent?.id && app.id) {
                await supabaseClient
                  .from('appointments')
                  .update({ googleEventId: createdGEvent.id })
                  .eq('id', app.id)
                exportedCount++
              }
            }
          } catch (e) {
            console.error('Falha ao exportar appointment para Google:', e)
          }
        }
      }

      return new Response(
        JSON.stringify({
          success: true,
          message: 'Sincronização concluída com sucesso!',
          importedFromGoogle: syncedAppointments.length,
          exportedToGoogle: exportedCount,
          totalGoogleEvents: googleEvents.length,
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200,
        },
      )
    }

    // ----------------------------------------------------
    // ACTION: CREATE EVENT
    // ----------------------------------------------------
    if (action === 'create_event') {
      if (!appointment) {
        return new Response(
          JSON.stringify({ success: false, error: 'Dados do compromisso ausentes' }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
          },
        )
      }

      const timePart = appointment.time ? `${appointment.time}:00` : '09:00:00'
      const startDateTime = `${appointment.date}T${timePart}`
      const endDate = new Date(new Date(startDateTime).getTime() + 60 * 60 * 1000)
      const endDateTime = endDate.toISOString().split('.')[0]

      const gRes = await fetchGoogleApi(
        'https://www.googleapis.com/calendar/v3/calendars/primary/events',
        {
          method: 'POST',
          body: JSON.stringify({
            summary: appointment.title,
            description: appointment.description || '',
            location: appointment.location || '',
            start: {
              dateTime: `${startDateTime}-03:00`,
              timeZone: 'America/Sao_Paulo',
            },
            end: {
              dateTime: `${endDateTime}-03:00`,
              timeZone: 'America/Sao_Paulo',
            },
          }),
        },
      )

      if (!gRes.ok) {
        const errJson = await gRes.json().catch(() => ({}))
        return new Response(
          JSON.stringify({
            success: false,
            error: errJson?.error?.message || 'Falha ao criar evento no Google Calendar',
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
          },
        )
      }

      const gEvent = await gRes.json()

      if (appointment.id && gEvent.id) {
        await supabaseClient
          .from('appointments')
          .update({ googleEventId: gEvent.id })
          .eq('id', appointment.id)
      }

      return new Response(
        JSON.stringify({
          success: true,
          googleEventId: gEvent.id,
          event: gEvent,
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200,
        },
      )
    }

    // ----------------------------------------------------
    // ACTION: UPDATE EVENT
    // ----------------------------------------------------
    if (action === 'update_event') {
      if (!appointment || !appointment.googleEventId) {
        return new Response(
          JSON.stringify({
            success: false,
            error: 'Compromisso não possui identificador do Google Calendar para atualizar',
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
          },
        )
      }

      const timePart = appointment.time ? `${appointment.time}:00` : '09:00:00'
      const startDateTime = `${appointment.date}T${timePart}`
      const endDate = new Date(new Date(startDateTime).getTime() + 60 * 60 * 1000)
      const endDateTime = endDate.toISOString().split('.')[0]

      const gRes = await fetchGoogleApi(
        `https://www.googleapis.com/calendar/v3/calendars/primary/events/${encodeURIComponent(
          appointment.googleEventId,
        )}`,
        {
          method: 'PATCH',
          body: JSON.stringify({
            summary: appointment.title,
            description: appointment.description || '',
            location: appointment.location || '',
            start: {
              dateTime: `${startDateTime}-03:00`,
              timeZone: 'America/Sao_Paulo',
            },
            end: {
              dateTime: `${endDateTime}-03:00`,
              timeZone: 'America/Sao_Paulo',
            },
          }),
        },
      )

      if (!gRes.ok) {
        const errJson = await gRes.json().catch(() => ({}))
        return new Response(
          JSON.stringify({
            success: false,
            error: errJson?.error?.message || 'Falha ao atualizar evento no Google Calendar',
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
          },
        )
      }

      const gEvent = await gRes.json()
      return new Response(JSON.stringify({ success: true, event: gEvent }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      })
    }

    // ----------------------------------------------------
    // ACTION: DELETE EVENT
    // ----------------------------------------------------
    if (action === 'delete_event') {
      if (!appointment?.googleEventId) {
        return new Response(
          JSON.stringify({
            success: false,
            error: 'Compromisso não possui identificador do Google Calendar para exclusão',
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
          },
        )
      }

      const gRes = await fetchGoogleApi(
        `https://www.googleapis.com/calendar/v3/calendars/primary/events/${encodeURIComponent(
          appointment.googleEventId,
        )}`,
        {
          method: 'DELETE',
        },
      )

      if (!gRes.ok && gRes.status !== 404) {
        const errJson = await gRes.json().catch(() => ({}))
        return new Response(
          JSON.stringify({
            success: false,
            error: errJson?.error?.message || 'Falha ao excluir evento no Google Calendar',
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
          },
        )
      }

      return new Response(
        JSON.stringify({ success: true, message: 'Evento removido do Google Calendar' }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200,
        },
      )
    }

    // ----------------------------------------------------
    // ACTION DESCONHECIDA
    // ----------------------------------------------------
    return new Response(JSON.stringify({ success: false, error: `Ação desconhecida: ${action}` }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error: any) {
    console.error('Erro geral na edge function google-calendar:', error)
    return new Response(
      JSON.stringify({
        success: false,
        error: error?.message || 'Erro inesperado na sincronização com o Google Agenda.',
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      },
    )
  }
})
