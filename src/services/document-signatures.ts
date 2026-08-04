import { supabase } from '@/lib/supabase/client'

export async function generateInternalDocument(caseId: string, clientId: string, docType: string) {
  try {
    const { data, error } = await supabase.functions.invoke('electronic-signature', {
      body: { action: 'generateDoc', caseId, clientId, docType },
    })
    if (!error && data?.error) return { data: null, error: { message: data.error } }
    if (data?.token) {
      data.signUrl = `${window.location.origin}/assinar/${data.token}`
    }
    return { data, error }
  } catch (err: any) {
    return { data: null, error: { message: err?.message || 'Erro ao gerar documento.' } }
  }
}

export async function fetchSignaturesByCase(caseId: string) {
  if (!caseId) return { data: [], error: null }
  try {
    const { data, error } = await supabase
      .from('document_signatures')
      .select('*')
      .eq('case_id', caseId)
      .order('created_at', { ascending: false })
    return { data: data || [], error }
  } catch (err: any) {
    console.error('Error fetching signatures:', err)
    return { data: [], error: err }
  }
}

export async function getSignatureByToken(token: string) {
  if (!token) {
    return { data: null, error: new Error('Token de assinatura não fornecido.') }
  }

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

  try {
    const { data, error } = await supabase
      .from('document_signatures')
      .select(`
        *,
        clients:client_id (id, name, document, email, phone, street, number, complement, neighborhood, city, state, marital_status),
        cases:case_id (id, number, type, court, comarca)
      `)
      .eq('token', token)
      .maybeSingle()

    if (error || !data) {
      return { data: null, error: error || new Error('Documento não encontrado ou link expirado.') }
    }

    return { data, error: null }
  } catch (err: any) {
    return { data: null, error: err || new Error('Erro ao buscar documento para assinatura.') }
  }
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
      .maybeSingle()

    if (error) return { data: null, error }
    return { data, error: null }
  } catch (err: any) {
    return { data: null, error: { message: err?.message || 'Falha ao processar assinatura.' } }
  }
}

export function getStoragePublicUrl(bucket: string, path: string): string {
  if (!path) return ''
  if (path.startsWith('http://') || path.startsWith('https://')) return path
  const targetBucket = bucket || 'signature_documents'
  let cleanPath = path
  if (cleanPath.startsWith(`${targetBucket}/`)) {
    cleanPath = cleanPath.substring(targetBucket.length + 1)
  }
  return supabase.storage.from(targetBucket).getPublicUrl(cleanPath).data.publicUrl
}

export async function getDocumentFileUrl(
  path: string,
  preferredBucket: string = 'signature_documents',
): Promise<{ url: string | null; error: string | null }> {
  if (!path) return { url: null, error: 'Caminho do documento não informado.' }

  if (path.startsWith('http://') || path.startsWith('https://')) {
    return { url: path, error: null }
  }

  const bucketsToTry = Array.from(
    new Set([preferredBucket, 'signature_documents', 'signed_documents', 'documents']),
  )

  for (const bucket of bucketsToTry) {
    let cleanPath = path
    if (cleanPath.startsWith(`${bucket}/`)) {
      cleanPath = cleanPath.substring(bucket.length + 1)
    }

    try {
      const { data: signedData, error: signedErr } = await supabase.storage
        .from(bucket)
        .createSignedUrl(cleanPath, 3600)

      if (!signedErr && signedData?.signedUrl) {
        return { url: signedData.signedUrl, error: null }
      }

      const { data: pubData } = supabase.storage.from(bucket).getPublicUrl(cleanPath)
      if (pubData?.publicUrl) {
        return { url: pubData.publicUrl, error: null }
      }
    } catch (e) {
      console.warn(`Error resolving storage URL for bucket ${bucket}:`, e)
    }
  }

  return { url: null, error: 'Documento não encontrado ou ainda não processado.' }
}

export async function viewOrDownloadDocument(
  path: string | null | undefined,
  preferredBucket: string = 'signature_documents',
): Promise<{ success: boolean; message?: string; url?: string }> {
  if (!path) {
    return { success: false, message: 'Documento não encontrado ou ainda não processado.' }
  }

  try {
    const { url, error } = await getDocumentFileUrl(path, preferredBucket)
    if (error || !url) {
      return {
        success: false,
        message: error || 'Documento não encontrado ou ainda não processado.',
      }
    }

    const win = window.open(url, '_blank', 'noopener,noreferrer')
    if (!win) {
      window.location.href = url
    }
    return { success: true, url }
  } catch (err: any) {
    console.error('Error viewing document:', err)
    return { success: false, message: err?.message || 'Erro ao abrir documento.' }
  }
}
