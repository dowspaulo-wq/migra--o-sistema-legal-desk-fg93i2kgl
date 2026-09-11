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
/**
 * Normalizes Brazilian phone numbers:
 * If it has leading 55 with 12 or 13 digits (55 + DDD + 8 or 9 digits), removes 55.
 * Returns only DDD + number (10 or 11 digits) if valid, or the sanitized digits.
 */
export function normalizePhoneForAsaas(phone: string | null | undefined): string | undefined {
  if (!phone) return undefined
  let digits = phone.replace(/\D/g, '')
  if (!digits || /^0+$/.test(digits) || digits.length < 8) return undefined

  // Se tiver 55 no início e totalizar 12 ou 13 dígitos (55 + 10 ou 11 dígitos)
  if (digits.startsWith('55') && (digits.length === 12 || digits.length === 13)) {
    digits = digits.slice(2)
  }

  // DDD (2 dígitos) + 8 ou 9 dígitos = 10 ou 11 dígitos
  if (digits.length === 10 || digits.length === 11) {
    return digits
  }

  // Se tiver outro tamanho mas for pelo menos 8 dígitos válidos, retorna os dígitos
  return digits
}

/**
 * Formats a Brazilian phone number for display or input
 * Pattern: (XX) XXXXX-XXXX ou (XX) XXXX-XXXX
 */
/**
 * Returns formatted phone for WhatsApp wa.me link:
 * WhatsApp requires country code (55 for Brazil).
 * If phone already has 55 (12/13 digits), keeps it.
 * If phone has 10/11 digits, prepends 55.
 */
export function getWhatsAppPhone(phone: string | null | undefined): string {
  if (!phone) return ''
  let digits = phone.replace(/\D/g, '')
  if (!digits || /^0+$/.test(digits)) return ''
  if (digits.startsWith('55') && (digits.length === 12 || digits.length === 13)) {
    return digits
  }
  if (digits.length === 10 || digits.length === 11) {
    return `55${digits}`
  }
  return digits
}

export function formatPhone(phone: string | null | undefined): string {
  if (!phone) return ''
  let digits = phone.replace(/\D/g, '')
  if (!digits) return ''

  // Se já veio com 55 e tem 12 ou 13 dígitos, remove o 55 para exibição amigável
  if (digits.startsWith('55') && (digits.length === 12 || digits.length === 13)) {
    digits = digits.slice(2)
  }

  if (digits.length <= 2) {
    return `(${digits}`
  }
  if (digits.length <= 6) {
    return `(${digits.slice(0, 2)}) ${digits.slice(2)}`
  }
  if (digits.length <= 10) {
    return `(${digits.slice(0, 2)}) ${digits.slice(2, 6)}-${digits.slice(6)}`
  }
  return `(${digits.slice(0, 2)}) ${digits.slice(2, 7)}-${digits.slice(7, 11)}`
}

/**
 * Returns raw DDD + number (10 or 11 digits) for database storage
 */
export function sanitizeClientPhone(phone: string | null | undefined): string {
  if (!phone) return ''
  let digits = phone.replace(/\D/g, '')
  if (digits.startsWith('55') && (digits.length === 12 || digits.length === 13)) {
    digits = digits.slice(2)
  }
  return digits.slice(0, 11)
}

/**
 * Validates if phone is valid Brazilian format: DDD (2 digits) + 8 or 9 digits (total 10 or 11 digits)
 */
export function isValidClientPhone(phone: string | null | undefined): boolean {
  if (!phone) return false
  let digits = phone.replace(/\D/g, '')
  if (digits.startsWith('55') && (digits.length === 12 || digits.length === 13)) {
    digits = digits.slice(2)
  }
  if (/^0+$/.test(digits)) return false
  return digits.length === 10 || digits.length === 11
}

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
