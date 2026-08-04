export function fixMojibake(str: string | null | undefined): string {
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

export function generateContractHtml(params: {
  clientName: string
  clientDoc: string
  caseNumber?: string
  caseTitle?: string
  date?: string
}): string {
  const clientName = fixMojibake(params.clientName || 'Cliente Signatário')
  const clientDoc = fixMojibake(params.clientDoc || 'Não informado')
  const caseNumber = fixMojibake(params.caseNumber || 'Não informado')
  const caseTitle = fixMojibake(params.caseTitle || '')
  const dateStr = params.date || new Date().toLocaleDateString('pt-BR')

  return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>CONTRATO DE PRESTAÇÃO DE SERVIÇOS ADVOCATÍCIOS</title>
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
  <h1>CONTRATO DE PRESTAÇÃO DE SERVIÇOS ADVOCATÍCIOS</h1>
  <p class="field-line"><span class="label">CONTRATANTE:</span> ${clientName}, CPF: ${clientDoc}</p>
  ${caseNumber !== 'Não informado' ? `<p class="field-line"><span class="label">Processo:</span> ${caseNumber}${caseTitle ? ` - ${caseTitle}` : ''}</p>` : ''}
  <p>Pelo presente instrumento particular, as partes acordam a prestação de serviços advocatícios conforme condições estabelecidas neste contrato.</p>
  <p class="date-line">Data: ${dateStr}</p>
  <div class="signature-section">
    <div class="signature-line"></div>
    <div class="signatory-name">${clientName}</div>
  </div>
</body>
</html>`
}
