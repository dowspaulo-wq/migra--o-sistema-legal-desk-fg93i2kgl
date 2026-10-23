import { useState, useMemo } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { Badge } from '@/components/ui/badge'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import {
  Zap,
  Plus,
  Edit2,
  Trash2,
  Info,
  Calendar,
  UserCheck,
  CheckCircle2,
  AlertCircle,
  Clock,
  Lock,
  Sparkles,
  ShieldAlert,
} from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { useToast } from '@/hooks/use-toast'
import { AutomationRule, AutomationTriggerEvent, AutomationDueType } from '@/lib/mockData'

const TRIGGER_LABELS: Record<AutomationTriggerEvent, string> = {
  client_created: 'Cliente cadastrado',
  case_created: 'Processo cadastrado',
  case_status_changed: 'Status do processo alterado',
  task_completed: 'Tarefa concluída',
  document_signed: 'Documento assinado',
}

interface RuleFormData {
  title: string
  taskTitle: string
  taskDescription: string
  triggerEvent: AutomationTriggerEvent
  caseStatusTrigger: string
  caseTypeTrigger: string
  taskTypeTrigger: string
  dueDays: number
  dueType: AutomationDueType
  responsibleId: string // 'default' ou user.id
  taskPriority: 'Baixa' | 'Média' | 'Alta' | 'Urgente'
  taskType: string
  active: boolean
}

interface BuiltinAutomation {
  id: string
  trigger: string
  triggerBadge: string
  triggerColor: string
  action: string
  description: string
  conditions?: string
  effectDetails: {
    taskOrRecord: string
    responsible: string
    dueOrTiming: string
    priorityOrNotes?: string
  }
}

