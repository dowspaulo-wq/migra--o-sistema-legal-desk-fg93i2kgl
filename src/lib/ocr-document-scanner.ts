import { BRAZILIAN_STATES } from './cep'
import { formatCPF, formatCNPJ } from './document-format'
import { sanitizeClientPhone } from './utils'

export interface ExtractedClientData {
  name?: string
  document?: string // CPF ou CNPJ formatado
  type?: 'PF' | 'PJ'
  rg?: string
  cnhRegister?: string // Nº Registro da CNH
  cnhCategory?: string // Categoria CNH (A, B, AB, C, D, E)
  birthday?: string // YYYY-MM-DD
  motherName?: string
  fatherName?: string
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
 * Aplica filtros no canvas para aumentar o contraste de documentos escaneados e CNHs
 * (que possuem fundo verde claro, marcas d'água de segurança e texto fino).
 */
function preprocessCanvasForOcr(canvas: HTMLCanvasElement, ctx: CanvasRenderingContext2D) {
  try {
    const imgData = ctx.getImageData(0, 0, canvas.width, canvas.height)
    const data = imgData.data
    const len = data.length

    // Aumenta contraste e binariza levemente para evidenciar o texto sobre fundos verdes/claros
    // Fator de contraste (1.35) e limiar adaptativo
    const contrast = 1.35
    const factor = (259 * (contrast * 255 + 255)) / (255 * (259 - contrast * 255))

    for (let i = 0; i < len; i += 4) {
      // Escala de cinza ponderada (luminância perceptiva)
      const r = data[i]
      const g = data[i + 1]
      const b = data[i + 2]
      const gray = 0.299 * r + 0.587 * g + 0.114 * b

      // Aplica contraste
      let contrasted = factor * (gray - 128) + 128
      if (contrasted < 0) contrasted = 0
      if (contrasted > 255) contrasted = 255

      // Binarização suave: clareia fundos leves e escurece texto
      if (contrasted > 195) {
        contrasted = 255
      } else if (contrasted < 90) {
        contrasted = 0
      }

      data[i] = contrasted
      data[i + 1] = contrasted
      data[i + 2] = contrasted
    }

    ctx.putImageData(imgData, 0, 0)
  } catch (err) {
    // Se o navegador bloquear getImageData (ex.: canvas taint), prossegue sem travar
    console.warn('Pré-processamento de canvas omitido:', err)
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

  // Se o PDF tem camada de texto apenas de rodapé de assinatura digital (ex: Serpro/Medida Provisória)
  // ou pouquíssimo texto útil de documento (sem CPF, sem nascimento, sem nome de cliente),
  // ele deve cair no fluxo de OCR por imagem para extrair os dados gráficos da CNH/documento.
  const cleanDirect = accumulatedDirectText.replace(/\s+/g, ' ').trim()
  const strippedDigitalSignatureFooter = cleanDirect
    .replace(
      /Documento assinado com certificado digital[^]+?https:\/\/www\.serpro\.gov\.br\/assinador-digital\.?/gi,
      '',
    )
    .replace(
      /REP[UÚ]BLICA FEDERATIVA DO BRASIL\s+MINIST[EÉ]RIO DOS TRANSPORTES\s+SECRETARIA NACIONAL DE TR[AÂ]NSITO\s*-\s*SENATRAN/gi,
      '',
    )
    .replace(/Medida Provis[oó]ria\s+n[ºo]?\s*2200-2\/2001/gi, '')
    .replace(/Assinador\s+Serpro/gi, '')
    .trim()

  const hasSubstantialNonFooterText =
    strippedDigitalSignatureFooter.length >= 60 &&
    /[a-zA-Z]{3,}/.test(strippedDigitalSignatureFooter) &&
    // Verifica se tem sinais de dados de documento real (CPF, datas, palavras-chave)
    /\d{3}\.\d{3}\.\d{3}-\d{2}|\b\d{11}\b|\b\d{2}\/\d{2}\/\d{4}\b|NOME|ENDERE[CÇ]O|FILIA[CÇ][AÃ]O|IDENTIDADE/i.test(
      strippedDigitalSignatureFooter,
    )

  if (hasSubstantialNonFooterText) {
    onProgress?.(100, 'Texto extraído com sucesso!')
    return cleanDirect
  }

  // Caso seja escaneado ou a camada de texto só contenha a assinatura digital/ruído:
  // renderiza TODAS as páginas em canvas com resolução aprimorada (escala 2.5x) e pré-processamento de contraste/nitidez
  onProgress?.(15, 'Documento com imagem detectado. Renderizando páginas para OCR...')
  let fullOcrText = strippedDigitalSignatureFooter ? `${strippedDigitalSignatureFooter}\n` : ''

  for (let pageNum = 1; pageNum <= numPages; pageNum++) {
    onProgress?.(
      Math.round(15 + ((pageNum - 1) / numPages) * 20),
      `Processando página ${pageNum} de ${numPages}...`,
    )
    const page = await pdfDoc.getPage(pageNum)
    // Escala 2.5x para maior legibilidade de fontes condensadas e pequenas de CNH
    const viewport = page.getViewport({ scale: 2.5 })
    const canvas = document.createElement('canvas')
    const context = canvas.getContext('2d', { willReadFrequently: true })
    if (!context) continue

    canvas.width = viewport.width
    canvas.height = viewport.height

    await page.render({
      canvasContext: context,
      viewport: viewport,
    }).promise

    // Aplica pré-processamento para aumentar contraste de layouts CNH (fundo esverdeado/texturas de segurança)
    preprocessCanvasForOcr(canvas, context)

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

  // 0. Limpeza prévia de ruídos de assinatura digital (Serpro / MP 2200-2/2001) para evitar falso-positivo em nomes e campos
  const sanitizedText = text
    .replace(
      /Documento assinado com certificado digital[^]+?https:\/\/www\.serpro\.gov\.br\/assinador-digital\.?/gi,
      ' ',
    )
    .replace(/Assinador\s+Serpro/gi, ' ')
    .replace(/Medida Provis[oó]ria\s+n[ºo]?\s*2200-2\/2001/gi, ' ')
    .replace(/SERPRO\s*\/\s*SENATRAN/gi, ' ')
    .replace(/QR-CODE/gi, ' ')

  // 1. Extração de CPF
  // Busca CPF formatado 000.000.000-00 ou com label ou 11 dígitos
  let foundCpf = ''
  const formattedCpfMatches = sanitizedText.match(/\b\d{3}\.\d{3}\.\d{3}-\d{2}\b/g)
  if (formattedCpfMatches) {
    for (const m of formattedCpfMatches) {
      if (isValidCPF(m)) {
        foundCpf = m
        break
      }
    }
  }

  if (!foundCpf) {
    // Busca CPF com labels típicas de CNH ("CPF", "C.P.F.", "CIC", etc.) tolerando pequenas falhas de OCR
    const labeledCpf = sanitizedText.match(
      /(?:CPF|C\.P\.F\.|CIC|CADASTRO DE PESSOAS F[IÍ]SICAS)[^\d]{0,15}(\d{3}[.\s]?\d{3}[.\s]?\d{3}[-\s]?\d{2}|\d{11})/i,
    )
    if (labeledCpf) {
      const cleanDigits = labeledCpf[1].replace(/\D/g, '')
      if (isValidCPF(cleanDigits)) {
        foundCpf = formatCPF(cleanDigits)
      }
    }
  }

  if (!foundCpf) {
    // Procura qualquer sequência isolada de 11 dígitos válida como CPF no documento
    const allElevenDigits = sanitizedText.match(/\b\d{11}\b/g)
    if (allElevenDigits) {
      for (const d of allElevenDigits) {
        if (isValidCPF(d)) {
          foundCpf = formatCPF(d)
          break
        }
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

  // 3. Extração de RG e Órgão Emissor (em CNH: "DOC. IDENTIDADE/ÓRG EMISSOR/UF")
  // Ex: "MG5070513 SSP MG" ou "12.345.678-9 SSP/SP" ou "MG-12.345.678"
  const cnhDocIdMatch = sanitizedText.match(
    /(?:DOC\.?\s*IDENTIDADE|DOC\.?\s*DE\s*IDENTIDADE|DOCUMENTO\s*DE\s*IDENTIDADE|RG|R\.G\.)(?:\s*[/\\-]\s*ÓRG[.\s]*EMISSOR(?:\s*[/\\-]\s*UF)?)?[:\s-]*([A-Za-z]{0,3}\s*[\d.-]{5,15}(?:\s+[A-Za-z0-9/]+){0,3})/i,
  )
  if (cnhDocIdMatch) {
    const candidateRg = cnhDocIdMatch[1].trim()
    const digitsOnly = candidateRg.replace(/\D/g, '')
    // Garante que não é o próprio CPF
    if (digitsOnly !== result.document?.replace(/\D/g, '') && digitsOnly.length >= 4) {
      result.rg = candidateRg
    }
  }

  if (!result.rg) {
    const generalRgMatch = sanitizedText.match(
      /(?:RG|R\.G\.|REGISTRO GERAL|DOC\.?\s*IDENTIDADE|IDENTIDADE|CARTEIRA DE IDENTIDADE)[^\d]{0,8}([0-9]{1,2}[.\s]?[0-9]{3}[.\s]?[0-9]{3}[-\s]?[0-9Xx]|\b[0-9]{7,10}\b)/i,
    )
    if (
      generalRgMatch &&
      !generalRgMatch[1].replace(/\D/g, '').includes(result.document?.replace(/\D/g, '') || 'xyz')
    ) {
      result.rg = generalRgMatch[1].trim()
    }
  }

  // 3.1 Extração de Registro CNH e Categoria
  // Ex CNH: "Nº REGISTRO" ou "REGISTRO" seguido de 11 dígitos, ex: 04116202105
  const cnhRegisterMatch = sanitizedText.match(
    /(?:N[º°ª.]?\s*REGISTRO|REGISTRO|N[º°ª.]\s*HABILITA[CÇ][AÃ]O|PDI)[:\s-]*([0-9]{9,12})\b/i,
  )
  if (cnhRegisterMatch) {
    result.cnhRegister = cnhRegisterMatch[1].trim()
  }

  // Categoria CNH: "CAT. HAB.", "CATEGORIA", "CAT" seguido de A, B, AB, C, D, E, etc.
  const cnhCategoryMatch = sanitizedText.match(
    /(?:CAT\.?\s*HAB\.?|CATEGORIA(?:\s*HABILITA[CÇ][AÃ]O)?|CAT\.?)[:\s-]*\b([A-E]{1,2})\b/i,
  )
  if (cnhCategoryMatch) {
    result.cnhCategory = cnhCategoryMatch[1].toUpperCase()
  }

  // 4. Data de nascimento
  // Em CNH: "DATA NASCIMENTO", "DT NASC", "NASCIMENTO", "DATA NASC"
  const birthMatch = sanitizedText.match(
    /(?:DATA\s*(?:DE)?\s*NASCIMENTO|DT\.?\s*NASC(?:IMENTO)?|DATA\s*NASC|NASCIMENTO|NASC\.?)[:\s-]*(\d{2}\/\d{2}\/\d{4})/i,
  )
  if (birthMatch) {
    const [d, m, y] = birthMatch[1].split('/')
    result.birthday = `${y}-${m}-${d}`
  } else {
    // Procura linha que contenha NASC e uma data na mesma linha ou logo a seguir
    const birthLineMatch = sanitizedText.match(
      /(?:NASC|NASCIMENTO)[^\n]{0,30}\b(\d{2}\/\d{2}\/\d{4})\b/i,
    )
    if (birthLineMatch) {
      const [d, m, y] = birthLineMatch[1].split('/')
      result.birthday = `${y}-${m}-${d}`
    } else {
      // Procura data antiga plausível de nascimento entre 1920 e 2012
      // Tomando cuidado para NÃO pegar data de emissão ou validade (que são 2020+)
      const dateMatches = Array.from(
        sanitizedText.matchAll(/\b(\d{2})\/(\d{2})\/(19\d{2}|20[01]\d)\b/g),
      )
      for (const match of dateMatches) {
        const year = parseInt(match[3], 10)
        if (year >= 1930 && year <= 2012) {
          result.birthday = `${match[3]}-${match[2]}-${match[1]}`
          break
        }
      }
    }
  }
  // 5. Nome completo e Filiação (Pai / Mãe)
  // CNH tem labels específicos: "NOME", "NOME DO CONDUTOR", e bloco "FILIAÇÃO"
  const sanitizedLines = sanitizedText
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean)

  for (let i = 0; i < sanitizedLines.length; i++) {
    const l = sanitizedLines[i]

    // Nome
    if (!result.name) {
      const nameHeaderMatch = l.match(
        /^(?:1\s*)?(?:NOME(?:\s+DO\s+CONDUTOR)?|NOME\s+COMPLETO|CLIENTE|NOME\s+DO\s+TITULAR)\b[:\s-]*(.*)$/i,
      )
      if (nameHeaderMatch) {
        const afterLabel = nameHeaderMatch[1]?.trim()
        if (afterLabel && afterLabel.length > 5 && isLikelyPersonName(afterLabel)) {
          result.name = cleanPersonName(afterLabel)
        } else {
          // Olha até 2 linhas abaixo se o OCR quebrou linha após o rótulo
          for (let step = 1; step <= 2 && i + step < sanitizedLines.length; step++) {
            const nextCandidate = sanitizedLines[i + step].trim()
            if (
              nextCandidate.length > 5 &&
              isLikelyPersonName(nextCandidate) &&
              !/FILIA|DOC|DATA|CPF|RG|PERMISS|CAT|HABILIT|LOCAL|ASSIN|MINAS|VALIDA|NACIONAL/i.test(
                nextCandidate,
              )
            ) {
              result.name = cleanPersonName(nextCandidate)
              break
            }
          }
        }
      }
    }

    // Filiação: Na CNH, vem tipicamente Pai e Mãe (duas linhas após FILIAÇÃO)
    if (!result.motherName || !result.fatherName) {
      const filiacaoMatch = l.match(/(?:FILIA[CÇ][AÃ]O|FILIACAO)[:\s-]*(.*)$/i)
      if (filiacaoMatch) {
        const parentNames: string[] = []
        const immediate = filiacaoMatch[1]?.trim()
        if (immediate && isLikelyPersonName(immediate)) {
          parentNames.push(immediate)
        }
        // Olha as linhas seguintes (até 3)
        for (let step = 1; step <= 3 && i + step < sanitizedLines.length; step++) {
          const nextL = sanitizedLines[i + step].trim()
          if (
            isLikelyPersonName(nextL) &&
            !/PERMISS|ACC|CAT|VALIDADE|HABILITA|LOCAL|DATA|EMISS|ASSIN|MINIST/i.test(nextL)
          ) {
            parentNames.push(nextL)
          } else if (/PERMISS|ACC|CAT|VALIDADE|LOCAL|DATA/i.test(nextL)) {
            break
          }
        }

        if (parentNames.length === 1) {
          result.motherName = cleanPersonName(parentNames[0])
        } else if (parentNames.length >= 2) {
          result.fatherName = cleanPersonName(parentNames[0])
          result.motherName = cleanPersonName(parentNames[1])
        }
      }
    }

    // Rótulos explícitos de MÃE ou PAI
    if (!result.motherName) {
      const explicitMother = l.match(/(?:M[AÃ]E|NOME\s+DA\s+M[AÃ]E)[:\s-]*(.*)$/i)
      if (explicitMother) {
        const mVal = explicitMother[1]?.trim()
        if (mVal && isLikelyPersonName(mVal)) {
          result.motherName = cleanPersonName(mVal)
        } else if (i + 1 < sanitizedLines.length && isLikelyPersonName(sanitizedLines[i + 1])) {
          result.motherName = cleanPersonName(sanitizedLines[i + 1])
        }
      }
    }

    if (!result.fatherName) {
      const explicitFather = l.match(/(?:PAI|NOME\s+DO\s+PAI)[:\s-]*(.*)$/i)
      if (explicitFather) {
        const pVal = explicitFather[1]?.trim()
        if (pVal && isLikelyPersonName(pVal)) {
          result.fatherName = cleanPersonName(pVal)
        } else if (i + 1 < sanitizedLines.length && isLikelyPersonName(sanitizedLines[i + 1])) {
          result.fatherName = cleanPersonName(sanitizedLines[i + 1])
        }
      }
    }
  }

  // Fallback para Nome: se ainda não achou, procura primeira linha em CAIXA ALTA com 2 a 5 palavras
  // que não seja cabeçalho governamental ou termo jurídico
  if (!result.name) {
    for (const l of sanitizedLines) {
      if (
        isLikelyPersonName(l) &&
        l.split(/\s+/).length >= 2 &&
        l.split(/\s+/).length <= 6 &&
        !/REP[UÚ]BLICA|FEDERATIVA|BRASIL|MINIST[EÉ]RIO|CARTEIRA|NACIONAL|HABILITA[CÇ][AÃ]O|IDENTIDADE|REGISTRO|INSTITUTO|V[AÁ]LIDA|TERRIT[OÓ]RIO|SECRETARIA|DEPARTAMENTO|TR[AÂ]NSITO|SENATRAN|CONTRAN|DENATRAN|ESTADUAL|DETRAN|ASSINADO|DIGITALMENTE|DOCUMENTO|CERTIFICADO|MEDIDA|PROVIS[OÓ]RIA/i.test(
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

  // 10. Endereço: CNH (bloco LOCAL / ENDEREÇO) e comprovantes de endereço
  // Em CNH antiga e nova: campo "LOCAL" pode conter "CIDADE, UF" ou "CIDADE - UF" (ex: "RIBEIRAO DAS NEVES, MG")
  const cnhLocalMatch = sanitizedText.match(
    /(?:LOCAL|MUNIC[IÍ]PIO\/UF|CIDADE\/UF)[:\s-]*([A-Za-zÀ-ÿ\s]+?)(?:,\s*|\s*-\s*|\s*\/\s*)([A-Z]{2})\b/i,
  )
  if (cnhLocalMatch) {
    const candCity = cnhLocalMatch[1].trim()
    const candUf = cnhLocalMatch[2].toUpperCase()
    if (
      candCity.length > 2 &&
      !/ASSINAD|SECRETAR|DETRAN|DEPARTAMENTO|TERRIT/i.test(candCity) &&
      !result.city
    ) {
      result.city = cleanCityName(candCity)
    }
    if (!result.state && BRAZILIAN_STATES.includes(candUf as any)) {
      result.state = candUf
    }
  }

  // Rótulos de ENDEREÇO / END / LOGRADOURO
  const addressLabelMatch = sanitizedText.match(
    /(?:ENDERE[CÇ]O|END\.?|LOGRADOURO)[:\s-]*([A-Za-zÀ-ÿ0-9\s.,º°ª-]+)/i,
  )
  if (addressLabelMatch) {
    const rawAddrLine = addressLabelMatch[1].split('\n')[0].trim()
    parseStreetAndNumber(rawAddrLine, result)
  }

  // Padrões de vias urbanas (RUA, R., AV., AVENIDA, TRAVESSA, ALAMEDA, etc.)
  if (!result.street) {
    const streetRegex =
      /(?:RUA|R\.|AVENIDA|AV\.|TRAVESSA|TRAV\.|ALAMEDA|AL\.|RODOVIA|ROD\.|ESTRADA|ESTR\.|PRA[CÇ]A|PC\.)\s+([A-Za-zÀ-ÿ0-9\s.,º°ª-]+)/i
    const streetMatch = sanitizedText.match(streetRegex)
    if (streetMatch) {
      const fullStreetLine = streetMatch[0].split('\n')[0].trim()
      parseStreetAndNumber(fullStreetLine, result)
    }
  }

  // Bairro
  if (!result.neighborhood) {
    const neighborhoodMatch = sanitizedText.match(
      /(?:BAIRRO|BAIRRO:)\s*([A-Za-zÀ-ÿ0-9\s-]+?)(?:[,\n]|$)/i,
    )
    if (neighborhoodMatch && neighborhoodMatch[1].trim().length > 2) {
      result.neighborhood = neighborhoodMatch[1].trim()
    }
  }

  // Cidade
  if (!result.city) {
    const cityMatch = sanitizedText.match(
      /(?:CIDADE|MUNIC[IÍ]PIO|MUN\.)[:\s-]*([A-Za-zÀ-ÿ\s]+?)(?:[,/\n-]|$)/i,
    )
    if (cityMatch && cityMatch[1].trim().length > 2) {
      result.city = cleanCityName(cityMatch[1])
    }
  }

  return result
}

function parseStreetAndNumber(line: string, result: ExtractedClientData) {
  // Limpa prefixos
  const cleanedLine = line.replace(/^(?:ENDERE[CÇ]O|END\.?|LOGRADOURO)[:\s-]*/i, '').trim()
  const numSubMatch = cleanedLine.match(
    /^(.*?)(?:,\s*|\s+(?:N[º°ª.]|N[UÚ]MERO|N)\s*|\s+)(\d+[A-Za-z]?)(?:[,\s]+(.*))?$/i,
  )
  if (numSubMatch) {
    result.street = numSubMatch[1].replace(/,\s*$/, '').trim()
    result.number = numSubMatch[2].trim()
    if (numSubMatch[3]) {
      const rest = numSubMatch[3].trim()
      if (/^(APTO|APT|BLOCO|BL|SALA|CASA|LOTE|QD|CONJ)\b/i.test(rest)) {
        result.complement = rest
      } else if (!result.neighborhood && rest.length > 3) {
        result.neighborhood = rest
      }
    }
  } else {
    result.street = cleanedLine
  }
}

function isLikelyPersonName(candidate: string): boolean {
  const c = candidate.trim()
  if (c.length < 5 || c.length > 60) return false
  // Não pode conter dígitos ou símbolos estranhos de código/assinatura
  if (/[0-9@_#$%&*=+/\\<>{}[\]|]/.test(c)) return false
  // Deve ter letras válidas e pelo menos 2 partes
  const words = c.split(/\s+/).filter(Boolean)
  if (words.length < 2) return false
  // Não pode ser rótulo ou termo governamental conhecido
  if (
    /^(VALIDA|TERRITORIO|REPUBLICA|MINISTERIO|SECRETARIA|DEPARTAMENTO|CARTEIRA|HABILITACAO|LOCAL|DATA|PERMISSAO|SENATRAN|DENATRAN|CONTRAN|SERPRO|ASSINADOR|DOCUMENTO|CERTIFICADO|MEDIDA|PROVISORIA|ASSINADO|DIGITALMENTE|OBSERVACOES|ASSINATURA)/i.test(
      c,
    )
  ) {
    return false
  }
  return true
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

function cleanCityName(city: string): string {
  return city
    .replace(/\s+/g, ' ')
    .replace(/[^\w\sÀ-ÿ]/g, '')
    .trim()
    .split(' ')
    .map((word) => {
      const lower = word.toLowerCase()
      if (['de', 'da', 'do', 'dos', 'das'].includes(lower)) {
        return lower
      }
      return lower.charAt(0).toUpperCase() + lower.slice(1)
    })
    .join(' ')
}
