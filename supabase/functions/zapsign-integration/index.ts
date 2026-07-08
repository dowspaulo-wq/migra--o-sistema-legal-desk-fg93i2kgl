import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'jsr:@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const ZAPSIGN_BASE_URL = 'https://api.zapsign.com.br/api/v1'

function escapePdfText(s: string): string {
  return s.replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)')
}

function stringToLatin1Bytes(str: string): Uint8Array {
  const bytes = new Uint8Array(str.length)
  for (let i = 0; i < str.length; i++) {
    bytes[i] = str.charCodeAt(i) & 0xff
  }
  return bytes
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = ''
  const chunkSize = 8192
  for (let i = 0; i < bytes.length; i += chunkSize) {
    const chunk = bytes.subarray(i, i + chunkSize)
    binary += String.fromCharCode(...chunk)
  }
  return btoa(binary)
}

function createPdfFromText(title: string, body: string): string {
  const lines = [title, '', ...body.split('\n')]
  let contentStream = 'BT /F1 11 Tf 50 750 Td 14 TL\n'

  for (let i = 0; i < lines.length; i++) {
    const escaped = escapePdfText(lines[i])
    if (i === 0) {
      contentStream += `(${escaped}) Tj\n`
    } else {
      contentStream += `T* (${escaped}) Tj\n`
    }
  }
  contentStream += 'ET'

  const objects: string[] = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    `<< /Length ${contentStream.length} >>\nstream\n${contentStream}\nendstream`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
  ]

  let pdf = '%PDF-1.4\n'
  const offsets: number[] = []

  for (let i = 0; i < objects.length; i++) {
    offsets.push(pdf.length)
    pdf += `${i + 1} 0 obj\n${objects[i]}\nendobj\n`
  }

  const xrefOffset = pdf.length
  pdf += `xref\n0 ${objects.length + 1}\n`
  pdf += '0000000000 65535 f \n'
  for (const offset of offsets) {
    pdf += `${String(offset).padStart(10, '0')} 00000 n \n`
  }
  pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF`

  return bytesToBase64(stringToLatin1Bytes(pdf))
}

function buildDocContent(
  docType: string,
  client: any,
  caseData: any,
): { title: string; body: string; docName: string } {
  const today = new Date().toLocaleDateString('pt-BR')
  const clientName = client.name || 'N/A'
  const document = client.document || 'N/A'
  const address = client.address || 'N/A'
  const caseNumber = caseData?.number || 'N/A'
  const court = caseData?.court || 'N/A'
  const comarca = caseData?.comarca ? caseData.comarca.toUpperCase() : 'N/A'
  const state = caseData?.state ? caseData.state.toUpperCase() : ''
  const caseValue = caseData?.value
    ? `R$ ${Number(caseData.value).toLocaleString('pt-BR', { minimumFractionDigits: 2 })}`
    : 'A combinar'

  if (docType === 'procuracao') {
    return {
      title: 'PROCURACAO AD JUDICIA ET EXTRA',
      docName: `Procuracao - ${clientName}`,
      body: [
        `OUTORGANTE: ${clientName}`,
        `Nacionalidade: Brasileiro(a)`,
        `Profissao: N/A`,
        `CPF/CNPJ: ${document}`,
        `Endereco: ${address}`,
        '',
        'OUTORGADO: DPSJUR Advocacia e Consultoria Juridica',
        '',
        'Pelos termos da presente procuracao, o(a) OUTORGANTE confere ao(à)',
        'OUTORGADO(A) seus mais amplos poderes para o fim especial de',
        'representa-lo(a) em juizo ou fora dele, em qualquer instancia ou',
        'tribunal, podendo propor acoes, contesta-las, apresentar defesa,',
        'recorrer, desistir, transigir, receber valores, dar quitacao,',
        'substabelecer com ou sem reservas, e praticar todos os atos',
        'necessarios a defesa de seus interesses.',
        '',
        `Especialmente para o processo nº ${caseNumber}, em trambique`,
        `perante a ${court} da Comarca de ${comarca}${state ? ` - ${state}` : ''}.`,
        '',
        `${comarca}${state ? ` - ${state}` : ''}, ${today}.`,
        '',
        '',
        '___________________________________________',
        clientName,
      ].join('\n'),
    }
  }

  if (docType === 'hipossuficiencia') {
    return {
      title: 'DECLARACAO DE HIPOSSUFICIENCIA',
      docName: `Declaracao de Hipossuficiencia - ${clientName}`,
      body: [
        `Eu, ${clientName}, portador(a) do CPF/CNPJ nº ${document},`,
        `residente e domiciliado(a) no endereco ${address}, declaro,`,
        'sob as penas da lei, para os devidos fins de direito e',
        'especialmente para fins de concessao dos beneficios da',
        'Justica Gratuita, nos termos do art. 98 do Codigo de',
        'Processo Civil, que nao tenho condicoes de pagar as custas,',
        'despesas processuais e os honorarios advocaticios sem',
        'prejuizo do meu proprio sustento e do sustento de minha familia.',
        '',
        'Declaro ainda serem verdadeiras todas as informacoes aqui',
        'prestadas, ciente das responsabilidades civil e criminal por',
        'eventuais divergencias.',
        '',
        `Processo relacionado: nº ${caseNumber}`,
        `Vara: ${court}`,
        `Comarca: ${comarca}${state ? ` - ${state}` : ''}`,
        '',
        `${comarca}${state ? ` - ${state}` : ''}, ${today}.`,
        '',
        '',
        '___________________________________________',
        clientName,
      ].join('\n'),
    }
  }

  if (docType === 'contrato') {
    return {
      title: 'CONTRATO DE HONORARIOS ADVOCATICIOS',
      docName: `Contrato de Honorarios - ${clientName}`,
      body: [
        'CONTRATANTE:',
        `Nome: ${clientName}`,
        `CPF/CNPJ: ${document}`,
        `Endereco: ${address}`,
        '',
        'CONTRATADO:',
        'DPSJUR Advocacia e Consultoria Juridica',
        '',
        'CLAUSULA 1a - DO OBJETO',
        `O presente contrato tem por objeto a prestacao de servicos`,
        `advocaticios referentes ao processo nº ${caseNumber}, em`,
        `trambique perante a ${court} da Comarca de ${comarca}${state ? ` - ${state}` : ''}.`,
        '',
        'CLAUSULA 2a - DOS HONORARIOS',
        `Pelos servicos prestados, o CONTRATANTE pagara ao CONTRATADO`,
        `honorarios advocaticios no valor de ${caseValue}.`,
        '',
        'CLAUSULA 3a - DAS OBRIGACOES',
        '3.1. O CONTRATADO compromete-se a desempenhar com zelo e',
        'dedicacao os servicos objeto deste contrato.',
        '3.2. O CONTRATANTE compromete-se a fornecer todas as',
        'informacoes e documentos necessarios.',
        '',
        `${comarca}${state ? ` - ${state}` : ''}, ${today}.`,
        '',
        '',
        '___________________________________________',
        'DPSJUR Advocacia',
        '',
        '___________________________________________',
        clientName,
      ].join('\n'),
    }
  }

  throw new Error('Tipo de documento invalido.')
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const apiToken = Deno.env.get('ZAPSIGN_API_TOKEN')
    if (!apiToken) {
      throw new Error(
        'ZAPSIGN_API_TOKEN nao configurado. Defina o token nas configuracoes do Supabase.',
      )
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !supabaseKey) {
      throw new Error('Variaveis de ambiente do Supabase nao configuradas.')
    }

    const supabase = createClient(supabaseUrl, supabaseKey)
    const { action, caseId, clientId, docType } = await req.json()

    if (action === 'createDoc') {
      const { data: client, error: clientErr } = await supabase
        .from('clients')
        .select('*')
        .eq('id', clientId)
        .single()

      if (clientErr || !client) {
        throw new Error('Cliente nao encontrado.')
      }

      if (!client.email) {
        throw new Error(
          'Cliente nao possui e-mail cadastrado. O e-mail e necessario para a assinatura digital.',
        )
      }

      let caseData: any = null
      if (caseId) {
        const { data: c, error: caseErr } = await supabase
          .from('cases')
          .select('*')
          .eq('id', caseId)
          .single()
        if (!caseErr && c) caseData = c
      }

      const { title, body, docName } = buildDocContent(docType, client, caseData)
      const base64Pdf = createPdfFromText(title, body)

      const zapsignBody = {
        name: docName,
        base64_pdf: base64Pdf,
        lang: 'pt_br',
        signers: [
          {
            email: client.email,
            name: client.name,
          },
        ],
      }

      const res = await fetch(`${ZAPSIGN_BASE_URL}/docs/`, {
        method: 'POST',
        headers: {
          Authorization: `Token ${apiToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(zapsignBody),
      })

      if (!res.ok) {
        const errText = await res.text()
        throw new Error(`Erro ao criar documento no ZapSign: ${errText}`)
      }

      const created = await res.json()
      const docToken = created.token || created.id
      const docUrl = docToken ? `https://app.zapsign.com.br/doc/${docToken}` : null

      return new Response(
        JSON.stringify({
          success: true,
          message: 'Documento criado e enviado para assinatura via ZapSign.',
          url: docUrl,
          token: docToken,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    throw new Error('Acao invalida.')
  } catch (error: any) {
    console.error('ZapSign Integration Error:', error.message || error)
    return new Response(JSON.stringify({ error: error.message || 'Erro interno' }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
