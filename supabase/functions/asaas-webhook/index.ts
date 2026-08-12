import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'jsr:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, x-supabase-client-platform, apikey, content-type, x-asaas-webhook-token',
}

const ASAAS_BASE_URL = 'https://api.asaas.com/v3'

const EVENT_STATUS_MAP: Record<string, string> = {
  PAYMENT_CONFIRMED: 'Paga',
  PAYMENT_RECEIVED: 'Paga',
  PAYMENT_OVERDUE: 'Vencida',
  PAYMENT_DELETED: 'Cancelada',
  PAYMENT_REFUNDED: 'Estornada',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const webhookToken = Deno.env.get('ASAAS_WEBHOOK_TOKEN')
    if (webhookToken) {
      const receivedToken = req.headers.get('x-asaas-webhook-token')
      if (receivedToken !== webhookToken) {
        return new Response(JSON.stringify({ error: 'Token de webhook inválido.' }), {
          status: 401,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !supabaseKey) {
      throw new Error('Variáveis de ambiente do Supabase não configuradas.')
    }

    const supabase = createClient(supabaseUrl, supabaseKey)

    const payload = await req.json()
    const eventType: string = payload?.event || ''
    const payment = payload?.payment || {}
    const asaasPaymentId: string = payment?.id || ''

    if (!asaasPaymentId) {
      return new Response(
        JSON.stringify({
          success: true,
          message: 'Webhook recebido sem ID de pagamento. Ignorado.',
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const targetStatus = EVENT_STATUS_MAP[eventType]
    if (!targetStatus) {
      return new Response(
        JSON.stringify({ success: true, message: `Evento ${eventType} não mapeado. Ignorado.` }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const { data: existingTx, error: txErr } = await supabase
      .from('transactions')
      .select('id, status, asaas_id')
      .eq('asaas_id', asaasPaymentId)
      .single()

    if (txErr || !existingTx) {
      return new Response(
        JSON.stringify({
          success: true,
          message: 'Transação não encontrada para o asaas_id informado.',
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    if (existingTx.status === targetStatus) {
      return new Response(
        JSON.stringify({
          success: true,
          message: 'Transação já está no status alvo. Idempotência garantida.',
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const { error: updateErr } = await supabase
      .from('transactions')
      .update({ status: targetStatus })
      .eq('id', existingTx.id)

    if (updateErr) {
      throw new Error(`Erro ao atualizar transação: ${updateErr.message}`)
    }

    const logDetails = JSON.stringify({
      asaas_id: asaasPaymentId,
      event: eventType,
      previous_status: existingTx.status,
      new_status: targetStatus,
      transaction_id: existingTx.id,
    })

    const { data: existingLog } = await supabase
      .from('logs')
      .select('id')
      .eq('action', 'webhook_update')
      .eq('entity', 'transactions')
      .eq('details', logDetails)
      .limit(1)

    if (!existingLog || existingLog.length === 0) {
      await supabase.from('logs').insert({
        action: 'webhook_update',
        entity: 'transactions',
        user: 'ASAAS Webhook',
        date: new Date().toISOString(),
        details: logDetails,
      })
    }

    if (eventType === 'PAYMENT_CONFIRMED') {
      const apiKey = Deno.env.get('ASAAS_API_KEY')
      if (!apiKey) {
        console.error('ASAAS_API_KEY não configurada. Não foi possível emitir NF.')
      } else {
        try {
          const listRes = await fetch(`${ASAAS_BASE_URL}/payments/${asaasPaymentId}/invoices`, {
            method: 'GET',
            headers: { access_token: apiKey, 'Content-Type': 'application/json' },
          })

          if (listRes.ok) {
            const listData = await listRes.json()
            const existingInvoices = listData.data || []
            if (existingInvoices.length > 0) {
              console.log(
                `NF já existente para pagamento ${asaasPaymentId}: ${existingInvoices[0].id}. Pulando emissão manual.`,
              )

              await supabase.from('logs').insert({
                action: 'invoice_already_issued',
                entity: 'transactions',
                user: 'ASAAS Webhook',
                date: new Date().toISOString(),
                details: JSON.stringify({
                  asaas_id: asaasPaymentId,
                  invoice_id: existingInvoices[0].id,
                  invoice_status: existingInvoices[0].status,
                  transaction_id: existingTx.id,
                  source: 'auto_nf_settings',
                }),
              })

              return new Response(
                JSON.stringify({
                  success: true,
                  message: `Transação atualizada para '${targetStatus}' (evento: ${eventType}). NF já emitida automaticamente.`,
                  transaction_id: existingTx.id,
                }),
                { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
              )
            }
          }

          const invoiceRes = await fetch(`${ASAAS_BASE_URL}/invoices`, {
            method: 'POST',
            headers: { access_token: apiKey, 'Content-Type': 'application/json' },
            body: JSON.stringify({ payment: asaasPaymentId }),
          })

          if (invoiceRes.ok) {
            const invoiceData = await invoiceRes.json()
            console.log(`NF emitida com sucesso para pagamento ${asaasPaymentId}:`, invoiceData.id)

            await supabase.from('logs').insert({
              action: 'invoice_issued',
              entity: 'transactions',
              user: 'ASAAS Webhook',
              date: new Date().toISOString(),
              details: JSON.stringify({
                asaas_id: asaasPaymentId,
                invoice_id: invoiceData.id,
                invoice_status: invoiceData.status,
                transaction_id: existingTx.id,
              }),
            })
          } else {
            const invoiceErr = await invoiceRes.json().catch(() => ({}))
            const errMsg = (invoiceErr as any)?.errors?.[0]?.description || invoiceRes.statusText
            console.warn(
              `NF já emitida ou erro ao emitir para pagamento ${asaasPaymentId}: ${errMsg}`,
            )

            await supabase.from('logs').insert({
              action: 'invoice_issuance_skipped',
              entity: 'transactions',
              user: 'ASAAS Webhook',
              date: new Date().toISOString(),
              details: JSON.stringify({
                asaas_id: asaasPaymentId,
                reason: errMsg,
                transaction_id: existingTx.id,
              }),
            })
          }
        } catch (invoiceError: any) {
          console.error('Falha ao emitir NF:', invoiceError.message || invoiceError)
        }
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: `Transação atualizada para '${targetStatus}' (evento: ${eventType}).${eventType === 'PAYMENT_CONFIRMED' ? ' NF emitida/verificada.' : ''}`,
        transaction_id: existingTx.id,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (error: any) {
    console.error('ASAAS Webhook Error:', error.message || error)
    return new Response(JSON.stringify({ error: error.message || 'Erro interno' }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
