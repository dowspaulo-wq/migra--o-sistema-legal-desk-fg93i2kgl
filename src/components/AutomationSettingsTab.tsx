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

        <CardContent className="space-y-5">
          {/* Aviso destacado obrigatório */}
          <div className="flex items-start gap-3 p-3.5 rounded-lg border border-amber-200 bg-amber-50/80 dark:border-amber-900/40 dark:bg-amber-950/20 text-amber-900 dark:text-amber-200 text-xs sm:text-sm">
            <Info className="h-4 w-4 text-amber-600 shrink-0 mt-0.5" />
            <div>
              <p className="font-semibold">
                As automações padrão do sistema continuam ativas. As regras abaixo são adicionais.
              </p>
              <p className="text-xs text-amber-800 dark:text-amber-300/80 mt-0.5">
                O checklist de onboarding de cliente novo e as tarefas padrão criadas na abertura de
                processos não são afetados.
              </p>
            </div>
          </div>

          {/* Lista de regras ou estado vazio */}
          {rules.length === 0 ? (
            <div className="text-center py-12 px-4 border border-dashed rounded-lg bg-slate-50/50 dark:bg-slate-900/20">
              <Zap className="h-10 w-10 text-slate-300 dark:text-slate-600 mx-auto mb-3" />
              <p className="text-sm font-medium text-slate-700 dark:text-slate-300">
                Nenhuma regra criada. Crie uma regra para automatizar tarefas.
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
