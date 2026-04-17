import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'jsr:@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    if (!supabaseUrl || !supabaseKey) {
      throw new Error('Supabase environment variables missing')
    }

    const supabase = createClient(supabaseUrl, supabaseKey)
    const { action, code, redirectUri } = await req.json()

    const clientId =
      Deno.env.get('GOOGLE_CLIENT_ID') ||
      '1017839822210-sh983cravgsdc40ip7lb08ncfuh00ft4.apps.googleusercontent.com'
    const clientSecret = Deno.env.get('GOOGLE_CLIENT_SECRET') || 'MOCK_SECRET'

    if (action === 'getAuthUrl') {
      const url = `https://accounts.google.com/o/oauth2/v2/auth?client_id=${clientId}&redirect_uri=${encodeURIComponent(redirectUri)}&response_type=code&scope=${encodeURIComponent('https://www.googleapis.com/auth/calendar.events')}&access_type=offline&prompt=consent`
      return new Response(JSON.stringify({ url }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (action === 'callback') {
      let tokens

      if (clientSecret === 'MOCK_SECRET' && code) {
        tokens = {
          access_token: 'mock_access_token',
          refresh_token: 'mock_refresh_token',
          expires_in: 3599,
          scope: 'https://www.googleapis.com/auth/calendar.events',
          token_type: 'Bearer',
        }
      } else {
        const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({
            code,
            client_id: clientId,
            client_secret: clientSecret,
            redirect_uri: redirectUri,
            grant_type: 'authorization_code',
          }),
        })

        tokens = await tokenResponse.json()
        if (tokens.error) {
          throw new Error(tokens.error_description || tokens.error)
        }
      }

      const { data: settings } = await supabase.from('settings').select('id').limit(1).single()
      if (settings) {
        await supabase
          .from('settings')
          .update({
            googleCalendarTokens: tokens,
          } as any)
          .eq('id', settings.id)
      }

      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (action === 'sync') {
      const { data: settings } = await supabase
        .from('settings')
        .select('id, "googleCalendarTokens"')
        .limit(1)
        .single()

      if (!settings?.googleCalendarTokens || !(settings.googleCalendarTokens as any).access_token) {
        throw new Error('Conta do Google não conectada.')
      }

      let tokens = settings.googleCalendarTokens as any

      async function fetchEvents(accessToken: string) {
        const timeMinDate = new Date()
        timeMinDate.setMonth(timeMinDate.getMonth() - 1)
        const timeMin = timeMinDate.toISOString()

        const timeMaxDate = new Date()
        timeMaxDate.setMonth(timeMaxDate.getMonth() + 6)
        const timeMax = timeMaxDate.toISOString()

        const url = `https://www.googleapis.com/calendar/v3/calendars/primary/events?timeMin=${encodeURIComponent(timeMin)}&timeMax=${encodeURIComponent(timeMax)}&singleEvents=true&orderBy=startTime`

        return await fetch(url, {
          headers: { Authorization: `Bearer ${accessToken}` },
        })
      }

      let res = await fetchEvents(tokens.access_token)

      if (res.status === 401 && tokens.refresh_token && clientSecret !== 'MOCK_SECRET') {
        const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({
            client_id: clientId,
            client_secret: clientSecret,
            refresh_token: tokens.refresh_token,
            grant_type: 'refresh_token',
          }),
        })
        const newTokens = await tokenResponse.json()
        if (newTokens.error) {
          await supabase
            .from('settings')
            .update({ googleCalendarTokens: null } as any)
            .eq('id', settings.id)
          throw new Error('Sessão expirada. Por favor, conecte sua conta do Google novamente.')
        }

        tokens = {
          ...tokens,
          access_token: newTokens.access_token,
          expires_in: newTokens.expires_in,
        }

        await supabase
          .from('settings')
          .update({ googleCalendarTokens: tokens } as any)
          .eq('id', settings.id)
        res = await fetchEvents(tokens.access_token)
      }

      if (!res.ok && clientSecret !== 'MOCK_SECRET') {
        const errData = await res.json().catch(() => ({}))
        throw new Error(
          `Erro ao buscar eventos do Google Calendar: ${errData.error?.message || res.statusText}`,
        )
      }

      let events = []
      if (clientSecret !== 'MOCK_SECRET') {
        const data = await res.json()
        events = data.items || []
      } else {
        events = [
          {
            id: 'mock_event_1',
            summary: 'Reunião Mock (Google)',
            start: { dateTime: new Date().toISOString() },
            description: 'Evento de teste mockado do Google Calendar',
          },
        ]
      }

      let { data: defaultClient } = await supabase
        .from('clients')
        .select('id')
        .eq('name', 'Sincronização Google')
        .limit(1)
        .maybeSingle()
      if (!defaultClient) {
        const { data: newClient, error: clientErr } = await supabase
          .from('clients')
          .insert({
            name: 'Sincronização Google',
            type: 'Outros',
            status: 'Ativo',
          })
          .select('id')
          .single()

        if (clientErr) throw new Error('Erro ao criar cliente padrão para sincronização')
        defaultClient = newClient
      }

      const defaultClientId = defaultClient.id

      const { data: existingAppts } = await supabase
        .from('appointments')
        .select('id, "googleEventId"')
        .not('googleEventId', 'is', null)

      const existingMap = new Map((existingAppts || []).map((a: any) => [a.googleEventId, a.id]))
      let processedCount = 0

      for (const event of events) {
        if (!event.start) continue

        const startDateTime = event.start.dateTime || event.start.date
        if (!startDateTime) continue

        let dateStr = ''
        let timeStr = '00:00'

        if (event.start.dateTime) {
          const match = startDateTime.match(/^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})/)
          if (match) {
            dateStr = match[1]
            timeStr = match[2]
          } else {
            const dateObj = new Date(startDateTime)
            dateStr = dateObj.toISOString().split('T')[0]
          }
        } else if (event.start.date) {
          dateStr = event.start.date
        }

        if (!dateStr) continue

        const appt: any = {
          title: event.summary || 'Evento sem título',
          date: dateStr,
          time: timeStr,
          type: 'Outro',
          priority: 'Média',
          status: 'Pendente',
          clientId: defaultClientId,
          description: event.description || null,
          googleEventId: event.id,
        }

        const existingId = existingMap.get(event.id)
        if (existingId) {
          await supabase.from('appointments').update(appt).eq('id', existingId)
        } else {
          await supabase.from('appointments').insert(appt)
        }
        processedCount++
      }

      return new Response(
        JSON.stringify({
          success: true,
          message: `${processedCount} eventos sincronizados com o Google Calendar!`,
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      )
    }

    throw new Error('Ação inválida')
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
