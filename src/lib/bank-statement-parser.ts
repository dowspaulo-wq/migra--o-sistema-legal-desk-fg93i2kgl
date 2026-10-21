export interface ParsedBankStatementItem {
  id: string
  date: string // YYYY-MM-DD
  rawDate: string
  description: string
  amount: number
  type: 'income' | 'expense'
  rawAmount: string
  confidence: 'high' | 'medium' | 'low'
  selected: boolean
  categorySuggestion?: string
}

// Converte texto em linhas limpas
export function cleanTextLines(text: string): string[] {
  return text
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l.length > 0)
}

// Extrai data no formato YYYY-MM-DD a partir de dd/mm/yyyy ou dd/mm/yy ou dd/mm
function parseBrazilianDate(dateStr: string, defaultYear?: number): string | null {
  const fullMatch = dateStr.match(/(\d{2})\/(\d{2})\/(\d{4}|\d{2})/)
  if (fullMatch) {
    const day = fullMatch[1]
    const month = fullMatch[2]
    let year = fullMatch[3]
    if (year.length === 2) {
      year = `20${year}`
    }
    return `${year}-${month}-${day}`
  }

  // Fatura de cartão costuma ter apenas dd/mm (ex: 15/10 GOOGLE ADS)
  const shortMatch = dateStr.match(/^(\d{2})\/(\d{2})$/)
  if (shortMatch) {
    const day = shortMatch[1]
    const month = shortMatch[2]
    const year = defaultYear || new Date().getFullYear()
    return `${year}-${month}-${day}`
  }

  return null
}

// Converte string monetária brasileira para número
function parseBrazilianCurrency(valStr: string): { amount: number; isNegative: boolean } | null {
  if (!valStr) return null
  const clean = valStr.trim()
  const isNegative =
    clean.startsWith('-') || clean.endsWith('-') || clean.endsWith('D') || clean.includes(' D')

  // Remove R$, espaços, e sinais
  let numStr = clean
    .replace(/R\$/g, '')
    .replace(/[+\-D]/g, '')
    .trim()
  // Se tem pontos como milhar e vírgula como decimal (ex: 1.234,56 ou 1234,56)
  if (numStr.includes(',')) {
    numStr = numStr.replace(/\./g, '').replace(',', '.')
  } else if ((numStr.match(/\./g) || []).length === 1 && numStr.split('.')[1].length === 2) {
    // Formato com ponto decimal
  }

  const num = parseFloat(numStr)
  if (isNaN(num)) return null
  return { amount: Math.abs(num), isNegative }
}

/**
 * Parser heurístico de extratos bancários brasileiros (Sicoob, Caixa, BB, Bradesco, Santander, Itaú, Inter).
 * Não utiliza inteligência artificial: baseado em regex determinístico.
 */
