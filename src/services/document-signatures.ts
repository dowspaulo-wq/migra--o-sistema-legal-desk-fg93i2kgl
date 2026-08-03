import { supabase } from '@/lib/supabase/client'
import { buildDocumentHtml } from '@/lib/internal-documents'

export async function generateInternalDocument(caseId: string, clientId: string, docType: string) {
  const { data: client, error: clientErr } = await supabase
    .from('clients')
    .select('*')
    .eq('id', clientId)
    .single()
  if (clientErr || !client) return { error: { message: 'Cliente não encontrado.' } }

  const { data: caseData, error: caseErr } = await supabase
    .from('cases')
    .select('*')
    .eq('id', caseId)
    .single()
  if (caseErr || !caseData) return { error: { message: 'Processo não encontrado.' } }

  const html = buildDocumentHtml(docType, client, caseData)
  const token = crypto.randomUUID()
  const fileName = `${token}/${docType}.html`
  const blob = new Blob([html], { type: 'text/html' })

  const { error: uploadErr } = await supabase.storage
    .from('signed_documents')
    .upload(fileName, blob)
  if (uploadErr) return { error: { message: 'Erro ao salvar documento.' } }

  const { data, error } = await supabase
    .from('document_signatures')
    .insert({
      token,
      doc_type: docType,
      client_id: clientId,
      case_id: caseId,
      document_path: fileName,
      status: 'pending',
    })
    .select()
    .single()

  if (error) return { error: { message: 'Erro ao criar registro de assinatura.' } }

  const signUrl = `${window.location.origin}/assinar/${token}`
  return { data: { ...data, signUrl }, error: null }
}

export async function getSignatureByToken(token: string) {
  const { data, error } = await supabase.functions.invoke('electronic-signature', {
    body: { action: 'getDoc', token },
  })
  if (!error && data?.error) return { data: null, error: { message: data.error } }
  return { data, error }
}

export async function submitSignature(
  token: string,
  selfieBase64: string,
  geolocation: { lat: number; lng: number },
) {
  const { data, error } = await supabase.functions.invoke('electronic-signature', {
    body: { action: 'sign', token, selfieBase64, geolocation },
  })
  if (!error && data?.error) return { data: null, error: { message: data.error } }
  return { data, error }
}
