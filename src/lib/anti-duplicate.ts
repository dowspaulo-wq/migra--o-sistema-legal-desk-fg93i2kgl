import { normalizeStr } from '@/lib/utils'
import type { Transaction } from '@/lib/mockData'

export interface DuplicateCandidate {
  date?: string | null
  amount?: number | string | null
  description?: string | null
  bankAccount?: string | null
  origem?: string | null
  clientId?: string | null
  id?: string
}

export interface DuplicateMatchResult {
  hasDuplicate: boolean
  matchedTransaction: Transaction | null
  reason?: string
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
