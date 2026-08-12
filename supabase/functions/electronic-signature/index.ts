import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

function sanitizeText(str: string | null | undefined): string {
  if (!str) return ''
  return str
    .replace(/PRESTAA‡ÃfO/g, 'PRESTAÇÃO')
    .replace(/PRESTAA‡ÃƒO/g, 'PRESTAÇÃO')
    .replace(/PRESTAÃ‡Ã̃O/g, 'PRESTAÇÃO')
    .replace(/PRESTAÃ‡ÃfO/g, 'PRESTAÇÃO')
    .replace(/PRESTAÃ‡Ã£O/g, 'PRESTAÇÃO')
    .replace(/SERVIÃ‡OS/g, 'SERVIÇOS')
    .replace(/ADVOCATÃI\?CIOS/g, 'ADVOCATÍCIOS')
    .replace(/ADVOCATÃI?CIOS/g, 'ADVOCATÍCIOS')
    .replace(/ADVOCATÃCIOS/g, 'ADVOCATÍCIOS')
    .replace(/ADVOCATÃi\?cios/g, 'advocatícios')
    .replace(/InterdiÃ§ÃfO/g, 'Interdição')
    .replace(/InterdiÃ§Ã̃o/g, 'Interdição')
    .replace(/JoÃfO/g, 'João')
    .replace(/JoÃ̃o/g, 'João')
    .replace(/condiÃ§ÃfUes/g, 'condições')
    .replace(/condiÃ§Ã̃es/g, 'condições')
    .replace(/prestaÃ§ÃfO/g, 'prestação')
    .replace(/prestaÃ§Ã̃o/g, 'prestação')
    .replace(/serviÃ§os/g, 'serviços')
    .replace(/Ã§ÃfO/g, 'ção')
    .replace(/Ã§Ã̃o/g, 'ção')
    .replace(/Ã§Ã£o/g, 'ção')
    .replace(/Ã‡ÃƒO/g, 'ÇÃO')
    .replace(/Ã‡Ã̃O/g, 'ÇÃO')
    .replace(/Ã§Ãµes/g, 'ções')
    .replace(/Ã§/g, 'ç')
    .replace(/Ã‡/g, 'Ç')
    .replace(/Ã£/g, 'ã')
    .replace(/Ã³/g, 'ó')
    .replace(/Ã´/g, 'ô')
    .replace(/Ãµ/g, 'õ')
    .replace(/Ã¡/g, 'á')
    .replace(/Ã©/g, 'é')
    .replace(/Ãª/g, 'ê')
    .replace(/Ã­/g, 'í')
    .replace(/Ãº/g, 'ú')
    .replace(/Ã¢/g, 'â')
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    const body = await req.json()
    const { action } = body

    if (action === 'generate') {
      const { clientId, caseId, docType, customTitle } = body

      let clientData: any = null
      let caseData: any = null

      if (clientId) {
        const { data: c } = await supabase.from('clients').select('*').eq('id', clientId).single()
        clientData = c
      }

      if (caseId) {
        const { data: cs } = await supabase.from('cases').select('*').eq('id', caseId).single()
        caseData = cs
      }

      const clientName = sanitizeText(clientData?.name || 'Cliente Signatário')
      const clientDoc = sanitizeText(clientData?.document || 'Não informado')
      const caseNumber = sanitizeText(caseData?.number || caseData?.process_name || 'Não informado')
      const caseTitle = sanitizeText(caseData?.process_name || caseData?.description || '')

      const rawDocType = docType || 'Contrato de Prestação de Serviços'
      const sanitizedDocType = sanitizeText(rawDocType)

      let title = 'CONTRATO DE PRESTAÇÃO DE SERVIÇOS ADVOCATÍCIOS'
      if (sanitizedDocType.toLowerCase().includes('procuracao') || sanitizedDocType.toLowerCase().includes('procuração')) {
        title = 'PROCURAÇÃO AD JUDICIA'
      } else if (sanitizedDocType.toLowerCase().includes('hipossuficiencia') || sanitizedDocType.toLowerCase().includes('hipossuficiência')) {
        title = 'DECLARAÇÃO DE HIPOSSUFICIÊNCIA'
      } else if (customTitle) {
        title = sanitizeText(customTitle).toUpperCase()
      }

      const today = new Date().toLocaleDateString('pt-BR')

      const htmlContent = `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title}</title>
  <style>
    body {
      font-family: Arial, Helvetica, sans-serif;
      padding: 40px;
      color: #111827;
      line-height: 1.6;
      max-width: 800px;
      margin: 0 auto;
      background-color: #ffffff;
    }
    h1 {
      text-align: center;
      font-size: 20px;
      font-weight: bold;
      margin-bottom: 28px;
      text-transform: uppercase;
      color: #0f172a;
      border-bottom: 2px solid #e2e8f0;
      padding-bottom: 12px;
    }
    p {
      margin-bottom: 14px;
      text-align: justify;
      font-size: 14px;
      color: #334155;
    }
    .field-line {
      margin-bottom: 10px;
      font-size: 14px;
    }
    .label {
      font-weight: bold;
      color: #0f172a;
    }
    .date-line {
      margin-top: 50px;
      text-align: left;
      font-size: 14px;
      color: #334155;
    }
    .signature-section {
      margin-top: 60px;
      text-align: center;
    }
    .signature-line {
      border-top: 1px solid #000000;
      width: 320px;
      margin: 0 auto 8px auto;
    }
    .signatory-name {
      font-weight: bold;
      font-size: 14px;
      color: #0f172a;
      text-transform: uppercase;
    }
  </style>
</head>
<body>
  <h1>${title}</h1>
  <p class="field-line"><span class="label">CONTRATANTE:</span> ${clientName}, CPF: ${clientDoc}</p>
  ${caseNumber !== 'Não informado' ? `<p class="field-line"><span class="label">Processo:</span> ${caseNumber}${caseTitle ? ` - ${caseTitle}` : ''}</p>` : ''}
  <p>Pelo presente instrumento particular, as partes acordam a prestação de serviços advocatícios conforme condições estabelecidas neste contrato.</p>
  <p class="date-line">Data: ${today}</p>
  <div class="signature-section">
    <div class="signature-line"></div>
    <div class="signatory-name">${clientName}</div>
  </div>
</body>
</html>`

      const token = crypto.randomUUID()
      const fileName = `doc_${token}.html`

      const encoder = new TextEncoder()
      const htmlBytes = encoder.encode(htmlContent)

      const { error: uploadErr } = await supabase.storage
        .from('signature_documents')
        .upload(fileName, htmlBytes, {
          contentType: 'text/html; charset=utf-8',
          upsert: true,
        })

      if (uploadErr) {
        console.error('Storage upload error:', uploadErr)
      }

      const { data: sigData, error: sigErr } = await supabase
        .from('document_signatures')
        .insert({
          token,
          doc_type: sanitizedDocType,
          client_id: clientId || null,
          case_id: caseId || null,
          document_path: fileName,
          status: 'pending',
        })
        .select()
        .single()

      if (sigErr) {
        throw sigErr
      }

      return new Response(
        JSON.stringify({
          success: true,
          token,
          document_path: fileName,
          data: sigData,
        }),
        {
          headers: { 'Content-Type': 'application/json; charset=utf-8', ...corsHeaders },
        },
      )
    }

    if (action === 'get_document_html') {
      const { path } = body
      if (!path) {
        return new Response(
          JSON.stringify({ error: 'Caminho não fornecido' }),
          { status: 400, headers: { 'Content-Type': 'application/json; charset=utf-8', ...corsHeaders } }
        )
      }

      const { data, error: downloadErr } = await supabase.storage
        .from('signature_documents')
        .download(path)

      if (downloadErr || !data) {
        return new Response(
          JSON.stringify({ error: downloadErr?.message || 'Documento não encontrado' }),
          { status: 404, headers: { 'Content-Type': 'application/json; charset=utf-8', ...corsHeaders } }
        )
      }

      const textContent = await data.text()
      const sanitizedHtml = sanitizeText(textContent)

      return new Response(sanitizedHtml, {
        headers: { 'Content-Type': 'text/html; charset=utf-8', ...corsHeaders },
      })
    }

    return new Response(
      JSON.stringify({ error: 'Ação não reconhecida' }),
      { status: 400, headers: { 'Content-Type': 'application/json; charset=utf-8', ...corsHeaders } }
    )
  } catch (err: any) {
    console.error('Error in electronic-signature edge function:', err)
    return new Response(
      JSON.stringify({ error: err.message || 'Erro interno no servidor' }),
      { status: 500, headers: { 'Content-Type': 'application/json; charset=utf-8', ...corsHeaders } }
    )
  }
})
