import { supabase } from '@/lib/supabase/client'

interface AsaasConfig {
  apiKey?: string | null
  apiUrl?: string | null
}

let cachedConfig: AsaasConfig | null = null

export function setCachedAsaasConfig(config: AsaasConfig) {
  cachedConfig = config
}

export async function getAsaasConfig(): Promise<AsaasConfig> {
  if (cachedConfig?.apiKey) {
    return cachedConfig
  }
  try {
    const { data } = await supabase
      .from('settings')
      .select('asaasApiKey, asaasApiUrl')
      .limit(1)
      .maybeSingle()

    if (data) {
      cachedConfig = {
        apiKey: (data as any).asaasApiKey || null,
        apiUrl: (data as any).asaasApiUrl || 'https://api.asaas.com/v3',
      }
      return cachedConfig
    }
  } catch (err) {
    console.warn('Erro ao ler configurações do Asaas:', err)
  }
  return cachedConfig || { apiKey: null, apiUrl: 'https://api.asaas.com/v3' }
}

async function invokeAsaasFunction(body: Record<string, any>) {
  const config = await getAsaasConfig()
  const headers: Record<string, string> = {}
  if (config.apiKey) {
    headers['x-asaas-api-key'] = config.apiKey
  }
  if (config.apiUrl) {
    headers['x-asaas-api-url'] = config.apiUrl
  }

  const { data, error } = await supabase.functions.invoke('asaas-integration', {
    body,
    headers,
  })

  // Se a resposta retornou erro amigável de chave não configurada no corpo, garantir formatação
  if (!config.apiKey && !data && error) {
    return {
      data: null,
      error: new Error(
        'Chave da API do Asaas não configurada. Cadastre-a em Configurações → Integrações no SBJur.',
      ),
    }
  }

  return { data, error }
}

export async function syncClientWithAsaas(clientId: string) {
  return invokeAsaasFunction({ action: 'syncClient', clientId })
}

export async function syncChargeWithAsaas(transactionId: string) {
  return invokeAsaasFunction({ action: 'syncCharge', transactionId })
}

export async function cancelChargeWithAsaas(transactionId: string) {
  return invokeAsaasFunction({ action: 'cancelPayment', transactionId })
}

export async function syncHistoryWithAsaas() {
  return invokeAsaasFunction({ action: 'sync-history' })
}

export async function importAsaasExtract(startDate: string, finishDate: string) {
  return invokeAsaasFunction({
    action: 'import-extract',
    startDate,
    finishDate,
  })
}
