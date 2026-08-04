export function getDocHtml(docType: string, client: any, caseData: any): string {
  const name = client?.name || '---'
  const doc = client?.document || '---'
  const cnj = caseData?.number || '---'
  const date = new Date().toLocaleDateString('pt-BR')

  const templates: Record<string, string> = {
    procuracao: `<html><body style="font-family:Arial;padding:40px;">
<h1 style="text-align:center;">PROCURAÇÃO AD JUDICIA</h1>
<p><strong>OUTORGANTE:</strong> ${name}, CPF: ${doc}</p>
<p><strong>Processo:</strong> ${cnj}</p>
<p>Pelo presente instrumento, o outorgante nomeia e constitui como seu procurador o advogado abaixo assinado, com poderes para o foro em geral, e em especial para promover, defender e acompanhar as causas e processos, podendo receber citação, confessar, transigir, desistir, renunciar, receber, dar quitação e substabelecer.</p>
<p style="margin-top:60px;">Data: ${date}</p>
<p style="margin-top:40px;">_________________________________________<br/>${name}</p>
</body></html>`,
    hipossuficiencia: `<html><body style="font-family:Arial;padding:40px;">
<h1 style="text-align:center;">DECLARAÇÃO DE HIPOSSUFICIÊNCIA</h1>
<p>Eu, <strong>${name}</strong>, CPF: <strong>${doc}</strong>, declaro para os devidos fins de direito, especialmente para concessão da gratuidade da justiça, nos termos do art. 5º, LXXIV, da CF e art. 98 do CPC, que não tenho condições de pagar as custas e despesas do processo sem prejuízo do meu próprio sustento e de minha família.</p>
<p><strong>Processo:</strong> ${cnj}</p>
<p style="margin-top:60px;">Data: ${date}</p>
<p style="margin-top:40px;">_________________________________________<br/>${name}</p>
</body></html>`,
    contrato: `<html><body style="font-family:Arial;padding:40px;">
<h1 style="text-align:center;">CONTRATO DE PRESTAÇÃO DE SERVIÇOS ADVOCATÍCIOS</h1>
<p><strong>CONTRATANTE:</strong> ${name}, CPF: ${doc}</p>
<p><strong>Processo:</strong> ${cnj}</p>
<p>Pelo presente instrumento particular, as partes acordam a prestação de serviços advocatícios conforme condições estabelecidas neste contrato.</p>
<p style="margin-top:60px;">Data: ${date}</p>
<p style="margin-top:40px;">_________________________________________<br/>${name}</p>
</body></html>`,
  }
  return templates[docType] || templates.procuracao
}
