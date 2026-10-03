import type { CSSProperties } from 'react'

export const getCaseStatusColor = (
  status: string | null | undefined,
  caseStatusesSettings: any[] = [],
): string => {
  if (!status) return '#cbd5e1'
  const s = caseStatusesSettings.find(
    (x: any) => (typeof x === 'string' ? x : x.label) === status,
  ) as any
  if (typeof s === 'object' && s && s.color) return s.color

  const lower = status.toLowerCase()
  if (lower === 'em andamento') return '#22c55e'
  if (lower === 'concluído' || lower === 'concluido') return '#f1f5f9'
  if (lower === 'suspenso') return '#eab308'
  if (lower === 'aguardando documentos') return '#ef4444'
  if (lower === 'pendente') return '#f97316'
  return '#cbd5e1'
}

export const getCaseStatusStyle = (
  status: string | null | undefined,
  caseStatusesSettings: any[] = [],
): CSSProperties => {
  if (!status) return {}
  const color = getCaseStatusColor(status, caseStatusesSettings)
  const isVeryLight = color.toLowerCase() === '#f1f5f9' || color.toLowerCase() === '#ffffff'
  return {
    backgroundColor: isVeryLight ? color : color + '15',
    borderLeft: `4px solid ${color}`,
  }
}

export const getCaseTypeColor = (
  type: string | null | undefined,
  caseTypesSettings: any[] = [],
): string => {
  if (!type) return '#94a3b8'
  const t = caseTypesSettings.find(
    (x: any) => (typeof x === 'string' ? x : x.label) === type,
  ) as any
  return typeof t === 'object' && t?.color ? t.color : '#94a3b8'
}

export const getCaseAlertLabel = (alert: string): string => {
  const trimmed = alert.trim()
  if (trimmed === 'Cobrar astreites' || trimmed === '💸 Cobrar astreites')
    return '💸 Cobrar astreites'
  if (trimmed === 'Litigância de má-fé' || trimmed === '🛑 Litigância de má-fé')
    return '🛑 Litigância de má-fé'
  if (trimmed === 'Segredo de Justiça' || trimmed === '🕵️ Segredo de Justiça')
    return '🕵️ Segredo de Justiça'
  return trimmed
}