export function parseBankStatementText(rawText: string): ParsedBankStatementItem[] {
  const lines = cleanTextLines(rawText)
  const results: ParsedBankStatementItem[] = []

  // Regex comum para linha de extrato ou fatura de cartão:
  // Exemplo: 02/03/2026 Pix Enviado Fulano -150,00 ou 150,00 D ou R$ 150,00
  // Também aceita dd/mm no início da linha para faturas de cartão (Santander, Inter)
  const dateRegex = /\b(\d{2}\/\d{2}\/(?:\d{4}|\d{2}))\b/
  const shortDateRegex = /^\s*(\d{2}\/\d{2})\b/
  const currencyRegex =
    /([+-]?\s*(?:R\$\s*|US\$\s*)?\d{1,3}(?:\.\d{3})*,\d{2}\s*(?:[CD-])?|[+-]?\s*(?:R\$\s*|US\$\s*)?\d+,\d{2}\s*(?:[CD-])?)/i

  // Tenta extrair ano de referência do cabeçalho se houver (para faturas dd/mm)
  let referenceYear = new Date().getFullYear()
  for (let h = 0; h < Math.min(lines.length, 15); h++) {
    const yMatch = lines[h].match(/\b(202\d)\b/)
    if (yMatch) {
      referenceYear = parseInt(yMatch[1], 10)
      break
    }
  }

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]

    // Ignora cabeçalhos e rodapés comuns
    if (
      /saldo\s+anterior|saldo\s+do\s+dia|saldo\s+atual|folha\s+\d|p[aá]gina\s+\d|limite\s+dispon[ií]vel|total\s+da\s+fatura|pagamento\s+m[ií]nimo/i.test(
        line,
      ) &&
      !/google|meta|ads|facebk|honor/i.test(line)
    ) {
      continue
    }

    let dateMatch = line.match(dateRegex)
    let isShortDate = false
    if (!dateMatch) {
      dateMatch = line.match(shortDateRegex)
      isShortDate = Boolean(dateMatch)
    }
    if (!dateMatch) continue

    const isoDate = parseBrazilianDate(dateMatch[1], referenceYear)
    if (!isoDate) continue

    // Extrai valores monetários presentes na linha
    const valMatches = Array.from(line.matchAll(new RegExp(currencyRegex.source, 'gi')))
    if (valMatches.length === 0) continue

    // Geralmente o valor do lançamento é o último ou penúltimo valor da linha (evitando pegar saldos quando presentes)
    // Se houver mais de um valor, o último costuma ser o saldo do dia em extratos Caixa/BB, então pegamos o primeiro ou o que tem sinal
    let chosenValMatch = valMatches[valMatches.length - 1][0]
    if (valMatches.length >= 2) {
      const matchWithSign = valMatches.find((m) => /[CD\-+]/i.test(m[0]))
      if (matchWithSign) {
        chosenValMatch = matchWithSign[0]
      } else {
        // Pega o penúltimo se houver 2 valores (valor + saldo)
        chosenValMatch = valMatches[0][0]
      }
    }

    const parsedCurr = parseBrazilianCurrency(chosenValMatch)
    if (!parsedCurr || parsedCurr.amount === 0) continue

    // Determina descrição removendo a data e o valor da linha
    let desc = line
      .replace(dateMatch[0], '')
      .replace(chosenValMatch, '')
      .replace(/\s+/g, ' ')
      .trim()

    // Se a descrição ficou vazia, pode ser que ela esteja na linha imediatamente anterior ou posterior
    if (desc.length < 3) {
      if (i > 0 && !lines[i - 1].match(dateRegex) && lines[i - 1].length > 3) {
        desc = lines[i - 1]
      } else if (i + 1 < lines.length && !lines[i + 1].match(dateRegex)) {
        desc = lines[i + 1]
      } else {
        desc = `Lançamento extrato bancário ${dateMatch[1]}`
      }
    }

    // Identificação de débito (saída) vs crédito (entrada)
    const upperLine = line.toUpperCase()
    const isExplicitDebit =
      upperLine.includes(' D') ||
      upperLine.endsWith('D') ||
      upperLine.includes('DEBITO') ||
      upperLine.includes('DÉBITO') ||
      upperLine.includes('PAGAMENTO') ||
      upperLine.includes('TARIFA') ||
      upperLine.includes('COMPRA') ||
      upperLine.includes('TRANSFERENCIA ENVIADA') ||
      upperLine.includes('PIX ENVIADO') ||
      upperLine.includes('GOOGLE') ||
      upperLine.includes('META') ||
      upperLine.includes('FACEBK') ||
      parsedCurr.isNegative

    const isExplicitCredit =
      upperLine.includes(' C') ||
      upperLine.endsWith('C') ||
      upperLine.includes('CREDITO') ||
      upperLine.includes('CRÉDITO') ||
      upperLine.includes('RECEBIMENTO') ||
      upperLine.includes('DEPOSITO') ||
      upperLine.includes('DEPÓSITO') ||
      upperLine.includes('TRANSFERENCIA RECEBIDA') ||
      upperLine.includes('PIX RECEBIDO') ||
      upperLine.includes('HONORARIOS') ||
      upperLine.includes('HONORÁRIOS')

    let type: 'income' | 'expense' = 'expense'
    let confidence: 'high' | 'medium' | 'low' = 'medium'

    if (isExplicitCredit && !isExplicitDebit) {
      type = 'income'
      confidence = 'high'
    } else if (isExplicitDebit) {
      type = 'expense'
      confidence = 'high'
    } else {
      // Quando não há sinal claro, em extrato de cartão de crédito compras são sempre despesas
      type = 'expense'
      confidence = 'medium'
    }

    // Sugestão de categoria e classificação inteligente
    // Despesas com GOOGLEADS e METAADS importadas de cartões devem ser classificadas
    // como despesas do escritório ("Marketing" ou "Marketing / Publicidade"), NUNCA como despesa do cliente.
    let categorySuggestion = type === 'income' ? 'Honorários Contratuais' : 'Despesas Gerais'
    const descLower = desc.toLowerCase()

    if (
      descLower.includes('google') ||
      descLower.includes('googleads') ||
      descLower.includes('google ads') ||
      descLower.includes('meta ads') ||
      descLower.includes('metaads') ||
      descLower.includes('facebook') ||
      descLower.includes('facebk')
    ) {
      categorySuggestion = 'Marketing'
      type = 'expense'
      confidence = 'high'
    } else if (
      descLower.includes('tarifa') ||
      descLower.includes('iof') ||
      descLower.includes('taxa')
    ) {
      categorySuggestion = 'Taxas Bancárias'
    } else if (descLower.includes('aluguel') || descLower.includes('condominio')) {
      categorySuggestion = 'Infraestrutura'
    } else if (
      descLower.includes('energia') ||
      descLower.includes('copel') ||
      descLower.includes('enel') ||
      descLower.includes('luz')
    ) {
      categorySuggestion = 'Serviços Públicos'
    } else if (
      descLower.includes('internet') ||
      descLower.includes('telefonia') ||
      descLower.includes('claro') ||
      descLower.includes('vivo')
    ) {
      categorySuggestion = 'Telecomunicações'
    }

    results.push({
      id: `ext_${Date.now()}_${results.length}_${Math.random().toString(36).substring(2, 7)}`,
      date: isoDate,
      rawDate: dateMatch[1],
      description: desc,
      amount: parsedCurr.amount,
      type,
      rawAmount: chosenValMatch,
      confidence,
      selected: true,
      categorySuggestion,
    })
  }

  return results
}

