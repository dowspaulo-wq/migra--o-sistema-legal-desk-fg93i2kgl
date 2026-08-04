import { fixMojibake } from '../../src/lib/internal-documents.ts'

export function getTemplateHtml(
  docType: string,
  clientName: string,
  clientDoc: string,
  caseNumber?: string,
  caseTitle?: string,
): string {
  const name = fixMojibake(clientName || 'Cliente Signatário')
  const doc = fixMojibake(clientDoc || 'Não informado')
  const caseNum = fixMojibake(caseNumber || 'Não informado')
  const caseT = fixMojibake(caseTitle || '')
  const today = new Date().toLocaleDateString('pt-BR')

  let title = 'CONTRATO DE PRESTAÇÃO DE SERVIÇOS ADVOCATÍCIOS'
  const typeLower = fixMojibake(docType || '').toLowerCase()

  if (typeLower.includes('procuracao') || typeLower.includes('procuração')) {
    title = 'PROCURAÇÃO AD JUDICIA'
  } else if (typeLower.includes('hipossuficiencia') || typeLower.includes('hipossuficiência')) {
    title = 'DECLARAÇÃO DE HIPOSSUFICIÊNCIA'
  }

  return `<!DOCTYPE html>
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
  <p class="field-line"><span class="label">CONTRATANTE:</span> ${name}, CPF: ${doc}</p>
  ${caseNum !== 'Não informado' ? `<p class="field-line"><span class="label">Processo:</span> ${caseNum}${caseT ? ` - ${caseT}` : ''}</p>` : ''}
  <p>Pelo presente instrumento particular, as partes acordam a prestação de serviços advocatícios conforme condições estabelecidas neste contrato.</p>
  <p class="date-line">Data: ${today}</p>
  <div class="signature-section">
    <div class="signature-line"></div>
    <div class="signatory-name">${name}</div>
  </div>
</body>
</html>`
}
