import { BRAZILIAN_STATES } from './cep'
import { formatCPF, formatCNPJ } from './document-format'
import { sanitizeClientPhone, formatPhone } from './utils'

export interface ExtractedClientData {
  name?: string
  document?: string // CPF ou CNPJ formatado
  type?: 'PF' | 'PJ'
  rg?: string
  birthday?: string // YYYY-MM-DD
  motherName?: string
  email?: string
  phone?: string // dígitos limpos
  cep?: string // 00000-000
  street?: string
  number?: string
  complement?: string
  neighborhood?: string
  city?: string
  state?: string // UF (2 letras)
  rawText?: string
}

/**
 * Carrega a biblioteca Tesseract.js sob demanda via CDN confiável (jsdelivr).
 * Zero custo, sem dependência pesada de bundle ou segredos de API.
 */
async function loadTesseract(): Promise<any> {
  const w = window as any
  if (w.Tesseract) {
    return w.Tesseract
  }

  const script = document.createElement('script')
  script.src = 'https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js'
  script.async = true

  await new Promise<void>((resolve, reject) => {
    script.onload = () => resolve()
    script.onerror = () =>
      reject(
        new Error(
          'Falha ao carregar o motor de OCR (Tesseract.js). Verifique a conexão com a internet.',
        ),
      )
    document.head.appendChild(script)
  })

  if (!w.Tesseract) {
    throw new Error('Motor de OCR não inicializado corretamente.')
  }
  return w.Tesseract
}

/**
 * Carrega o PDF.js dinamicamente se necessário
 */
async function loadPdfJs(): Promise<any> {
  const w = window as any
  if (w.pdfjsLib) {
    return w.pdfjsLib
  }

  const script = document.createElement('script')
  script.src = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js'
  script.async = true

  await new Promise<void>((resolve, reject) => {
    script.onload = () => resolve()
    script.onerror = () => reject(new Error('Falha ao carregar motor de PDF da CDN primária.'))
    document.head.appendChild(script)
  })

  if (w.pdfjsLib) {
    w.pdfjsLib.GlobalWorkerOptions.workerSrc =
      'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js'
    return w.pdfjsLib
  }
  throw new Error('Motor PDF.js não inicializado.')
}

/**
 * Executa OCR em imagem ou canvas usando Tesseract.js (treinado em português)
 */
export async function runTesseractOcr(
  imageSource: string | HTMLCanvasElement | Blob,
  onProgress?: (progress: number, statusText: string) => void,
): Promise<string> {
  const Tesseract = await loadTesseract()

  onProgress?.(5, 'Inicializando motor de OCR...')
  const worker = await Tesseract.createWorker('por', 1, {
    workerPath: 'https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/worker.min.js',
    corePath: 'https://cdn.jsdelivr.net/npm/tesseract.js-core@5.1.1',
    langPath: 'https://tessdata.projectnaptha.com/4.0.0',
    logger: (m: any) => {
      if (m && m.status === 'recognizing text') {
        const pct = Math.min(99, Math.round(15 + (m.progress || 0) * 80))
        onProgress?.(pct, `Reconhecendo texto... ${pct}%`)
      } else if (m && m.status) {
        onProgress?.(10, 'Preparando leitura...')
      }
    },
  })

  try {
    const res = await worker.recognize(imageSource)
    return res?.data?.text || ''
  } finally {
    try {
      await worker.terminate()
    } catch {
      /* ignore */
    }
  }
}

/**
 * Extrai texto de PDF: se tiver camada de texto, usa direto;
 * se for escaneado (sem texto suficiente), renderiza as páginas em canvas e roda OCR.
 */
