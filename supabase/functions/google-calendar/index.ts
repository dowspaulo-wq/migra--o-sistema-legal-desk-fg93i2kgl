import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface GoogleTokens {
  access_token: string
  refresh_token?: string
  expires_in?: number
  scope?: string
  token_type?: string
  error?: string
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || ''
    const supabaseKey =
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_ANON_KEY') || ''

    let body: any = {}
    try {
      body = await req.json()
    } catch {
      body = {}
    }
    const { action, code, redirectUri, appointments, appointment } = body

    // Fallbacks passados no header ou body pelo frontend para máxima resiliência
    const headerClientId = req.headers.get('x-google-client-id')?.trim() || ''
    const headerClientSecret = req.headers.get('x-google-client-secret')?.trim() || ''
    const bodyClientId = typeof body.clientId === 'string' ? body.clientId.trim() : ''
    const bodyClientSecret = typeof body.clientSecret === 'string' ? body.clientSecret.trim() : ''

    let supabaseClient: any = null
    if (supabaseUrl && supabaseKey) {
      try {
        supabaseClient = createClient(supabaseUrl, supabaseKey, {
          auth: { persistSession: false },
        })
      } catch (clientErr) {
        console.warn('Erro ao inicializar supabaseClient:', clientErr)
      }
    }

    // 1. Carrega tokens e credenciais salvas no banco (tabela settings)
    let settingsData: any = null
    if (supabaseClient) {
      try {
        const { data, error } = await supabaseClient
          .from('settings')
          .select('id, googleCalendarTokens, googleClientId, googleClientSecret')
          .limit(1)
          .maybeSingle()

        if (error) {
          console.warn('Aviso ao consultar settings no banco:', error?.message || error)
        } else {
          settingsData = data
        }
      } catch (err) {
        console.warn('Exceção ao consultar settings:', err)
      }
    }

    // Prioridade de leitura de credenciais:
    // 1. Registro da tabela public.settings no PostgreSQL (fonte de verdade confiável no VPS)
    // 2. Header da requisição
    // 3. Body da requisição
    // 4. Variáveis de ambiente do servidor (GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET)
    const GOOGLE_CLIENT_ID =
      settingsData?.googleClientId?.trim() ||
      headerClientId ||
      bodyClientId ||
      Deno.env.get('GOOGLE_CLIENT_ID')?.trim() ||
      ''

    const GOOGLE_CLIENT_SECRET =
      settingsData?.googleClientSecret?.trim() ||
      headerClientSecret ||
      bodyClientSecret ||
      Deno.env.get('GOOGLE_CLIENT_SECRET')?.trim() ||
      ''

    // ----------------------------------------------------
    // ACTION: GET AUTH URL (Gerar URL de consentimento OAuth)
    // ----------------------------------------------------
    if (action === 'getAuthUrl' || action === 'get_auth_url') {
      if (!GOOGLE_CLIENT_ID) {
        return new Response(
          JSON.stringify({
            success: false,
            error:
              'Google Client ID não configurado. Preencha o Client ID em Configurações > Integrações ou defina GOOGLE_CLIENT_ID no servidor.',
            missingCredentials: true,
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
          },
        )
      }

      const clientRedirectUri =
        redirectUri || 'https://sistema.advdouglaspsantos.com.br/google-callback'
      const scope = encodeURIComponent(
        'https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.readonly',
      )
      const authUrl = `https://accounts.google.com/o/oauth2/v2/auth?client_id=${encodeURIComponent(
        GOOGLE_CLIENT_ID,
      )}&redirect_uri=${encodeURIComponent(
        clientRedirectUri,
      )}&response_type=code&scope=${scope}&access_type=offline&prompt=consent`

      return new Response(
        JSON.stringify({
          success: true,
          url: authUrl,
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200,
        },
      )
    }

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
            status: 200,
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
      const finalRefreshToken = tokenData.refresh_token || prevTokens.refresh_token

      const tokensToSave: GoogleTokens = {
        ...tokenData,
        refresh_token: finalRefreshToken,
      }

      if (supabaseClient && settingsData?.id) {
        await supabaseClient
          .from('settings')
          .update({ googleCalendarTokens: tokensToSave })
          .eq('id', settingsData.id)
      }

      return new Response(
        JSON.stringify({
          success: true,
          message: finalRefreshToken
            ? 'Google Agenda conectado com sucesso!'
            : 'Google Agenda conectado (aviso: sem refresh_token permanente retornado pelo Google. Caso expire em 1h, reconecte autorizando o acesso offline).',
          hasRefreshToken: !!finalRefreshToken,
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
    // Aceita tokens passados diretamente no body caso o frontend tenha estado mais fresco
    const rawTokens =
      (settingsData?.googleCalendarTokens as GoogleTokens | undefined) ||
      (body?.tokens as GoogleTokens | undefined)

    if (!rawTokens || (!rawTokens.access_token && !rawTokens.refresh_token)) {
      return new Response(
        JSON.stringify({
          success: false,
          error:
            'A conta do Google Agenda não está conectada. Acesse Configurações > Integrações e conecte sua conta Google.',
          notConnected: true,
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200,
        },
      )
    }

    const tokens: GoogleTokens = { ...rawTokens }

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
          tokens.access_token = data.access_token
          if (supabaseClient && settingsData?.id) {
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

    // Tenta renovar preventivamente se não tiver access_token válido ou se tiver refresh_token
    if (!accessToken && tokens.refresh_token) {
      accessToken = (await refreshGoogleToken()) || ''
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
      // Janela ampla: 2 anos atrás até 3 anos à frente para cobrir compromissos futuros do escritório
      const timeMin = new Date(now.getFullYear() - 2, 0, 1).toISOString()
      const timeMax = new Date(now.getFullYear() + 3, 11, 31, 23, 59, 59).toISOString()

      // Paginação completa de eventos do Google Calendar
      const googleEvents: any[] = []
      let pageToken: string | null = null

      do {
        const pageParam = pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : ''
        const googleEventsRes = await fetchGoogleApi(
          `https://www.googleapis.com/calendar/v3/calendars/primary/events?singleEvents=true&orderBy=startTime&timeMin=${encodeURIComponent(
            timeMin,
          )}&timeMax=${encodeURIComponent(timeMax)}&maxResults=2500${pageParam}`,
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
                `Erro do Google Calendar (${googleEventsRes.status}): verifique se a Google Calendar API está ativada no Google Cloud.`,
            }),
            {
              headers: { ...corsHeaders, 'Content-Type': 'application/json' },
              status: 200,
            },
          )
        }

        const googleData = await googleEventsRes.json()
        if (Array.isArray(googleData.items)) {
          googleEvents.push(...googleData.items)
        }
        pageToken = googleData.nextPageToken || null
      } while (pageToken)

      // 1. Sincroniza eventos do Google -> DPSjur (cria ou atualiza)
      const syncedAppointments = []
      if (supabaseClient) {
        for (const gEvent of googleEvents) {
          // Ignora eventos cancelados/removidos no Google
          if (gEvent.status === 'cancelled' || !gEvent.start) continue

          const isAllDay = !!gEvent.start.date && !gEvent.start.dateTime
          const startDateTime = gEvent.start.dateTime || gEvent.start.date
          const dateStr = startDateTime ? startDateTime.split('T')[0] : ''
          const timeStr =
            gEvent.start.dateTime && gEvent.start.dateTime.includes('T')
              ? gEvent.start.dateTime.split('T')[1].substring(0, 5)
              : '08:00'

          // Procura se já temos um appointment com este googleEventId
          const { data: existing } = await supabaseClient
            .from('appointments')
            .select('id, title, date, time, description, location')
            .eq('googleEventId', gEvent.id)
            .maybeSingle()

          if (existing) {
            // Atualiza se houve mudança nos dados
            await supabaseClient
              .from('appointments')
              .update({
                title: gEvent.summary || existing.title || 'Sem título',
                description: gEvent.description ?? existing.description ?? '',
                date: dateStr || existing.date,
                time: isAllDay ? existing.time || '08:00' : timeStr,
                location: gEvent.location ?? existing.location ?? '',
              })
              .eq('id', existing.id)
            syncedAppointments.push({ id: existing.id, action: 'updated' })
          } else {
            // Se não encontrou por googleEventId, procura correspondência por título + data + hora
            // para vincular compromisso já existente e evitar duplicação
            const cleanSummary = (gEvent.summary || '').trim()
            let existingMatch: any = null

            if (cleanSummary && dateStr) {
              const { data: matchedApp } = await supabaseClient
                .from('appointments')
                .select('id, title')
                .is('googleEventId', null)
                .eq('date', dateStr)
                .ilike('title', `%${cleanSummary.substring(0, 30)}%`)
                .limit(1)
                .maybeSingle()
              existingMatch = matchedApp
            }

            if (existingMatch) {
              // Vincula o googleEventId ao compromisso do sistema existente
              await supabaseClient
                .from('appointments')
                .update({ googleEventId: gEvent.id })
                .eq('id', existingMatch.id)
              syncedAppointments.push({ id: existingMatch.id, action: 'linked' })
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
        }
      }

      // 2. Exporta compromissos do DPSjur para o Google Calendar
      // Busca todos os appointments sem googleEventId diretamente do banco (fonte de verdade)
      // e une com a lista opcional passada no payload da requisição
      const pendingToExport: any[] = []
      const seenAppIds = new Set<string>()

      if (supabaseClient) {
        try {
          const { data: dbPending, error: dbErr } = await supabaseClient
            .from('appointments')
            .select(
              'id, title, description, date, time, modality, type, clientId, processId, googleEventId',
            )
            .is('googleEventId', null)

          if (!dbErr && Array.isArray(dbPending)) {
            for (const app of dbPending) {
              if (app.id && !seenAppIds.has(app.id)) {
                seenAppIds.add(app.id)
                pendingToExport.push(app)
              }
            }
          }
        } catch (fetchErr) {
          console.warn('Erro ao consultar appointments pendentes no banco:', fetchErr)
        }
      }

      // Inclui também os compromissos enviados pelo frontend que possam não ter googleEventId
      if (Array.isArray(appointments)) {
        for (const app of appointments) {
          if (!app.googleEventId && app.title && app.date) {
            const appId = app.id || `${app.title}-${app.date}-${app.time}`
            if (!seenAppIds.has(appId)) {
              seenAppIds.add(appId)
              pendingToExport.push(app)
            }
          }
        }
      }

      // Busca dados complementares de clientes para enriquecer a descrição e título no Google
      const clientNameMap = new Map<string, string>()
      if (supabaseClient && pendingToExport.some((a) => a.clientId)) {
        try {
          const clientIds = Array.from(
            new Set(pendingToExport.map((a) => a.clientId).filter(Boolean)),
          )
          if (clientIds.length > 0) {
            const { data: clientsData } = await supabaseClient
              .from('clients')
              .select('id, name')
              .in('id', clientIds)
            if (Array.isArray(clientsData)) {
              for (const c of clientsData) {
                clientNameMap.set(c.id, c.name)
              }
            }
          }
        } catch {
          // fallback silencioso
        }
      }

      let exportedCount = 0
      const exportErrors: string[] = []

      for (const app of pendingToExport) {
        if (!app.title || !app.date) continue

        try {
          const timeClean = (app.time || '09:00').trim()
          const timePart = timeClean.length === 5 ? `${timeClean}:00` : timeClean
          const cleanDate = app.date.split('T')[0]

          // Monta o timestamp ISO com fuso horário de Brasília (UTC-3)
          const startDateTime = `${cleanDate}T${timePart}`
          const startDate = new Date(startDateTime)
          const endDate = !isNaN(startDate.getTime())
            ? new Date(startDate.getTime() + 60 * 60 * 1000)
            : new Date()
          const endTimePart = !isNaN(endDate.getTime())
            ? endDate.toTimeString().split(' ')[0]
            : '10:00:00'
          const endDateTime = `${cleanDate}T${endTimePart}`

          // Enriquece título com nome do cliente se não estiver presente
          const clientName = clientNameMap.get(app.clientId) || ''
          let summary = app.title
          if (clientName && !summary.toLowerCase().includes(clientName.toLowerCase())) {
            summary = `${summary} - ${clientName}`
          }

          // Monta descrição com detalhes do processo/sistema
          const descParts: string[] = []
          if (app.description) descParts.push(app.description)
          if (app.type) descParts.push(`Tipo: ${app.type}`)
          if (app.modality) descParts.push(`Modalidade: ${app.modality}`)
          if (clientName) descParts.push(`Cliente: ${clientName}`)
          descParts.push('Sincronizado via DPSjur')
          const descriptionText = descParts.join('\n')

          const postRes = await fetchGoogleApi(
            'https://www.googleapis.com/calendar/v3/calendars/primary/events',
            {
              method: 'POST',
              body: JSON.stringify({
                summary,
                description: descriptionText,
                location:
                  app.location || (app.modality === 'Virtual' ? 'Online / Videoconferência' : ''),
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
            if (createdGEvent?.id) {
              exportedCount++
              if (app.id && supabaseClient) {
                await supabaseClient
                  .from('appointments')
                  .update({ googleEventId: createdGEvent.id })
                  .eq('id', app.id)
              }
            }
          } else {
            const errData = await postRes.json().catch(() => ({}))
            console.error(`Erro ao criar evento "${app.title}" no Google:`, errData)
            if (exportErrors.length < 3) {
              exportErrors.push(errData?.error?.message || `HTTP ${postRes.status}`)
            }
          }
        } catch (e: any) {
          console.error(`Falha ao exportar compromisso "${app.title}" para Google:`, e)
          if (exportErrors.length < 3) {
            exportErrors.push(e?.message || 'Falha de rede')
          }
        }
      }

      const summaryMessage =
        exportedCount > 0 || syncedAppointments.length > 0
          ? `Sincronização concluída: ${exportedCount} evento(s) enviado(s) ao Google e ${syncedAppointments.length} harmonizado(s) no sistema.`
          : 'Sincronização concluída: a agenda do DPSjur e o Google Calendar já estão em harmonia.'

      return new Response(
        JSON.stringify({
          success: true,
          message: summaryMessage,
          importedFromGoogle: syncedAppointments.length,
          exportedToGoogle: exportedCount,
          pendingTotal: pendingToExport.length,
          totalGoogleEvents: googleEvents.length,
          errors: exportErrors.length > 0 ? exportErrors : undefined,
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
    if (action === 'create_event' || action === 'createEvent') {
      if (!appointment) {
        return new Response(
          JSON.stringify({ success: false, error: 'Dados do compromisso ausentes' }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
          },
        )
      }

      const timeClean = (appointment.time || '09:00').trim()
      const timePart = timeClean.length === 5 ? `${timeClean}:00` : timeClean
      const cleanDate = (appointment.date || '').split('T')[0]
      const startDateTime = `${cleanDate}T${timePart}`
      const startDate = new Date(startDateTime)
      const endDate = !isNaN(startDate.getTime())
        ? new Date(startDate.getTime() + 60 * 60 * 1000)
        : new Date()
      const endTimePart = !isNaN(endDate.getTime())
        ? endDate.toTimeString().split(' ')[0]
        : '10:00:00'
      const endDateTime = `${cleanDate}T${endTimePart}`

      const gRes = await fetchGoogleApi(
        'https://www.googleapis.com/calendar/v3/calendars/primary/events',
        {
          method: 'POST',
          body: JSON.stringify({
            summary: appointment.title,
            description: appointment.description || '',
            location:
              appointment.location ||
              (appointment.modality === 'Virtual' ? 'Online / Videoconferência' : ''),
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

      if (appointment.id && gEvent.id && supabaseClient) {
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
    if (action === 'update_event' || action === 'updateEvent') {
      const gEventId = appointment?.googleEventId || body.eventId

      if (!appointment || !gEventId) {
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

      const timeClean = (appointment.time || '09:00').trim()
      const timePart = timeClean.length === 5 ? `${timeClean}:00` : timeClean
      const cleanDate = (appointment.date || '').split('T')[0]
      const startDateTime = `${cleanDate}T${timePart}`
      const startDate = new Date(startDateTime)
      const endDate = !isNaN(startDate.getTime())
        ? new Date(startDate.getTime() + 60 * 60 * 1000)
        : new Date()
      const endTimePart = !isNaN(endDate.getTime())
        ? endDate.toTimeString().split(' ')[0]
        : '10:00:00'
      const endDateTime = `${cleanDate}T${endTimePart}`

      const gRes = await fetchGoogleApi(
        `https://www.googleapis.com/calendar/v3/calendars/primary/events/${encodeURIComponent(
          gEventId,
        )}`,
        {
          method: 'PATCH',
          body: JSON.stringify({
            summary: appointment.title,
            description: appointment.description || '',
            location:
              appointment.location ||
              (appointment.modality === 'Virtual' ? 'Online / Videoconferência' : ''),
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
    // Suporta tanto 'delete_event' quanto 'deleteEvent' (e eventId direto)
    // ----------------------------------------------------
    if (action === 'delete_event' || action === 'deleteEvent') {
      const gEventId = appointment?.googleEventId || body.eventId

      if (!gEventId) {
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
          gEventId,
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
