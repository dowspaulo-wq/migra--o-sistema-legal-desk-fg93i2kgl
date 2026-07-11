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