const BUILTIN_AUTOMATIONS: BuiltinAutomation[] = [
  {
    id: 'builtin-client-onboarding',
    trigger: 'Cadastro de novo cliente',
    triggerBadge: 'Cliente cadastrado',
    triggerColor:
      'border-blue-200 text-blue-700 dark:border-blue-800 dark:text-blue-300 bg-blue-50/50 dark:bg-blue-950/30',
    action: 'Disparar Checklist de Onboarding (Tarefas em lote)',
    description:
      'Gera as etapas configuradas em Configurações → Onboarding de Cliente como tarefas do tipo "Onboarding", vinculadas ao cliente cadastrado.',
    conditions:
      'Possui trava inteligente anti-duplicidade: não recria etapas que já existam em aberto para o mesmo cliente.',
    effectDetails: {
      taskOrRecord:
        'Gera até 8 tarefas sequenciais (ex: Cadastrar processos, Coletar documentos, Redigir procuração, etc.)',
      responsible: 'Responsável configurado por etapa ou responsável do cliente',
      dueOrTiming: 'Data de hoje (vencimento imediato para início da esteira)',
      priorityOrNotes: 'Prioridade: Média | 1ª etapa marcada como concluída se novo cliente',
    },
  },
  {
    id: 'builtin-case-routine-tasks',
    trigger: 'Abertura de processo (caso principal)',
    triggerBadge: 'Processo cadastrado',
    triggerColor:
      'border-emerald-200 text-emerald-700 dark:border-emerald-800 dark:text-emerald-300 bg-emerald-50/50 dark:bg-emerald-950/30',
    action: 'Criar tarefas padrão de Redação e Acompanhamento',
    description:
      'Cria automaticamente a tarefa "Redigir Inicial ou Defesa" e a tarefa "Acompanhamento processual" vinculadas ao processo recém-aberto.',
    conditions:
      'Apenas para processos principais (não dispara em subprocessos/recursos vinculados).',
    effectDetails: {
      taskOrRecord:
        '1) "Redigir Inicial ou Defesa" (tipo: Redigir inicial)\n2) "Acompanhamento processual" (tipo: interna e adm)',
      responsible: 'Redigir: Usuário cadastrador | Acompanhamento: Usuário Mestre (Admin)',
      dueOrTiming:
        'Redigir: Próximo dia útil subsequente | Acompanhamento: Dia 25 do mês subsequente',
      priorityOrNotes: 'Prioridade: Baixa | Status: pendente / atualização',
    },
  },
  {
    id: 'builtin-task-completion-review',
    trigger: 'Conclusão de tarefa técnica por colaborador',
    triggerBadge: 'Tarefa concluída',
    triggerColor:
      'border-purple-200 text-purple-700 dark:border-purple-800 dark:text-purple-300 bg-purple-50/50 dark:bg-purple-950/30',
    action: 'Gerar tarefa de "Revisão/protocolo" para o Dr. Douglas',
    description:
      'Quando um colaborador conclui uma tarefa das categorias técnicas, o sistema cria automaticamente uma tarefa de revisão e protocolo sob responsabilidade do Dr. Douglas.',
    conditions:
      'Dispara quando o status muda para "Concluída", o usuário que concluiu é Colaborador, e o tipo da tarefa original é "recorrer", "redigir inicial" ou "petições".',
    effectDetails: {
      taskOrRecord: 'Gera tarefa "Revisão/protocolo" com título "[Cliente] - [Processo]"',
      responsible: 'Dr. Douglas (dowspaulo@gmail.com / Admin)',
      dueOrTiming: 'Data atual (hoje)',
      priorityOrNotes: 'Prioridade: Média | Tipo: Revisão/protocolo',
    },
  },
  {
    id: 'builtin-case-status-date',
    trigger: 'Status do processo alterado para "Concluído"',
    triggerBadge: 'Status do processo',
    triggerColor:
      'border-amber-200 text-amber-700 dark:border-amber-800 dark:text-amber-300 bg-amber-50/50 dark:bg-amber-950/30',
    action: 'Atualizar data de encerramento do processo (updatedAt)',
    description:
      'Preenche e carimba a data de atualização do processo no momento exato em que ele passa para um status de conclusão.',
    conditions: 'Transição de qualquer status não concluído para "Concluído" / "Concluída".',
    effectDetails: {
      taskOrRecord:
        'Atualiza o campo de data de encerramento/atualização (updatedAt) no cadastro do processo',
      responsible: 'Execução automática no sistema',
      dueOrTiming: 'Imediato (data corrente YYYY-MM-DD)',
    },
  },
  {
    id: 'builtin-task-audit-completed-by',
    trigger: 'Marcação de tarefa como concluída ou reaberta',
    triggerBadge: 'Status da tarefa',
    triggerColor:
      'border-slate-300 text-slate-700 dark:border-slate-700 dark:text-slate-300 bg-slate-50/50 dark:bg-slate-900/30',
    action: 'Auditoria de conclusão (completed_by)',
    description:
      'Grava o ID do usuário que concluiu a tarefa para prestação de contas da equipe; caso a tarefa seja reaberta, o registro é limpo automaticamente.',
    conditions: 'Transição entre status aberto e status "Concluída" / "Concluído".',
    effectDetails: {
      taskOrRecord:
        'Preenche campo completed_by com o ID do usuário logado; ao reabrir, define como NULL',
      responsible: 'Usuário autenticado ativo',
      dueOrTiming: 'Imediato',
    },
  },
  {
    id: 'builtin-holiday-recurrence',
    trigger: 'Cadastro ou edição de compromisso do tipo "Feriado"',
    triggerBadge: 'Agenda / Feriado',
    triggerColor:
      'border-rose-200 text-rose-700 dark:border-rose-800 dark:text-rose-300 bg-rose-50/50 dark:bg-rose-950/30',
    action: 'Projeção automática para os próximos 5 anos',
    description:
      'Replica automaticamente o feriado nos anos seguintes mantendo a data do calendário e tratando anos bissextos.',
    conditions: 'Compromisso com tipo definido como "Feriado".',
    effectDetails: {
      taskOrRecord: 'Cria 5 registros futuros na agenda com prioridade Baixa',
      responsible: 'Responsável do compromisso original',
      dueOrTiming:
        'Mesmo dia e mês nos próximos 5 anos (trata 29/fev para 28/fev em não bissextos)',
    },
  },
  {
    id: 'builtin-case-financial-fees',
    trigger: 'Abertura de processo com honorários contratuais parcelados',
    triggerBadge: 'Processo / Financeiro',
    triggerColor:
      'border-emerald-200 text-emerald-700 dark:border-emerald-800 dark:text-emerald-300 bg-emerald-50/50 dark:bg-emerald-950/30',
    action: 'Geração automática das parcelas a receber no Financeiro',
    description:
      'Se o processo tiver honorários configurados e não for marcado como "noFees", gera lançamentos de receita futura em série unificada (recurring_id).',
    conditions:
      'Processo com feeConfig.hasFees ativo e tipo financeiro (não se aplica a honorários não financeiros).',
    effectDetails: {
      taskOrRecord:
        'Gera N lançamentos no financeiro (tipo income, categoria Honorários Contratuais, status Previsto)',
      responsible: 'Escritório / Conta bancária selecionada',
      dueOrTiming: 'Parcelamento mensal a partir da primeira data de vencimento informada',
      priorityOrNotes: 'Vinculado com recurring_id para edição em lote quando necessário',
    },
  },
]

