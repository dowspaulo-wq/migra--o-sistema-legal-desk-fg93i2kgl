export function buildDocumentHtml(docType: string, client: any, caseData: any): string {
  const today = new Date().toLocaleDateString('pt-BR')
  const name = client.name || 'N/A'
  const doc = client.document || 'N/A'
  const addr =
    [client.street, client.number, client.neighborhood, client.city, client.state]
      .filter(Boolean)
      .join(', ') ||
    client.address ||
    'N/A'
  const caseNum = caseData?.number || 'N/A'
  const court = caseData?.court || 'N/A'
  const comarca = caseData?.comarca?.toUpperCase() || 'N/A'
  const state = caseData?.state?.toUpperCase() || ''
  const processName = caseData?.process_name || ''
  const reu = caseData?.adverseParty || 'N/A'
  const marital = client.marital_status || ''
  const loc = `${comarca}${state ? ` - ${state}` : ''}`
  const style = `<style>body{font-family:'Times New Roman',serif;line-height:1.8;max-width:800px;margin:0 auto;padding:40px;color:#1a1a1a}h1{text-align:center;text-transform:uppercase;font-size:16px;letter-spacing:1px;margin-bottom:40px}.c{margin-bottom:20px;text-align:justify}.sig{margin-top:80px;text-align:center}.ln{border-top:1px solid #000;width:300px;margin:0 auto 5px}.fi{text-align:center;font-size:14px}</style>`
  const footer = `<div class="sig"><div class="ln"></div><div class="fi">${name}</div><div class="fi">CPF/CNPJ: ${doc}</div></div>`
  const dateLine = `<p style="text-align:center;margin-top:40px;">${loc}, ${today}</p>`

  if (docType === 'procuracao') {
    return `<html><head><meta charset="utf-8">${style}</head><body><h1>Procuração Ad Judicia et Extra</h1><div class="c"><strong>OUTORGANTE:</strong> ${name}${marital ? `, ${marital}` : ''}, portador(a) do CPF/CNPJ nº ${doc}, residente e domiciliado(a) em ${addr}.</div><div class="c"><strong>OUTORGADO:</strong> DPSJUR Advocacia e Consultoria Jurídica.</div><div class="c">Pelos termos da presente procuração, o(a) OUTORGANTE confere ao(à) OUTORGADO(A) seus mais amplos poderes para o fim especial de representá-lo(a) em juízo ou fora dele, em qualquer instância ou tribunal, podendo propor ações, contestá-las, apresentar defesa, recorrer, desistir, transigir, receber valores, dar quitação, substabelecer com ou sem reservas, e praticar todos os atos necessários à defesa de seus interesses.</div><div class="c">Especialmente para o processo nº ${caseNum}${processName ? ` (${processName})` : ''} em trâmite perante a ${court} da Comarca de ${loc}, em face de ${reu}.</div>${dateLine}${footer}</body></html>`
  }

  if (docType === 'hipossuficiencia') {
    return `<html><head><meta charset="utf-8">${style}</head><body><h1>Declaração de Hipossuficiência</h1><div class="c">Eu, ${name}${marital ? `, ${marital}` : ''}, portador(a) do CPF/CNPJ nº ${doc}, residente e domiciliado(a) no endereço ${addr}, declaro, sob as penas da lei, para os devidos fins de direito e especialmente para fins de concessão dos benefícios da Justiça Gratuita, nos termos do art. 98 do Código de Processo Civil, que não tenho condições de pagar as custas, despesas processuais e os honorários advocatícios sem prejuízo do meu próprio sustento e do sustento de minha família.</div><div class="c">Declaro ainda serem verdadeiras todas as informações aqui prestadas, ciente das responsabilidades civil e criminal por eventuais divergências.</div>${dateLine}${footer}</body></html>`
  }

  if (docType === 'contrato') {
    return `<html><head><meta charset="utf-8">${style}</head><body><h1>Contrato de Prestação de Serviços</h1><div class="c"><strong>CONTRATANTE:</strong> ${name}, portador(a) do CPF/CNPJ nº ${doc}, residente e domiciliado(a) em ${addr}.</div><div class="c"><strong>CONTRATADO:</strong> DPSJUR Advocacia e Consultoria Jurídica.</div><div class="c"><strong>CLÁUSULA 1ª - DO OBJETO:</strong> O presente contrato tem por objeto a prestação de serviços advocatícios referentes ao processo nº ${caseNum}${processName ? ` (${processName})` : ''}, em trâmite perante a ${court} da Comarca de ${loc}, em face de ${reu}.</div><div class="c"><strong>CLÁUSULA 2ª - DAS OBRIGAÇÕES:</strong> O CONTRATADO compromete-se a desempenhar com zelo e dedicação os serviços objeto deste contrato. O CONTRATANTE compromete-se a fornecer todas as informações e documentos necessários.</div><div class="c"><strong>CLÁUSULA 3ª - DOS HONORÁRIOS:</strong> Os honorários advocatícios serão pactuados separadamente, conforme acordo entre as partes.</div>${dateLine}<div class="sig"><div class="ln"></div><div class="fi">DPSJUR Advocacia</div></div><div class="sig" style="margin-top:40px"><div class="ln"></div><div class="fi">${name}</div><div class="fi">CPF/CNPJ: ${doc}</div></div></body></html>`
  }

  return ''
}
