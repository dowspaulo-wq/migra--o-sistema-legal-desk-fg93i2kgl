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
  try {
    const { data, error } = await supabase.functions.invoke('electronic-signature', {
      body: { action: 'getByToken', token },
    })
    if (!error && data && !data.error) {
      return { data, error: null }
    }
  } catch (e) {
    console.warn('Edge function error, falling back to direct DB lookup', e)
  }

  const { data, error } = await supabase
    .from('document_signatures')
    .select(`
      *,
      clients:client_id (id, name, document, email, phone, street, number, complement, neighborhood, city, state, marital_status),
      cases:case_id (id, number, type, court, comarca)
    `)
    .eq('token', token)
    .single()

  if (error || !data) {
    return { data: null, error: error || new Error('Documento não encontrado ou link expirado.') }
  }

  return { data, error: null }
}

function dataURLtoBlob(dataurl: string) {
  const arr = dataurl.split(',')
  const mime = arr[0].match(/:(.*?);/)?.[1] || 'image/png'
  const bstr = atob(arr[1])
  let n = bstr.length
  const u8arr = new Uint8Array(n)
  while (n--) {
    u8arr[n] = bstr.charCodeAt(n)
  }
  return new Blob([u8arr], { type: mime })
}

export async function confirmSignature(
  token: string,
  payload: {
    selfie: string
    signature: string
    geolocation?: { latitude: number; longitude: number } | null
  },
) {
  try {
    const { data, error } = await supabase.functions.invoke('electronic-signature', {
      body: { action: 'confirmSignature', token, ...payload },
    })
    if (!error && data && !data.error) {
      return { data, error: null }
    }
  } catch (e) {
    console.warn('Edge function error on confirmSignature, using fallback update', e)
  }

  try {
    let selfiePath: string | null = null
    let signaturePath: string | null = null

    if (payload.selfie && payload.selfie.startsWith('data:image')) {
      const selfieBlob = dataURLtoBlob(payload.selfie)
      const fileName = `selfie_${token}_${Date.now()}.png`
      const { data: uploadData } = await supabase.storage
        .from('selfie_images')
        .upload(fileName, selfieBlob, { contentType: 'image/png', upsert: true })
      if (uploadData) selfiePath = uploadData.path
    }

    if (payload.signature && payload.signature.startsWith('data:image')) {
      const sigBlob = dataURLtoBlob(payload.signature)
      const fileName = `sig_${token}_${Date.now()}.png`
      const { data: uploadData } = await supabase.storage
        .from('signature_drawings')
        .upload(fileName, sigBlob, { contentType: 'image/png', upsert: true })
      if (uploadData) signaturePath = uploadData.path
    }

    const { data, error } = await supabase
      .from('document_signatures')
      .update({
        status: 'signed',
        signed_at: new Date().toISOString(),
        selfie_path: selfiePath,
        signature_path: signaturePath,
        geolocation: payload.geolocation || null,
        user_agent: navigator.userAgent,
      })
      .eq('token', token)
      .select()
      .single()

    if (error) return { data: null, error }
    return { data, error: null }
  } catch (err: any) {
    return { data: null, error: { message: err?.message || 'Falha ao processar assinatura.' } }
  }
}

export function getStoragePublicUrl(bucket: string, path: string): string {
  return supabase.storage.from(bucket).getPublicUrl(path).data.publicUrl
}
