import { useMemo } from 'react'

export function EnvironmentBanner() {
  const isPreview = useMemo(() => {
    if (typeof window === 'undefined') return false
    const hostname = window.location.hostname || ''
    return hostname.includes('goskip.app')
  }, [])

  if (!isPreview) {
    return null
  }

  return (
    <aside
      aria-label="Aviso de ambiente de testes"
      className="sticky top-0 z-[100] w-full bg-amber-500 text-amber-950 font-semibold px-3 py-1.5 text-xs sm:text-sm text-center shadow-sm border-b border-amber-600/40 select-none leading-tight"
    >
      <div className="max-w-7xl mx-auto flex items-center justify-center gap-1.5 flex-wrap">
        <span>
          ⚠️ AMBIENTE DE TESTES — cadastros aqui NÃO aparecem no sistema oficial. Use{' '}
          <a
            href="https://sistema.advdouglaspsantos.com.br"
            target="_blank"
            rel="noopener noreferrer"
            className="underline font-bold hover:text-black transition-colors"
          >
            sistema.advdouglaspsantos.com.br
          </a>
        </span>
      </div>
    </aside>
  )
}
