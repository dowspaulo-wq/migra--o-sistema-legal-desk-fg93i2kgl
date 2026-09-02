import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

/**
 * Merges multiple class names into a single string
 * @param inputs - Array of class names
 * @returns Merged class names
 */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

/**
 * Normalizes a string by removing diacritics and converting to lowercase
 */
export function normalizeStr(str: string | null | undefined): string {
  if (!str) return ''
  return str
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
}

/**
 * Normalizes a process number by removing special characters like dots, hyphens, underscores and spaces
 */
export function normalizeProcessNumber(str: string | null | undefined): string {
  if (!str) return ''
  return str.replace(/[.\-_ ]/g, '')
}

/**
 * Parses a YYYY-MM-DD string into a safe local Date object (at noon)
 * to avoid timezone offset shifts (e.g., getting previous day)
 */
export function parseSafeLocalDate(dateStr: string | null | undefined): Date {
  if (!dateStr) return new Date()
  const parts = dateStr.split('T')[0].split('-')
  if (parts.length !== 3) return new Date()
  const [y, m, d] = parts
  return new Date(Number(y), Number(m) - 1, Number(d), 12, 0, 0)
}

/**
 * Safely formats a YYYY-MM-DD string to local pt-BR date format
 */
export function formatSafeLocalDate(dateStr: string | null | undefined): string {
  if (!dateStr) return ''
  return parseSafeLocalDate(dateStr).toLocaleDateString('pt-BR')
}

/**
 * Safely formats an ISO timestamp or date string to local pt-BR date and time (Brasília time)
 * Format: DD/MM/YYYY HH:mm
 */
export function formatSafeDateTime(dateStr: string | null | undefined): string {
  if (!dateStr) return ''
  const date = new Date(dateStr)
  if (isNaN(date.getTime())) return ''
  return date.toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'America/Sao_Paulo',
  })
}

/**
 * Returns Tailwind CSS color classes for a given priority level
 */
export function getPriorityColorClass(priority: string | null | undefined): string {
  const p = (priority || '').toLowerCase()
  if (p === 'baixa') return 'bg-green-100 text-green-800 border-green-200'
  if (p === 'média' || p === 'media') return 'bg-yellow-100 text-yellow-800 border-yellow-200'
  if (p === 'alta') return 'bg-orange-100 text-orange-800 border-orange-200'
  if (p === 'urgente') return 'bg-red-100 text-red-800 border-red-200'
  return 'bg-slate-100 text-slate-800 border-slate-200'
}

/**
 * Formats a CPF string to the pattern 000.000.000-00
 * Accepts both raw digits and partially formatted strings
 */
export function formatCPF(value: string): string {
  const digits = (value || '').replace(/\D/g, '').slice(0, 11)
  if (digits.length <= 3) return digits
  if (digits.length <= 6) return `${digits.slice(0, 3)}.${digits.slice(3)}`
  if (digits.length <= 9) return `${digits.slice(0, 3)}.${digits.slice(3, 6)}.${digits.slice(6)}`
  return `${digits.slice(0, 3)}.${digits.slice(3, 6)}.${digits.slice(6, 9)}-${digits.slice(9)}`
}

/**
 * Removes all non-digit characters from a document string
 */
export function sanitizeDocument(doc: string | null | undefined): string {
  return (doc || '').replace(/\D/g, '')
}

/**
 * Strips HTML tags from a string, returning plain text
 */
export function stripHtml(html: string | null | undefined): string {
  if (!html) return ''
  const tmp = document.createElement('div')
  tmp.innerHTML = html
  return tmp.textContent || tmp.innerText || ''
}

/**
 * Returns detailed process duration: "X dias (Y anos, Z meses e W dias)"
 */
export function getDetailedDuration(
  start: string | null | undefined,
  end?: string | null,
  status?: string | null,
): string {
  if (!start) return '0 dias (0 dias)'
  const isConcluido = status && normalizeStr(status).includes('concluido')
  const endDate = isConcluido && end ? parseSafeLocalDate(end) : new Date()
  const startDate = parseSafeLocalDate(start)

  let totalDays = Math.floor((endDate.getTime() - startDate.getTime()) / (1000 * 3600 * 24))
  if (totalDays < 0) totalDays = 0

  let years = endDate.getFullYear() - startDate.getFullYear()
  let months = endDate.getMonth() - startDate.getMonth()
  let days = endDate.getDate() - startDate.getDate()

  if (days < 0) {
    months--
    const prevMonth = new Date(endDate.getFullYear(), endDate.getMonth(), 0)
    days += prevMonth.getDate()
  }
  if (months < 0) {
    years--
    months += 12
  }

  const parts = []
  if (years > 0) parts.push(`${years} ${years === 1 ? 'ano' : 'anos'}`)
  if (months > 0) parts.push(`${months} ${months === 1 ? 'mês' : 'meses'}`)
  if (days > 0 || (years === 0 && months === 0))
    parts.push(`${days} ${days === 1 ? 'dia' : 'dias'}`)

  const detailed = parts.join(', ').replace(/, ([^,]*)$/, ' e $1')
  return `${totalDays} dias (${detailed || '0 dias'})`
}
