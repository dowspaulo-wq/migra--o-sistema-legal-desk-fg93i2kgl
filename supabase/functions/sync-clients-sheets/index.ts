import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'jsr:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, x-supabase-client-platform, apikey, content-type',
}

// ID padrão da planilha indicado pelo usuário
const SPREADSHEET_ID = '181rftkYO4nVnAVsc-mKuYjBqDsm-_YnoiGWtEqf2Ahw'
const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token'
const GOOGLE_SHEETS_BASE_URL = 'https://sheets.googleapis.com/v4/spreadsheets'
const SHEETS_SCOPE = 'https://www.googleapis.com/auth/spreadsheets'

interface ServiceAccountKey {
  client_email: string
  private_key: string
  project_id?: string
  private_key_id?: string
  type?: string
}

// ============================================================================
// Utilitários de Criptografia WebCrypto (RS256 JWT para Google Service Account)
// ============================================================================

function arrayBufferToBase64Url(buffer: ArrayBuffer | Uint8Array): string {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer)
  let binary = ''
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i])
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function stringToBase64Url(str: string): string {
  const bytes = new TextEncoder().encode(str)
  return arrayBufferToBase64Url(bytes)
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const cleanPem = pem
    .replace(/-----BEGIN[A-Z\s]+-----/g, '')
    .replace(/-----END[A-Z\s]+-----/g, '')
    .replace(/[\r\n\s]/g, '')

  const binaryString = atob(cleanPem)
  const bytes = new Uint8Array(binaryString.length)
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i)
  }
  return bytes.buffer
}

async function signJwtRs256(serviceAccount: ServiceAccountKey): Promise<string> {
  const header = {
    alg: 'RS256',
    typ: 'JWT',
    kid: serviceAccount.private_key_id,
  }

  const nowSec = Math.floor(Date.now() / 1000)
  const payload = {
    iss: serviceAccount.client_email,
    scope: SHEETS_SCOPE,
    aud: GOOGLE_TOKEN_URL,
    iat: nowSec,
    exp: nowSec + 3600, // 1 hora de validade
  }

  const encodedHeader = stringToBase64Url(JSON.stringify(header))
  const encodedPayload = stringToBase64Url(JSON.stringify(payload))
  const unsignedToken = `${encodedHeader}.${encodedPayload}`

  const binaryDer = pemToArrayBuffer(serviceAccount.private_key)

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryDer,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: { name: 'SHA-256' },
    },
    false,
    ['sign'],
  )

  const signatureBuffer = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(unsignedToken),
  )

  const encodedSignature = arrayBufferToBase64Url(signatureBuffer)
  return `${unsignedToken}.${encodedSignature}`
}

async function getGoogleAccessToken(serviceAccount: ServiceAccountKey): Promise<string> {
  const jwt = await signJwtRs256(serviceAccount)

  const params = new URLSearchParams()
  params.append('grant_type', 'urn:ietf:params:oauth:grant-type:jwt-bearer')
  params.append('assertion', jwt)

  const res = await fetch(GOOGLE_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params.toString(),
  })

  if (!res.ok) {
    const errorText = await res.text()
    console.error('Falha ao autenticar com Google OAuth:', errorText)
    throw new Error(
      `Falha na autenticação da Service Account no Google OAuth (${res.status}): ${errorText}`,
    )
  }

  const data = await res.json()
  return data.access_token
}

// ============================================================================
// Normalização conforme regras do usuário
// ============================================================================

function normalizeEmail(email: string | null | undefined): string {
  if (!email) return ''
  const trimmed = email.trim().toLowerCase()
  if (trimmed === 'n/a' || trimmed === 'na' || trimmed === 'sem email') return ''
  return trimmed
}

