// Definições padronizadas de tipos de honorários e categorias financeiras
// Conforme decisões do Douglas:
// 1. Quota littis extinta -> unificada como 'Honorários de Êxito'
// 2. Modais de honorários listam APENAS honorários / receitas
// 3. Ordem alfabética nas opções de seleção
// 4. Capitalização correta: primeira letra em maiúscula

export const SUCCESS_FEE_TYPE = 'Honorários de Êxito'

// Lista exclusiva de tipos de honorários (apenas receitas / honorários)
export const ONLY_FEE_TYPES = [
  'Honorários Contratuais',
  'Honorários de Êxito',
  'Honorários Sucumbenciais',
  'Honorários Periciais',
  'Honorários de Permuta',
  'Acordo',
  'Alvará / Condenação',
  'Outros',
]

// Tipos de despesas do cliente (caminho próprio: subaba / modal específico)
export const CLIENT_EXPENSE_TYPES = [
  'Custas Iniciais',
  'Custas Finais',
  'Diligência',
  'Depósito Recursal',
  'Outros',
]

// Modalidades que não geram lançamento financeiro automático (apenas no processo)
export const NON_FINANCIAL_FEE_TYPES = ['Não gera honorários', 'pro bono']

export const isSuccessFeeType = (feeType: string | null | undefined): boolean => {
  if (!feeType) return false
  const lower = feeType.toLowerCase()
  return (
    lower.includes('êxito') ||
    lower.includes('exito') ||
    lower.includes('quota') ||
    lower.includes('litis') ||
    lower.includes('littis')
  )
}

export const isNonFinancialFeeType = (feeType: string | null | undefined): boolean => {
  if (!feeType) return false
  const lower = feeType.toLowerCase()
  return (
    NON_FINANCIAL_FEE_TYPES.includes(lower) ||
    lower === 'não gera lançamento financeiro' ||
    lower === 'não gera honorários'
  )
}

// Retorna apenas tipos de honorários (receitas), ordenados alfabeticamente
export const getFeeTypeOptions = (
  transactionCategories?: string[] | null,
  includeNonFinancial = true,
): string[] => {
  const customFees = (transactionCategories || []).filter((c) => {
    const l = c.toLowerCase()
    return (
      l.includes('honor') ||
      l.includes('êxito') ||
      l.includes('exito') ||
      l.includes('acordo') ||
      l.includes('alvará') ||
      l.includes('alvara')
    )
  })

  const base = Array.from(new Set([...ONLY_FEE_TYPES, ...customFees]))
    // Remove qualquer variação antiga de quota
    .filter((t) => !t.toLowerCase().includes('quota'))

  const nonFin = includeNonFinancial ? NON_FINANCIAL_FEE_TYPES : []
  const combined = Array.from(new Set([...base, ...nonFin]))

  return combined.sort((a, b) => a.localeCompare(b, 'pt-BR'))
}

// Retorna apenas categorias de despesas do cliente, ordenadas alfabeticamente
export const getClientExpenseOptions = (transactionCategories?: string[] | null): string[] => {
  const customExpenses = (transactionCategories || []).filter((c) => {
    const l = c.toLowerCase()
    return (
      l.includes('custa') || l.includes('dilig') || l.includes('depósito') || l.includes('deposito')
    )
  })

  const combined = Array.from(new Set([...CLIENT_EXPENSE_TYPES, ...customExpenses]))
  return combined.sort((a, b) => a.localeCompare(b, 'pt-BR'))
}

// Normaliza primeira letra em maiúscula
export const capitalizeFirstLetter = (str: string | null | undefined): string => {
  if (!str) return ''
  const trimmed = str.trim()
  if (!trimmed) return ''
  return trimmed.charAt(0).toUpperCase() + trimmed.slice(1)
}
