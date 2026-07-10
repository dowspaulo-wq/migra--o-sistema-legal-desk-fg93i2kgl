import { supabase } from '@/lib/supabase/client'

export async function syncClientWithAsaas(clientId: string) {
  const { data, error } = await supabase.functions.invoke('asaas-integration', {
    body: { action: 'syncClient', clientId },
  })
  return { data, error }
}

export async function syncChargeWithAsaas(transactionId: string) {
  const { data, error } = await supabase.functions.invoke('asaas-integration', {
    body: { action: 'syncCharge', transactionId },
  })
  return { data, error }
}

export async function cancelChargeWithAsaas(transactionId: string) {
  const { data, error } = await supabase.functions.invoke('asaas-integration', {
    body: { action: 'cancelPayment', transactionId },
  })
  return { data, error }
}

export async function syncHistoryWithAsaas() {
  const { data, error } = await supabase.functions.invoke('asaas-integration', {
    body: { action: 'sync-history' },
  })
  return { data, error }
}
