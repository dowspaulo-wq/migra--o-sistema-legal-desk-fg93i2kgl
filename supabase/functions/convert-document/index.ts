import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { corsHeaders } from '../_shared/cors.ts'

/**
 * CONVERT DOCUMENT EDGE FUNCTION (DPSjur / SBJur)
 *
 * Endpoint de conversão DOCX -> PDF com alta fidelidade:
 * 1. Health check via GET / POST com { action: 'status' }
 * 2. Conversão via POST multipart/form-data (campo 'file') ou JSON { docxBase64, fileName }
 * 3. Encaminha para o serviço Gotenberg/LibreOffice no VPS (ex: http://gotenberg:3000 ou http://127.0.0.1:3000)
 *    configurado via variável GOTENBERG_URL ou fallback para rede interna do Docker.
 * 4. Se o Gotenberg ainda não estiver ativo no VPS, retorna status explicativo orientando
 *    a execução do script docs/vps/03-instalar-conversor-pdf-vps.sh.
 */

const DEFAULT_GOTENBERG_URL =
  Deno.env.get('GOTENBERG_URL') ||
  Deno.env.get('LIBREOFFICE_CONVERT_URL') ||
  'http://gotenberg:3000'

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const url = new URL(req.url)

  // 1. Health check rápido
  if (req.method === 'GET' || url.searchParams.get('action') === 'status') {
    let gotenbergOnline = false
    let detail = 'Gotenberg / LibreOffice não respondeu'

    try {
      const controller = new AbortController()
      const tId = setTimeout(() => controller.abort(), 2000)
      const healthRes = await fetch(`${DEFAULT_GOTENBERG_URL}/health`, {
        signal: controller.signal,
      })
      clearTimeout(tId)
      if (healthRes.ok) {
        gotenbergOnline = true
        detail = 'Gotenberg / LibreOffice está pronto para conversão de alta fidelidade.'
      }
    } catch (e: any) {
      detail = `Gotenberg não alcançado em ${DEFAULT_GOTENBERG_URL}: ${e?.message || 'timeout/conexão recusada'}`
    }

    return new Response(
      JSON.stringify({
        status: gotenbergOnline ? 'ready' : 'unavailable',
        gotenbergOnline,
        gotenbergUrl: DEFAULT_GOTENBERG_URL,
        detail,
        instructions:
          'Para habilitar conversão fiel no VPS, execute no terminal do VPS: docs/vps/03-instalar-conversor-pdf-vps.sh',
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      },
    )
  }

  // 2. Ação de conversão DOCX -> PDF
  try {
    let docxBytes: Uint8Array | null = null
    let fileName = 'documento.docx'

    const contentType = req.headers.get('content-type') || ''

    if (contentType.includes('multipart/form-data')) {
      const formData = await req.formData()
      const file = formData.get('file')
      if (file && file instanceof File) {
        fileName = file.name || fileName
        docxBytes = new Uint8Array(await file.arrayBuffer())
      }
    } else if (contentType.includes('application/json')) {
      const body = await req.json()
      if (body.action === 'status') {
        // Fallback status request
        return new Response(
          JSON.stringify({
            status: 'ready',
            endpoint: 'convert-document',
          }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }
      if (body.docxBase64) {
        const binaryStr = atob(body.docxBase64)
        docxBytes = new Uint8Array(binaryStr.length)
        for (let i = 0; i < binaryStr.length; i++) {
          docxBytes[i] = binaryStr.charCodeAt(i)
        }
        if (body.fileName) fileName = body.fileName
      }
    } else {
      // Raw binary body
      const buf = await req.arrayBuffer()
      if (buf.byteLength > 0) {
        docxBytes = new Uint8Array(buf)
      }
    }

    if (!docxBytes || docxBytes.byteLength === 0) {
      return new Response(
        JSON.stringify({
          error: 'Nenhum arquivo .docx fornecido para conversão.',
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      )
    }

    // Tentar converter via Gotenberg / LibreOffice
    // Gotenberg API: POST /forms/libreoffice/convert com multipart field "files"
    const candidateUrls = [
      DEFAULT_GOTENBERG_URL,
      'http://127.0.0.1:3000',
      'http://localhost:3000',
      'http://gotenberg:3000',
    ]
    const uniqUrls = Array.from(new Set(candidateUrls))

    let pdfBlob: Blob | null = null
    let lastError: string = 'Gotenberg não configurado'

    for (const gUrl of uniqUrls) {
      try {
        const form = new FormData()
        const docxBlob = new Blob([docxBytes], {
          type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        })
        form.append('files', docxBlob, fileName.endsWith('.docx') ? fileName : `${fileName}.docx`)

        const convertController = new AbortController()
        const timeout = setTimeout(() => convertController.abort(), 25000)

        const convertRes = await fetch(`${gUrl}/forms/libreoffice/convert`, {
          method: 'POST',
          body: form,
          signal: convertController.signal,
        })
        clearTimeout(timeout)

        if (convertRes.ok) {
          pdfBlob = await convertRes.blob()
          break
        } else {
          lastError = `Gotenberg ${gUrl} retornou HTTP ${convertRes.status}: ${await convertRes.text()}`
        }
      } catch (err: any) {
        lastError = `Falha ao conectar com ${gUrl}: ${err?.message || String(err)}`
      }
    }

    if (pdfBlob) {
      const pdfBytes = new Uint8Array(await pdfBlob.arrayBuffer())
      const basePdfName = fileName.replace(/\.docx$/i, '') + '.pdf'

      // Se o cliente solicitou JSON base64
      if (
        url.searchParams.get('format') === 'json' ||
        req.headers.get('accept')?.includes('application/json')
      ) {
        let binary = ''
        const len = pdfBytes.byteLength
        for (let i = 0; i < len; i++) {
          binary += String.fromCharCode(pdfBytes[i])
        }
        const b64 = btoa(binary)
        return new Response(
          JSON.stringify({
            success: true,
            fileName: basePdfName,
            pdfBase64: b64,
            sizeBytes: pdfBytes.byteLength,
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
          },
        )
      }

      // Retorno binário direto do PDF
      return new Response(pdfBytes, {
        status: 200,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/pdf',
          'Content-Disposition': `attachment; filename="${encodeURIComponent(basePdfName)}"`,
        },
      })
    }

    // Se o conversor do VPS ainda não está disponível
    return new Response(
      JSON.stringify({
        error:
          'O serviço de conversão fiel de DOCX para PDF (LibreOffice / Gotenberg) não está ativo no VPS.',
        details: lastError,
        requiresScript: true,
        scriptCommand:
          'curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/vps/03-instalar-conversor-pdf-vps.sh" -o /root/03-instalar-conversor-pdf-vps.sh && bash /root/03-instalar-conversor-pdf-vps.sh',
      }),
      {
        status: 503,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    )
  } catch (err: any) {
    return new Response(
      JSON.stringify({
        error: 'Erro interno ao processar conversão de documento.',
        message: err?.message || String(err),
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    )
  }
})
