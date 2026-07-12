import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'jsr:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, x-supabase-client-platform, apikey, content-type',
}

const DATAJUD_BASE_URL = 'https://api-publica.datajud.cnj.jus.br/api_publica'

function isValidCNJ(number: string): boolean {
  const clean = (number || '').replace(/[.\-_ ]/g, '')
  return /^\d{20}$/.test(clean)
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !supabaseKey) {
      throw new Error('Variáveis de ambiente do Supabase não configuradas.')
    }

    const supabase = createClient(supabaseUrl, supabaseKey)
    const { number, caseId } = await req.json()

    if (!number || !isValidCNJ(number)) {
      throw new Error('Número de processo inválido. Formato esperado: NNNNNNN-DD.YYYY.J.TR.OOOO')
    }

    const cleanNumber = number.replace(/[.\-_ ]/g, '')

    const apiKey = Deno.env.get('DATAJUD_API_KEY') || 'ApiKey c0616f5a-7b12-43ea-8b6f-f8b4a4e7b7c0'

    const tribunalMap: Record<string, string> = {
      '8.26': 'TJSP',
      '8.02': 'TJAC',
      '8.01': 'TJAL',
      '8.03': 'TJAP',
      '8.04': 'TJAM',
      '8.05': 'TJBA',
      '8.06': 'TJCE',
      '8.07': 'TJDF',
      '8.08': 'TJES',
      '8.09': 'TJGO',
      '8.10': 'TJMA',
      '8.11': 'TJMT',
      '8.12': 'TJMS',
      '8.13': 'TJMG',
      '8.14': 'TJPA',
      '8.15': 'TJPB',
      '8.16': 'TJPR',
      '8.17': 'TJPE',
      '8.18': 'TJPI',
      '8.19': 'TJRJ',
      '8.20': 'TJRN',
      '8.21': 'TJRS',
      '8.22': 'TJRO',
      '8.23': 'TJRR',
      '8.24': 'TJSC',
      '8.25': 'TJSE',
      '8.27': 'TJTO',
    }

    const segment = cleanNumber.substring(13, 14)
    const tribunalCode = cleanNumber.substring(11, 14)
    const tribId = `${segment}.${tribunalCode}`
    const tribunalEndpoint = tribunalMap[tribId] || `TJ${tribunalCode.substring(1)}`

    const res = await fetch(`${DATAJUD_BASE_URL}/${tribunalEndpoint}/_search`, {
      method: 'POST',
      headers: {
        Authorization: apiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        query: {
          match: {
            numeroProcesso: cleanNumber,
          },
        },
        size: 1,
      }),
    })

    if (!res.ok) {
      const errText = await res.text().catch(() => '')
      throw new Error(`Erro ao consultar DataJud (${res.status}): ${errText || res.statusText}`)
    }

    const result = await res.json()
    const hits = result?.hits?.hits || []
    const source = hits[0]?._source || null

    if (!source) {
      const emptyUpdate: any = {
        last_sync_at: new Date().toISOString(),
        court_details: { not_found: true, queried_at: new Date().toISOString() },
      }

      if (caseId) {
        await supabase.from('cases').update(emptyUpdate).eq('id', caseId)
      }

      return new Response(
        JSON.stringify({
          success: true,
          found: false,
          message: 'Processo não encontrado no DataJud.',
          last_sync_at: emptyUpdate.last_sync_at,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const movimentos = source.movimentos || []
    const lastMovimento = movimentos.length > 0 ? movimentos[movimentos.length - 1] : null

    let lastMovementText = ''
    if (lastMovimento) {
      const nomeMov = lastMovimento.nome || ''
      const dataHora = lastMovimento.dataHora || ''
      const dateStr = dataHora ? new Date(dataHora).toLocaleDateString('pt-BR') : ''
      lastMovementText = [nomeMov, dateStr].filter(Boolean).join(' - ')
    }

    const statusFromDataJud = source.codigoClasse || source.assuntos?.[0]?.codigo || ''

    const updateData: any = {
      last_movement: lastMovementText || source.ultimoMovimento || '',
      last_sync_at: new Date().toISOString(),
      court_details: {
        classe: source.classe || null,
        codigoClasse: source.codigoClasse || null,
        assuntos: source.assuntos || [],
        orgaoJulgador: source.orgaoJulgador || null,
        sistema: source.sistema || null,
        formato: source.formato || null,
        nivelSigilo: source.nivelSigilo || null,
        dataAjuizamento: source.dataAjuizamento || null,
        movimentosCount: movimentos.length,
        movimentos: movimentos.slice(-10),
        queried_at: new Date().toISOString(),
      },
    }

    if (caseId) {
      await supabase.from('cases').update(updateData).eq('id', caseId)
    }

    return new Response(
      JSON.stringify({
        success: true,
        found: true,
        last_movement: updateData.last_movement,
        last_sync_at: updateData.last_sync_at,
        court_details: updateData.court_details,
        statusHint: statusFromDataJud,
        message: 'Movimentações sincronizadas com sucesso.',
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (error: any) {
    console.error('DataJud Sync Error:', error.message || error)
    return new Response(
      JSON.stringify({ success: false, error: error.message || 'Erro interno' }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    )
  }
})
