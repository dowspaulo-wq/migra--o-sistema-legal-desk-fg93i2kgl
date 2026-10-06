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

export function resolveEnvVar(key: 'VITE_SUPABASE_URL' | 'VITE_SUPABASE_PUBLISHABLE_KEY'): string {
  // 1. Runtime dinâmico no browser: window.__ENV__ ou window.env (gerado pelo env.js do contêiner Docker/EasyPanel)
  try {
    if (typeof window !== 'undefined') {
      const win = window as any
      const runtimeObj = win.__ENV__ || win.env
      const runtimeVal = runtimeObj?.[key]
      if (typeof runtimeVal === 'string' && runtimeVal.trim().length > 0) {
        return runtimeVal.trim()
      }
    }
  } catch {
    /* falha silenciosa ao inspecionar window */
  }

  // 2. Build-time (Vite import.meta.env, injetado quando definido no build do Vite)
  try {
    const metaVal = (import.meta as any)?.env?.[key]
    if (typeof metaVal === 'string' && metaVal.trim().length > 0) {
      return metaVal.trim()
    }
  } catch {
    /* ambiente sem import.meta */
  }

  // 3. Fallback padrão embutido (backend Supabase cpcafthwnqazopqftemj)
  return DEFAULT_FALLBACKS[key] || ''
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
