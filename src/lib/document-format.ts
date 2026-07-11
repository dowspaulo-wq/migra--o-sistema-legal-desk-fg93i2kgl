import { sanitizeDocument } from '@/lib/utils'

export function formatCPF(value: string): string {
  const digits = value.replace(/\D/g, '').slice(0, 11)
  return digits
    .replace(/(\d{3})(\d)/, '$1.$2')
    .replace(/(\d{3})(\d)/, '$1.$2')
    .replace(/(\d{3})(\d{1,2})$/, '$1-$2')
}

export function formatCNPJ(value: string): string {
  const digits = value.replace(/\D/g, '').slice(0, 14)
  return digits
    .replace(/(\d{2})(\d)/, '$1.$2')
    .replace(/(\d{3})(\d)/, '$1.$2')
    .replace(/(\d{3})(\d)/, '$1/$2')
    .replace(/(\d{4})(\d{1,2})$/, '$1-$2')
}

export function formatDocument(value: string, type: string): string {
  if (type === 'PJ') {
    return formatCNPJ(value)
  }
  return formatCPF(value)
}

export function isValidDocumentFormat(value: string, type: string): boolean {
  const clean = sanitizeDocument(value)
  if (type === 'PJ') {
    return /^\d{14}$/.test(clean)
  }
  return /^\d{11}$/.test(clean)
}

export function getDocumentMaskPlaceholder(type: string): string {
  if (type === 'PJ') {
    return '00.000.000/0000-00'
  }
  return '000.000.000-00'
}

export function getDocumentMaxLength(type: string): number {
  if (type === 'PJ') {
    return 18
  }
  return 14
}