export async function extractTextFromPdfOrScanned(
  file: File,
  onProgress?: (progress: number, statusText: string) => void,
): Promise<string> {
  onProgress?.(5, 'Carregando leitor de PDF...')
  const pdfjsLib = await loadPdfJs()
  const arrayBuffer = await file.arrayBuffer()
  const loadingTask = pdfjsLib.getDocument({ data: new Uint8Array(arrayBuffer) })
  const pdfDoc = await loadingTask.promise
  const numPages = Math.min(pdfDoc.numPages, 4) // Até 4 páginas para documentos de identidade/endereço

  let accumulatedDirectText = ''
  for (let i = 1; i <= numPages; i++) {
    const page = await pdfDoc.getPage(i)
    const textContent = await page.getTextContent()
    const pageStr = textContent.items.map((item: any) => item.str).join(' ')
    accumulatedDirectText += ' ' + pageStr
  }

  // Se tem pelo menos 40 caracteres legíveis com letras, considera que o PDF já tem camada de texto
  const cleanDirect = accumulatedDirectText.replace(/\s+/g, ' ').trim()
  if (cleanDirect.length >= 40 && /[a-zA-Z]{3,}/.test(cleanDirect)) {
    onProgress?.(100, 'Texto extraído com sucesso!')
    return cleanDirect
  }

  // Caso seja escaneado: renderiza páginas em canvas e roda OCR com Tesseract
  onProgress?.(15, 'PDF digitalizado detectado. Renderizando imagem para OCR...')
  let fullOcrText = ''

  for (let pageNum = 1; pageNum <= numPages; pageNum++) {
    onProgress?.(
      Math.round(15 + ((pageNum - 1) / numPages) * 20),
      `Processando página ${pageNum} de ${numPages}...`,
    )
    const page = await pdfDoc.getPage(pageNum)
    const viewport = page.getViewport({ scale: 2.0 }) // Resolução 2x para melhor precisão de OCR
    const canvas = document.createElement('canvas')
    const context = canvas.getContext('2d')
    if (!context) continue

    canvas.width = viewport.width
    canvas.height = viewport.height

    await page.render({
      canvasContext: context,
      viewport: viewport,
    }).promise

    const pageText = await runTesseractOcr(canvas, (p, msg) => {
      const stepBase = 20 + ((pageNum - 1) / numPages) * 75
      const stepSpan = 75 / numPages
      const currentProgress = Math.round(stepBase + (p / 100) * stepSpan)
      onProgress?.(Math.min(98, currentProgress), `Pág ${pageNum}/${numPages}: ${msg}`)
    })

    fullOcrText += '\n' + pageText
  }

  onProgress?.(100, 'OCR concluído com sucesso!')
  return fullOcrText
}

/**
 * Validador de CPF pelos dígitos verificadores
 */
export function isValidCPF(cpfDigits: string): boolean {
  const clean = cpfDigits.replace(/\D/g, '')
  if (clean.length !== 11) return false
  if (/^(\d)\1{10}$/.test(clean)) return false

  let sum = 0
  for (let i = 0; i < 9; i++) {
    sum += parseInt(clean.charAt(i), 10) * (10 - i)
  }
  let rev = 11 - (sum % 11)
  if (rev === 10 || rev === 11) rev = 0
  if (rev !== parseInt(clean.charAt(9), 10)) return false

  sum = 0
  for (let i = 0; i < 10; i++) {
    sum += parseInt(clean.charAt(i), 10) * (11 - i)
  }
  rev = 11 - (sum % 11)
  if (rev === 10 || rev === 11) rev = 0
  if (rev !== parseInt(clean.charAt(10), 10)) return false

  return true
}

/**
 * Heurísticas de extração de dados de documentos PT-BR
 * (CNH, RG, Identidade Digital, Faturas de Energia/Água/Internet, etc.)
 */
