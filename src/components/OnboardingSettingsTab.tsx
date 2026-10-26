import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  CheckCircle2,
  Plus,
  Trash2,
  Edit2,
  Check,
  X,
  ArrowUp,
  ArrowDown,
  RotateCcw,
  Sparkles,
  ClipboardList,
  UserCheck,
  Briefcase,
  Users,
} from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import {
  DEFAULT_CLIENT_ONBOARDING_STEPS,
  DEFAULT_CASE_ONBOARDING_STEPS,
  OnboardingStep,
  OnboardingType,
} from '@/lib/mockData'
import { toast } from '@/hooks/use-toast'

interface OnboardingSectionProps {
  type: OnboardingType
  title: string
  subtitle: string
  explanation: string
  steps: OnboardingStep[]
  defaultSteps: OnboardingStep[]
  onSave: (updatedSteps: OnboardingStep[]) => Promise<void>
  users: Array<{ id: string; name: string }>
  isSaving: boolean
  badgeColorClass: string
  accentColorClass: string
}

function OnboardingModelSection({
  type,
  title,
  subtitle,
  explanation,
  steps,
  defaultSteps,
  onSave,
  users,
  isSaving,
  badgeColorClass,
  accentColorClass,
}: OnboardingSectionProps) {
  const [newTitle, setNewTitle] = useState('')
  const [newResponsibleId, setNewResponsibleId] = useState<string>('default')
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editingTitle, setEditingTitle] = useState('')

  const handleAdd = () => {
    const trimmed = newTitle.trim()
    if (!trimmed) return

    if (steps.some((st) => st.title.toLowerCase() === trimmed.toLowerCase())) {
      toast({
        title: 'Etapa já existe',
        description: `Já existe uma etapa com esse título no checklist de ${type}.`,
        variant: 'destructive',
      })
      return
    }

    const newStep: OnboardingStep = {
      id: `step-${type}-${Date.now()}`,
      title: trimmed,
      order: steps.length + 1,
      type,
      responsibleId: newResponsibleId === 'default' ? null : newResponsibleId,
    }

    const next = [...steps, newStep]
    setNewTitle('')
    setNewResponsibleId('default')
    onSave(next)
  }

  const handleStepResponsibleChange = (stepId: string, value: string) => {
    const nextResponsibleId = value === 'default' ? null : value
    const next = steps.map((st) =>
      st.id === stepId ? { ...st, responsibleId: nextResponsibleId } : st,
    )
    onSave(next)
  }

  const handleRemove = (id: string) => {
    if (steps.length <= 1) {
      toast({
        title: 'Atenção',
        description: 'O checklist precisa conter pelo menos 1 etapa.',
        variant: 'destructive',
      })
      return
    }
    const next = steps.filter((st) => st.id !== id)
    onSave(next)
  }

  const handleStartEdit = (step: OnboardingStep) => {
    setEditingId(step.id)
    setEditingTitle(step.title)
  }

  const handleSaveEdit = (id: string) => {
    const trimmed = editingTitle.trim()
    if (!trimmed) return

    const next = steps.map((st) => (st.id === id ? { ...st, title: trimmed } : st))
    setEditingId(null)
    setEditingTitle('')
    onSave(next)
  }

  const handleCancelEdit = () => {
    setEditingId(null)
    setEditingTitle('')
  }

  const handleMove = (index: number, direction: 'up' | 'down') => {
    const targetIndex = direction === 'up' ? index - 1 : index + 1
    if (targetIndex < 0 || targetIndex >= steps.length) return

    const reordered = [...steps]
    const [moved] = reordered.splice(index, 1)
    reordered.splice(targetIndex, 0, moved)
    onSave(reordered)
  }

  const handleReset = () => {
    if (
      confirm(
        `Deseja restaurar as ${defaultSteps.length} etapas padrão do checklist de ${type} sugeridas pelo escritório?`,
      )
    ) {
      onSave(defaultSteps)
    }
  }

  return (
    <Card className="shadow-sm border">
      <CardHeader>
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <CardTitle className="text-xl flex items-center gap-2">
              {type === 'cliente' ? (
                <Users className="h-5 w-5 text-blue-600" />
              ) : (
                <Briefcase className="h-5 w-5 text-indigo-600" />
              )}
              {title}
            </CardTitle>
            <CardDescription className="mt-1">{subtitle}</CardDescription>
          </div>
          <div className="flex items-center gap-2 shrink-0">
            <Badge variant="outline" className={badgeColorClass}>
              {steps.length} {steps.length === 1 ? 'etapa ativa' : 'etapas ativas'}
            </Badge>
            <Button
              variant="outline"
              size="sm"
              onClick={handleReset}
              disabled={isSaving}
              className="text-slate-600 hover:text-slate-900 hover:bg-slate-100"
              title="Restaurar lista padrão sugerida"
            >
              <RotateCcw className="h-3.5 w-3.5 mr-1.5" />
              Restaurar Padrão
            </Button>
          </div>
        </div>
      </CardHeader>
      <CardContent className="space-y-6">
        {/* Caixa explicativa de contexto */}
        <div
          className={`rounded-lg p-4 border text-xs leading-relaxed space-y-2 ${accentColorClass}`}
        >
          <div className="flex items-center gap-2 font-semibold text-sm">
            <Sparkles className="h-4 w-4 shrink-0" />
            Como funciona a rotina de {type === 'cliente' ? 'CLIENTES' : 'PROCESSOS'} no DPSjur:
          </div>
          <p>{explanation}</p>
        </div>

        {/* Campo para adicionar nova etapa */}
        <div className="space-y-2">
          <label className="text-sm font-semibold text-slate-800 dark:text-slate-200">
            Adicionar Nova Etapa ao Modelo ({type === 'cliente' ? 'Cliente' : 'Processo'})
          </label>
          <div className="flex flex-col sm:flex-row gap-2">
            <Input
              value={newTitle}
              onChange={(e) => setNewTitle(e.target.value)}
              placeholder={
                type === 'cliente'
                  ? "Ex.: 'Validar comprovante de residência', 'Coletar biometria'..."
                  : "Ex.: 'Distribuir petição inicial', 'Protocolar no eproc'..."
              }
              className="flex-1"
              disabled={isSaving}
              onKeyDown={(e) => e.key === 'Enter' && handleAdd()}
            />
            <div className="w-full sm:w-56 shrink-0">
              <Select
                value={newResponsibleId}
                onValueChange={setNewResponsibleId}
                disabled={isSaving}
              >
                <SelectTrigger className="h-10 text-xs">
                  <SelectValue placeholder="Colaborador responsável" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="default" className="text-xs">
                    {type === 'cliente'
                      ? 'Padrão (Resp. do Cliente)'
                      : 'Padrão (Resp. do Processo)'}
                  </SelectItem>
                  {users.map((u) => (
                    <SelectItem key={u.id} value={u.id} className="text-xs">
                      {u.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <Button
              onClick={handleAdd}
              disabled={!newTitle.trim() || isSaving}
              className={
                type === 'cliente'
                  ? 'bg-blue-600 hover:bg-blue-700 text-white shrink-0'
                  : 'bg-indigo-600 hover:bg-indigo-700 text-white shrink-0'
              }
            >
              <Plus className="h-4 w-4 mr-1.5" /> Adicionar Etapa
            </Button>
          </div>
        </div>

        {/* Lista de etapas com ordenação, edição e exclusão */}
        <div className="space-y-2.5">
          <div className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
            Ordem das Etapas do Checklist ({steps.length})
          </div>

          <div className="divide-y rounded-lg border bg-card">
            {steps.map((step, index) => {
              const isEditing = editingId === step.id
              return (
                <div
                  key={step.id || `step-${type}-${index}`}
                  className="flex flex-col sm:flex-row sm:items-center justify-between p-3.5 hover:bg-slate-50/80 dark:hover:bg-slate-900/50 transition-colors gap-3"
                >
                  <div className="flex items-center gap-3 flex-1 min-w-0">
                    <span
                      className={`flex items-center justify-center h-6 w-6 rounded-full font-bold text-xs shrink-0 ${
                        type === 'cliente'
                          ? 'bg-blue-100 text-blue-800 dark:bg-blue-950 dark:text-blue-300'
                          : 'bg-indigo-100 text-indigo-800 dark:bg-indigo-950 dark:text-indigo-300'
                      }`}
                    >
                      {index + 1}
                    </span>

                    {isEditing ? (
                      <div className="flex items-center gap-2 flex-1">
                        <Input
                          value={editingTitle}
                          onChange={(e) => setEditingTitle(e.target.value)}
                          className="h-8 text-sm"
                          autoFocus
                          onKeyDown={(e) => {
                            if (e.key === 'Enter') handleSaveEdit(step.id)
                            if (e.key === 'Escape') handleCancelEdit()
                          }}
                        />
                        <Button
                          size="sm"
                          className="h-8 w-8 p-0 bg-green-600 hover:bg-green-700 text-white shrink-0"
                          onClick={() => handleSaveEdit(step.id)}
                          title="Salvar alteração"
                        >
                          <Check className="h-4 w-4" />
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          className="h-8 w-8 p-0 shrink-0"
                          onClick={handleCancelEdit}
                          title="Cancelar"
                        >
                          <X className="h-4 w-4" />
                        </Button>
                      </div>
                    ) : (
                      <div className="flex items-center gap-2 truncate">
                        <CheckCircle2
                          className={`h-4 w-4 shrink-0 ${
                            type === 'cliente' ? 'text-blue-500' : 'text-indigo-500'
                          }`}
                        />
                        <span className="text-sm font-medium text-slate-900 dark:text-slate-100 truncate">
                          {step.title}
                        </span>
                      </div>
                    )}
                  </div>

                  <div className="flex items-center justify-between sm:justify-end gap-2 shrink-0 pl-9 sm:pl-0">
                    <div className="w-48 shrink-0">
                      <Select
                        value={step.responsibleId || 'default'}
                        onValueChange={(val) => handleStepResponsibleChange(step.id, val)}
                        disabled={isSaving}
                      >
                        <SelectTrigger
                          className="h-7 text-xs bg-white dark:bg-slate-950 border-slate-200"
                          title="Colaborador responsável por esta etapa"
                        >
                          <UserCheck className="h-3 w-3 mr-1 text-slate-500 shrink-0" />
                          <SelectValue placeholder="Resp. da Etapa" />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="default" className="text-xs">
                            <span className="text-slate-500 italic">
                              {type === 'cliente'
                                ? 'Padrão (Resp. Cliente)'
                                : 'Padrão (Resp. Processo)'}
                            </span>
                          </SelectItem>
                          {users.map((u) => (
                            <SelectItem key={u.id} value={u.id} className="text-xs">
                              {u.name}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>

                    {!isEditing && (
                      <div className="flex items-center gap-1 shrink-0">
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7 text-slate-500 hover:text-slate-900 disabled:opacity-30"
                          onClick={() => handleMove(index, 'up')}
                          disabled={index === 0 || isSaving}
                          title="Mover para cima"
                        >
                          <ArrowUp className="h-3.5 w-3.5" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7 text-slate-500 hover:text-slate-900 disabled:opacity-30"
                          onClick={() => handleMove(index, 'down')}
                          disabled={index === steps.length - 1 || isSaving}
                          title="Mover para baixo"
                        >
                          <ArrowDown className="h-3.5 w-3.5" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7 text-slate-500 hover:text-slate-900"
                          onClick={() => handleStartEdit(step)}
                          disabled={isSaving}
                          title="Renomear etapa"
                        >
                          <Edit2 className="h-3.5 w-3.5" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7 text-red-500 hover:text-red-700 hover:bg-red-50"
                          onClick={() => handleRemove(step.id)}
                          disabled={isSaving}
                          title="Excluir etapa do modelo"
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                        </Button>
                      </div>
                    )}
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      </CardContent>
    </Card>
  )
}

export function OnboardingSettingsTab() {
  const { state, updateItem } = useLegalStore()
  const s = state.settings
  const users = state.users || []
  const [isSaving, setIsSaving] = useState(false)
  const [currentTab, setCurrentTab] = useState<'cliente' | 'processo'>('cliente')

  // Etapas do modelo de Cliente
  const clientSteps: OnboardingStep[] =
    Array.isArray(s.onboardingChecklist) && s.onboardingChecklist.length > 0
      ? [...s.onboardingChecklist]
          .filter((st) => !st.type || st.type === 'cliente')
          .sort((a, b) => (a.order ?? 0) - (b.order ?? 0))
      : DEFAULT_CLIENT_ONBOARDING_STEPS

  // Etapas do modelo de Processo
  const caseSteps: OnboardingStep[] =
    Array.isArray(s.caseOnboardingChecklist) && s.caseOnboardingChecklist.length > 0
      ? [...s.caseOnboardingChecklist]
          .filter((st) => !st.type || st.type === 'processo')
          .sort((a, b) => (a.order ?? 0) - (b.order ?? 0))
      : DEFAULT_CASE_ONBOARDING_STEPS

  const saveClientSteps = async (updatedSteps: OnboardingStep[]) => {
    setIsSaving(true)
    try {
      const normalized = updatedSteps.map((step, idx) => ({
        ...step,
        order: idx + 1,
        type: 'cliente' as const,
      }))

      await updateItem('settings', s.id, {
        onboardingChecklist: normalized,
      })

      toast({
        title: 'Modelo de Cliente salvo',
        description: 'Checklist de Onboarding de Cliente atualizado com sucesso!',
      })
    } catch (err: any) {
      toast({
        title: 'Erro ao salvar modelo de cliente',
        description: err?.message || 'Falha ao gravar etapas do checklist no banco.',
        variant: 'destructive',
      })
    } finally {
      setIsSaving(false)
    }
  }

  const saveCaseSteps = async (updatedSteps: OnboardingStep[]) => {
    setIsSaving(true)
    try {
      const normalized = updatedSteps.map((step, idx) => ({
        ...step,
        order: idx + 1,
        type: 'processo' as const,
      }))

      await updateItem('settings', s.id, {
        caseOnboardingChecklist: normalized,
      })

      toast({
        title: 'Modelo de Processo salvo',
        description: 'Checklist de Onboarding de Processo atualizado com sucesso!',
      })
    } catch (err: any) {
      toast({
        title: 'Erro ao salvar modelo de processo',
        description: err?.message || 'Falha ao gravar etapas do checklist no banco.',
        variant: 'destructive',
      })
    } finally {
      setIsSaving(false)
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-2 border-b">
        <div>
          <h2 className="text-xl font-bold tracking-tight text-slate-900 dark:text-slate-100 flex items-center gap-2">
            <ClipboardList className="h-6 w-6 text-primary" />
            Modelos de Onboarding
          </h2>
          <p className="text-sm text-muted-foreground mt-0.5">
            Gerencie separadamente as rotinas de integração para cadastro de Clientes e abertura de
            Processos.
          </p>
        </div>
      </div>

      <Tabs
        value={currentTab}
        onValueChange={(val) => setCurrentTab(val as 'cliente' | 'processo')}
        className="w-full space-y-4"
      >
        <TabsList className="grid w-full grid-cols-2 max-w-md">
          <TabsTrigger value="cliente" className="flex items-center gap-2">
            <Users className="h-4 w-4" />
            <span>Onboarding de Cliente ({clientSteps.length})</span>
          </TabsTrigger>
          <TabsTrigger value="processo" className="flex items-center gap-2">
            <Briefcase className="h-4 w-4" />
            <span>Onboarding de Processo ({caseSteps.length})</span>
          </TabsTrigger>
        </TabsList>

        <TabsContent value="cliente" className="space-y-4">
          <OnboardingModelSection
            type="cliente"
            title="Modelo de Onboarding de CLIENTES"
            subtitle="Rotina disparada automaticamente ao cadastrar um novo cliente no escritório."
            explanation="Cadastrar cliente, cadastrar o processo e coletar documentos é uma rotina de CLIENTES. As etapas são criadas vinculadas ao cliente e exibidas no card de Onboarding na ficha do cliente e em Tarefas."
            steps={clientSteps}
            defaultSteps={DEFAULT_CLIENT_ONBOARDING_STEPS}
            onSave={saveClientSteps}
            users={users}
            isSaving={isSaving}
            badgeColorClass="bg-blue-50 text-blue-700 border-blue-200"
            accentColorClass="bg-blue-50/70 border-blue-200 text-blue-950"
          />
        </TabsContent>

        <TabsContent value="processo" className="space-y-4">
          <OnboardingModelSection
            type="processo"
            title="Modelo de Onboarding de PROCESSOS"
            subtitle="Rotina disparada automaticamente ao cadastrar um novo processo/caso."
            explanation="Redigir procuração, declaração, lançar honorários, tratar documentos, monitorar assinaturas, já é uma rotina de PROCESSOS. As etapas são criadas vinculadas diretamente ao caso judicial e exibidas na ficha do processo e em Tarefas."
            steps={caseSteps}
            defaultSteps={DEFAULT_CASE_ONBOARDING_STEPS}
            onSave={saveCaseSteps}
            users={users}
            isSaving={isSaving}
            badgeColorClass="bg-indigo-50 text-indigo-700 border-indigo-200"
            accentColorClass="bg-indigo-50/70 border-indigo-200 text-indigo-950"
          />
        </TabsContent>
      </Tabs>
    </div>
  )
}
