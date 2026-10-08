import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'jsr:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, x-supabase-client-platform, apikey, content-type, x-asaas-webhook-token, x-asaas-api-key, x-asaas-api-url, asaas-access-token',
}

// Mapeamento abrangente de eventos de cobrança do Asaas para status do sistema DPSjur
const EVENT_STATUS_MAP: Record<string, string> = {
  PAYMENT_CONFIRMED: 'Paga',
  PAYMENT_RECEIVED: 'Paga',
  PAYMENT_OVERDUE: 'Vencida',
  PAYMENT_DELETED: 'Cancelada',
  PAYMENT_REFUNDED: 'Estornada',
  PAYMENT_CHARGEBACK_REQUESTED: 'Vencida',
  PAYMENT_CHARGEBACK_DISPUTE: 'Vencida',
  PAYMENT_AWAITING_RISK_ANALYSIS: 'Previsto',
  PAYMENT_APPROVED_BY_RISK_ANALYSIS: 'Previsto',
  PAYMENT_REPROVED_BY_RISK_ANALYSIS: 'Cancelada',
  PAYMENT_RESTORED: 'Previsto',
  PAYMENT_UPDATED: 'Previsto',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // GET de healthcheck amigável para navegador / monitoramento
  if (req.method === 'GET') {
    return new Response(
      JSON.stringify({
        status: 'online',
        service: 'asaas-webhook',
        message: 'Endpoint de webhook do Asaas ativo e pronto para receber notificações POST.',
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 },
    )
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !supabaseKey) {
      throw new Error(
        'Variáveis de ambiente do Supabase não configuradas (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY).',
      )
    }

    const supabase = createClient(supabaseUrl, supabaseKey)

    // 1. Ler credenciais do Asaas da tabela settings (com fallback para env local)
    // No VPS self-hosted via EasyPanel, variáveis .env não são injetadas no contêiner edge-runtime,
    // então a fonte primária é a tabela settings no PostgreSQL local.
    let asaasApiKeyFromDb: string | null = null
    let asaasApiUrlFromDb: string = 'https://api.asaas.com/v3'
    try {
      const { data: dbSettings } = await supabase
        .from('settings')
        .select('asaasApiKey, asaasApiUrl')
        .limit(1)
        .maybeSingle()
      if (dbSettings) {
        asaasApiKeyFromDb = (dbSettings as any).asaasApiKey || null
        if ((dbSettings as any).asaasApiUrl) {
          asaasApiUrlFromDb = String((dbSettings as any).asaasApiUrl)
            .trim()
            .replace(/\/+$/, '')
        }
      }
    } catch (settErr) {
      console.warn('Não foi possível ler asaasApiKey da tabela settings:', settErr)
    }

    const effectiveApiKey =
      req.headers.get('x-asaas-api-key')?.trim() ||
      Deno.env.get('ASAAS_API_KEY')?.trim() ||
      asaasApiKeyFromDb

    const effectiveApiUrl =
      req.headers.get('x-asaas-api-url')?.trim()?.replace(/\/+$/, '') ||
      Deno.env.get('ASAAS_API_URL')?.trim()?.replace(/\/+$/, '') ||
      asaasApiUrlFromDb ||
      'https://api.asaas.com/v3'

    // 2. Validação de Token de Segurança do Webhook (se configurado)
    // O Asaas permite configurar uma "Fila de sincronização" com Token de autenticação.
    // O token pode vir no header asaas-access-token, x-asaas-webhook-token ou query param ?token=
    const expectedToken =
      Deno.env.get('ASAAS_WEBHOOK_TOKEN')?.trim() ||
      Deno.env.get('ASSAS_WEBHOOK_TOKEN')?.trim() ||
      null

    if (expectedToken) {
      const urlObj = new URL(req.url)
      const receivedToken =
        req.headers.get('asaas-access-token')?.trim() ||
        req.headers.get('x-asaas-webhook-token')?.trim() ||
        urlObj.searchParams.get('token')?.trim() ||
        ''

      if (receivedToken !== expectedToken) {
        console.warn('Webhook rejeitado: Token de autenticação inválido ou ausente.')
        // Responde 401 quando o token é estritamente exigido e diverge
        return new Response(
          JSON.stringify({
            error: 'Token de webhook inválido.',
            hint: 'Configure o mesmo token no painel do Asaas ou na URL ?token=...',
          }),
          {
            status: 401,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          },
        )
      }
    }

    // 3. Parse seguro do Payload do Asaas
    const payload = await req.json().catch(() => null)
    if (!payload || typeof payload !== 'object') {
      return new Response(
        JSON.stringify({ success: true, message: 'Payload vazio ou inválido. Ignorado.' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 },
      )
    }

    const eventType: string = String(payload.event || '').trim()
    const payment = payload.payment || {}
    const asaasPaymentId: string = String(payment.id || '').trim()

    // Se for evento de ping/teste de webhook disparado pelo painel do Asaas
    if (eventType === 'WEBHOOK_TEST' || eventType === 'PING' || payload.test === true) {
      return new Response(
        JSON.stringify({
          success: true,
          message: 'Webhook de teste recebido com sucesso!',
          timestamp: new Date().toISOString(),
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 },
      )
    }

    if (!asaasPaymentId) {
      return new Response(
        JSON.stringify({
          success: true,
          message: `Webhook recebido sem ID de cobrança (evento: ${eventType || 'desconhecido'}). Ignorado sem erro.`,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 },
      )
    }

    const targetStatus = EVENT_STATUS_MAP[eventType]
    if (!targetStatus) {
      // Evento desconhecido ou não relevante para financeiro: responder 200 e ignorar
      console.log(
        `Evento Asaas ignorado (não altera status financeiro): ${eventType} (${asaasPaymentId})`,
      )
      return new Response(
        JSON.stringify({
          success: true,
          message: `Evento '${eventType}' recebido e ignorado com sucesso (não requer alteração no sistema).`,
          asaas_id: asaasPaymentId,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 },
      )
    }

    // 4. Localizar a transação no banco de dados
    const { data: existingTx, error: txErr } = await supabase
      .from('transactions')
      .select('id, status, asaas_id, amount, date, bankAccount, clientId, description')
      .eq('asaas_id', asaasPaymentId)
      .maybeSingle()

    if (txErr) {
      console.error('Erro ao consultar transação por asaas_id:', txErr.message)
    }

    if (!existingTx) {
      // Não temos essa cobrança cadastrada no sistema ainda.
      // Pode ser cobrança gerada avulsa fora do SBJur. Registra log para auditoria e responde 200.
      await supabase
        .from('logs')
        .insert({
          action: 'webhook_unmatched',
          entity: 'transactions',
          user: 'ASAAS Webhook',
          date: new Date().toISOString(),
          details: JSON.stringify({
            asaas_id: asaasPaymentId,
            event: eventType,
            value: payment.value,
            customer: payment.customer,
            description: payment.description,
            note: 'Cobrança não encontrada no banco do DPSjur; ignorada com sucesso.',
          }),
        })
        .catch(() => {})

      return new Response(
        JSON.stringify({
          success: true,
          message: 'Cobrança não encontrada no banco do DPSjur. Ignorada sem efeitos colaterais.',
          asaas_id: asaasPaymentId,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 },
      )
    }

    // 5. Idempotência: se já está com o status alvo, responder 200 e encerrar sem reprocessamento
    const isAlreadyTargetStatus =
      existingTx.status === targetStatus ||
      (targetStatus === 'Paga' &&
        (existingTx.status === 'Pago' || existingTx.status === 'Realizado'))

    if (isAlreadyTargetStatus) {
      return new Response(
        JSON.stringify({
          success: true,
          message: `Transação já está no status '${existingTx.status}'. Idempotência garantida, nenhum reprocessamento necessário.`,
          transaction_id: existingTx.id,
          asaas_id: asaasPaymentId,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 },
      )
    }

    // 6. Atualização da transação (baixa automática)
    const updatePayload: Record<string, any> = {
      status: targetStatus,
    }

    // Se o evento é de pagamento recebido/confirmado, garantir bankAccount = 'ASAAS'
    // e atualizar a data do pagamento se informada pelo Asaas
    if (targetStatus === 'Paga') {
      updatePayload.bankAccount = existingTx.bankAccount || 'ASAAS'
      const paymentDate =
        payment.paymentDate ||
        payment.clientPaymentDate ||
        payment.confirmedDate ||
        new Date().toISOString().split('T')[0]
      if (paymentDate && !existingTx.date) {
        updatePayload.date = paymentDate
      }
      // Se estava pendente de vínculo na conciliação, o webhook confirma que é real
      updatePayload.pendente_vinculo = false
    }

    const { error: updateErr } = await supabase
      .from('transactions')
      .update(updatePayload)
      .eq('id', existingTx.id)

    if (updateErr) {
      throw new Error(`Erro ao atualizar transação: ${updateErr.message}`)
    }

    // 7. Log de Auditoria
    const logDetails = JSON.stringify({
      asaas_id: asaasPaymentId,
      event: eventType,
      previous_status: existingTx.status,
      new_status: targetStatus,
      transaction_id: existingTx.id,
      value: payment.value ?? existingTx.amount,
      netValue: payment.netValue,
      paymentDate: payment.paymentDate,
    })

    await supabase
      .from('logs')
      .insert({
        action: 'webhook_update',
        entity: 'transactions',
        user: 'ASAAS Webhook',
        date: new Date().toISOString(),
        details: logDetails,
      })
      .catch((e) => console.warn('Erro ao gravar log de auditoria do webhook:', e))

    // 8. Se confirmou pagamento, verificar se há emissão de NF pendente no Asaas
    let invoiceInfo = 'Sem emissão de NF requerida.'
    if (eventType === 'PAYMENT_CONFIRMED' || eventType === 'PAYMENT_RECEIVED') {
      if (effectiveApiKey) {
        try {
          // Consultar se NF já foi emitida
          const listRes = await fetch(`${effectiveApiUrl}/payments/${asaasPaymentId}/invoices`, {
            method: 'GET',
            headers: { access_token: effectiveApiKey, 'Content-Type': 'application/json' },
          })

          if (listRes.ok) {
            const listData = await listRes.json()
            const existingInvoices = listData?.data || []
            if (existingInvoices.length > 0) {
              invoiceInfo = `NF já existente (${existingInvoices[0].id}).`
            } else {
              // Tentar disparar emissão se configurado no Asaas
              const invRes = await fetch(`${effectiveApiUrl}/invoices`, {
                method: 'POST',
                headers: { access_token: effectiveApiKey, 'Content-Type': 'application/json' },
                body: JSON.stringify({ payment: asaasPaymentId }),
              })
              if (invRes.ok) {
                const invData = await invRes.json()
                invoiceInfo = `NF emitida com sucesso (${invData?.id}).`
                await supabase
                  .from('logs')
                  .insert({
                    action: 'invoice_issued',
                    entity: 'transactions',
                    user: 'ASAAS Webhook',
                    date: new Date().toISOString(),
                    details: JSON.stringify({
                      asaas_id: asaasPaymentId,
                      invoice_id: invData?.id,
                      transaction_id: existingTx.id,
                    }),
                  })
                  .catch(() => {})
              }
            }
          }
        } catch (nfErr: any) {
          console.warn('Tentativa de checagem/emissão de NF no Asaas:', nfErr?.message || nfErr)
        }
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: `Transação ${existingTx.id} atualizada com sucesso de '${existingTx.status}' para '${targetStatus}' (evento: ${eventType}). ${invoiceInfo}`,
        transaction_id: existingTx.id,
        asaas_id: asaasPaymentId,
        new_status: targetStatus,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 },
    )
  } catch (error: any) {
    // IMPORTANTE: Nunca retornar 500 no webhook se o Asaas continuar reenviando payloads infinitamente.
    // Retorna 200 com flag de erro documentado no corpo para o Asaas registrar sucesso de entrega.
    console.error('ASAAS Webhook Uncaught Error:', error.message || error)
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message || 'Erro interno no processamento do webhook.',
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})