/**
 * Extrai texto de um PDF client-side utilizando carregamento dinâmico do pdfjs-dist via CDN oficial.
 * Não envia o arquivo para nenhum servidor externo.
 */
export async function extractTextFromPdf(file: File): Promise<string> {
  const arrayBuffer = await file.arrayBuffer()

  // Tenta carregar PDF.js dinamicamente de CDNs confiáveis (cdnjs/jsdelivr)
  let pdfjsLib: any = (window as any).pdfjsLib

  if (!pdfjsLib) {
    try {
      const script = document.createElement('script')
      script.src = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js'
      const loadPromise = new Promise((resolve, reject) => {
        script.onload = resolve
        script.onerror = () => reject(new Error('Falha ao carregar motor de PDF da CDN primária.'))
      })
      document.head.appendChild(script)
      await loadPromise

      pdfjsLib = (window as any).pdfjsLib
      if (pdfjsLib) {
        pdfjsLib.GlobalWorkerOptions.workerSrc =
          'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js'
      }
    } catch {
      // Fallback: tentar carregar script secundário do jsDelivr caso cdnjs falhe
      try {
        const fallbackScript = document.createElement('script')
        fallbackScript.src = 'https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/build/pdf.min.js'
        const fallbackPromise = new Promise((resolve, reject) => {
          fallbackScript.onload = resolve
          fallbackScript.onerror = () =>
            reject(new Error('Falha ao carregar motor de PDF da CDN secundária.'))
        })
        document.head.appendChild(fallbackScript)
        await fallbackPromise

        pdfjsLib = (window as any).pdfjsLib
        if (pdfjsLib) {
          pdfjsLib.GlobalWorkerOptions.workerSrc =
            'https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/build/pdf.worker.min.js'
        }
      } catch {
        throw new Error(
          'Não foi possível carregar o leitor de PDF no navegador. Use a opção de colar o texto ou CSV do extrato diretamente.',
        )
      }
    }
  }

  if (!pdfjsLib) {
    throw new Error('Motor PDF.js não inicializado.')
  }

  const loadingTask = pdfjsLib.getDocument({ data: new Uint8Array(arrayBuffer) })
  const pdfDoc = await loadingTask.promise
  const numPages = pdfDoc.numPages

  const textLines: string[] = []

  for (let pageNum = 1; pageNum <= numPages; pageNum++) {
    const page = await pdfDoc.getPage(pageNum)
    const textContent = await page.getTextContent()

    // Agrupar itens de texto por proximidade vertical (linhas)
    const items = textContent.items as Array<{ str: string; transform: number[] }>
    let currentLine = ''
    let lastY: number | null = null

    for (const item of items) {
      const y = item.transform ? Math.round(item.transform[5]) : 0
      if (lastY === null || Math.abs(y - lastY) <= 3) {
        currentLine += (currentLine ? ' ' : '') + item.str
      } else {
        if (currentLine.trim()) {
          textLines.push(currentLine.trim())
        }
        currentLine = item.str
      }
      lastY = y
    }

    if (currentLine.trim()) {
      textLines.push(currentLine.trim())
    }
  }

  return textLines.join('\n')
}
