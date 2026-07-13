import type { CSSProperties } from 'react'

export const getCaseStatusColor = (status: string, caseStatusesSettings: any[]): string => {
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
  caseStatusesSettings: any[],
): CSSProperties => {
  if (!status) return {}
  const color = getCaseStatusColor(status, caseStatusesSettings)
  const isVeryLight = color.toLowerCase() === '#f1f5f9' || color.toLowerCase() === '#ffffff'
  return {
    backgroundColor: isVeryLight ? color : color + '15',
    borderLeft: `4px solid ${color}`,
  }
}
