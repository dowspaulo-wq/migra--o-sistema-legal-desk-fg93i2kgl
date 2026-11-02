import { normalizeStr } from '@/lib/utils'
import type { Transaction } from '@/lib/mockData'

export { normalizeStr }

export interface DuplicateCandidate {
  date?: string | null
  amount?: number | string | null
  description?: string | null
  bankAccount?: string | null
  origem?: string | null
  clientId?: string | null
  id?: string
  status?: string | null
}

export interface DuplicateMatchResult {
  hasDuplicate: boolean
  matchedTransaction: Transaction | null
  reason?: string
  matchType?: 'exact' | 'cross_origin'
}

/**
 * Calcula a diferença absoluta em dias entre duas datas (YYYY-MM-DD ou ISO).
 * Retorna null se alguma data for inválida.
 */
export function getDaysDifference(
  dateA: string | null | undefined,
  dateB: string | null | undefined,
): number | null {
  const normA = normalizeDate(dateA)
  const normB = normalizeDate(dateB)
  if (!normA || !normB) return null

  const partsA = normA.split('-').map(Number)
  const partsB = normB.split('-').map(Number)
  if (partsA.length !== 3 || partsB.length !== 3) return null

  const dtA = Date.UTC(partsA[0], partsA[1] - 1, partsA[2])
  const dtB = Date.UTC(partsB[0], partsB[1] - 1, partsB[2])

  const diffMs = Math.abs(dtA - dtB)
  return Math.round(diffMs / (1000 * 60 * 60 * 24))
}

/**
 * Normaliza a descrição removendo acentos, reduzindo para minúsculas e
 * condensando múltiplos espaços para permitir comparação fiel e tolerante.
 */
export function normalizeDescription(desc: string | null | undefined): string {
  if (!desc) return ''
  return normalizeStr(desc).replace(/\s+/g, ' ').trim()
}

/**
 * Normaliza a conta/origem bancária para comparação
 * Ex.: 'SICOOB', 'sicoob', ' SICOOB ' -> 'sicoob'
 * Se for nulo ou vazio, retorna 'sem_conta'
 */
export function normalizeAccount(account: string | null | undefined): string {
  if (!account || !account.trim()) return ''
  return normalizeStr(account).trim()
}

/**
 * Normaliza valores monetários para centavos/duas casas decimais
 */
export function normalizeAmount(amount: number | string | null | undefined): number {
  if (amount == null) return 0
  const num = typeof amount === 'number' ? amount : parseFloat(String(amount).replace(',', '.'))
  if (isNaN(num)) return 0
  return Math.round(num * 100) / 100
}

/**
 * Normaliza data para YYYY-MM-DD
 */
export function normalizeDate(date: string | null | undefined): string {
  if (!date) return ''
  return date.split('T')[0].trim()
}

/**
 * Verifica se um candidato de transação bate com uma transação existente.
 * Critérios:
 * 1. Mesma data (YYYY-MM-DD)
 * 2. Mesmo valor absoluto (com precisão de centavos)
 * 3. Mesma descrição normalizada (ou descrição existente contendo a nova ou vice-versa quando idênticas normalizadas)
 * 4. Mesma conta/origem bancária (ex: SICOOB, ASAAS, PESSOAL)
 * 5. Se ambos tiverem clientId preenchido, devem ser do mesmo cliente (ou ambos despesa/escritório sem cliente)
 * 6. Desconsidera o próprio registro em edição (se excludeId for fornecido)
 */
