import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { ChevronDown, ChevronRight, Star } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import useLegalStore from '@/stores/useLegalStore'
import { CaseFeeBadge } from '@/components/CaseFeeBadge'

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

/**
 * Árvore de subprocessos em LINHAS (sublinhas em cascata): cada filho aparece
 * como uma linha indentada abaixo do pai, com guia vertical + conector
 * horizontal (linha de árvore), sem caixas aninhadas. Profundidade ilimitada
 * na prática (limite alto de segurança), expandida chevron por chevron.
 */
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
    <div className="space-y-1">
      {roots.map((c) => {
        const children = childrenOf[c.id] || []
        const hasChildren = children.length > 0
        const isOpen = !!expanded[c.id]
        const canExpand = hasChildren && depth < MAX_DEPTH
        const resp = state.users?.find((u: any) => u.id === c.responsibleId)

        return (
          <div key={c.id} className="relative">
            {/* conector horizontal ligando esta linha ao guia vertical do pai */}
            {depth > 0 && <span className="absolute -left-4 top-[13px] w-4 h-px bg-slate-300" />}

            <div
              className="flex items-center gap-1.5 flex-wrap py-0.5 min-w-0"
              data-native-system-icon="true"
            >
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
                    <ChevronDown className={depth === 0 ? 'h-4 w-4' : 'h-3.5 w-3.5'} />
                  ) : (
                    <ChevronRight className={depth === 0 ? 'h-4 w-4' : 'h-3.5 w-3.5'} />
                  )}
                </button>
              ) : (
                <span className="w-[18px] shrink-0" aria-hidden="true" />
              )}
              {(() => {
                const sys = state.caseSystems?.find((s: any) => s.name === c.system)
                if (sys?.image_url) {
                  return (
                    <img
                      src={sys.image_url}
                      alt={sys.name}
                      className="w-4 h-4 object-contain shrink-0"
                      title={sys.name}
                    />
                  )
                }
                return null
              })()}
              <Link
                to={`/processos/${c.id}`}
                className={cn(
                  'font-bold text-primary hover:underline shrink-0',
                  depth === 0 ? 'text-base' : 'text-sm',
                )}
              >
                {c.number}
              </Link>
              <CaseFeeBadge hasFees={(c as any).hasFees} noFees={(c as any).noFees} />
              {(c as any).isSpecial && (
                <Star className="h-3.5 w-3.5 fill-yellow-400 text-yellow-400 shrink-0" />
              )}
              {(c as any).isProblematic && (
                <span className="text-sm leading-none shrink-0" title="Problemático">
                  💩
                </span>
              )}
              {(c as any).isRestricted && (
                <span
                  className="text-sm leading-none shrink-0"
                  title="Visibilidade Interna Restrita"
                >
                  🔒
                </span>
              )}
              {c.status && (
                <Badge variant="outline" className="text-[10px] bg-slate-50">
                  {c.status}
                </Badge>
              )}
              {c.type && (
                <Badge variant="secondary" className="text-[10px]">
                  {c.type}
                </Badge>
              )}
              <span className="text-[11px] text-muted-foreground truncate max-w-[24rem]">
                {(c as any).position || 'Autor'}
                {(c as any).adverseParty ? ` x ${(c as any).adverseParty}` : ''}
              </span>
              {resp && (
                <span
                  className="ml-auto px-2 py-0.5 rounded-full font-medium text-[10px] shrink-0"
                  style={{
                    backgroundColor: `${resp.color}20`,
                    color: resp.color,
                    border: `1px solid ${resp.color}40`,
                  }}
                >
                  Resp: {resp.name.split(' ')[0]}
                </span>
              )}
            </div>

            {canExpand && isOpen && (
              <div className="relative ml-2 pl-6 before:absolute before:left-2 before:top-0 before:bottom-0 before:w-px before:bg-slate-300">
                <CaseTree roots={children} allCases={allCases} depth={depth + 1} />
              </div>
            )}
          </div>
        )
      })}
    </div>
  )
}