export function parseDocumentText(rawText: string): ExtractedClientData {
  const result: ExtractedClientData = { rawText }
  if (!rawText) return result

  // Normaliza quebras de linha e múltiplos espaços
  const text = rawText.replace(/\r/g, '')
  const lines = text
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean)

  // 1. Extração de CPF
  // Regex busca 000.000.000-00 ou 11 dígitos isolados
  const formattedCpfMatches = text.match(/\b\d{3}\.\d{3}\.\d{3}-\d{2}\b/g)
  let foundCpf = ''
  if (formattedCpfMatches) {
    for (const m of formattedCpfMatches) {
      if (isValidCPF(m)) {
        foundCpf = m
        break
      }
    }
  }

  if (!foundCpf) {
    // Busca CPF com labels como "CPF", "CIC", "DOCUMENTO" ou 11 dígitos
    const labeledCpf = text.match(
      /(?:CPF|C\.P\.F\.|CIC|CADASTRO DE PESSOAS F[IÍ]SICAS)[^\d]{0,10}(\d{3}[.\s]?\d{3}[.\s]?\d{3}[-\s]?\d{2})/i,
    )
    if (labeledCpf) {
      const cleanDigits = labeledCpf[1].replace(/\D/g, '')
      if (isValidCPF(cleanDigits)) {
        foundCpf = formatCPF(cleanDigits)
      }
    }
  }

  // 2. Extração de CNPJ (se não achou CPF e o documento aparentar PJ)
  let foundCnpj = ''
  const formattedCnpjMatches = text.match(/\b\d{2}\.\d{3}\.\d{3}\/\d{4}-\d{2}\b/g)
  if (formattedCnpjMatches && formattedCnpjMatches.length > 0) {
    foundCnpj = formattedCnpjMatches[0]
  }

  if (foundCpf) {
    result.document = formatCPF(foundCpf)
    result.type = 'PF'
  } else if (foundCnpj) {
    result.document = formatCNPJ(foundCnpj)
    result.type = 'PJ'
  }

  // 3. Extração de RG
  // Padrões de RG: "RG 12.345.678-9", "DOC IDENTIDADE", "RG / ORG"
  const rgMatch = text.match(
    /(?:RG|R\.G\.|REGISTRO GERAL|DOC\.?\s*IDENTIDADE|IDENTIDADE|CARTEIRA DE IDENTIDADE)[^\d]{0,8}([0-9]{1,2}[.\s]?[0-9]{3}[.\s]?[0-9]{3}[-\s]?[0-9Xx]|\b[0-9]{7,10}\b)/i,
  )
  if (
    rgMatch &&
    !rgMatch[1].replace(/\D/g, '').includes(result.document?.replace(/\D/g, '') || 'xyz')
  ) {
    result.rg = rgMatch[1].trim()
  }

  // 4. Data de nascimento
  // Padrões: "NASCIMENTO: 12/03/1985", "DATA NASC", "DATA DE NASCIMENTO"
  const birthMatch = text.match(
    /(?:DATA\s+DE\s+NASCIMENTO|DATA\s+NASC|NASCIMENTO|NASC\.?|DT\.?\s*NASC)[^\d]{0,10}(\d{2}\/\d{2}\/\d{4})/i,
  )
  if (birthMatch) {
    const [d, m, y] = birthMatch[1].split('/')
    result.birthday = `${y}-${m}-${d}`
  } else {
    // Procura qualquer data antiga plausível entre 1920 e 2015 se houver label próxima
    const dateMatches = Array.from(text.matchAll(/\b(\d{2})\/(\d{2})\/(19\d{2}|20[01]\d)\b/g))
    for (const match of dateMatches) {
      const year = parseInt(match[3], 10)
      if (year >= 1930 && year <= 2012) {
        result.birthday = `${match[3]}-${match[2]}-${match[1]}`
        break
      }
    }
  }

  // 5. Nome completo e Filiação (Mãe)
  // Em CNH: "NOME" na linha anterior ou posterior; "FILIAÇÃO" com nome da mãe
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i]

    // Nome
    if (!result.name) {
      const nameHeaderMatch = l.match(
        /^(?:1\s*)?(?:NOME|NOME COMPLETO|CLIENTE|NOME DO TITULAR)\b[:\s-]*(.*)$/i,
      )
      if (nameHeaderMatch) {
        const afterLabel = nameHeaderMatch[1]?.trim()
        if (afterLabel && afterLabel.length > 5 && /^[A-Za-zÀ-ÿ\s]+$/.test(afterLabel)) {
          result.name = cleanPersonName(afterLabel)
        } else if (i + 1 < lines.length) {
          const nextLine = lines[i + 1].trim()
          if (
            nextLine.length > 5 &&
            /^[A-Za-zÀ-ÿ\s]+$/.test(nextLine) &&
            !/FILIA|DOC|DATA|CPF|RG/i.test(nextLine)
          ) {
            result.name = cleanPersonName(nextLine)
          }
        }
      }
    }

    // Filiação / Nome da mãe
    if (!result.motherName) {
      const motherHeaderMatch = l.match(/(?:FILIA[CÇ][AÃ]O|M[AÃ]E|NOME DA M[AÃ]E)[:\s-]*(.*)$/i)
      if (motherHeaderMatch) {
        const afterLabel = motherHeaderMatch[1]?.trim()
        if (afterLabel && afterLabel.length > 5 && /^[A-Za-zÀ-ÿ\s]+$/.test(afterLabel)) {
          result.motherName = cleanPersonName(afterLabel)
        } else if (i + 1 < lines.length) {
          const nextLine = lines[i + 1].trim()
          if (
            nextLine.length > 5 &&
            /^[A-Za-zÀ-ÿ\s]+$/.test(nextLine) &&
            !/PAI|DATA|CPF|RG/i.test(nextLine)
          ) {
            result.motherName = cleanPersonName(nextLine)
          }
        }
      }
    }
  }

  // Se o nome não foi encontrado por label, procura uma linha em CAIXA ALTA com formato de nome (3+ palavras)
  if (!result.name) {
    for (const l of lines) {
      if (
        /^[A-ZÀ-Ý\s]{10,60}$/.test(l) &&
        l.split(/\s+/).length >= 2 &&
        !/REP[UÚ]BLICA|FEDERATIVA|BRASIL|MINIST[EÉ]RIO|CARTEIRA|NACIONAL|HABILITA[CÇ][AÃ]O|IDENTIDADE|REGISTRO|INSTITUTO|V[AÁ]LIDA|TERRIT[OÓ]RIO/i.test(
          l,
        )
      ) {
        result.name = cleanPersonName(l)
        break
      }
    }
  }

  // 6. E-mail
  const emailMatch = text.match(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/)
  if (emailMatch) {
    result.email = emailMatch[0].toLowerCase()
  }

  // 7. Telefone / Celular
  const phoneMatch = text.match(
    /(?:(?:TEL|CEL|TELEFONE|CELULAR|FONE|WHATSAPP|CONTATO)[^\d]{0,8})?(\(?\d{2}\)?\s*9?\d{4}[-\s]?\d{4})\b/i,
  )
  if (phoneMatch) {
    const rawDigits = sanitizeClientPhone(phoneMatch[1])
    if (rawDigits.length >= 10 && rawDigits.length <= 11) {
      result.phone = rawDigits
    }
  }

  // 8. CEP (00000-000 ou 00000 000 ou CEP: 00000000)
  const cepMatch = text.match(/(?:CEP[:\s-]*)?(\b\d{5}[-\s]?\d{3}\b)/i)
  if (cepMatch) {
    const rawCep = cepMatch[1].replace(/\D/g, '')
    if (rawCep.length === 8) {
      result.cep = `${rawCep.substring(0, 5)}-${rawCep.substring(5)}`
    }
  }

  // 9. UF / Estado
  const stateMatch = text.match(/\b(?:UF|ESTADO)[:\s-]*([A-Z]{2})\b/i)
  if (stateMatch && BRAZILIAN_STATES.includes(stateMatch[1].toUpperCase() as any)) {
    result.state = stateMatch[1].toUpperCase()
  } else {
    // Procura barra seguida de UF, ex: "BELO HORIZONTE/MG" ou "- MG"
    const slashUfMatch = text.match(/[/-]\s*([A-Z]{2})\b/)
    if (slashUfMatch && BRAZILIAN_STATES.includes(slashUfMatch[1].toUpperCase() as any)) {
      result.state = slashUfMatch[1].toUpperCase()
    }
  }

  // 10. Endereço: Rua / Logradouro, Número, Bairro, Cidade
  // Busca padrões como "RUA DAS FLORES, 123", "AV. BRASIL, Nº 450", "ENDEREÇO:"
  const streetRegex =
    /(?:RUA|AVENIDA|AV\.|TRAVESSA|TRAV\.|ALAMEDA|AL\.|RODOVIA|ROD\.|ESTRADA|ESTR\.|PRA[CÇ]A|PC\.)\s+([A-Za-zÀ-ÿ0-9\s.,º°ª-]+)/i
  const streetMatch = text.match(streetRegex)
  if (streetMatch) {
    const fullStreetLine = streetMatch[0].split('\n')[0].trim()
    // Tenta separar Rua e Número
    const numSubMatch = fullStreetLine.match(
      /^(.*?)(?:,\s*|\s+(?:N[º°ª.]|N[UÚ]MERO|N)\s*|\s+)(\d+[A-Za-z]?)(?:[,\s]+(.*))?$/i,
    )
    if (numSubMatch) {
      result.street = numSubMatch[1].replace(/,\s*$/, '').trim()
      result.number = numSubMatch[2].trim()
      if (numSubMatch[3]) {
        // Possível complemento ou bairro
        const rest = numSubMatch[3].trim()
        if (/^(APTO|APT|BLOCO|BL|SALA|CASA|LOTE|QD)\b/i.test(rest)) {
          result.complement = rest
        } else if (!result.neighborhood && rest.length > 3) {
          result.neighborhood = rest
        }
      }
    } else {
      result.street = fullStreetLine
    }
  }

  // Bairro
  const neighborhoodMatch = text.match(/(?:BAIRRO|BAIRRO:)\s*([A-Za-zÀ-ÿ0-9\s-]+?)(?:[,\n]|$)/i)
  if (neighborhoodMatch && neighborhoodMatch[1].trim().length > 2) {
    result.neighborhood = neighborhoodMatch[1].trim()
  }

  // Cidade
  const cityMatch = text.match(
    /(?:CIDADE|MUNIC[IÍ]PIO|MUN\.)[:\s-]*([A-Za-zÀ-ÿ\s]+?)(?:[,/\n-]|$)/i,
  )
  if (cityMatch && cityMatch[1].trim().length > 2) {
    result.city = cityMatch[1].trim()
  }

  return result
}

function cleanPersonName(name: string): string {
  return name
    .replace(/\s+/g, ' ')
    .replace(/[^\w\sÀ-ÿ]/g, '')
    .trim()
    .split(' ')
    .map((word) => {
      const lower = word.toLowerCase()
      if (['de', 'da', 'do', 'dos', 'das', 'e'].includes(lower)) {
        return lower
      }
      return lower.charAt(0).toUpperCase() + lower.slice(1)
    })
    .join(' ')
}