function normalizeBirthday(birthday: string | null | undefined): string {
  if (!birthday) return ''
  const trimmed = birthday.trim()
  if (!trimmed || trimmed === '0001-01-01' || trimmed.startsWith('0001-')) {
    return ''
  }

  // Se já for YYYY-MM-DD
  if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
    const [year, month, day] = trimmed.split('-').map(Number)
    if (year < 1900 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) {
      return ''
    }
    return trimmed
  }

  // Se for DD/MM/YYYY
  if (/^\d{2}\/\d{2}\/\d{4}$/.test(trimmed)) {
    const [day, month, year] = trimmed.split('/')
    const yNum = Number(year)
    const mNum = Number(month)
    const dNum = Number(day)
    if (yNum < 1900 || yNum > 2100 || mNum < 1 || mNum > 12 || dNum < 1 || dNum > 31) {
      return ''
    }
    return `${year}-${month}-${day}`
  }

  return ''
}

function normalizePhone(phone: string | null | undefined): string {
  // Replicar como está, sem alteração de formatação conforme pedido expresso do usuário
  if (phone === null || phone === undefined) return ''
  return String(phone).trim()
}

function getBrasiliaIsoDateString(): string {
  // Formata data e hora no fuso de Brasília (UTC-3)
  const d = new Date()
  const brasiliaDate = new Date(d.getTime() - 3 * 3600 * 1000)
  return brasiliaDate.toISOString().replace('Z', '-03:00').substring(0, 19).replace('T', ' ')
}

