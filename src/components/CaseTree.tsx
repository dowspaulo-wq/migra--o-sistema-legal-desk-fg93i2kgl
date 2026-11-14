import { useMemo } from 'react'
import { Link } from 'react-router-dom'
import { Star } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import useLegalStore from '@/stores/useLegalStore'
import { CaseFeeBadge } from '@/components/CaseFeeBadge'
import { getCaseStatusStyle, getCaseTypeColor } from '@/lib/case-status'

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
 * Árvore de subprocessos em CARDS: cada subprocesso aparece como um card com a
 * mesma paleta do card do processo principal (fundo/borda lateral pelo status,
 * badges de status/tipo), sempre EXPANDIDO — todos os níveis visíveis de uma
 * vez, sem chevron de expandir/colapsar. Os filhos ficam indentados sob o pai
 * com guia de árvore (linha vertical + cotovelo de 1px). Profundidade
 * ilimitada na prática (limite alto de segurança).
 */
export function CaseTree({ roots, allCases, depth = 0 }: CaseTreeProps) {
  const { state } = useLegalStore()

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

  return (
    <div className="space-y-2">
      {roots.map((c) => {
        const children = childrenOf[c.id] || []
        const hasChildren = children.length > 0 && depth < MAX_DEPTH
        const resp = state.users?.find((u: any) => u.id === c.responsibleId)
        const typeColor = getCaseTypeColor(c.type, state.settings.caseTypes || [])

        return (
          <div key={c.id} className="relative">
            <div
              className="border p-3 rounded-lg hover:opacity-95 transition-colors bg-card"
              style={getCaseStatusStyle(c.status, state.settings.caseStatuses || [])}
            >
              <div
                className="flex items-center gap-2 flex-wrap min-w-0"
                data-native-system-icon="true"
              >
                <Link
                  to={`/processos/${c.id}`}
                  className="text-sm font-bold text-primary hover:underline flex items-center gap-1.5 shrink-0"
                >
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
                {c.status && <Badge variant="outline">{c.status}</Badge>}
                {c.type && (
                  <Badge
                    style={{ backgroundColor: typeColor }}
                    className="text-white border-0 hover:opacity-90 text-[10px]"
                  >
                    {c.type}
                  </Badge>
                )}
                <span className="text-xs text-muted-foreground truncate max-w-[20rem]">
                  {(c as any).position || 'Autor'}
                  {(c as any).adverseParty ? ` x ${(c as any).adverseParty}` : ''}
                </span>
                {resp && (
                  <span
                    className={cn(
                      'px-2 py-0.5 rounded-full font-medium text-[10px] shrink-0',
                      'ml-auto md:ml-2',
                    )}
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
            </div>

            {hasChildren && (
              <div className="relative mt-2 ml-2 pl-6 before:absolute before:left-2 before:top-0 before:bottom-0 before:w-px before:bg-slate-300">
                <CaseTree roots={children} allCases={allCases} depth={depth + 1} />
              </div>
            )}
          </div>
        )
      })}
    </div>
  )
}
