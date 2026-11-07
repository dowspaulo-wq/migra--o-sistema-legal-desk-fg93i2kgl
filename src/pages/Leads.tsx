import { useEffect, useMemo, useState } from 'react'
import { CheckCircle2 } from 'lucide-react'
import { useLeadsStore, LEAD_STAGES, type Lead } from '@/stores/useLeadsStore'
import useLegalStore from '@/stores/useLegalStore'
import { useAuth } from '@/hooks/use-auth'
import { LeadDialog } from '@/components/leads/LeadDialog'
import { LeadDetailSheet } from '@/components/leads/LeadDetailSheet'
import { ConvertLeadDialog } from '@/components/leads/ConvertLeadDialog'
import {
  LeadListsSettingsDialog,
  LEAD_LISTS_DEFAULTS,
  type LeadListsConfig,
} from '@/components/leads/LeadListsSettingsDialog'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Label } from '@/components/ui/label'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Skeleton } from '@/components/ui/skeleton'
import { formatSafeLocalDate, formatPhone } from '@/lib/utils'
import { toast } from '@/hooks/use-toast'
import {
  UserPlus,
  PhoneCall,
  Clock,
  Percent,
  AlertTriangle,
  CalendarClock,
  BellRing,
  FileQuestion,
  TrendingUp,
  LayoutGrid,
  List,
  Search,
  Settings as SettingsIcon,
} from 'lucide-react'

// ============================================================
// MÓDULO DE GESTÃO DE LEADS — painel, lista e Kanban
// ============================================================

const stageBadgeClass = (stage: string) => {
  switch (stage) {
    case 'Novo':
      return 'bg-sky-100 text-sky-800'
    case 'Aguardando contato':
      return 'bg-slate-100 text-slate-700'
    case 'Em atendimento':
      return 'bg-blue-100 text-blue-800'
    case 'Qualificado':
      return 'bg-indigo-100 text-indigo-800'
    case 'Proposta enviada':
      return 'bg-amber-100 text-amber-800'
    case 'Contratado':
      return 'bg-emerald-100 text-emerald-800'
    case 'Perdido':
      return 'bg-rose-100 text-rose-800'
    case 'Não qualificado':
      return 'bg-zinc-100 text-zinc-600'
    default:
      return 'bg-slate-100 text-slate-700'
  }
}

const dayMs = 24 * 60 * 60 * 1000
const isoDay = (d: Date) => d.toISOString().slice(0, 10)
const parseDay = (v?: string | null) => (v ? new Date(String(v).slice(0, 10) + 'T12:00:00') : null)
const daysBetween = (a: Date, b: Date) => Math.floor((b.getTime() - a.getTime()) / dayMs)

