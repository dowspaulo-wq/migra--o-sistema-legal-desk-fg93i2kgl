import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { getDocHtml } from '../_shared/doc-templates.ts'

const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)

function b64ToBlob(dataUrl: string, contentType: string): Blob {
  const base64 = dataUrl.split(',')[1]
  const raw = atob(base64)
  const bytes = new Uint8Array(raw.length)
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i)
  return new Blob([bytes], { type: contentType })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  const body = await req.json()
  const headers = { 'Content-Type': 'application/json', ...corsHeaders }

  if (body.action === 'generateDoc') {
    const { caseId, clientId, docType } = body
    const { data: client } = await sb.from('clients').select('*').eq('id', clientId).single()
    const { data: caseData } = await sb.from('cases').select('*').eq('id', caseId).single()
    const html = getDocHtml(docType, client, caseData)
    const fileName = `${docType}_${caseId}_${Date.now()}.html`
    const { error: uploadErr } = await sb.storage
      .from('signature_documents')
      .upload(fileName, new Blob([html], { type: 'text/html' }), { contentType: 'text/html' })
    if (uploadErr)
      return new Response(JSON.stringify({ error: uploadErr.message }), { status: 500, headers })
    const token = crypto.randomUUID()
    const { error: insertErr } = await sb.from('document_signatures').insert({
      token,
      doc_type: docType,
      client_id: clientId,
      case_id: caseId,
      document_path: fileName,
      status: 'pending',
    })
    if (insertErr)
      return new Response(JSON.stringify({ error: insertErr.message }), { status: 500, headers })
    return new Response(JSON.stringify({ token }), { headers })
  }

  if (body.action === 'getByToken') {
    const { data: sig } = await sb
      .from('document_signatures')
      .select('*')
      .eq('token', body.token)
      .single()
    if (!sig)
      return new Response(JSON.stringify({ error: 'Document not found' }), { status: 404, headers })
    let documentContent = ''
    if (sig.document_path) {
      const { data: file } = await sb.storage
        .from('signature_documents')
        .download(sig.document_path)
      if (file) documentContent = await file.text()
    }
    return new Response(JSON.stringify({ ...sig, documentContent }), { headers })
  }

  if (body.action === 'confirmSignature') {
    const { token, selfie, signature, geolocation } = body
    const { data: sig } = await sb
      .from('document_signatures')
      .select('*')
      .eq('token', token)
      .single()
    if (!sig) return new Response(JSON.stringify({ error: 'Not found' }), { status: 404, headers })
    if (sig.status === 'signed')
      return new Response(JSON.stringify({ error: 'Already signed' }), { status: 400, headers })
    const selfiePath = `selfie_${sig.id}_${Date.now()}.png`
    const sigPath = `signature_${sig.id}_${Date.now()}.png`
    await sb.storage
      .from('signature_photos')
      .upload(selfiePath, b64ToBlob(selfie, 'image/png'), { contentType: 'image/png' })
    await sb.storage
      .from('signature_drawings')
      .upload(sigPath, b64ToBlob(signature, 'image/png'), { contentType: 'image/png' })
    const ip =
      req.headers.get('x-forwarded-for')?.split(',')[0] || req.headers.get('x-real-ip') || 'unknown'
    const userAgent = req.headers.get('user-agent') || 'unknown'
    const { error } = await sb
      .from('document_signatures')
      .update({
        selfie_path: selfiePath,
        signature_path: sigPath,
        geolocation,
        ip_address: ip,
        user_agent: userAgent,
        signed_at: new Date().toISOString(),
        status: 'signed',
      })
      .eq('id', sig.id)
    if (error)
      return new Response(JSON.stringify({ error: error.message }), { status: 500, headers })
    return new Response(JSON.stringify({ success: true }), { headers })
  }

  return new Response(JSON.stringify({ error: 'Invalid action' }), { status: 400, headers })
})
