import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'jsr:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, x-supabase-client-platform, apikey, content-type, x-asaas-api-key, x-asaas-api-url',
}

function getAsaasBaseUrl(req?: Request): string {
  const headerUrl = req?.headers?.get('x-asaas-api-url')
  if (headerUrl && headerUrl.trim()) {
    return headerUrl.trim().replace(/\/+$/, '')
  }
  const customUrl = Deno.env.get('ASAAS_API_URL')
  if (customUrl && customUrl.trim()) {
    return customUrl.trim().replace(/\/+$/, '')
  }
  return 'https://api.asaas.com/v3'
}

function getAsaasApiKey(req?: Request): string | null {
  const headerKey = req?.headers?.get('x-asaas-api-key')
  if (headerKey && headerKey.trim()) {
    return headerKey.trim()
  }
  const envKey = Deno.env.get('ASAAS_API_KEY')
  if (envKey && envKey.trim()) {
    return envKey.trim()
  }
  return null
}

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
  let digits = phone.replace(/\D/g, '')
  if (digits.length === 0) return undefined
  // Se for apenas zeros ou numero invalido menor que 8 digitos
  if (/^0+$/.test(digits) || digits.length < 8) return undefined

  // O Asaas espera DDD + número (10 ou 11 dígitos), SEM o código do país (55).
  // Se o número salvo possuir o '55' inicial (com 12 ou 13 dígitos: 55 + DDD + 8 ou 9 dígitos),
  // removemos o prefixo '55' para não gerar erro na API do Asaas.
  if (digits.startsWith('55') && (digits.length === 12 || digits.length === 13)) {
    digits = digits.slice(2)
  }

  // DDD (2 dígitos) + 8 ou 9 dígitos -> 10 ou 11 dígitos
  if (digits.length === 10 || digits.length === 11) {
    return digits
  }

  // Se tiver pelo menos 8 dígitos (ex: 8 ou 9 dígitos locais), retorna sem 55
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
    const apiKey = getAsaasApiKey(req)
    if (!apiKey) {
      throw new Error(
        'Chave da API do Asaas não configurada. Cadastre-a em Configurações → Integrações no SBJur.',
      )
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !supabaseKey) {
      throw new Error('Variáveis de ambiente do Supabase não configuradas.')
    }

    const supabase = createClient(supabaseUrl, supabaseKey)
    const requestData = await req.json().catch(() => ({}))
    const { action, clientId, transactionId } = requestData
    const asaasBaseUrl = getAsaasBaseUrl(req)

    if (action === 'syncClient') {
      const { data: client, error: clientErr } = await supabase
        .from('clients')
        .select('*')
        .eq('id', clientId)
        .single()

      if (clientErr || !client) {
        throw new Error('Cliente não encontrado.')
      }

      let asaasId = (client as any).asaas_id

      const fullAddress = [
        (client as any).street,
        (client as any).number,
        (client as any).complement,
        (client as any).neighborhood,
        (client as any).city,
      ]
        .filter(Boolean)
        .join(', ')

      const hasNoPhone = (client as any).no_phone || (client as any).phone_na
      const hasNoEmail = (client as any).no_email || (client as any).email_na
      const normalizedCpfCnpj = normalizeDocument(client.document)

      // Se não possui asaas_id salvo, verificar se já existe no Asaas por CPF/CNPJ
      // para evitar duplicar ou tomar erro do Asaas
      if (!asaasId && normalizedCpfCnpj) {
        try {
          const searchRes = await fetch(
            `${asaasBaseUrl}/customers?cpfCnpj=${encodeURIComponent(normalizedCpfCnpj)}`,
            {
              method: 'GET',
              headers: { access_token: apiKey, 'Content-Type': 'application/json' },
            },
          )
          if (searchRes.ok) {
            const searchData = await searchRes.json()
            if (searchData?.data && searchData.data.length > 0) {
              asaasId = searchData.data[0].id
              await supabase.from('clients').update({ asaas_id: asaasId }).eq('id', clientId)
            }
          }
        } catch (searchErr) {
          console.warn('Erro ao consultar cliente existente no Asaas por CPF:', searchErr)
        }
      }

      const customerData: any = {
        name: client.name,
        cpfCnpj: normalizedCpfCnpj || undefined,
        email: !hasNoEmail && client.email ? client.email : undefined,
        phone: !hasNoPhone ? formatPhone(client.phone) : undefined,
        mobilePhone: !hasNoPhone ? formatPhone(client.phone) : undefined,
        postalCode: formatCep((client as any).cep),
        address: (client as any).street || client.address || undefined,
        addressNumber: (client as any).number || undefined,
        complement: (client as any).complement || undefined,
        province: (client as any).neighborhood || undefined,
        city: (client as any).city || undefined,
        state: (client as any).state || undefined,
        notificationDisabled: false,
      }

      if (!customerData.address && fullAddress) {
        customerData.address = fullAddress
      }

      Object.keys(customerData).forEach((k) => {
        if (customerData[k] === undefined || customerData[k] === '') delete customerData[k]
      })

      if (asaasId) {
        const res = await fetch(`${asaasBaseUrl}/customers/${asaasId}`, {
          method: 'PUT',
          headers: { access_token: apiKey, 'Content-Type': 'application/json' },
          body: JSON.stringify(customerData),
        })

        if (!res.ok) {
          const err = await res.json().catch(() => ({}))
          const msg = (err as any)?.errors?.[0]?.description || res.statusText
          throw new Error(`Erro ao atualizar cliente no ASAAS: ${msg}`)
        }

        const updated = await res.json()
        const finalId = updated?.id || asaasId
        await supabase.from('clients').update({ asaas_id: finalId }).eq('id', clientId)

        return new Response(
          JSON.stringify({
            success: true,
            message: 'Cliente atualizado no ASAAS com sucesso.',
            asaas_id: finalId,
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          },
        )
      } else {
        const res = await fetch(`${asaasBaseUrl}/customers`, {
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

      const normalizedDoc = normalizeDocument(client.document)
      if (!normalizedDoc) {
        throw new Error(
          'Cliente não possui documento (CPF/CNPJ) válido. Necessário para emissão de NF.',
        )
      }

      const fullAddress = [
        (client as any).street,
        (client as any).number,
        (client as any).complement,
        (client as any).neighborhood,
        (client as any).city,
        (client as any).state,
      ]
        .filter(Boolean)
        .join(', ')
      const clientAddress = (client as any).street || client.address || undefined
      if (!clientAddress && !fullAddress) {
        throw new Error('Cliente não possui endereço válido. Necessário para emissão de NF.')
      }

      const paymentData: any = {
        customer: clientAsaasId,
        billingType,
        value: Number(transaction.amount),
        dueDate: transaction.date || new Date().toISOString().split('T')[0],
        description: transaction.description || 'Honorários advocatícios',
        nfSettings: {
          generationType: 'AUTO',
          effectiveDate: 'PAYMENT_DATE',
          statusToInvoice: 'PAYMENT_CONFIRMED',
        },
      }

      if (txAsaasId) {
        // Cobrança já existe no Asaas -> Atualizar / Reativar
        // Se no Asaas ela estivesse deletada/cancelada, tentar reativar ou atualizar
        const updateRes = await fetch(`${asaasBaseUrl}/payments/${txAsaasId}`, {
          method: 'PUT',
          headers: { access_token: apiKey, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            billingType: paymentData.billingType,
            value: paymentData.value,
            dueDate: paymentData.dueDate,
            description: paymentData.description,
          }),
        })

        if (updateRes.ok) {
          const updated = await updateRes.json()
          return new Response(
            JSON.stringify({
              success: true,
              message: 'Cobrança atualizada no ASAAS com sucesso.',
              asaas_id: updated.id,
            }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
          )
        }

        // Se o PUT falhou (ex: cobrança foi excluída no Asaas), recria no Asaas e atualiza o asaas_id
        const recreateRes = await fetch(`${asaasBaseUrl}/payments`, {
          method: 'POST',
          headers: { access_token: apiKey, 'Content-Type': 'application/json' },
          body: JSON.stringify(paymentData),
        })

        if (!recreateRes.ok) {
          const err = await recreateRes.json().catch(() => ({}))
          const msg = (err as any)?.errors?.[0]?.description || recreateRes.statusText
          throw new Error(`Erro ao reativar/sincronizar cobrança no ASAAS: ${msg}`)
        }

        const recreated = await recreateRes.json()
        await supabase
          .from('transactions')
          .update({ asaas_id: recreated.id })
          .eq('id', transactionId)

        return new Response(
          JSON.stringify({
            success: true,
            message: 'Cobrança reativada e sincronizada no ASAAS com sucesso.',
            asaas_id: recreated.id,
          }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }

      // Cobrança ainda não tem asaas_id -> criar nova no Asaas
      const res = await fetch(`${asaasBaseUrl}/payments`, {
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

      const delRes = await fetch(`${asaasBaseUrl}/payments/${asaasPayId}`, {
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
        const url = `${asaasBaseUrl}/payments?offset=${offset}&limit=${limit}&status=RECEIVED,CONFIRMED,PENDING,OVERDUE,REFUNDED`
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
              const custRes = await fetch(`${asaasBaseUrl}/customers/${asaasCustomerId}`, {
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

    if (action === 'import-extract' || action === 'importExtract') {
      const { startDate, finishDate } = requestData
      if (!startDate || !finishDate) {
        throw new Error(
          'Data inicial (startDate) e final (finishDate) são obrigatórias no formato AAAA-MM-DD.',
        )
      }

      // Buscar clientes cadastrados para casamento por nome/documento
      const { data: clients } = await supabase
        .from('clients')
        .select('id, name, document, asaas_id')
      const clientByAsaasId = new Map<string, any>()
      const clientByDocument = new Map<string, any>()
      const clientByName = new Map<string, any>()

      const normalizeName = (name: string) =>
        (name || '')
          .toLowerCase()
          .normalize('NFD')
          .replace(/[\u0300-\u036f]/g, '')
          .replace(/[^a-z0-9]/g, '')

      for (const c of clients || []) {
        if (c.asaas_id) clientByAsaasId.set(c.asaas_id, c)
        if (c.document) {
          const normDoc = normalizeDocument(c.document)
          if (normDoc) clientByDocument.set(normDoc, c)
        }
        if (c.name) {
          const normName = normalizeName(c.name)
          if (normName) clientByName.set(normName, c)
        }
      }

      // Buscar fornecedores cadastrados para casamento em saídas
      const { data: suppliers } = await supabase.from('suppliers').select('id, name, document')
      const supplierByDocument = new Map<string, any>()
      const supplierByName = new Map<string, any>()
      for (const s of suppliers || []) {
        if (s.document) {
          const normDoc = normalizeDocument(s.document)
          if (normDoc) supplierByDocument.set(normDoc, s)
        }
        if (s.name) {
          const normName = normalizeName(s.name)
          if (normName) supplierByName.set(normName, s)
        }
      }

      // Buscar transações existentes no período para casar automaticamente
      // (ex.: lançamentos já agendados de honorários ou contas a pagar com valor e data próximos)
      const { data: existingTxs } = await supabase
        .from('transactions')
        .select('id, amount, date, type, clientId, supplierId, asaas_id, pendente_vinculo, status')
        .gte('date', startDate)
        .lte('date', finishDate)

      let offset = 0
      const limit = 100
      let hasMore = true
      let totalFetched = 0
      let insertedCount = 0
      let preReconciledCount = 0
      let pendingReviewCount = 0
      let skippedExistingCount = 0

      const processedAsaasIds = new Set<string>()

      while (hasMore) {
        const url = `${asaasBaseUrl}/financialTransactions?startDate=${encodeURIComponent(startDate)}&finishDate=${encodeURIComponent(finishDate)}&offset=${offset}&limit=${limit}&order=asc`
        const res = await fetch(url, {
          method: 'GET',
          headers: { access_token: apiKey, 'Content-Type': 'application/json' },
        })

        if (!res.ok) {
          const err = await res.json().catch(() => ({}))
          const msg = (err as any)?.errors?.[0]?.description || res.statusText
          throw new Error(`Erro ao buscar extrato financeiro do ASAAS: ${msg}`)
        }

        const result = await res.json()
        const items: any[] = result.data || []
        totalFetched += items.length

        for (const item of items) {
          const ftId = item.id ? String(item.id) : ''
          if (!ftId || processedAsaasIds.has(ftId)) continue
          processedAsaasIds.add(ftId)

          // Verifica se já existe uma transação com este asaas_id
          const alreadyExists = (existingTxs || []).some((tx: any) => tx.asaas_id === ftId)
          if (alreadyExists) {
            skippedExistingCount++
            continue
          }

          const rawValue = Number(item.value ?? 0)
          const absAmount = Math.abs(rawValue)
          const isIncome = rawValue >= 0
          const txDate = item.date || item.paymentDate || startDate

          const description =
            item.description ||
            item.transfer?.description ||
            item.bill?.description ||
            `Extrato Asaas: ${item.type || 'Movimentação'}`

          // Tentativa de casamento por regras simples (sem IA)
          let matchedClientId: string | null = null
          let matchedSupplierId: string | null = null
          let matchedExistingTxId: string | null = null

          // 1. Tentar casar cliente via item.customer ou dados da transferência
          if (item.customer && clientByAsaasId.has(item.customer)) {
            matchedClientId = clientByAsaasId.get(item.customer).id
          }

          // 2. Se for saída, verificar se casa com fornecedor conhecido pelo nome/descrição
          if (!isIncome) {
            const descNorm = normalizeName(description)
            for (const [normSName, sup] of supplierByName.entries()) {
              if (descNorm.includes(normSName) && normSName.length >= 3) {
                matchedSupplierId = sup.id
                break
              }
            }
          }

          // 3. Tentar casar com lançamento existente não conciliado (mesmo valor, tipo idêntico e data com tolerância de até 3 dias)
          const itemTime = new Date(txDate).getTime()
          const matchedTx = (existingTxs || []).find((tx: any) => {
            if (tx.asaas_id && tx.asaas_id !== ftId) return false
            if (tx.type !== (isIncome ? 'income' : 'expense')) return false
            const diffAmount = Math.abs(Number(tx.amount || 0) - absAmount)
            if (diffAmount > 0.01) return false
            if (!tx.date) return false
            const txTime = new Date(tx.date).getTime()
            const diffDays = Math.abs(itemTime - txTime) / (1000 * 60 * 60 * 24)
            return diffDays <= 3
          })

          if (matchedTx) {
            matchedExistingTxId = matchedTx.id
            if (!matchedClientId && matchedTx.clientId) matchedClientId = matchedTx.clientId
            if (!matchedSupplierId && matchedTx.supplierId) matchedSupplierId = matchedTx.supplierId
          }

          // Se casou com lançamento existente, podemos atualizar o lançamento existente com asaas_id e dar baixa/conciliar
          if (matchedExistingTxId) {
            const { error: patchErr } = await supabase
              .from('transactions')
              .update({
                asaas_id: ftId,
                status: 'Pago',
                bankAccount: 'ASAAS',
                pendente_vinculo: false,
              })
              .eq('id', matchedExistingTxId)

            if (!patchErr) {
              preReconciledCount++
              continue
            }
          }

          // Caso não tenha casado com lançamento pré-existente no sistema,
          // cria um lançamento novo na fila de conciliação
          const isPreReconciled = Boolean(matchedClientId || matchedSupplierId)
          const newTx = {
            description,
            amount: absAmount,
            type: isIncome ? 'income' : 'expense',
            category: isIncome
              ? 'Honorários Contratuais'
              : (item.type || '').includes('FEE')
                ? 'Taxas Bancárias'
                : 'Despesas Gerais',
            status: 'Pago',
            date: txDate,
            clientId: matchedClientId,
            supplierId: matchedSupplierId,
            asaas_id: ftId,
            sendToFinance: true,
            bankAccount: 'ASAAS',
            payment_method: (item.type || '').includes('PIX')
              ? 'PIX'
              : (item.type || '').includes('BOLETO')
                ? 'BOLETO'
                : 'TRANSFERÊNCIA',
            pendente_vinculo: !isPreReconciled,
            origem: 'ASAAS',
          }

          const { error: insertErr } = await supabase.from('transactions').insert(newTx)
          if (!insertErr) {
            insertedCount++
            if (isPreReconciled) {
              preReconciledCount++
            } else {
              pendingReviewCount++
            }
          } else {
            console.error('Erro ao inserir movimentação do extrato Asaas:', insertErr.message)
          }
        }

        hasMore = Boolean(result.hasMore)
        offset += limit
        if (offset > 10000) break
      }

      return new Response(
        JSON.stringify({
          success: true,
          message: `Extrato Asaas importado com sucesso: ${totalFetched} itens lidos (${insertedCount} novos lançamentos, ${preReconciledCount} pré-conciliados, ${pendingReviewCount} para conferência manual, ${skippedExistingCount} já existiam).`,
          totalFetched,
          insertedCount,
          preReconciledCount,
          pendingReviewCount,
          skippedExistingCount,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    throw new Error('Ação inválida.')
  } catch (error: any) {
    console.error('ASAAS Integration Error:', error.message || error)
    return new Response(JSON.stringify({ error: error.message || 'Erro interno' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
