import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { ChevronDown, ChevronRight } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import useLegalStore from '@/stores/useLegalStore'
import { formatSafeLocalDate } from '@/lib/utils'

export interface CaseNode {
  id: string
  number: string
  status?: string | null
  system?: string | null
  type?: string | null
  [key: string]: any
}

interface CaseTreeProps {
  roots: CaseNode[]
  allCases: CaseNode[]
  depth?: number
}

const MAX_DEPTH = 12

export function CaseTree({ roots, allCases, depth = 0 }: CaseTreeProps) {
  const { state } = useLegalStore()
  const [expanded, setExpanded] = useState<Record<string, boolean>>({})

  const childrenOf = useMemo(() => {
    const map: Record<string, CaseNode[]> = {}
    for (const c of allCases) {
      if (!c.parentId) continue
      if (state.currentUser?.role !== 'Admin' && (c as any).isRestricted) continue
      const list = (map[c.parentId] ||= [])
      list.push(c)
    }
    for (const list of Object.values(map)) {
      list.sort((a, b) =>
        (a.number || '').localeCompare(b.number || '', 'pt-BR', { numeric: true }),
      )
    }
    return map
  }, [allCases, state.currentUser?.role])

  const toggle = (caseId: string) => setExpanded((prev) => ({ ...prev, [caseId]: !prev[caseId] }))

  return (
    <div className="space-y-2">
      {roots.map((c) => {
        const children = childrenOf[c.id] || []
        const hasChildren = children.length > 0
        const isOpen = !!expanded[c.id]
        const canExpand = hasChildren && depth < MAX_DEPTH

        return (
          <div key={c.id} className="space-y-2">
            <div
              className={cn(
                'border p-4 rounded-md hover:border-primary/50 transition-colors bg-white shadow-sm relative',
                depth > 0 && 'bg-slate-50/60',
              )}
              data-native-system-icon="true"
            >
              {depth > 0 && (
                <>
                  <span className="absolute top-0 -left-3 w-px h-full bg-slate-200" />
                  <span className="absolute top-1/2 -left-3 w-3 h-px bg-slate-200" />
                </>
              )}

              <div className="flex justify-between items-start mb-3 gap-2">
                <div className="flex items-center gap-1.5 flex-wrap min-w-0">
                  {canExpand ? (
                    <button
                      type="button"
                      onClick={() => toggle(c.id)}
                      className="shrink-0 p-0.5 rounded hover:bg-slate-100 text-slate-500 hover:text-primary transition-colors"
                      aria-expanded={isOpen}
                      aria-label={isOpen ? 'Recolher subprocessos' : 'Expandir subprocessos'}
                      title={isOpen ? 'Recolher subprocessos' : 'Expandir subprocessos'}
                    >
                      {isOpen ? (
                        <ChevronDown className="h-4 w-4" />
                      ) : (
                        <ChevronRight className="h-4 w-4" />
                      )}
                    </button>
                  ) : null}
                  {(() => {
                    const sys = state.caseSystems?.find((s: any) => s.name === c.system)
                    if (sys?.image_url) {
                      return (
                        <img
                          src={sys.image_url}
                          alt={sys.name}
                          className="w-5 h-5 object-contain shrink-0"
                          title={sys.name}
                        />
                      )
                    }
                    return null
                  })()}
                  <Link
                    to={`/processos/${c.id}`}
                    className="font-bold text-base text-primary hover:underline"
                  >
                    {c.number}
                  </Link>
                  {c.status && (
                    <Badge variant="outline" className="bg-slate-50">
                      {c.status}
                    </Badge>
                  )}
                  {c.type && (
                    <Badge variant="secondary" className="text-[10px]">
                      {c.type}
                    </Badge>
                  )}
                </div>
                <div className="flex items-center gap-1.5 shrink-0">
                  {c.noFees && (
                    <span className="text-base leading-none" title="Não gera honorários">
                      🚫
                    </span>
                  )}
                </div>
              </div>

              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-5 gap-3 text-xs text-slate-700">
                <div>
                  <span className="font-semibold block text-slate-500 mb-0.5">Tipo</span>
                  {c.type || '—'}
                </div>
                <div>
                  <span className="font-semibold block text-slate-500 mb-0.5">Tribunal/Vara</span>
                  {c.court || '—'}
                </div>
                <div>
                  <span className="font-semibold block text-slate-500 mb-0.5">Comarca/UF</span>
                  {c.comarca
                    ? `${String(c.comarca).toUpperCase()}${c.state ? ` - ${String(c.state).toUpperCase()}` : ''}`
                    : '—'}
                </div>
                <div>
                  <span className="font-semibold block text-slate-500 mb-0.5">Parte Adversa</span>
                  <span className="truncate block" title={c.adverseParty || ''}>
                    {c.adverseParty || '—'}
                  </span>
                </div>
                <div>
                  <span className="font-semibold block text-slate-500 mb-0.5">Sistema</span>
                  {c.system || '—'}
                </div>
                <div>
                  <span className="font-semibold block text-slate-500 mb-0.5">Valor da Causa</span>
                  {c.value != null
                    ? `R$ ${Number(c.value).toLocaleString('pt-BR', { minimumFractionDigits: 2 })}`
                    : '—'}
                </div>
                <div>
                  <span className="font-semibold block text-slate-500 mb-0.5">Data de Início</span>
                  {c.startDate ? formatSafeLocalDate(c.startDate) : '—'}
                </div>
              </div>
            </div>

            {canExpand && isOpen && (
              <div className="pl-6 relative before:absolute before:inset-y-0 before:left-3 before:w-px before:bg-slate-200">
                <CaseTree roots={children} allCases={allCases} depth={depth + 1} />
              </div>
            )}
          </div>
        )
      })}
    </div>
  )
}