export function findDuplicateTransaction(
  candidate: DuplicateCandidate,
  existingTransactions: Transaction[],
  excludeId?: string | null,
): Transaction | null {
  const candDate = normalizeDate(candidate.date)
  const candAmount = normalizeAmount(candidate.amount)
  const candDesc = normalizeDescription(candidate.description)
  const candAccount = normalizeAccount(candidate.bankAccount)

  if (!candDate || candAmount === 0 || !candDesc) {
    return null
  }

  for (const tx of existingTransactions) {
    if (excludeId && tx.id === excludeId) {
      continue
    }

    const txDate = normalizeDate(tx.date)
    if (txDate !== candDate) {
      continue
    }

    const txAmount = normalizeAmount(tx.amount)
    if (Math.abs(txAmount - candAmount) > 0.009) {
      continue
    }

    const txAccount = normalizeAccount(tx.bankAccount)
    // Se ambos informarem conta, devem bater; se um estiver vazio e o outro tiver,
    // consideramos que se a conta do candidato foi informada, deve casar
    if (candAccount && txAccount && candAccount !== txAccount) {
      continue
    }

    // Se ambos tiverem clientId diferente, não são o mesmo lançamento
    if (candidate.clientId && tx.clientId && candidate.clientId !== tx.clientId) {
      continue
    }

    const txDesc = normalizeDescription(tx.description)
    if (!txDesc) {
      continue
    }

    // Bate descrição idêntica após normalização de acentos, maiúsculas/minúsculas e espaços
    if (candDesc === txDesc) {
      return tx
    }
  }

  return null
}

/**
 * Normaliza o campo origem para comparação lógica:
 * - 'ASAAS' se for ASAAS_WEBHOOK ou se tiver identificador de cobrança Asaas
 * - 'OTHER' se for MANUAL, IMPORT_SICOOB ou qualquer extrato bancário
 */
export function classifyOrigem(origem: string | null | undefined): 'ASAAS' | 'OTHER' {
  const norm = (origem || '').toUpperCase().trim()
  if (norm === 'ASAAS_WEBHOOK' || norm === 'ASAAS') {
    return 'ASAAS'
  }
  return 'OTHER'
}

export interface CrossOriginCandidate {
  date?: string | null
  amount?: number | string | null
  clientId?: string | null
  origem?: string | null
  id?: string | null
  status?: string | null
}

/**
 * Trava de duplicidade ENTRE ORIGENS:
 * Dado um clientId + valor + data alvo:
 * Se o novo lançamento vem de IMPORT_SICOOB ou MANUAL (origem OTHER),
 * procura lançamento existente com origem ASAAS_WEBHOOK:
 *   - mesmo cliente (clientId igual e preenchido)
 *   - mesmo amount (tolerância de centavos)
 *   - |diferença de datas| <= 5 dias
 *   - status 'Pago'
 * E vice-versa: se novo é ASAAS_WEBHOOK, procura existente com origem IMPORT_SICOOB ou MANUAL.
 *
 * Esta trava NÃO compara descrição nem conta bancária — apenas cliente + valor + janela de 5 dias + status Pago.
 */
export function findCrossOriginDuplicateTransaction(
  candidate: CrossOriginCandidate,
  existingTransactions: Transaction[],
  excludeId?: string | null,
): Transaction | null {
  if (!candidate.clientId) {
    return null
  }

  const candAmount = normalizeAmount(candidate.amount)
  if (candAmount <= 0) {
    return null
  }

  const candDate = normalizeDate(candidate.date)
  if (!candDate) {
    return null
  }

  const candGroup = classifyOrigem(candidate.origem)
  const targetGroup: 'ASAAS' | 'OTHER' = candGroup === 'ASAAS' ? 'OTHER' : 'ASAAS'

  for (const tx of existingTransactions) {
    if (excludeId && tx.id === excludeId) {
      continue
    }

    // Apenas status 'Pago' (ou Realizado, tratado como Pago no sistema)
    const txStatus = (tx.status || '').trim()
    if (txStatus !== 'Pago' && txStatus !== 'Realizado') {
      continue
    }

    // Mesmo cliente
    if (!tx.clientId || tx.clientId !== candidate.clientId) {
      continue
    }

    // Mesmo valor monetário
    const txAmount = normalizeAmount(tx.amount)
    if (Math.abs(txAmount - candAmount) > 0.009) {
      continue
    }

    // Origem oposta
    const txGroup = classifyOrigem(tx.origem)
    if (txGroup !== targetGroup) {
      continue
    }

    // Janela de datas: |data Asaas - data outro| <= 5 dias
    const daysDiff = getDaysDifference(candidate.date, tx.date)
    if (daysDiff === null || daysDiff > 5) {
      continue
    }

    return tx
  }

  return null
}
