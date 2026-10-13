import React from 'react'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'
import type { Transaction } from '@/lib/mockData'
import type { TransactionCase } from '@/stores/useLegalStore'

/**
 * Normaliza e verifica se uma categoria de transação é considerada honorário.
 * No projeto, honorários são categorizados como:
 * - 'Honorários Contratuais'
 * - 'Honorários de Êxito'
 * - 'Honorários Sucumbenciais'
 * - 'Honorários Periciais'
 * - 'Honorários de Permuta'
 * - Ou qualquer categoria que contenha 'honorário' / 'honorario' (case/acentos insensíveis).
 */
export function isFeeCategory(category?: string | null): boolean {
  if (!category) return false
  const cat = category
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
  return cat.includes('honorario')
}

/**
 * Constrói um Set de process_ids que possuem ao menos uma transação de honorários vinculada.
 * Trata tanto o vínculo direto (`processId` na transação) quanto a relação N:N (`transaction_cases`).
 * Executa em O(T + TC) em lote para permitir consultas O(1) durante a renderização de listas.
 */
export function buildCasesWithFeesSet(
  transactions: Transaction[] = [],
  transactionCases: TransactionCase[] = [],
): Set<string> {
  const feeTxIdSet = new Set<string>()
  const caseIdSet = new Set<string>()

  for (let i = 0; i < transactions.length; i++) {
    const t = transactions[i]
    if (isFeeCategory(t.category)) {
      feeTxIdSet.add(t.id)
      if (t.processId) {
        caseIdSet.add(t.processId)
      }
    }
  }

  for (let i = 0; i < transactionCases.length; i++) {
    const tc = transactionCases[i]
    if (tc.case_id && feeTxIdSet.has(tc.transaction_id)) {
      caseIdSet.add(tc.case_id)
    }
  }

  return caseIdSet
}

interface CaseFeeBadgeProps {
  hasFees: boolean
  className?: string
  showNoFeeWarning?: boolean
}

/**
 * Componente visual de indicador de honorários do processo.
 * - hasFees = true: 💰 com tooltip "Honorários lançados"
 * - hasFees = false: 🟡 com tooltip "Sem honorários lançados" (ou alerta de atenção)
 */
export const CaseFeeBadge: React.FC<CaseFeeBadgeProps> = ({
  hasFees,
  className = '',
  showNoFeeWarning = true,
}) => {
  if (!hasFees && !showNoFeeWarning) {
    return null
  }

  const tooltipText = hasFees ? 'Honorários lançados' : 'Sem honorários lançados'
  const emoji = hasFees ? '💰' : '🟡'
  const ariaLabel = tooltipText

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <span
          className={`inline-flex items-center justify-center cursor-default select-none transition-transform hover:scale-110 text-sm leading-none shrink-0 ${className}`}
          title={tooltipText}
          aria-label={ariaLabel}
          role="img"
        >
          {emoji}
        </span>
      </TooltipTrigger>
      <TooltipContent side="top" className="text-xs py-1 px-2 font-medium">
        {tooltipText}
      </TooltipContent>
    </Tooltip>
  )
}
