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
  }
}

function resolveEnvVar(key: 'VITE_SUPABASE_URL' | 'VITE_SUPABASE_PUBLISHABLE_KEY'): string {
  // 1. Tenta ler do build-time (Vite import.meta.env)
  try {
    const metaVal = (import.meta as any)?.env?.[key]
    if (typeof metaVal === 'string' && metaVal.trim().length > 0) {
      return metaVal.trim()
    }
  } catch {
    /* ambiente sem import.meta */
  }

  // 2. Tenta ler do runtime (window.__ENV__ gerado pelo entrypoint do contêiner)
  try {
    if (typeof window !== 'undefined' && window.__ENV__) {
      const runtimeVal = window.__ENV__[key]
      if (typeof runtimeVal === 'string' && runtimeVal.trim().length > 0) {
        return runtimeVal.trim()
      }
    }
  } catch {
    /* falha silenciosa ao ler window */
  }

  return ''
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