export default function Leads() {
  const {
    leads,
    isLoading,
    fetchLeads,
    fetchInteractions,
    addLead,
    updateLead,
    changeStage,
    batchRenameStage,
    addInteraction,
    convertLead,
    checkLeadDuplicates,
  } = useLeadsStore()
  const legal = useLegalStore()
  const { user } = useAuth()
  const isAdmin =
    user?.role === 'Admin' ||
    legal.state.currentUser?.role === 'Admin' ||
    (user?.email &&
      ['dowspaulo@gmail.com', 'douglas@advdouglaspsantos.com.br'].includes(user.email))

  const [tab, setTab] = useState('painel')
  const [view, setView] = useState<'lista' | 'kanban'>('lista')
  const [search, setSearch] = useState('')
  const [fStage, setFStage] = useState('todos')
  const [fOrigin, setFOrigin] = useState('todas')
  const [fArea, setFArea] = useState('todas')
  const [fResponsible, setFResponsible] = useState('todos')
  const [fPriority, setFPriority] = useState('todas')
  const [fromDate, setFromDate] = useState('')
  const [toDate, setToDate] = useState('')
  const [nextContactDate, setNextContactDate] = useState('')
  const [page, setPage] = useState(1)
  const pageSize = 20

  const [dialogOpen, setDialogOpen] = useState(false)
  const [editingLead, setEditingLead] = useState<Lead | null>(null)
  const [detailLead, setDetailLead] = useState<Lead | null>(null)
  const [detailOpen, setDetailOpen] = useState(false)
  const [convertLeadObj, setConvertLeadObj] = useState<Lead | null>(null)
  const [convertOpen, setConvertOpen] = useState(false)
  const [settingsOpen, setSettingsOpen] = useState(false)

  useEffect(() => {
    fetchLeads()
  }, [fetchLeads])

  const users = useMemo(
    () =>
      (legal.state.users || []).map((u: any) => ({ id: u.id, name: u.name || u.email || u.id })),
    [legal.state.users],
  )

  // Configuração de listas com fallback para os padrões
  const settingsRecord = legal.state.settings as any
  const leadListsConfig: LeadListsConfig = useMemo(() => {
    const rawOrigins = settingsRecord?.leadOrigins
    const rawStages = settingsRecord?.leadStages
    const rawInteractions = settingsRecord?.leadInteractionTypes
    const rawAreas = settingsRecord?.leadAreas
    const rawSubjects = settingsRecord?.leadSubjects

    return {
      leadOrigins:
        Array.isArray(rawOrigins) && rawOrigins.length > 0
          ? rawOrigins
          : LEAD_LISTS_DEFAULTS.leadOrigins,
      leadStages:
        Array.isArray(rawStages) && rawStages.length === 8
          ? rawStages
          : LEAD_LISTS_DEFAULTS.leadStages,
      leadInteractionTypes:
        Array.isArray(rawInteractions) && rawInteractions.length > 0
          ? rawInteractions
          : LEAD_LISTS_DEFAULTS.leadInteractionTypes,
      leadAreas:
        Array.isArray(rawAreas) && rawAreas.length > 0 ? rawAreas : LEAD_LISTS_DEFAULTS.leadAreas,
      leadSubjects:
        Array.isArray(rawSubjects) && rawSubjects.length > 0
          ? rawSubjects
          : LEAD_LISTS_DEFAULTS.leadSubjects,
    }
  }, [settingsRecord])

  const configuredStages = useMemo(
    () => leadListsConfig.leadStages.map((s) => s.label),
    [leadListsConfig.leadStages],
  )
  const configuredOrigins = leadListsConfig.leadOrigins
  const configuredAreas = leadListsConfig.leadAreas
  const configuredSubjects = leadListsConfig.leadSubjects
  const configuredInteractionTypes = leadListsConfig.leadInteractionTypes

  const userName = (id?: string | null) => users.find((u) => u.id === id)?.name || '—'

  // ---------- FILTROS ----------
  const filtered = useMemo(() => {
    const s = search.trim().toUpperCase()
    return leads.filter((l) => {
      if (s) {
        const hay = [l.name, l.phone, l.email, l.subject, l.city]
          .filter(Boolean)
          .join(' ')
          .toUpperCase()
        if (!hay.includes(s)) return false
      }
      if (fStage !== 'todos' && l.stage !== fStage) return false
      if (fOrigin !== 'todas' && l.origin !== fOrigin) return false
      if (fArea !== 'todas' && l.area !== fArea) return false
      if (fResponsible !== 'todos' && l.responsibleId !== fResponsible) return false
      if (fPriority !== 'todas' && (l.priority || 'Média') !== fPriority) return false
      if (fromDate && (l.entryDate || '') < fromDate) return false
      if (toDate && (l.entryDate || '') > toDate) return false
      if (nextContactDate && (l.nextContactAt || '') !== nextContactDate) return false
      return true
    })
  }, [
    leads,
    search,
    fStage,
    fOrigin,
    fArea,
    fResponsible,
    fPriority,
    fromDate,
    toDate,
    nextContactDate,
  ])

  const totalPages = Math.max(1, Math.ceil(filtered.length / pageSize))
  const paged = filtered.slice((page - 1) * pageSize, page * pageSize)

  useEffect(
    () => setPage(1),
    [search, fStage, fOrigin, fArea, fResponsible, fPriority, fromDate, toDate, nextContactDate],
  )

  // ---------- PAINEL / INDICADORES (período selecionável) ----------
  const periodFiltered = useMemo(() => {
    return leads.filter((l) => {
      const d = l.entryDate || String(l.created_at || '').slice(0, 10) || ''
      if (fromDate && d < fromDate) return false
      if (toDate && d > toDate) return false
      return true
    })
  }, [leads, fromDate, toDate])

  const metrics = useMemo(() => {
    const now = new Date()
    const todayStr = isoDay(now)
    const count = (stage: string) => periodFiltered.filter((l) => l.stage === stage).length
    const active = periodFiltered.filter((l) => !l.convertedClientId)
    const novos = count('Novo')
    const aguardando = count('Aguardando contato')
    const atendimento = count('Em atendimento')
    const qualificados = count('Qualificado')
    const propostas = count('Proposta enviada')
    const convertidos = count('Contratado')
    const perdidos = count('Perdido') + count('Não qualificado')

    const pendentesRetorno = active.filter(
      (l) =>
        l.nextContactAt &&
        l.nextContactAt <= todayStr &&
        l.stage !== 'Perdido' &&
        l.stage !== 'Não qualificado',
    ).length

    const closedOutcomes = convertidos + perdidos
    const taxa = closedOutcomes > 0 ? Math.round((convertidos / closedOutcomes) * 100) : 0

    const byOrigin: Record<string, { total: number; convertidos: number }> = {}
    periodFiltered.forEach((l) => {
      const o = l.origin || 'Sem origem'
      if (!byOrigin[o]) byOrigin[o] = { total: 0, convertidos: 0 }
      byOrigin[o].total++
      if (l.stage === 'Contratado') byOrigin[o].convertidos++
    })
    const originRows = Object.entries(byOrigin)
      .map(([origin, v]) => ({
        origin,
        total: v.total,
        convertidos: v.convertidos,
        taxa: v.total ? Math.round((v.convertidos / v.total) * 100) : 0,
      }))
      .sort((a, b) => b.total - a.total)

    const byCampaign: Record<string, number> = {}
    periodFiltered.forEach((l) => {
      const c = l.campaign?.trim()
      if (c) byCampaign[c] = (byCampaign[c] || 0) + 1
    })
    const campaignRows = Object.entries(byCampaign)
      .map(([campaign, total]) => ({ campaign, total }))
      .sort((a, b) => b.total - a.total)

    const lostReasons: Record<string, number> = {}
    periodFiltered
      .filter((l) => l.stage === 'Perdido' || l.stage === 'Não qualificado')
      .forEach((l) => {
        const r = (l.lostReason || 'Não informado').trim()
        lostReasons[r] = (lostReasons[r] || 0) + 1
      })
    const lostRows = Object.entries(lostReasons)
      .map(([motivo, total]) => ({ motivo, total }))
      .sort((a, b) => b.total - a.total)

    // Tempo até o 1º atendimento (média em dias entre entrada e 1º contato registrado)
    let firstContactSamples = 0
    let firstContactSum = 0
    periodFiltered.forEach((l) => {
      const entry = parseDay(l.entryDate || l.created_at)
      const last = parseDay(l.lastContactAt)
      if (entry && last) {
        const d = daysBetween(entry, last)
        if (d >= 0) {
          firstContactSamples++
          firstContactSum += d
        }
      }
    })
    const tempoPrimeiroAtendimento =
      firstContactSamples > 0 ? Math.round((firstContactSum / firstContactSamples) * 10) / 10 : null

    return {
      novos,
      aguardando,
      atendimento,
      qualificados,
      propostas,
      convertidos,
      perdidos,
      pendentesRetorno,
      taxa,
      originRows,
      campaignRows,
      lostRows,
      tempoPrimeiroAtendimento,
    }
  }, [periodFiltered])

  // ---------- ALERTAS ----------
  const alerts = useMemo(() => {
    const now = new Date()
    const todayStr = isoDay(now)
    const list: Array<{
      key: string
      tone: 'destructive' | 'warning' | 'info'
      title: string
      desc: string
      lead: Lead
    }> = []
    const active = leads.filter((l) => !l.convertedClientId)

    active.forEach((l) => {
      const entry = l.entryDate || String(l.created_at || '').slice(0, 10) || ''
      const daysOld = entry ? daysBetween(new Date(entry + 'T12:00:00'), now) : 0

      // Lead novo sem atendimento
      if (l.stage === 'Novo' && daysOld >= 2) {
        list.push({
          key: `new-${l.id}`,
          tone: 'destructive',
          title: 'Lead novo sem atendimento',
          desc: `${l.name} entrou há ${daysOld} dias e ainda não saiu da etapa "Novo".`,
          lead: l,
        })
      }

      // Retorno agendado para hoje
      if (l.nextContactAt && l.nextContactAt === todayStr) {
        list.push({
          key: `today-${l.id}`,
          tone: 'warning',
          title: 'Retorno agendado para hoje',
          desc: `${l.name} — contato combinado para hoje.`,
          lead: l,
        })
      }

      // Contato atrasado
      if (
        l.nextContactAt &&
        l.nextContactAt < todayStr &&
        l.stage !== 'Perdido' &&
        l.stage !== 'Não qualificado'
      ) {
        const late = daysBetween(new Date(l.nextContactAt + 'T12:00:00'), now)
        list.push({
          key: `late-${l.id}`,
          tone: 'destructive',
          title: 'Contato atrasado',
          desc: `${l.name} — retorno atrasado há ${late} dia(s).`,
          lead: l,
        })
      }

      // Proposta aguardando resposta
      if (l.stage === 'Proposta enviada') {
        const ref = l.updated_at || l.created_at
        const since = ref ? daysBetween(new Date(String(ref).slice(0, 10) + 'T12:00:00'), now) : 0
        if (since >= 5) {
          list.push({
            key: `proposal-${l.id}`,
            tone: 'warning',
            title: 'Proposta aguardando resposta',
            desc: `${l.name} — proposta enviada há ${since} dias sem fechamento.`,
            lead: l,
          })
        }
      }

      // Lead sem movimentação há X dias (usa updated_at como proxy)
      const mov = l.updated_at || l.created_at
      if (mov && l.stage !== 'Perdido' && l.stage !== 'Não qualificado' && !l.convertedClientId) {
        const daysIdle = daysBetween(new Date(String(mov).slice(0, 10) + 'T12:00:00'), now)
        if (daysIdle >= 15) {
          list.push({
            key: `idle-${l.id}`,
            tone: 'info',
            title: 'Lead sem movimentação',
            desc: `${l.name} está há ${daysIdle} dias sem movimentação na etapa "${l.stage}".`,
            lead: l,
          })
        }
      }
    })

    const order = { destructive: 0, warning: 1, info: 2 }
    return list.sort((a, b) => order[a.tone] - order[b.tone])
  }, [leads])

  // ---------- AÇÕES ----------
  const openNew = () => {
    setEditingLead(null)
    setDialogOpen(true)
  }
  const openEdit = (l: Lead) => {
    setEditingLead(l)
    setDialogOpen(true)
  }
  const openDetail = (l: Lead) => {
    setDetailLead(l)
    setDetailOpen(true)
  }
  const openConvert = (l: Lead) => {
    if (l.convertedClientId) {
      toast({
        title: 'Lead já convertido',
        description: 'Este lead já foi convertido em cliente.',
        variant: 'destructive',
      })
      return
    }
    if (l.stage !== 'Qualificado' && l.stage !== 'Proposta enviada') {
      toast({
        title: 'Conversão indisponível',
        description:
          'Só é possível converter leads nas etapas "Qualificado" ou "Proposta enviada". Mova o lead no funil primeiro.',
        variant: 'destructive',
      })
      return
    }
    setConvertLeadObj(l)
    setConvertOpen(true)
  }

  const handleSave = async (payload: Partial<Lead>) => {
    if (editingLead) {
      return await updateLead(editingLead.id, payload)
    }
    return !!(await addLead(payload))
  }

  const handleScheduleFollowUp = async (id: string, date: string) => {
    return updateLead(id, { nextContactAt: date })
  }

  const handleSaveListsConfig = async (newConfig: LeadListsConfig): Promise<boolean> => {
    try {
      const oldStages = leadListsConfig.leadStages
      const renameMap: Array<{ oldLabel: string; newLabel: string }> = []
      newConfig.leadStages.forEach((ns) => {
        const prev = oldStages.find((os) => os.id === ns.id)
        if (prev && prev.label !== ns.label) {
          renameMap.push({ oldLabel: prev.label, newLabel: ns.label })
        }
      })

      // Atualiza o registro de settings usando o updateItem existente do useLegalStore
      const currentSettings = legal.state.settings as any
      const settingsId = currentSettings?.id || 'default'
      const payload = {
        leadOrigins: newConfig.leadOrigins,
        leadStages: newConfig.leadStages,
        leadInteractionTypes: newConfig.leadInteractionTypes,
        leadAreas: newConfig.leadAreas,
        leadSubjects: newConfig.leadSubjects,
      }

      await legal.updateItem('settings', settingsId, payload)

      // Propaga renomeações de etapas aos leads existentes
      for (const { oldLabel, newLabel } of renameMap) {
        await batchRenameStage(oldLabel, newLabel)
      }

      toast({
        title: 'Listas atualizadas',
        description: 'As alterações nas listas de leads foram salvas com sucesso.',
      })
      return true
    } catch (err: any) {
      console.warn('Erro ao salvar listas de leads:', err)
      toast({
        title: 'Erro ao salvar listas',
        description: String(err?.message || 'Tente novamente.'),
        variant: 'destructive',
      })
      return false
    }
  }

  const clients = (legal.state.clients || []) as Array<Record<string, any>>

  return (
    <div className="p-4 md:p-6 space-y-6">
      <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">Leads</h1>
          <p className="text-sm text-muted-foreground">
            Captação e acompanhamento até a contratação. Um lead só vira cliente por conversão
            manual e confirmada.
          </p>
        </div>
        <div className="flex items-center gap-2">
          {isAdmin && (
            <Button
              variant="outline"
              onClick={() => setSettingsOpen(true)}
              title="Configurar listas de origem, etapa, área, assunto e interação"
            >
              <SettingsIcon className="h-4 w-4 mr-2" /> Configurar listas
            </Button>
          )}
          <Button onClick={openNew}>
            <UserPlus className="h-4 w-4 mr-2" /> Novo lead
          </Button>
        </div>
      </div>

      <Tabs value={tab} onValueChange={setTab}>
        <TabsList>
          <TabsTrigger value="painel">Painel</TabsTrigger>
          <TabsTrigger value="funil">Funil</TabsTrigger>
        </TabsList>

        {/* ---------------- PAINEL ---------------- */}
        <TabsContent value="painel" className="space-y-4">
          {/* Filtros de período */}
          <Card>
            <CardContent className="pt-4 flex flex-wrap items-end gap-3">
              <div className="space-y-1">
                <Label className="text-xs">Entrada de</Label>
                <Input type="date" value={fromDate} onChange={(e) => setFromDate(e.target.value)} />
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Entrada até</Label>
                <Input type="date" value={toDate} onChange={(e) => setToDate(e.target.value)} />
              </div>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => {
                  setFromDate('')
                  setToDate('')
                }}
              >
                Limpar período
              </Button>
            </CardContent>
          </Card>

          {/* Indicadores */}
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {[
              { label: 'Novos leads', value: metrics.novos, icon: UserPlus, cls: 'text-sky-600' },
              {
                label: 'Aguardando contato',
                value: metrics.aguardando,
                icon: Clock,
                cls: 'text-slate-600',
              },
              {
                label: 'Em atendimento',
                value: metrics.atendimento,
                icon: PhoneCall,
                cls: 'text-blue-600',
              },
              {
                label: 'Qualificados',
                value: metrics.qualificados,
                icon: TrendingUp,
                cls: 'text-indigo-600',
              },
              {
                label: 'Propostas enviadas',
                value: metrics.propostas,
                icon: FileQuestion,
                cls: 'text-amber-600',
              },
              {
                label: 'Convertidos',
                value: metrics.convertidos,
                icon: CheckCircle2,
                cls: 'text-emerald-600',
              },
              {
                label: 'Perdidos/descartados',
                value: metrics.perdidos,
                icon: AlertTriangle,
                cls: 'text-rose-600',
              },
              {
                label: 'Retornos pendentes',
                value: metrics.pendentesRetorno,
                icon: CalendarClock,
                cls: 'text-orange-600',
              },
              {
                label: 'Taxa de conversão',
                value: `${metrics.taxa}%`,
                icon: Percent,
                cls: 'text-emerald-700',
              },
              {
                label: 'Tempo até 1º atendimento',
                value:
                  metrics.tempoPrimeiroAtendimento != null
                    ? `${metrics.tempoPrimeiroAtendimento} dias`
                    : '—',
                icon: Clock,
                cls: 'text-slate-700',
              },
            ].map((m) => (
              <Card key={m.label}>
                <CardContent className="pt-4 flex items-center gap-3">
                  <m.icon className={`h-5 w-5 ${m.cls}`} />
                  <div>
                    <div className="text-2xl font-bold leading-none">{m.value}</div>
                    <div className="text-xs text-muted-foreground">{m.label}</div>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>

          {/* Marketing */}
          <div className="grid gap-3 lg:grid-cols-3">
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-sm">Leads por origem</CardTitle>
              </CardHeader>
              <CardContent className="space-y-1 text-sm">
                {metrics.originRows.length === 0 && (
                  <div className="text-muted-foreground">Sem dados no período.</div>
                )}
                {metrics.originRows.map((r) => (
                  <div key={r.origin} className="flex items-center justify-between">
                    <span>{r.origin}</span>
                    <span className="text-muted-foreground">
                      {r.total} · {r.taxa}% conv.
                    </span>
                  </div>
                ))}
              </CardContent>
            </Card>
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-sm">Por campanha</CardTitle>
              </CardHeader>
              <CardContent className="space-y-1 text-sm">
                {metrics.campaignRows.length === 0 && (
                  <div className="text-muted-foreground">Nenhuma campanha informada.</div>
                )}
                {metrics.campaignRows.slice(0, 8).map((r) => (
                  <div key={r.campaign} className="flex items-center justify-between">
                    <span className="truncate max-w-[220px]">{r.campaign}</span>
                    <span className="text-muted-foreground">{r.total}</span>
                  </div>
                ))}
              </CardContent>
            </Card>
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-sm">Principais motivos de perda</CardTitle>
              </CardHeader>
              <CardContent className="space-y-1 text-sm">
                {metrics.lostRows.length === 0 && (
                  <div className="text-muted-foreground">Sem perdas no período.</div>
                )}
                {metrics.lostRows.slice(0, 8).map((r) => (
                  <div key={r.motivo} className="flex items-center justify-between">
                    <span className="truncate max-w-[220px]">{r.motivo}</span>
                    <span className="text-muted-foreground">{r.total}</span>
                  </div>
                ))}
              </CardContent>
            </Card>
          </div>

          {/* Alertas */}
          <div className="space-y-2">
            <h3 className="text-sm font-semibold flex items-center gap-2">
              <BellRing className="h-4 w-4" /> Alertas de acompanhamento
            </h3>
            {alerts.length === 0 ? (
              <div className="text-sm text-muted-foreground">Nenhum alerta no momento. 🎉</div>
            ) : (
              <div className="grid gap-2 md:grid-cols-2">
                {alerts.slice(0, 20).map((a) => (
                  <Alert
                    key={a.key}
                    className={
                      a.tone === 'destructive'
                        ? 'border-rose-200 bg-rose-50'
                        : a.tone === 'warning'
                          ? 'border-amber-200 bg-amber-50'
                          : 'border-sky-200 bg-sky-50'
                    }
                  >
                    <AlertTriangle className="h-4 w-4" />
                    <AlertTitle className="text-sm">{a.title}</AlertTitle>
                    <AlertDescription className="text-xs flex items-center justify-between gap-2">
                      <span>{a.desc}</span>
                      <Button size="sm" variant="outline" onClick={() => openDetail(a.lead)}>
                        Abrir
                      </Button>
                    </AlertDescription>
                  </Alert>
                ))}
              </div>
            )}
          </div>
        </TabsContent>

        {/* ---------------- FUNIL ---------------- */}
        <TabsContent value="funil" className="space-y-4">
          {/* Busca e filtros */}
          <Card>
            <CardContent className="pt-4 grid gap-3 md:grid-cols-3 lg:grid-cols-5">
              <div className="relative md:col-span-2 lg:col-span-2">
                <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
                <Input
                  className="pl-8"
                  placeholder="Buscar por nome, telefone, e-mail, assunto..."
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                />
              </div>
              <Select value={fStage} onValueChange={setFStage}>
                <SelectTrigger>
                  <SelectValue placeholder="Etapa" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="todos">Todas as etapas</SelectItem>
                  {(() => {
                    const allStages = [
                      ...configuredStages,
                      ...leads
                        .map((l) => l.stage)
                        .filter((s) => s && !configuredStages.includes(s)),
                    ]
                    return allStages.map((s) => (
                      <SelectItem key={s} value={s}>
                        {s}
                      </SelectItem>
                    ))
                  })()}
                </SelectContent>
              </Select>
              <Select value={fOrigin} onValueChange={setFOrigin}>
                <SelectTrigger>
                  <SelectValue placeholder="Origem" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="todas">Todas as origens</SelectItem>
                  {(() => {
                    const uniqueOrigins = [
                      ...configuredOrigins,
                      ...leads
                        .map((l) => l.origin)
                        .filter((o): o is string => !!o && !configuredOrigins.includes(o)),
                    ]
                    return uniqueOrigins.map((o) => (
                      <SelectItem key={o} value={o}>
                        {o}
                      </SelectItem>
                    ))
                  })()}
                </SelectContent>
              </Select>
              <Select value={fArea} onValueChange={setFArea}>
                <SelectTrigger>
                  <SelectValue placeholder="Área" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="todas">Todas as áreas</SelectItem>
                  {(() => {
                    const uniqueAreas = [
                      ...configuredAreas,
                      ...leads
                        .map((l) => l.area)
                        .filter((a): a is string => !!a && !configuredAreas.includes(a)),
                    ]
                    return uniqueAreas.map((a) => (
                      <SelectItem key={a} value={a}>
                        {a}
                      </SelectItem>
                    ))
                  })()}
                </SelectContent>
              </Select>
              <Select value={fResponsible} onValueChange={setFResponsible}>
                <SelectTrigger>
                  <SelectValue placeholder="Responsável" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="todos">Todos os responsáveis</SelectItem>
                  {users.map((u) => (
                    <SelectItem key={u.id} value={u.id}>
                      {u.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Select value={fPriority} onValueChange={setFPriority}>
                <SelectTrigger>
                  <SelectValue placeholder="Prioridade" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="todas">Toda prioridade</SelectItem>
                  {['Urgente', 'Alta', 'Média', 'Baixa'].map((p) => (
                    <SelectItem key={p} value={p}>
                      {p}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <div className="space-y-1">
                <Label className="text-xs">Entrada de</Label>
                <Input type="date" value={fromDate} onChange={(e) => setFromDate(e.target.value)} />
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Entrada até</Label>
                <Input type="date" value={toDate} onChange={(e) => setToDate(e.target.value)} />
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Próximo contato</Label>
                <Input
                  type="date"
                  value={nextContactDate}
                  onChange={(e) => setNextContactDate(e.target.value)}
                />
              </div>
            </CardContent>
          </Card>

          <div className="flex items-center justify-between">
            <div className="text-sm text-muted-foreground">
              {filtered.length} lead(s) encontrado(s)
            </div>
            <div className="flex gap-1">
              <Button
                size="sm"
                variant={view === 'lista' ? 'default' : 'outline'}
                onClick={() => setView('lista')}
              >
                <List className="h-4 w-4 mr-1" /> Lista
              </Button>
              <Button
                size="sm"
                variant={view === 'kanban' ? 'default' : 'outline'}
                onClick={() => setView('kanban')}
              >
                <LayoutGrid className="h-4 w-4 mr-1" /> Kanban
              </Button>
            </div>
          </div>

          {isLoading && (
            <div className="grid gap-2">
              {[1, 2, 3].map((i) => (
                <Skeleton key={i} className="h-14 w-full" />
              ))}
            </div>
          )}

          {!isLoading && view === 'lista' && (
            <div className="space-y-2">
              {paged.length === 0 && (
                <div className="text-sm text-muted-foreground">Nenhum lead encontrado.</div>
              )}
              {paged.map((l) => (
                <Card key={l.id} className="hover:bg-slate-50 transition-colors">
                  <CardContent className="py-3 flex flex-wrap items-center gap-3">
                    <button
                      className="text-left flex-1 min-w-[200px]"
                      onClick={() => openDetail(l)}
                    >
                      <div className="font-medium">{l.name}</div>
                      <div className="text-xs text-muted-foreground">
                        {[l.phone && formatPhone(l.phone), l.email].filter(Boolean).join(' · ') ||
                          'sem contato'}
                        {l.area ? ` · ${l.area}` : ''}
                        {l.subject ? ` — ${l.subject}` : ''}
                      </div>
                    </button>
                    <Badge className={stageBadgeClass(l.stage)}>{l.stage}</Badge>
                    {l.priority && l.priority !== 'Média' && (
                      <Badge
                        variant="outline"
                        className={l.priority === 'Urgente' ? 'border-rose-300 text-rose-700' : ''}
                      >
                        {l.priority}
                      </Badge>
                    )}
                    <div className="text-xs text-muted-foreground w-32">
                      {l.nextContactAt ? `Retorno: ${formatSafeLocalDate(l.nextContactAt)}` : ''}
                    </div>
                    <div className="text-xs text-muted-foreground w-24">
                      {userName(l.responsibleId)}
                    </div>
                    <div className="flex gap-1">
                      <Button size="sm" variant="outline" onClick={() => openDetail(l)}>
                        Ficha
                      </Button>
                      {(l.stage === 'Qualificado' || l.stage === 'Proposta enviada') &&
                        !l.convertedClientId && (
                          <Button
                            size="sm"
                            className="bg-emerald-600 hover:bg-emerald-700"
                            onClick={() => openConvert(l)}
                          >
                            Converter
                          </Button>
                        )}
                    </div>
                  </CardContent>
                </Card>
              ))}
              {totalPages > 1 && (
                <div className="flex items-center justify-center gap-2 pt-2">
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={page <= 1}
                    onClick={() => setPage(page - 1)}
                  >
                    Anterior
                  </Button>
                  <span className="text-sm">
                    Página {page} de {totalPages}
                  </span>
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={page >= totalPages}
                    onClick={() => setPage(page + 1)}
                  >
                    Próxima
                  </Button>
                </div>
              )}
            </div>
          )}

          {!isLoading && view === 'kanban' && (
            <div className="overflow-x-auto pb-2">
              <div className="flex gap-3 min-w-max">
                {configuredStages.map((stage) => {
                  const cols = filtered.filter((l) => l.stage === stage)
                  return (
                    <div key={stage} className="w-72 shrink-0">
                      <div className="flex items-center justify-between mb-2 px-1">
                        <span className="text-sm font-semibold">{stage}</span>
                        <Badge variant="secondary">{cols.length}</Badge>
                      </div>
                      <div className="rounded-lg bg-slate-100 p-2 space-y-2 min-h-[120px]">
                        {cols.length === 0 && (
                          <div className="text-xs text-muted-foreground text-center py-4">
                            Vazio
                          </div>
                        )}
                        {cols.map((l) => (
                          <div
                            key={l.id}
                            className="rounded-md bg-white border p-2 shadow-sm cursor-pointer hover:shadow"
                            onClick={() => openDetail(l)}
                          >
                            <div className="text-sm font-medium">{l.name}</div>
                            <div className="text-xs text-muted-foreground truncate">
                              {l.phone ? formatPhone(l.phone) : l.email || ''}
                            </div>
                            <div className="flex flex-wrap gap-1 mt-1">
                              {l.priority && l.priority !== 'Média' && (
                                <Badge variant="outline" className="text-[10px] px-1 py-0">
                                  {l.priority}
                                </Badge>
                              )}
                              {l.origin && (
                                <Badge variant="secondary" className="text-[10px] px-1 py-0">
                                  {l.origin}
                                </Badge>
                              )}
                            </div>
                            <Select
                              value={l.stage}
                              onValueChange={(v) => changeStage(l.id, v)}
                              disabled={!!l.convertedClientId}
                            >
                              <SelectTrigger className="mt-2 h-7 text-xs">
                                <SelectValue />
                              </SelectTrigger>
                              <SelectContent>
                                {(() => {
                                  const allSelectStages =
                                    l.stage && !configuredStages.includes(l.stage)
                                      ? [l.stage, ...configuredStages]
                                      : configuredStages
                                  return allSelectStages.map((s) => (
                                    <SelectItem key={s} value={s}>
                                      {s === 'Contratado' ? 'Contratado (via conversão)' : s}
                                    </SelectItem>
                                  ))
                                })()}
                              </SelectContent>
                            </Select>
                          </div>
                        ))}
                      </div>
                    </div>
                  )
                })}
              </div>
            </div>
          )}
        </TabsContent>
      </Tabs>

      {/* Diálogos */}
      <LeadDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        lead={editingLead}
        users={users}
        leadAreas={configuredAreas}
        leadSubjects={configuredSubjects}
        leadOrigins={configuredOrigins}
        leadStages={configuredStages}
        onSave={handleSave}
        onCheckDuplicates={checkLeadDuplicates}
      />
      <LeadDetailSheet
        open={detailOpen}
        onOpenChange={setDetailOpen}
        lead={detailLead}
        users={users}
        leadStages={configuredStages}
        leadInteractionTypes={configuredInteractionTypes}
        fetchInteractions={fetchInteractions}
        addInteraction={addInteraction}
        onChangeStage={changeStage}
        onScheduleFollowUp={handleScheduleFollowUp}
        onConvert={openConvert}
        onEdit={(l) => {
          setDetailOpen(false)
          openEdit(l)
        }}
      />
      <ConvertLeadDialog
        open={convertOpen}
        onOpenChange={setConvertOpen}
        lead={convertLeadObj}
        clients={clients}
        onConvert={convertLead}
      />
      <LeadListsSettingsDialog
        open={settingsOpen}
        onOpenChange={setSettingsOpen}
        config={leadListsConfig}
        onSave={handleSaveListsConfig}
      />
    </div>
  )
}
