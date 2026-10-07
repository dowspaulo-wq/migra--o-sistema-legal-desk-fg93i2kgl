/**
 * DPSjur - Centralização de variáveis de ambiente com suporte a runtime e build-time.
 *
 * Prioridade de leitura:
 * 1. import.meta.env.VITE_* (injetado estaticamente em tempo de build Vite)
 * 2. window.__ENV__.VITE_* (injetado dinamicamente em tempo de execução via /env.js gerado pelo docker-entrypoint)
 */

declare global {
  interface Window {
    __ENV__?: {
      VITE_SUPABASE_URL?: string
      VITE_SUPABASE_PUBLISHABLE_KEY?: string
      [key: string]: string | undefined
    }
    env?: {
      VITE_SUPABASE_URL?: string
      VITE_SUPABASE_PUBLISHABLE_KEY?: string
      [key: string]: string | undefined
    }
  }
}

const DEFAULT_FALLBACKS: Record<'VITE_SUPABASE_URL' | 'VITE_SUPABASE_PUBLISHABLE_KEY', string> = {
  VITE_SUPABASE_URL: 'https://cpcafthwnqazopqftemj.supabase.co',
  VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_n8rNjvEg6i-Sjme1-5Yhug_nNwxBRwO',
}

/**
 * Sanitiza valores de variáveis de ambiente do Supabase de forma defensiva:
 * - Remove espaços/quebras de linha nas extremidades;
 * - Remove aspas ou crases acidentais nas extremidades ("...", '...', `...`);
 * - Remove prefixos literais como "ANON_KEY=", "VITE_SUPABASE_PUBLISHABLE_KEY=", "VITE_SUPABASE_URL=";
 * - Remove barra "/" final se for uma URL.
 */
export function sanitizeEnvValue(val: unknown, isUrl: boolean = false): string {
  if (typeof val !== 'string') return ''
  let sanitized = val.trim()

  // Remove aspas ou crases acidentais nas extremidades (inclusive repetidas ou aninhadas)
  let prev = ''
  while (sanitized !== prev && sanitized.length > 0) {
    prev = sanitized
    sanitized = sanitized.replace(/^["'`\s]+|["'`\s]+$/g, '').trim()
  }

  // Remove prefixos literais colados por acidente
  // Ex: "ANON_KEY=ey...", "VITE_SUPABASE_PUBLISHABLE_KEY=ey...", "VITE_SUPABASE_URL=http...", "anon_key=..."
  const prefixRegex =
    /^(?:ANON_KEY|VITE_SUPABASE_PUBLISHABLE_KEY|VITE_SUPABASE_URL|SUPABASE_ANON_KEY|SUPABASE_URL)\s*[:=]\s*/i
  while (prefixRegex.test(sanitized)) {
    sanitized = sanitized.replace(prefixRegex, '').trim()
    // Limpa aspas novamente caso o prefixo tivesse aspas logo após o '='
    prev = ''
    while (sanitized !== prev && sanitized.length > 0) {
      prev = sanitized
      sanitized = sanitized.replace(/^["'`\s]+|["'`\s]+$/g, '').trim()
    }
  }

  // Se for URL, garante que não termine com "/"
  if (isUrl) {
    sanitized = sanitized.replace(/\/+$/, '').trim()
  }

  return sanitized
}

export function resolveEnvVar(key: 'VITE_SUPABASE_URL' | 'VITE_SUPABASE_PUBLISHABLE_KEY'): string {
  const isUrl = key === 'VITE_SUPABASE_URL'

  // 1. Runtime dinâmico no browser: window.__ENV__ ou window.env (gerado pelo env.js do contêiner Docker/EasyPanel)
  // Tem PRECEDÊNCIA MÁXIMA para permitir mudar o Supabase na VPS sem rebuild do bundle JS estático
  try {
    if (typeof window !== 'undefined') {
      const win = window as any
      const runtimeObj = win.__ENV__ || win.env
      const rawVal = runtimeObj?.[key]
      const sanitized = sanitizeEnvValue(rawVal, isUrl)
      if (sanitized.length > 0) {
        return sanitized
      }
    }
  } catch {
    /* falha silenciosa ao inspecionar window */
  }

  // 2. Build-time (Vite import.meta.env, injetado quando definido no build do Vite)
  try {
    const metaVal = (import.meta as any)?.env?.[key]
    const sanitized = sanitizeEnvValue(metaVal, isUrl)
    if (sanitized.length > 0) {
      return sanitized
    }
  } catch {
    /* ambiente sem import.meta */
  }

  // 3. Fallback padrão embutido (backend Supabase cpcafthwnqazopqftemj)
  return sanitizeEnvValue(DEFAULT_FALLBACKS[key] || '', isUrl)
}

export const SUPABASE_URL = resolveEnvVar('VITE_SUPABASE_URL')
export const SUPABASE_PUBLISHABLE_KEY = resolveEnvVar('VITE_SUPABASE_PUBLISHABLE_KEY')

// Alerta claro e explícito no console se as variáveis estiverem ausentes
if (!SUPABASE_URL || !SUPABASE_PUBLISHABLE_KEY) {
  const missing: string[] = []
  if (!SUPABASE_URL) missing.push('VITE_SUPABASE_URL')
  if (!SUPABASE_PUBLISHABLE_KEY) missing.push('VITE_SUPABASE_PUBLISHABLE_KEY')

  console.error(
    `[DPSjur] ⚠️ Configuração de ambiente incompleta! Variável(is) ausente(s): ${missing.join(', ')}. ` +
      'No EasyPanel, garanta que essas variáveis estão cadastradas na aba "Environment" do serviço ' +
      'ou passadas como build-args no Dockerfile. O app pode não conseguir se comunicar com o banco.',
  )
}
