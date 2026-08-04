import { supabase } from '@/lib/supabase/client'
import { fixMojibake } from '@/lib/internal-documents'

export { fixMojibake }

export async function generateInternalDocument(params: {
  clientId?: string
  caseId?: string
  docType: string
  customTitle?: string
}) {
  try {
    const { data, error } = await supabase.functions.invoke('electronic-signature', {
      body: {
        action: 'generate',
        clientId: params.clientId,
        caseId: params.caseId,
        docType: params.docType,
        customTitle: params.customTitle,
      },
    })
    return { data, error }
  } catch (err: any) {
    return { data: null, error: err }
  }
}

export async function fetchSignaturesByCase(caseId: string) {
  const { data, error } = await supabase
    .from('document_signatures')
    .select('*, clients(*), cases(*)')
    .eq('case_id', caseId)
    .order('created_at', { ascending: false })

  if (data) {
    data.forEach((sig) => {
      if (sig.doc_type) sig.doc_type = fixMojibake(sig.doc_type)
    })
  }

  return { data, error }
}

export async function getSignatureByToken(token: string) {
  const { data, error } = await supabase
    .from('document_signatures')
    .select('*, clients(*), cases(*)')
    .eq('token', token)
    .single()

  if (data) {
    if (data.doc_type) data.doc_type = fixMojibake(data.doc_type)
    if (data.clients?.name) data.clients.name = fixMojibake(data.clients.name)
    if (data.cases?.process_name) data.cases.process_name = fixMojibake(data.cases.process_name)
  }

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
  try {
    const now = new Date().toISOString()
    const { data: updated, error } = await supabase
      .from('document_signatures')
      .update({
        status: 'signed',
        signed_at: now,
        geolocation: payload.geolocation || null,
        selfie_path: payload.selfie,
        signature_path: payload.signature,
      })
      .eq('token', token)
      .select('*, clients(*), cases(*)')
      .single()

    if (error) return { data: null, error }

    if (updated) {
      if (updated.doc_type) updated.doc_type = fixMojibake(updated.doc_type)
      if (updated.clients?.name) updated.clients.name = fixMojibake(updated.clients.name)
    }

    return { data: updated, error: null }
  } catch (err: any) {
    return { data: null, error: err }
  }
}

export async function getRawDocumentHtml(
  path: string,
  bucket = 'signature_documents',
): Promise<{ success: boolean; html?: string; message?: string }> {
  try {
    if (!path) return { success: false, message: 'Caminho do documento não fornecido.' }

    const { data, error } = await supabase.storage.from(bucket).download(path)
    if (error || !data) {
      return { success: false, message: error?.message || 'Arquivo não encontrado na storage.' }
    }

    const text = await data.text()
    const cleanHtml = fixMojibake(text)

    let finalHtml = cleanHtml
    if (!finalHtml.includes('charset=')) {
      if (finalHtml.includes('<head>')) {
        finalHtml = finalHtml.replace('<head>', '<head><meta charset="UTF-8">')
      } else {
        finalHtml = `<meta charset="UTF-8">\n${finalHtml}`
      }
    }

    return { success: true, html: finalHtml }
  } catch (err: any) {
    return { success: false, message: err.message || 'Erro ao carregar o conteúdo do documento.' }
  }
}

export async function viewOrDownloadDocument(
  path: string,
  bucket = 'signature_documents',
): Promise<{ success: boolean; message?: string }> {
  try {
    if (!path) return { success: false, message: 'Caminho do documento não fornecido.' }

    const { data, error } = await supabase.storage.from(bucket).download(path)

    if (error || !data) {
      const { data: urlData } = await supabase.storage.from(bucket).createSignedUrl(path, 3600)
      if (urlData?.signedUrl) {
        window.open(urlData.signedUrl, '_blank')
        return { success: true }
      }
      return { success: false, message: error?.message || 'Documento não encontrado na storage.' }
    }

    const text = await data.text()
    const trimmed = text.trim().toLowerCase()
    const isHtml =
      trimmed.startsWith('<!doctype html') || trimmed.startsWith('<html') || path.endsWith('.html')

    if (isHtml) {
      const cleanHtml = fixMojibake(text)

      let finalHtml = cleanHtml
      if (!finalHtml.includes('charset=')) {
        if (finalHtml.includes('<head>')) {
          finalHtml = finalHtml.replace('<head>', '<head><meta charset="UTF-8">')
        } else {
          finalHtml = `<meta charset="UTF-8">\n${finalHtml}`
        }
      }

      const blob = new Blob([finalHtml], { type: 'text/html; charset=utf-8' })
      const blobUrl = URL.createObjectURL(blob)

      const win = window.open(blobUrl, '_blank')
      if (!win) {
        window.location.href = blobUrl
      }
      return { success: true }
    } else {
      const blobUrl = URL.createObjectURL(data)
      window.open(blobUrl, '_blank')
      return { success: true }
    }
  } catch (err: any) {
    console.error('Error viewing/downloading document:', err)
    return { success: false, message: err.message || 'Falha ao visualizar o documento.' }
  }
}
