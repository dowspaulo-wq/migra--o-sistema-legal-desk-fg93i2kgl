import { supabase } from '@/lib/supabase/client'

export async function generateInternalDocument(caseId: string, clientId: string, docType: string) {
  const { data, error } = await supabase.functions.invoke('electronic-signature', {
    body: { action: 'generateDoc', caseId, clientId, docType },
  })
  if (!error && data?.error) return { data: null, error: { message: data.error } }
  if (data?.token) {
    data.signUrl = `${window.location.origin}/assinar/${data.token}`
  }
  return { data, error }
}

export async function fetchSignaturesByCase(caseId: string) {
  const { data, error } = await supabase
    .from('document_signatures')
    .select('*')
    .eq('case_id', caseId)
    .order('created_at', { ascending: false })
  return { data: data || [], error }
}

export async function getSignatureByToken(token: string) {
  const { data, error } = await supabase.functions.invoke('electronic-signature', {
    body: { action: 'getByToken', token },
  })
  if (!error && data?.error) return { data: null, error: { message: data.error } }
  return { data, error }
}

export async function confirmSignature(
  token: string,
  payload: {
    selfie: string
    signature: string
    geolocation?: { latitude: number; longitude: number } | null
  },
) {
  const { data, error } = await supabase.functions.invoke('electronic-signature', {
    body: { action: 'confirmSignature', token, ...payload },
  })
  if (!error && data?.error) return { data: null, error: { message: data.error } }
  return { data, error }
}

export function getStoragePublicUrl(bucket: string, path: string): string {
  return supabase.storage.from(bucket).getPublicUrl(path).data.publicUrl
}
