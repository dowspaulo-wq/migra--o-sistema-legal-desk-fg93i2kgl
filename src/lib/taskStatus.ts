/**
 * Helpers para padronização de status de tarefas (tasks).
 * Evita inconsistências entre escrita e leitura de status ("Concluído", "Concluída", "concluido", "pendente", etc.)
 */

export function isTaskDone(status?: string | null): boolean {
  if (!status) return false
  const normalized = status
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
  return (
    normalized === 'concluido' || normalized === 'concluida' || normalized.startsWith('conclui')
  )
}

export function canonicalTaskStatus(status?: string | null): string {
  if (!status) return 'Pendente'
  if (isTaskDone(status)) {
    return 'Concluída'
  }
  const normalized = status
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
  if (normalized === 'pendente') {
    return 'Pendente'
  }
  return status
}
