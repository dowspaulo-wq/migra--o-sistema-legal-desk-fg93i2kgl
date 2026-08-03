import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, x-supabase-client-platform, apikey, content-type',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    const { action, token, selfieBase64, geolocation } = await req.json()

    if (action === 'getDoc') {
      const { data, error } = await supabase
        .from('document_signatures')
        .select('*')
        .eq('token', token)
        .single()

      if (error || !data) {
        return new Response(JSON.stringify({ error: 'Documento não encontrado.' }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      let documentContent = null
      if (data.document_path) {
        const { data: fileData } = await supabase.storage
          .from('signed_documents')
          .download(data.document_path)
        if (fileData) {
          documentContent = await fileData.text()
        }
      }

      let client = null
      let caseData = null
      if (data.client_id) {
        const { data: c } = await supabase
          .from('clients')
          .select('*')
          .eq('id', data.client_id)
          .single()
        client = c
      }
      if (data.case_id) {
        const { data: cd } = await supabase
          .from('cases')
          .select('*')
          .eq('id', data.case_id)
          .single()
        caseData = cd
      }

      return new Response(
        JSON.stringify({ ...data, document_content: documentContent, client, case: caseData }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    if (action === 'sign') {
      const { data: record, error: recordError } = await supabase
        .from('document_signatures')
        .select('*')
        .eq('token', token)
        .single()

      if (recordError || !record) {
        return new Response(JSON.stringify({ error: 'Documento não encontrado.' }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      if (record.status === 'signed') {
        return new Response(JSON.stringify({ error: 'Documento já assinado.' }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      let selfiePath = null
      if (selfieBase64) {
        const base64Data = selfieBase64.includes(',') ? selfieBase64.split(',')[1] : selfieBase64
        const binary = atob(base64Data)
        const bytes = new Uint8Array(binary.length)
        for (let i = 0; i < binary.length; i++) {
          bytes[i] = binary.charCodeAt(i)
        }
        selfiePath = `${token}/selfie.jpg`
        await supabase.storage
          .from('signature_photos')
          .upload(selfiePath, bytes, { contentType: 'image/jpeg', upsert: true })
      }

      const ip = req.headers.get('x-forwarded-for') || req.headers.get('x-real-ip') || ''
      const userAgent = req.headers.get('user-agent') || ''

      const { error: updateError } = await supabase
        .from('document_signatures')
        .update({
          status: 'signed',
          selfie_path: selfiePath,
          geolocation: geolocation,
          ip_address: ip,
          user_agent: userAgent,
          signed_at: new Date().toISOString(),
        })
        .eq('token', token)

      if (updateError) {
        return new Response(JSON.stringify({ error: 'Erro ao registrar assinatura.' }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      return new Response(
        JSON.stringify({ success: true, message: 'Documento assinado com sucesso.' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    return new Response(JSON.stringify({ error: 'Ação inválida.' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message || 'Erro interno' }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
