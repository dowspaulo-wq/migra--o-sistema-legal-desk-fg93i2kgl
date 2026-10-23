import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
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
} from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { DEFAULT_ONBOARDING_STEPS, OnboardingStep } from '@/lib/mockData'
import { toast } from '@/hooks/use-toast'

export function OnboardingSettingsTab() {
  const { state, updateItem } = useLegalStore()
  const s = state.settings

  // Lista atual no store ou fallback padrão
  const steps: OnboardingStep[] =
    Array.isArray(s.onboardingChecklist) && s.onboardingChecklist.length > 0
      ? [...s.onboardingChecklist].sort((a, b) => (a.order ?? 0) - (b.order ?? 0))
      : DEFAULT_ONBOARDING_STEPS

  const [newTitle, setNewTitle] = useState('')
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editingTitle, setEditingTitle] = useState('')
  const [isSaving, setIsSaving] = useState(false)

  const saveSteps = async (updatedSteps: OnboardingStep[]) => {
    setIsSaving(true)
    try {
      // Normalizar ordem sequencial de 1 até N
      const normalized = updatedSteps.map((step, idx) => ({
        ...step,
        order: idx + 1,
      }))

      await updateItem('settings', s.id, {
        onboardingChecklist: normalized,
      })

      toast({
        title: 'Modelo atualizado',
        description: 'Checklist de Onboarding de Cliente Novo salvo com sucesso!',
      })
    } catch (err: any) {
      toast({
        title: 'Erro ao salvar modelo',
        description: err?.message || 'Falha ao gravar etapas do checklist no banco.',
        variant: 'destructive',
      })
    } finally {
      setIsSaving(false)
    }
  }

  const handleAdd = () => {
    const trimmed = newTitle.trim()
    if (!trimmed) return

    if (steps.some((st) => st.title.toLowerCase() === trimmed.toLowerCase())) {
      toast({
        title: 'Etapa já existe',
        description: 'Já existe uma etapa com esse título no checklist.',
        variant: 'destructive',
      })
      return
    }

    const newStep: OnboardingStep = {
      id: `step-${Date.now()}`,
      title: trimmed,
      order: steps.length + 1,
    }

    const next = [...steps, newStep]
    setNewTitle('')
    saveSteps(next)
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
    saveSteps(next)
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
    saveSteps(next)
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
    saveSteps(reordered)
  }

  const handleResetToDefault = () => {
    if (
      confirm(
        'Deseja restaurar as 8 etapas padrão do checklist de onboarding sugeridas pelo escritório?',
      )
    ) {
      saveSteps(DEFAULT_ONBOARDING_STEPS)
    }
  }

  return (
    <div className="space-y-6">
      <Card className="shadow-sm border">
        <CardHeader>
          <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
            <div>
              <CardTitle className="text-xl flex items-center gap-2">
                <ClipboardList className="h-5 w-5 text-blue-600" />
                Modelo de Checklist de Onboarding de Cliente Novo
              </CardTitle>
              <CardDescription className="mt-1">
                Configure as etapas padrão geradas automaticamente como tarefas quando um cliente
                novo for cadastrado. Você pode criar novas etapas, renomear, reordenar e excluir.
              </CardDescription>
            </div>
            <div className="flex items-center gap-2 shrink-0">
              <Badge variant="outline" className="bg-blue-50 text-blue-700 border-blue-200">
                {steps.length} {steps.length === 1 ? 'etapa ativa' : 'etapas ativas'}
              </Badge>
              <Button
                variant="outline"
                size="sm"
                onClick={handleResetToDefault}
                disabled={isSaving}
                className="text-slate-600 hover:text-slate-900 hover:bg-slate-100"
                title="Restaurar lista padrão inicial"
              >
                <RotateCcw className="h-3.5 w-3.5 mr-1.5" />
                Restaurar Padrão
              </Button>
            </div>
          </div>
        </CardHeader>
        <CardContent className="space-y-6">
          {/* Caixa explicativa de contexto de negócio */}
          <div className="rounded-lg bg-blue-50/70 p-4 border border-blue-200 text-xs text-blue-950 space-y-2">
            <div className="flex items-center gap-2 font-semibold text-sm text-blue-950">
              <Sparkles className="h-4 w-4 text-blue-600 shrink-0" />
              Como funciona o Onboarding Automático no DPSjur:
            </div>
            <p className="text-blue-900 leading-relaxed">
              Assim que qualquer usuário cadastrar um <strong>cliente novo</strong> no sistema, o
              módulo de tarefas dispara automaticamente todas as etapas deste modelo vinculadas ao
              cliente com a tag de tipo <code>Onboarding</code>. Os estagiários e responsáveis
              acompanham o progresso (ex: 3/8) diretamente na ficha do cliente e na listagem de
              clientes.
            </p>
          </div>

          {/* Campo para adicionar nova etapa */}
          <div className="space-y-2">
            <label className="text-sm font-semibold text-slate-800 dark:text-slate-200">
              Adicionar Nova Etapa ao Modelo
            </label>
            <div className="flex gap-2">
              <Input
                value={newTitle}
                onChange={(e) => setNewTitle(e.target.value)}
                placeholder="Ex.: 'Validar comprovante de residência', 'Emitir guia inicial'..."
                className="flex-1"
                disabled={isSaving}
                onKeyDown={(e) => e.key === 'Enter' && handleAdd()}
              />
              <Button
                onClick={handleAdd}
                disabled={!newTitle.trim() || isSaving}
                className="bg-blue-600 hover:bg-blue-700 text-white shrink-0"
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
                    key={step.id || `step-${index}`}
                    className="flex items-center justify-between p-3.5 hover:bg-slate-50/80 dark:hover:bg-slate-900/50 transition-colors gap-3"
                  >
                    <div className="flex items-center gap-3 flex-1 min-w-0">
                      {/* Badge do número da etapa */}
                      <span className="flex items-center justify-center h-6 w-6 rounded-full bg-blue-100 text-blue-800 dark:bg-blue-950 dark:text-blue-300 font-bold text-xs shrink-0">
                        {index + 1}
                      </span>

                      {/* Título ou campo de edição */}
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
                          <CheckCircle2 className="h-4 w-4 text-blue-500 shrink-0" />
                          <span className="text-sm font-medium text-slate-900 dark:text-slate-100 truncate">
                            {step.title}
                          </span>
                        </div>
                      )}
                    </div>

                    {/* Botões de Ação: Subir, Descer, Editar, Excluir */}
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
                )
              })}
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
