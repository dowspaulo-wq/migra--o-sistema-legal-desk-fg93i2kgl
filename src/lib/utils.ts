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
