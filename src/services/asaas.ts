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

export interface AsaasInvokeResponse<T = any> {
  data: T | null
  error: Error | null
}

async function invokeAsaasFunction(body: Record<string, any>): Promise<AsaasInvokeResponse> {
  const config = await getAsaasConfig()

  if (!config.apiKey || !config.apiKey.trim()) {
    return {
      data: null,
      error: new Error(
        'Chave da API do Asaas não configurada. Cadastre-a em Configurações → Integrações no SBJur.',
      ),
    }
  }

  const headers: Record<string, string> = {
    'x-asaas-api-key': config.apiKey.trim(),
  }
  if (config.apiUrl && config.apiUrl.trim()) {
    headers['x-asaas-api-url'] = config.apiUrl.trim()
  }

  try {
    const { data, error } = await supabase.functions.invoke('asaas-integration', {
      body,
      headers,
    })

    if (error) {
      // Supabase FunctionsHttpError costuma ter context com a resposta JSON da edge function
      let message = error.message || 'Erro ao comunicar com o servidor.'
      const ctx = (error as any)?.context
      if (ctx) {
        try {
          if (typeof ctx.json === 'function') {
            const bodyJson = await ctx.json().catch(() => null)
            if (bodyJson?.error) {
              message = bodyJson.error
            } else if (bodyJson?.message) {
              message = bodyJson.message
            }
          } else if (typeof ctx.text === 'function') {
            const bodyText = await ctx.text().catch(() => '')
            if (bodyText) {
              try {
                const parsed = JSON.parse(bodyText)
                message = parsed.error || parsed.message || bodyText
              } catch {
                message = bodyText
              }
            }
          }
        } catch {
          // fallback para error.message
        }
      }
      return { data: null, error: new Error(message) }
    }

    // Se o backend retornou { error: '...' } no payload com status 200 (legado)
    if (data && typeof data === 'object' && 'error' in data && (data as any).error) {
      const errMsg = (data as any).error
      return {
        data: null,
        error: new Error(typeof errMsg === 'string' ? errMsg : JSON.stringify(errMsg)),
      }
    }

    return { data, error: null }
  } catch (err: any) {
    return {
      data: null,
      error: new Error(err?.message || 'Falha de conexão com o serviço Asaas.'),
    }
  }
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