const DEFAULT_FORM: RuleFormData = {
  title: '',
  taskTitle: '',
  taskDescription: '',
  triggerEvent: 'case_created',
  caseStatusTrigger: '',
  caseTypeTrigger: '',
  taskTypeTrigger: '',
  dueDays: 3,
  dueType: 'calendar_days',
  responsibleId: 'default',
  taskPriority: 'Média',
  taskType: 'Petições',
  active: true,
}

export function AutomationSettingsTab() {
  const { state, updateItem } = useLegalStore()
  const { toast } = useToast()

  const [isDialogOpen, setIsDialogOpen] = useState(false)
  const [editingRuleId, setEditingRuleId] = useState<string | null>(null)
  const [formData, setFormData] = useState<RuleFormData>(DEFAULT_FORM)
  const [isSaving, setIsSaving] = useState(false)

  // Lista de regras garantindo que null/undefined seja tratado como []
  const rules = useMemo(() => {
    return Array.isArray(state.settings?.automationRules) ? state.settings.automationRules : []
  }, [state.settings?.automationRules])

  const users = state.users.filter((u) => u.is_active !== false)
  const caseStatuses = state.settings.caseStatuses || []
  const caseTypes = state.settings.caseTypes || []
  const taskTypes = state.settings.taskTypes || [
    'Cartórios',
    'Petições',
    'Recorrer',
    'Redigir inicial',
    'interna e adm',
  ]

  const handleOpenCreate = () => {
    setEditingRuleId(null)
    setFormData(DEFAULT_FORM)
    setIsDialogOpen(true)
  }

  const handleOpenEdit = (rule: AutomationRule) => {
    setEditingRuleId(rule.id)
    setFormData({
      title: rule.title || '',
      taskTitle: rule.taskTitle || '',
      taskDescription: rule.taskDescription || '',
      triggerEvent: rule.triggerEvent || 'case_created',
      caseStatusTrigger: rule.caseStatusTrigger || '',
      caseTypeTrigger: rule.caseTypeTrigger || '',
      taskTypeTrigger: rule.taskTypeTrigger || '',
      dueDays: Number(rule.dueDays) || 1,
      dueType: rule.dueType || 'calendar_days',
      responsibleId: rule.responsibleId || 'default',
      taskPriority: rule.taskPriority || 'Média',
      taskType: rule.taskType || 'Petições',
      active: rule.active !== false,
    })
    setIsDialogOpen(true)
  }

  const handleSaveRule = async () => {
    if (!formData.title.trim()) {
      toast({
        title: 'Nome obrigatório',
        description: 'Informe um nome descritivo para a regra de automação.',
        variant: 'destructive',
      })
      return
    }

    if (!formData.taskTitle.trim()) {
      toast({
        title: 'Título da tarefa obrigatório',
        description: 'Informe o título da tarefa que será gerada pela regra.',
        variant: 'destructive',
      })
      return
    }

    setIsSaving(true)
    try {
      const nowIso = new Date().toISOString()
      const rulePayload: AutomationRule = {
        id: editingRuleId || `rule-${Date.now()}-${Math.random().toString(36).substr(2, 6)}`,
        title: formData.title.trim(),
        taskTitle: formData.taskTitle.trim(),
        taskDescription: formData.taskDescription.trim() || undefined,
        triggerEvent: formData.triggerEvent,
        caseStatusTrigger:
          formData.triggerEvent === 'case_status_changed' && formData.caseStatusTrigger.trim()
            ? formData.caseStatusTrigger.trim()
            : undefined,
        caseTypeTrigger: formData.caseTypeTrigger.trim() || undefined,
        taskTypeTrigger:
          formData.triggerEvent === 'task_completed' && formData.taskTypeTrigger.trim()
            ? formData.taskTypeTrigger.trim()
            : undefined,
        dueDays: Math.max(0, Number(formData.dueDays) || 0),
        dueType: formData.dueType,
        responsibleId: formData.responsibleId === 'default' ? null : formData.responsibleId,
        taskPriority: formData.taskPriority,
        taskType: formData.taskType.trim() || 'Automação',
        active: formData.active,
        updatedAt: nowIso,
        createdAt: editingRuleId
          ? rules.find((r) => r.id === editingRuleId)?.createdAt || nowIso
          : nowIso,
      }

      let updatedRules: AutomationRule[] = []
      if (editingRuleId) {
        updatedRules = rules.map((r) => (r.id === editingRuleId ? rulePayload : r))
      } else {
        updatedRules = [rulePayload, ...rules]
      }

      await updateItem('settings', state.settings.id, {
        automationRules: updatedRules,
      })

      toast({
        title: editingRuleId ? 'Regra atualizada' : 'Regra criada',
        description: `A regra "${rulePayload.title}" foi salva com sucesso.`,
      })
      setIsDialogOpen(false)
    } catch (err: any) {
      console.error('Erro ao salvar regra de automação:', err)
      toast({
        title: 'Erro ao salvar',
        description: err?.message || 'Falha ao gravar a regra de automação.',
        variant: 'destructive',
      })
    } finally {
      setIsSaving(false)
    }
  }

  const handleToggleActive = async (ruleId: string, currentActive: boolean) => {
    try {
      const updatedRules = rules.map((r) =>
        r.id === ruleId ? { ...r, active: !currentActive, updatedAt: new Date().toISOString() } : r,
      )
      await updateItem('settings', state.settings.id, {
        automationRules: updatedRules,
      })
      toast({
        title: !currentActive ? 'Regra ativada' : 'Regra desativada',
        description: 'Status da regra atualizado com sucesso.',
      })
    } catch (err: any) {
      console.error('Erro ao alternar status da regra:', err)
      toast({
        title: 'Erro',
        description: err?.message || 'Falha ao atualizar regra.',
        variant: 'destructive',
      })
    }
  }

  const handleDeleteRule = async (rule: AutomationRule) => {
    if (!window.confirm(`Deseja realmente excluir a regra "${rule.title}"?`)) {
      return
    }
    try {
      const updatedRules = rules.filter((r) => r.id !== rule.id)
      await updateItem('settings', state.settings.id, {
        automationRules: updatedRules,
      })
      toast({
        title: 'Regra excluída',
        description: `A regra "${rule.title}" foi removida.`,
      })
    } catch (err: any) {
      console.error('Erro ao excluir regra:', err)
      toast({
        title: 'Erro ao excluir',
        description: err?.message || 'Falha ao remover regra.',
        variant: 'destructive',
      })
    }
  }

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader className="pb-4">
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
            <div>
              <CardTitle className="text-xl flex items-center gap-2 text-slate-800 dark:text-slate-100">
                <Zap className="h-5 w-5 text-amber-500" />
                Regras de Automação
              </CardTitle>
              <CardDescription className="mt-1">
                Crie gatilhos adicionais para geração automática de tarefas com base em eventos do
                sistema.
              </CardDescription>
            </div>
            <Button
              onClick={handleOpenCreate}
              className="bg-amber-600 hover:bg-amber-700 text-white shrink-0"
            >
              <Plus className="h-4 w-4 mr-1.5" /> Nova Regra
            </Button>
          </div>
        </CardHeader>

        <CardContent className="space-y-6">
          {/* Seção: Automações Padrão do Sistema (Somente Leitura) */}
          <div className="space-y-3">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 pb-1 border-b">
              <div className="flex items-center gap-2">
                <Sparkles className="h-4 w-4 text-amber-600 dark:text-amber-400" />
                <h3 className="text-sm font-semibold text-slate-900 dark:text-slate-100">
                  Automações padrão do sistema
                </h3>
                <Badge
                  variant="secondary"
                  className="bg-amber-100 text-amber-900 dark:bg-amber-950/60 dark:text-amber-200 border border-amber-300/60 dark:border-amber-800 text-[11px] font-medium"
                >
                  Padrão do sistema
                </Badge>
              </div>
              <span className="text-xs text-muted-foreground flex items-center gap-1.5 italic">
                <Lock className="h-3.5 w-3.5 text-slate-400 shrink-0" />
                Somente leitura — para alterar uma automação padrão, procure o suporte
              </span>
            </div>

            <div className="grid grid-cols-1 gap-3">
              {BUILTIN_AUTOMATIONS.map((builtin) => (
                <div
                  key={builtin.id}
                  className="rounded-lg border border-slate-200 dark:border-slate-800 bg-slate-50/60 dark:bg-slate-900/40 p-3.5 text-xs sm:text-sm space-y-2 hover:border-slate-300 dark:hover:border-slate-700 transition-colors"
                >
                  <div className="flex flex-col sm:flex-row sm:items-start justify-between gap-2">
                    <div className="space-y-1 flex-1">
                      <div className="flex items-center gap-2 flex-wrap">
                        <Badge
                          variant="outline"
                          className={`text-[10px] sm:text-[11px] font-medium ${builtin.triggerColor}`}
                        >
                          Gatilho: {builtin.triggerBadge}
                        </Badge>
                        <span className="font-semibold text-slate-900 dark:text-slate-100">
                          {builtin.action}
                        </span>
                      </div>
                      <p className="text-xs text-slate-600 dark:text-slate-300 leading-relaxed">
                        {builtin.description}
                      </p>
                      {builtin.conditions && (
                        <p className="text-[11px] text-amber-800 dark:text-amber-300/90 font-medium">
                          Condição: {builtin.conditions}
                        </p>
                      )}
                    </div>
                    <div className="shrink-0 flex items-center gap-1 text-[11px] font-medium text-slate-600 dark:text-slate-300 bg-white dark:bg-slate-800/80 border border-slate-200 dark:border-slate-700 rounded-md px-2.5 py-1 self-start">
                      <Lock className="h-3 w-3 text-slate-400" />
                      Ativa (Padrão)
                    </div>
                  </div>

                  <div className="pt-2 border-t border-slate-200/70 dark:border-slate-800/70 grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2 text-[11px] text-slate-600 dark:text-slate-400">
                    <div>
                      <span className="font-medium text-slate-700 dark:text-slate-300 block">
                        Efeito / Registro:
                      </span>
                      <span className="whitespace-pre-line">
                        {builtin.effectDetails.taskOrRecord}
                      </span>
                    </div>
                    <div>
                      <span className="font-medium text-slate-700 dark:text-slate-300 block">
                        Responsável & Prazo:
                      </span>
                      <span>
                        {builtin.effectDetails.responsible} • {builtin.effectDetails.dueOrTiming}
                      </span>
                    </div>
                    {builtin.effectDetails.priorityOrNotes && (
                      <div>
                        <span className="font-medium text-slate-700 dark:text-slate-300 block">
                          Detalhes adicionais:
                        </span>
                        <span>{builtin.effectDetails.priorityOrNotes}</span>
                      </div>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Divisor com cabeçalho de regras customizadas adicionais */}
          <div className="pt-2 space-y-3">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 pb-1 border-b">
              <div className="flex items-center gap-2">
                <Zap className="h-4 w-4 text-amber-500" />
                <h3 className="text-sm font-semibold text-slate-900 dark:text-slate-100">
                  Regras customizadas adicionais
                </h3>
                <Badge variant="outline" className="text-[11px]">
                  {rules.length} {rules.length === 1 ? 'regra' : 'regras'}
                </Badge>
              </div>
              <span className="text-xs text-muted-foreground">
                Regras personalizadas configuradas pelo escritório
              </span>
            </div>

            {/* Aviso destacado obrigatório sobre coexistência */}
            <div className="flex items-start gap-3 p-3.5 rounded-lg border border-amber-200 bg-amber-50/80 dark:border-amber-900/40 dark:bg-amber-950/20 text-amber-900 dark:text-amber-200 text-xs sm:text-sm">
              <Info className="h-4 w-4 text-amber-600 shrink-0 mt-0.5" />
              <div>
                <p className="font-semibold">
                  As automações padrão do sistema continuam ativas. As regras abaixo são adicionais.
                </p>
                <p className="text-xs text-amber-800 dark:text-amber-300/80 mt-0.5">
                  O checklist de onboarding de cliente novo e as tarefas padrão criadas na abertura
                  de processos não são afetados pelas regras criadas aqui.
                </p>
              </div>
            </div>

            {/* Lista de regras ou estado vazio */}
            {rules.length === 0 ? (
              <div className="text-center py-10 px-4 border border-dashed rounded-lg bg-slate-50/50 dark:bg-slate-900/20">
                <Zap className="h-9 w-9 text-slate-300 dark:text-slate-600 mx-auto mb-2.5" />
                <p className="text-sm font-medium text-slate-700 dark:text-slate-300">
                  Nenhuma regra customizada criada. Crie uma regra para automatizar tarefas
                  adicionais.
                </p>
                <p className="text-xs text-muted-foreground mt-1 max-w-md mx-auto">
                  Exemplo: quando um processo for cadastrado, criar automaticamente a tarefa
                  &ldquo;Solicitar documentos complementares&rdquo; com prazo de 5 dias.
                </p>
                <Button variant="outline" size="sm" onClick={handleOpenCreate} className="mt-4">
                  <Plus className="h-3.5 w-3.5 mr-1" /> Criar primeira regra
                </Button>
              </div>
            ) : (
              <div className="divide-y rounded-lg border bg-card">
                {rules.map((rule) => {
                  const responsibleUser = users.find((u) => u.id === rule.responsibleId)
                  return (
                    <div
                      key={rule.id}
                      className="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-4 hover:bg-slate-50/60 dark:hover:bg-slate-900/40 transition-colors"
                    >
                      <div className="space-y-1.5 flex-1 min-w-0">
                        <div className="flex items-center gap-2 flex-wrap">
                          <span className="font-medium text-sm text-slate-900 dark:text-slate-100">
                            {rule.title}
                          </span>
                          <Badge
                            variant={rule.active ? 'default' : 'secondary'}
                            className={
                              rule.active
                                ? 'bg-green-100 text-green-800 dark:bg-green-950 dark:text-green-300 text-[10px] font-medium'
                                : 'text-[10px]'
                            }
                          >
                            {rule.active ? 'Ativa' : 'Inativa'}
                          </Badge>
                          <Badge
                            variant="outline"
                            className="text-[10px] bg-slate-50 dark:bg-slate-900"
                          >
                            {TRIGGER_LABELS[rule.triggerEvent] || rule.triggerEvent}
                          </Badge>
                          {rule.caseStatusTrigger && (
                            <Badge
                              variant="outline"
                              className="text-[10px] border-amber-200 text-amber-700 dark:text-amber-400"
                            >
                              Status: {rule.caseStatusTrigger}
                            </Badge>
                          )}
                          {rule.caseTypeTrigger && (
                            <Badge
                              variant="outline"
                              className="text-[10px] border-blue-200 text-blue-700 dark:text-blue-400"
                            >
                              Tipo: {rule.caseTypeTrigger}
                            </Badge>
                          )}
                          {rule.taskTypeTrigger && (
                            <Badge
                              variant="outline"
                              className="text-[10px] border-purple-200 text-purple-700 dark:text-purple-400"
                            >
                              Tipo tarefa: {rule.taskTypeTrigger}
                            </Badge>
                          )}
                        </div>

                        <div className="text-xs text-muted-foreground flex items-center gap-3 flex-wrap">
                          <span className="flex items-center gap-1 font-medium text-slate-700 dark:text-slate-300">
                            <CheckCircle2 className="h-3.5 w-3.5 text-blue-500" />
                            Gera: &ldquo;{rule.taskTitle}&rdquo;
                          </span>
                          <span className="flex items-center gap-1">
                            <Clock className="h-3 w-3" />
                            Prazo: {rule.dueDays}{' '}
                            {rule.dueType === 'business_days' ? 'dias úteis' : 'dias corridos'}
                          </span>
                          <span className="flex items-center gap-1">
                            <UserCheck className="h-3 w-3" />
                            {responsibleUser ? responsibleUser.name : 'Responsável do registro'}
                          </span>
                          <span className="text-[11px] text-slate-500">
                            Prioridade: {rule.taskPriority || 'Média'}
                          </span>
                        </div>
                      </div>

                      <div className="flex items-center gap-3 shrink-0 self-end sm:self-center">
                        <div className="flex items-center gap-2">
                          <span className="text-xs text-muted-foreground hidden sm:inline">
                            {rule.active ? 'Ativa' : 'Inativa'}
                          </span>
                          <Switch
                            checked={rule.active}
                            onCheckedChange={() => handleToggleActive(rule.id, rule.active)}
                            title="Ativar/desativar regra"
                          />
                        </div>
                        <div className="flex items-center gap-1 border-l pl-2">
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-8 w-8 text-slate-500 hover:text-slate-900"
                            onClick={() => handleOpenEdit(rule)}
                            title="Editar regra"
                          >
                            <Edit2 className="h-3.5 w-3.5" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-8 w-8 text-red-500 hover:text-red-700 hover:bg-red-50"
                            onClick={() => handleDeleteRule(rule)}
                            title="Excluir regra"
                          >
                            <Trash2 className="h-3.5 w-3.5" />
                          </Button>
                        </div>
                      </div>
                    </div>
                  )
                })}
              </div>
            )}
          </div>
        </CardContent>
      </Card>

      {/* Diálogo de Criação/Edição */}
      <Dialog open={isDialogOpen} onOpenChange={setIsDialogOpen}>
        <DialogContent className="max-w-xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Zap className="h-5 w-5 text-amber-500" />
              {editingRuleId ? 'Editar Regra de Automação' : 'Nova Regra de Automação'}
            </DialogTitle>
            <DialogDescription>
              Configure o gatilho, as condições e a tarefa que será gerada automaticamente.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4 py-2">
            <div className="space-y-1.5">
              <Label htmlFor="rule-title" className="text-xs font-semibold">
                Nome da Regra <span className="text-red-500">*</span>
              </Label>
              <Input
                id="rule-title"
                value={formData.title}
                onChange={(e) => setFormData((prev) => ({ ...prev, title: e.target.value }))}
                placeholder="Ex: Tarefa inicial para processo previdenciário"
              />
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label className="text-xs font-semibold">Evento Gatilho</Label>
                <Select
                  value={formData.triggerEvent}
                  onValueChange={(val: AutomationTriggerEvent) =>
                    setFormData((prev) => ({ ...prev, triggerEvent: val }))
                  }
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="case_created">Processo cadastrado</SelectItem>
                    <SelectItem value="case_status_changed">Status do processo alterado</SelectItem>
                    <SelectItem value="client_created">Cliente cadastrado</SelectItem>
                    <SelectItem value="task_completed">Tarefa concluída</SelectItem>
                    <SelectItem value="document_signed">Documento assinado</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              {formData.triggerEvent === 'case_status_changed' && (
                <div className="space-y-1.5">
                  <Label className="text-xs font-semibold">Status de Destino do Processo</Label>
                  <Select
                    value={formData.caseStatusTrigger || 'any'}
                    onValueChange={(val) =>
                      setFormData((prev) => ({
                        ...prev,
                        caseStatusTrigger: val === 'any' ? '' : val,
                      }))
                    }
                  >
                    <SelectTrigger>
                      <SelectValue placeholder="Selecione o status" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="any">Qualquer status</SelectItem>
                      {caseStatuses.map((st: any) => {
                        const lbl = typeof st === 'string' ? st : st.label
                        return (
                          <SelectItem key={lbl} value={lbl}>
                            {lbl}
                          </SelectItem>
                        )
                      })}
                    </SelectContent>
                  </Select>
                </div>
              )}

              {formData.triggerEvent === 'task_completed' && (
                <div className="space-y-1.5">
                  <Label className="text-xs font-semibold">
                    Tipo da Tarefa Concluída (Opcional)
                  </Label>
                  <Select
                    value={formData.taskTypeTrigger || 'any'}
                    onValueChange={(val) =>
                      setFormData((prev) => ({
                        ...prev,
                        taskTypeTrigger: val === 'any' ? '' : val,
                      }))
                    }
                  >
                    <SelectTrigger>
                      <SelectValue placeholder="Qualquer tipo" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="any">Qualquer tipo de tarefa</SelectItem>
                      {taskTypes.map((t) => (
                        <SelectItem key={t} value={t}>
                          {t}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              )}

              {(formData.triggerEvent === 'case_created' ||
                formData.triggerEvent === 'case_status_changed') && (
                <div className="space-y-1.5">
                  <Label className="text-xs font-semibold">
                    Filtro por Tipo de Processo (Opcional)
                  </Label>
                  <Select
                    value={formData.caseTypeTrigger || 'any'}
                    onValueChange={(val) =>
                      setFormData((prev) => ({
                        ...prev,
                        caseTypeTrigger: val === 'any' ? '' : val,
                      }))
                    }
                  >
                    <SelectTrigger>
                      <SelectValue placeholder="Qualquer tipo de processo" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="any">Qualquer tipo de processo</SelectItem>
                      {caseTypes.map((ct: any) => {
                        const lbl = typeof ct === 'string' ? ct : ct.label
                        return (
                          <SelectItem key={lbl} value={lbl}>
                            {lbl}
                          </SelectItem>
                        )
                      })}
                    </SelectContent>
                  </Select>
                </div>
              )}
            </div>

            <div className="border-t pt-3 space-y-3">
              <div className="text-xs font-semibold text-slate-700 dark:text-slate-300 uppercase tracking-wider flex items-center gap-1.5">
                <CheckCircle2 className="h-3.5 w-3.5 text-blue-500" />
                Ação: Criar Tarefa
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="task-title" className="text-xs font-semibold">
                  Título da Tarefa <span className="text-red-500">*</span>
                </Label>
                <Input
                  id="task-title"
                  value={formData.taskTitle}
                  onChange={(e) => setFormData((prev) => ({ ...prev, taskTitle: e.target.value }))}
                  placeholder="Ex: Coletar extrato CNIS do cliente"
                />
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="task-desc" className="text-xs font-semibold">
                  Descrição da Tarefa (Opcional)
                </Label>
                <Input
                  id="task-desc"
                  value={formData.taskDescription}
                  onChange={(e) =>
                    setFormData((prev) => ({ ...prev, taskDescription: e.target.value }))
                  }
                  placeholder="Instruções ou orientações para a execução da tarefa"
                />
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div className="space-y-1.5">
                  <Label className="text-xs font-semibold">Tipo da Tarefa</Label>
                  <Select
                    value={formData.taskType}
                    onValueChange={(val) => setFormData((prev) => ({ ...prev, taskType: val }))}
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {taskTypes.map((t) => (
                        <SelectItem key={t} value={t}>
                          {t}
                        </SelectItem>
                      ))}
                      <SelectItem value="Automação">Automação</SelectItem>
                    </SelectContent>
                  </Select>
                </div>

                <div className="space-y-1.5">
                  <Label className="text-xs font-semibold">Prioridade</Label>
                  <Select
                    value={formData.taskPriority}
                    onValueChange={(val: any) =>
                      setFormData((prev) => ({ ...prev, taskPriority: val }))
                    }
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Baixa">Baixa</SelectItem>
                      <SelectItem value="Média">Média</SelectItem>
                      <SelectItem value="Alta">Alta</SelectItem>
                      <SelectItem value="Urgente">Urgente</SelectItem>
                    </SelectContent>
                  </Select>
                </div>

                <div className="space-y-1.5">
                  <Label className="text-xs font-semibold">Prazo em Dias</Label>
                  <div className="flex items-center gap-2">
                    <Input
                      type="number"
                      min={0}
                      max={365}
                      value={formData.dueDays}
                      onChange={(e) =>
                        setFormData((prev) => ({
                          ...prev,
                          dueDays: Math.max(0, parseInt(e.target.value, 10) || 0),
                        }))
                      }
                      className="w-24"
                    />
                    <Select
                      value={formData.dueType}
                      onValueChange={(val: AutomationDueType) =>
                        setFormData((prev) => ({ ...prev, dueType: val }))
                      }
                    >
                      <SelectTrigger className="flex-1">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="calendar_days">Dias corridos</SelectItem>
                        <SelectItem value="business_days">Dias úteis</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                </div>

                <div className="space-y-1.5">
                  <Label className="text-xs font-semibold">Responsável pela Tarefa</Label>
                  <Select
                    value={formData.responsibleId}
                    onValueChange={(val) =>
                      setFormData((prev) => ({ ...prev, responsibleId: val }))
                    }
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="default">
                        <span className="italic text-muted-foreground">
                          Responsável do registro (Cliente / Processo)
                        </span>
                      </SelectItem>
                      {users.map((u) => (
                        <SelectItem key={u.id} value={u.id}>
                          {u.name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              </div>

              <div className="flex items-center justify-between pt-2 border-t">
                <div className="space-y-0.5">
                  <Label className="text-xs font-semibold">Regra Ativa</Label>
                  <p className="text-[11px] text-muted-foreground">
                    Quando desativada, a regra não disparará criação de tarefas.
                  </p>
                </div>
                <Switch
                  checked={formData.active}
                  onCheckedChange={(checked) =>
                    setFormData((prev) => ({ ...prev, active: checked }))
                  }
                />
              </div>
            </div>
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setIsDialogOpen(false)} disabled={isSaving}>
              Cancelar
            </Button>
            <Button
              onClick={handleSaveRule}
              disabled={isSaving}
              className="bg-amber-600 hover:bg-amber-700 text-white"
            >
              {isSaving ? 'Salvando...' : editingRuleId ? 'Salvar Alterações' : 'Criar Regra'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
