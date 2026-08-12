export const NON_FINANCIAL_FEE_TYPES = ['Não gera honorários', 'apenas quota littis', 'pro bono']

export const isSuccessFeeType = (feeType: string): boolean => {
  const lower = feeType.toLowerCase()
  return lower.includes('êxito') || lower.includes('exito')
}

export const isNonFinancialFeeType = (feeType: string): boolean => {
  return NON_FINANCIAL_FEE_TYPES.includes(feeType.toLowerCase())
}

export const getFeeTypeOptions = (transactionCategories: string[] | null | undefined): string[] => {
  return [...(transactionCategories || []), ...NON_FINANCIAL_FEE_TYPES]
}
