import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'jsr:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, x-supabase-client-platform, apikey, content-type',
}

const ASAAS_BASE_URL = 'https://api.asaas.com/v3'

const ASAAS_STATUS_MAP: Record<string, string> = {
  PENDING: 'Pendente',
  RECEIVED: 'Paga',
  CONFIRMED: 'Paga',
  OVERDUE: 'Vencida',
  REFUNDED: 'Estornada',
  DELETED: 'Cancelada',
}

const ASAAS_PAYMENT_METHOD_MAP: Record<string, string> = {
  PIX: 'PIX',
  BOLETO: 'BOLETO',
  CREDIT_CARD: 'CARTÃO',
}

function formatPhone(phone: string): string | undefined {
  if (!phone) return undefined
  const digits = phone.replace(/\D/g, '')
  if (digits.length === 0) return undefined
  if (digits.startsWith('55')) return digits
  if (digits.length === 10 || digits.length === 11) return `55${digits}`
  return digits
}

function formatCep(cep: string): string | undefined {
  if (!cep) return undefined
  const digits = cep.replace(/\D/g, '')
  if (digits.length === 0) return undefined
  return digits
}

function normalizeDocument(doc: string): string {
  return (doc || '').replace(/\D/g, '')
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const apiKey = Deno.env.get('ASAAS_API_KEY')
    if (!apiKey) {
      throw new Error(
        'ASAAS_API_KEY não configurada. Defina a chave da API nos segredos do Supabase.',
      )
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !supabaseKey) {
      throw new Error('Variáveis de ambiente do Supabase não configuradas.')
    }

    const supabase = createClient(supabaseUrl, supabaseKey)
    const { action, clientId, transactionId } = await req.json()

    if (action === 'syncClient') {
      const { data: client, error: clientErr } = await supabase
        .from('clients')
        .select('*')
        .eq('id', clientId)
        .single()

      if (clientErr || !client) {
        throw new Error('Cliente não encontrado.')
      }

      const asaasId = (client as any).asaas_id

      const fullAddress = [
        (client as any).street,
        (client as any).number,
        (client as any).complement,
        (client as any).neighborhood,
        (client as any).city,
      ]
        .filter(Boolean)
        .join(', ')

      const customerData: any = {
        name: client.name,
        cpfCnpj: normalizeDocument(client.document) || undefined,
        email: client.email || undefined,
        phone: formatPhone(client.phone),
        mobilePhone: formatPhone(client.phone),
        postalCode: formatCep((client as any).cep),
        address: (client as any).street || client.address || undefined,
        addressNumber: (client as any).number || undefined,
        complement: (client as any).complement || undefined,
        province: (client as any).neighborhood || undefined,
        city: (client as any).city || undefined,
        notificationDisabled: false,
      }

      if (!customerData.address && fullAddress) {
        customerData.address = fullAddress
      }

      Object.keys(customerData).forEach((k) => {
        if (customerData[k] === undefined || customerData[k] === '') delete customerData[k]
      })

      if (asaasId) {
        const res = await fetch(`${ASAAS_BASE_URL}/customers/${asaasId}`, {
          method: 'PUT',
          headers: { access_token: apiKey, 'Content-Type': 'application/json' },
          body: JSON.stringify(customerData),
        })

        if (!res.ok) {
          const err = await res.json().catch(() => ({}))
          const msg = (err as any)?.errors?.[0]?.description || res.statusText
          throw new Error(`Erro ao atualizar cliente no ASAAS: ${msg}`)
        }

        return new Response(
          JSON.stringify({ success: true, message: 'Cliente atualizado no ASAAS com sucesso.' }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          },
        )
      } else {
        const res = await fetch(`${ASAAS_BASE_URL}/customers`, {
          method: 'POST',
          headers: { access_token: apiKey, 'Content-Type': 'application/json' },
          body: JSON.stringify(customerData),
        })

        if (!res.ok) {
          const err = await res.json().catch(() => ({}))
          const msg = (err as any)?.errors?.[0]?.description || res.statusText
          throw new Error(`Erro ao criar cliente no ASAAS: ${msg}`)
        }

        const created = await res.json()

        await supabase.from('clients').update({ asaas_id: created.id }).eq('id', clientId)

        return new Response(
          JSON.stringify({
            success: true,
            message: 'Cliente criado no ASAAS com sucesso.',
            asaas_id: created.id,
          }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }
    }

    if (action === 'syncCharge') {
      const { data: transaction, error: txErr } = await supabase
        .from('transactions')
        .select('*')
        .eq('id', transactionId)
        .single()

      if (txErr || !transaction) {
        throw new Error('Transação não encontrada.')
      }

      const txAsaasId = (transaction as any).asaas_id
      if (txAsaasId) {
        return new Response(
          JSON.stringify({ success: true, message: 'Cobrança já sincronizada com ASAAS.' }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }

      if (!transaction.clientId) {
        throw new Error('Transação não possui cliente vinculado.')
      }

      const { data: client, error: clientErr } = await supabase
        .from('clients')
        .select('*')
        .eq('id', transaction.clientId)
        .single()

      if (clientErr || !client) {
        throw new Error('Cliente da transação não encontrado.')
      }

      const clientAsaasId = (client as any).asaas_id
      if (!clientAsaasId) {
        throw new Error('Cliente não sincronizado com ASAAS. Sincronize o cliente primeiro.')
      }

      const billingType = (transaction as any).payment_method === 'BOLETO' ? 'BOLETO' : 'PIX'
      const paymentData: any = {
        customer: clientAsaasId,
        billingType,
        value: Number(transaction.amount),
        dueDate: transaction.date,
        description: transaction.description,
      }

      const res = await fetch(`${ASAAS_BASE_URL}/payments`, {
        method: 'POST',
        headers: { access_token: apiKey, 'Content-Type': 'application/json' },
        body: JSON.stringify(paymentData),
      })

      if (!res.ok) {
        const err = await res.json().catch(() => ({}))
        const msg = (err as any)?.errors?.[0]?.description || res.statusText
        throw new Error(`Erro ao criar cobrança no ASAAS: ${msg}`)
      }

      const created = await res.json()

      await supabase.from('transactions').update({ asaas_id: created.id }).eq('id', transactionId)

      return new Response(
        JSON.stringify({
          success: true,
          message: 'Cobrança criada no ASAAS com sucesso.',
          asaas_id: created.id,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    if (action === 'cancelPayment') {
      const { data: txData, error: txErr2 } = await supabase
        .from('transactions')
        .select('asaas_id')
        .eq('id', transactionId)
        .single()

      if (txErr2 || !txData) {
        throw new Error('Transação não encontrada.')
      }

      const asaasPayId = (txData as any).asaas_id
      if (!asaasPayId) {
        return new Response(
          JSON.stringify({ success: true, message: 'Transação não possui cobrança no ASAAS.' }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }

      const delRes = await fetch(`${ASAAS_BASE_URL}/payments/${asaasPayId}`, {
        method: 'DELETE',
        headers: { access_token: apiKey, 'Content-Type': 'application/json' },
      })

      if (!delRes.ok) {
        const delErr = await delRes.json().catch(() => ({}))
        const delMsg = (delErr as any)?.errors?.[0]?.description || delRes.statusText
        throw new Error(`Erro ao cancelar cobrança no ASAAS: ${delMsg}`)
      }

      await supabase.from('transactions').update({ asaas_id: null }).eq('id', transactionId)

      return new Response(
        JSON.stringify({ success: true, message: 'Cobrança cancelada no ASAAS com sucesso.' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    if (action === 'sync-history') {
      const { data: clients, error: clientsErr } = await supabase
        .from('clients')
        .select('id, name, document, asaas_id')

      if (clientsErr) {
        throw new Error('Erro ao buscar clientes do banco de dados.')
      }

      const clientByAsaasId = new Map<string, any>()
      const clientByDocument = new Map<string, any>()

      for (const c of clients || []) {
        if (c.asaas_id) {
          clientByAsaasId.set(c.asaas_id, c)
        }
        if (c.document) {
          const normalized = normalizeDocument(c.document)
          if (normalized) {
            clientByDocument.set(normalized, c)
          }
        }
      }

      let offset = 0
      const limit = 100
      let hasMore = true
      let syncedCount = 0
      let unmatchedCount = 0
      const unmatchedPayments: any[] = []
      const customerCache = new Map<string, any>()

      while (hasMore) {
        const url = `${ASAAS_BASE_URL}/payments?offset=${offset}&limit=${limit}&status=RECEIVED,CONFIRMED,PENDING,OVERDUE,REFUNDED`
        const res = await fetch(url, {
          method: 'GET',
          headers: { access_token: apiKey, 'Content-Type': 'application/json' },
        })

        if (!res.ok) {
          const err = await res.json().catch(() => ({}))
          const msg = (err as any)?.errors?.[0]?.description || res.statusText
          throw new Error(`Erro ao buscar pagamentos do ASAAS: ${msg}`)
        }

        const result = await res.json()
        const payments: any[] = result.data || []

        for (const payment of payments) {
          const asaasCustomerId = payment.customer
          let matchedClient: any = clientByAsaasId.get(asaasCustomerId) || null

          if (!matchedClient && !customerCache.has(asaasCustomerId)) {
            try {
              const custRes = await fetch(`${ASAAS_BASE_URL}/customers/${asaasCustomerId}`, {
                method: 'GET',
                headers: { access_token: apiKey, 'Content-Type': 'application/json' },
              })
              if (custRes.ok) {
                const custData = await custRes.json()
                customerCache.set(asaasCustomerId, custData)
                if (custData.cpfCnpj) {
                  const normalizedDoc = normalizeDocument(custData.cpfCnpj)
                  matchedClient = clientByDocument.get(normalizedDoc) || null
                  if (matchedClient && !matchedClient.asaas_id) {
                    await supabase
                      .from('clients')
                      .update({ asaas_id: asaasCustomerId })
                      .eq('id', matchedClient.id)
                    clientByAsaasId.set(asaasCustomerId, matchedClient)
                  }
                }
              } else {
                customerCache.set(asaasCustomerId, null)
              }
            } catch {
              customerCache.set(asaasCustomerId, null)
            }
          }

          if (!matchedClient) {
            unmatchedCount++
            unmatchedPayments.push({
              asaas_id: payment.id,
              customer: asaasCustomerId,
              value: payment.value,
              description: payment.description,
            })
            continue
          }

          const txStatus = ASAAS_STATUS_MAP[payment.status] || 'Pendente'
          const txDate =
            payment.paymentDate ||
            payment.confirmationDate ||
            payment.dueDate ||
            new Date().toISOString().split('T')[0]
          const txPaymentMethod = ASAAS_PAYMENT_METHOD_MAP[payment.billingType] || 'PIX'

          const txData = {
            description: payment.description || `Pagamento ASAAS ${payment.id}`,
            amount: Number(payment.value) || 0,
            type: 'income',
            category: 'Honorários Contratuais',
            status: txStatus,
            date: txDate,
            clientId: matchedClient.id,
            asaas_id: payment.id,
            sendToFinance: true,
            bankAccount: 'ASAAS',
            payment_method: txPaymentMethod,
          }

          const { error: upsertErr } = await supabase
            .from('transactions')
            .upsert(txData, { onConflict: 'asaas_id' })

          if (upsertErr) {
            console.error('Erro ao upsert transação:', upsertErr.message)
          } else {
            syncedCount++
          }
        }

        hasMore = result.hasMore || false
        offset += limit

        if (offset > 10000) break
      }

      return new Response(
        JSON.stringify({
          success: true,
          message: `Sincronização concluída. ${syncedCount} pagamento(s) sincronizado(s), ${unmatchedCount} não correspondido(s).`,
          synced: syncedCount,
          unmatched: unmatchedCount,
          unmatchedDetails: unmatchedPayments.slice(0, 20),
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    throw new Error('Ação inválida.')
  } catch (error: any) {
    console.error('ASAAS Integration Error:', error.message || error)
    return new Response(JSON.stringify({ error: error.message || 'Erro interno' }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