// ============================================================================
// Handler principal da Edge Function
// ============================================================================

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method === 'GET') {
    return new Response(
      JSON.stringify({
        status: 'online',
        service: 'sync-clients-sheets',
        message: 'Endpoint de espelhamento de clientes com Google Sheets ativo.',
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 },
    )
  }

  const syncStartTime = new Date()

  try {
    const supabaseUrl =
      Deno.env.get('SUPABASE_URL') || Deno.env.get('SUPABASE_INTERNAL_URL') || 'http://kong:8000'
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') || ''
    const supabaseKey = serviceRoleKey || anonKey

    if (!supabaseUrl || !supabaseKey) {
      throw new Error('Configuração do Supabase incompleta (SUPABASE_URL ou chaves ausentes).')
    }

    const supabase = createClient(supabaseUrl, supabaseKey, {
      auth: { persistSession: false },
    })

    // 1. Obter Service Account JSON (settings -> env GOOGLE_SERVICE_ACCOUNT_JSON)
    let serviceAccountRaw: string | null = null

    try {
      const { data: dbSettings, error: settErr } = await supabase
        .from('settings')
        .select('googleServiceAccount')
        .limit(1)
        .maybeSingle()

      if (!settErr && dbSettings && (dbSettings as any).googleServiceAccount) {
        serviceAccountRaw = String((dbSettings as any).googleServiceAccount).trim()
      }
    } catch (settReadErr) {
      console.warn('Erro ao ler googleServiceAccount da tabela settings:', settReadErr)
    }

    if (!serviceAccountRaw) {
      serviceAccountRaw = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_JSON')?.trim() || null
    }

    if (!serviceAccountRaw) {
      const friendlyGuide =
        'Google Service Account (JSON) não configurada.\n' +
        'Para ativar o espelhamento de clientes no Google Sheets:\n' +
        '1. Acesse o Google Cloud Console e crie uma Service Account.\n' +
        '2. Ative a "Google Sheets API" no seu projeto do Google Cloud.\n' +
        '3. Crie uma chave JSON para a Service Account e baixe o arquivo.\n' +
        '4. Abra a planilha (ID: 181rftkYO4nVnAVsc-mKuYjBqDsm-_YnoiGWtEqf2Ahw) e compartilhe-a com o e-mail da Service Account (client_email) com permissão de "Editor".\n' +
        '5. Acesse Configurações → Integrações no DPSjur/SBJur, cole o JSON completo no campo "Google Service Account (JSON)" e salve.'

      return new Response(
        JSON.stringify({
          success: false,
          error: friendlyGuide,
          missingCredentials: true,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      )
    }

    let serviceAccount: ServiceAccountKey
    try {
      serviceAccount = JSON.parse(serviceAccountRaw)
      if (!serviceAccount.client_email || !serviceAccount.private_key) {
        throw new Error('Campos "client_email" e "private_key" são obrigatórios no JSON.')
      }
    } catch (parseErr: any) {
      return new Response(
        JSON.stringify({
          success: false,
          error: `O JSON da Service Account configurado é inválido: ${parseErr.message}. Cole o arquivo JSON completo gerado pelo Google Cloud em Configurações → Integrações.`,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      )
    }

    // 2. Trocar JWT por access_token do Google
    let accessToken: string
    try {
      accessToken = await getGoogleAccessToken(serviceAccount)
    } catch (authErr: any) {
      return new Response(
        JSON.stringify({
          success: false,
          error: `Falha ao autenticar Service Account no Google: ${authErr.message}. Verifique se a private_key e o client_email do JSON estão corretos e válidos.`,
        }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      )
    }

    // 3. Obter metadados da planilha para identificar a primeira aba (aba "Página1" ou primeira aba física)
    const metadataRes = await fetch(
      `${GOOGLE_SHEETS_BASE_URL}/${SPREADSHEET_ID}?fields=sheets.properties`,
      {
        method: 'GET',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
      },
    )

    if (!metadataRes.ok) {
      const errText = await metadataRes.text()
      console.error('Erro ao acessar metadados da planilha:', metadataRes.status, errText)

      let friendlyMsg = `Erro ao acessar planilha do Google (${metadataRes.status}): ${errText}`
      if (metadataRes.status === 404) {
        friendlyMsg = `Planilha não encontrada (ID: ${SPREADSHEET_ID}). Verifique se o ID está correto.`
      } else if (metadataRes.status === 403) {
        friendlyMsg =
          `Permissão negada (403). Certifique-se de:\n` +
          `1. Ter ativado a "Google Sheets API" no Google Cloud Console.\n` +
          `2. Ter compartilhado a planilha (ID: ${SPREADSHEET_ID}) com o e-mail da Service Account (${serviceAccount.client_email}) concedendo a permissão "Editor".`
      }

      return new Response(
        JSON.stringify({
          success: false,
          error: friendlyMsg,
          googleStatus: metadataRes.status,
        }),
        {
          status: metadataRes.status === 403 ? 403 : 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      )
    }

    const metadata = await metadataRes.json()
    const sheetsList = metadata.sheets || []
    if (sheetsList.length === 0) {
      throw new Error('A planilha informada não possui nenhuma aba.')
    }

    // Procura aba com título "Página1" ou "Pagina1", senão pega a primeira aba existente
    let targetSheet = sheetsList.find(
      (s: any) =>
        s.properties?.title === 'Página1' ||
        s.properties?.title === 'Pagina1' ||
        s.properties?.title === 'Sheet1',
    )
    if (!targetSheet) {
      targetSheet = sheetsList[0]
    }

    const sheetTitle = targetSheet.properties.title
    const sheetId = targetSheet.properties.sheetId // ID numérico da aba (gid)

    // 4. Ler clientes do banco de dados (SOMENTE SELECT em clients, TODOS os clientes, sem filtro)
    // O pedido expressamente manda não escrever no banco, apenas ler.
    const { data: dbClients, error: clientsErr } = await supabase
      .from('clients')
      .select('id, name, email, phone, birthday')
      .order('name', { ascending: true })

    if (clientsErr) {
      throw new Error(`Erro ao ler clientes do banco de dados: ${clientsErr.message}`)
    }

    const totalClientsInDb = dbClients?.length || 0

    // 5. Ler linhas atuais da aba na planilha (colunas A até F)
    const readRange = `'${sheetTitle}'!A:F`
    const sheetValuesRes = await fetch(
      `${GOOGLE_SHEETS_BASE_URL}/${SPREADSHEET_ID}/values/${encodeURIComponent(readRange)}`,
      {
        method: 'GET',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
      },
    )

    if (!sheetValuesRes.ok) {
      const errText = await sheetValuesRes.text()
      throw new Error(`Erro ao ler valores da aba "${sheetTitle}": ${errText}`)
    }

    const sheetValuesData = await sheetValuesRes.json()
    const existingRows: any[][] = sheetValuesData.values || []

    const header = [
      'ID do cliente',
      'Nome',
      'Email',
      'Telefone',
      'Aniversário',
      'Data da última atualização',
    ]

    const nowBrasilia = getBrasiliaIsoDateString()

    // 6. Analisar estrutura da aba: verificar cabeçalho
    // Se a aba estiver totalmente vazia (0 linhas), gravamos o cabeçalho na linha 1
    const needsHeader = existingRows.length === 0
    if (needsHeader) {
      await fetch(
        `${GOOGLE_SHEETS_BASE_URL}/${SPREADSHEET_ID}/values/'${encodeURIComponent(sheetTitle)}'!A1:F1?valueInputOption=USER_ENTERED`,
        {
          method: 'PUT',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            range: `'${sheetTitle}'!A1:F1`,
            values: [header],
          }),
        },
      )
    }

    // Mapa de linhas existentes na planilha indexadas pelo ID do cliente (coluna A)
    // linha 1 é cabeçalho (índice 0 nos arrays se existir).
    // Linha física na planilha = rowIndex + 1 (1-based).
    interface SheetRowItem {
      rowIndex: number // 0-based no array existingRows
      sheetRowNum: number // 1-based na planilha
      id: string
      name: string
      email: string
      phone: string
      birthday: string
      updatedAt: string
    }

    const sheetRowsByClientId = new Map<string, SheetRowItem>()
    const extraRowsToDelete: number[] = [] // Linhas de clientes que não existem mais no banco (0-based)

    const startIndex = existingRows.length > 0 ? 1 : 0 // pula cabeçalho se houver linha 0

    for (let i = startIndex; i < existingRows.length; i++) {
      const row = existingRows[i]
      const rawId = row[0] ? String(row[0]).trim() : ''
      if (!rawId) {
        // Linha em branco ou sem ID no meio da planilha
        continue
      }

      sheetRowsByClientId.set(rawId, {
        rowIndex: i,
        sheetRowNum: i + 1,
        id: rawId,
        name: row[1] ? String(row[1]) : '',
        email: row[2] ? String(row[2]) : '',
        phone: row[3] ? String(row[3]) : '',
        birthday: row[4] ? String(row[4]) : '',
        updatedAt: row[5] ? String(row[5]) : '',
      })
    }

    // Mapeia clientes do banco por ID
    const dbClientsMap = new Map<string, any>()
    for (const c of dbClients || []) {
      if (c.id) dbClientsMap.set(String(c.id), c)
    }

    // 7. Identificar linhas que precisam ser removidas (cliente removido da base → remove linha)
    for (const [sheetClientId, sheetItem] of sheetRowsByClientId.entries()) {
      if (!dbClientsMap.has(sheetClientId)) {
        extraRowsToDelete.push(sheetItem.rowIndex)
      }
    }

    // 8. Comparar e preparar:
    // (a) Clientes novos → acrescenta linha
    // (b) Clientes existentes com dado alterado (B-E) → atualiza linha e coluna F
    const rowsToAppend: any[][] = []
    const batchUpdateValueData: { range: string; values: any[][] }[] = []

    let insertedCount = 0
    let updatedCount = 0
    let unchangedCount = 0

    for (const client of dbClients || []) {
      const clientId = String(client.id)
      const normName = client.name ? String(client.name).trim() : ''
      const normEmail = normalizeEmail(client.email)
      const normPhone = normalizePhone(client.phone)
      const normBirthday = normalizeBirthday(client.birthday)

      const existingSheetRow = sheetRowsByClientId.get(clientId)

      if (!existingSheetRow) {
        // Cliente NOVO → acrescenta linha
        rowsToAppend.push([clientId, normName, normEmail, normPhone, normBirthday, nowBrasilia])
        insertedCount++
      } else {
        // Cliente EXISTENTE → verifica se houve alteração nos campos B a E
        const isChanged =
          existingSheetRow.name !== normName ||
          existingSheetRow.email !== normEmail ||
          existingSheetRow.phone !== normPhone ||
          existingSheetRow.birthday !== normBirthday

        if (isChanged) {
          // Atualiza a linha e a coluna F (data/hora da última atualização)
          batchUpdateValueData.push({
            range: `'${sheetTitle}'!A${existingSheetRow.sheetRowNum}:F${existingSheetRow.sheetRowNum}`,
            values: [[clientId, normName, normEmail, normPhone, normBirthday, nowBrasilia]],
          })
          updatedCount++
        } else {
          unchangedCount++
        }
      }
    }

    // 9. Executar atualizações de valores existentes (batchUpdate values)
    if (batchUpdateValueData.length > 0) {
      // Divide em lotes de 200 para segurança de payload
      const chunkSize = 200
      for (let i = 0; i < batchUpdateValueData.length; i += chunkSize) {
        const chunk = batchUpdateValueData.slice(i, i + chunkSize)
        const updateRes = await fetch(
          `${GOOGLE_SHEETS_BASE_URL}/${SPREADSHEET_ID}/values:batchUpdate`,
          {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${accessToken}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              valueInputOption: 'USER_ENTERED',
              data: chunk,
            }),
          },
        )

        if (!updateRes.ok) {
          const errText = await updateRes.text()
          throw new Error(`Erro ao atualizar linhas na planilha: ${errText}`)
        }
      }
    }

    // 10. Executar inserção de novos clientes (append values)
    if (rowsToAppend.length > 0) {
      const appendRes = await fetch(
        `${GOOGLE_SHEETS_BASE_URL}/${SPREADSHEET_ID}/values/'${encodeURIComponent(sheetTitle)}'!A:F:append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            range: `'${sheetTitle}'!A:F`,
            values: rowsToAppend,
          }),
        },
      )

      if (!appendRes.ok) {
        const errText = await appendRes.text()
        throw new Error(`Erro ao inserir novas linhas na planilha: ${errText}`)
      }
    }

    // 11. Executar remoção de linhas de clientes excluídos do banco (deleteDimension)
    // CRÍTICO: Deletar da MAIOR linha para a MENOR para não invalidar os índices das linhas anteriores
    let removedCount = 0
    if (extraRowsToDelete.length > 0) {
      extraRowsToDelete.sort((a, b) => b - a) // decrescente

      const deleteRequests = extraRowsToDelete.map((rowIdx) => ({
        deleteDimension: {
          range: {
            sheetId: sheetId,
            dimension: 'ROWS',
            startIndex: rowIdx,
            endIndex: rowIdx + 1,
          },
        },
      }))

      // Executa em lotes de 100 requests por batchUpdate
      const deleteChunkSize = 100
      for (let i = 0; i < deleteRequests.length; i += deleteChunkSize) {
        const chunk = deleteRequests.slice(i, i + deleteChunkSize)
        const delRes = await fetch(`${GOOGLE_SHEETS_BASE_URL}/${SPREADSHEET_ID}:batchUpdate`, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            requests: chunk,
          }),
        })

        if (!delRes.ok) {
          const errText = await delRes.text()
          throw new Error(`Erro ao remover linhas excluídas na planilha: ${errText}`)
        }
      }
      removedCount = extraRowsToDelete.length
    }

    const durationMs = Date.now() - syncStartTime.getTime()

    // 12. Registrar log simples (stdout da edge function + resposta JSON)
    const logSummary = {
      timestamp: nowBrasilia,
      spreadsheetId: SPREADSHEET_ID,
      sheetTitle: sheetTitle,
      totalProcessed: totalClientsInDb,
      inserted: insertedCount,
      updated: updatedCount,
      unchanged: unchangedCount,
      removed: removedCount,
      durationMs: durationMs,
    }

    console.log(
      `[SHEETS-MIRROR-SYNC] Sincronização concluída com sucesso em ${durationMs}ms | ` +
        `Total base: ${totalClientsInDb} | +${insertedCount} novos | ~${updatedCount} atualizados | ` +
        `=${unchangedCount} inalterados | -${removedCount} removidos`,
    )

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Espelhamento de clientes com Google Sheets concluído com sucesso.',
        ...logSummary,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    )
  } catch (err: any) {
    console.error('[SHEETS-MIRROR-SYNC] Erro durante o espelhamento:', err)
    return new Response(
      JSON.stringify({
        success: false,
        error: err.message || 'Erro inesperado ao sincronizar com Google Sheets.',
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    )
  }
})
