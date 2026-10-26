import { useState, useMemo } from 'react'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Checkbox } from '@/components/ui/checkbox'
import { Progress } from '@/components/ui/progress'
import {
  CheckCircle2,
  Clock,
  Sparkles,
  RotateCcw,
  PlusCircle,
  ExternalLink,
  Lock,
} from 'lucide-react'
import { Link } from 'react-router-dom'
import { Task } from '@/lib/mockData'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip'

interface CaseOnboardingCardProps {
  caseId: string
  caseNumber: string
  clientId: string
  caseResponsibleId?: string | null
}

export function CaseOnboardingCard({
  caseId,
  caseNumber,
  clientId,
  caseResponsibleId,
}: CaseOnboardingCardProps) {
  const { state, updateItem, generateCaseOnboardingTasks } = useLegalStore()
  const [isGenerating, setIsGenerating] = useState(false)

  // Identificação do processo e verificação de regras de permissão
  const c = state.cases.find((item) => item.id === caseId)
  const currentUserId = state.currentUser?.id
  const isAdmin = state.currentUser?.role === 'Admin'

  const isNewCase = useMemo(() => {
    if (!c) return false
    // 1. Criado pelo próprio usuário logado
    if (c.created_by && currentUserId && c.created_by === currentUserId) {
      return true
    }
    // 2. Cadastrado há ≤ 7 dias
    const createdAtStr = (c as any).created_at || (c as any).createdAt
    if (createdAtStr) {
      const createdDate = new Date(createdAtStr)
      if (!isNaN(createdDate.getTime())) {
        const diffMs = Date.now() - createdDate.getTime()
        const diffDays = diffMs / (1000 * 60 * 60 * 24)
        if (diffDays <= 7) {
          return true
        }
      }
    }
    return false
  }, [c, currentUserId])

  // Pode disparar onboarding: processo novo (qualquer usuário) OU admin (mesmo para processos antigos)
  const canTriggerOnboarding = isNewCase || isAdmin

  // Filtra as tarefas de onboarding vinculadas a este processo
  const onboardingTasks = state.tasks
    .filter(
      (t) =>
        t.relatedProcessId === caseId &&
        (t.type === 'Onboarding' || (t.type || '').toLowerCase().includes('onboarding')),
    )
    .sort((a, b) => {
      const aCreated = new Date(a.created_at || a.dueDate || 0).getTime()
      const bCreated = new Date(b.created_at || b.dueDate || 0).getTime()
      return aCreated - bCreated
    })

  // Contagem de progresso
  const totalSteps = onboardingTasks.length
  const completedSteps = onboardingTasks.filter(
    (t) =>
      (t.status || '').toLowerCase() === 'concluída' ||
      (t.status || '').toLowerCase() === 'concluido' ||
      (t.status || '').toLowerCase() === 'concluida',
  ).length
  const progressPercent = totalSteps > 0 ? Math.round((completedSteps / totalSteps) * 100) : 0

  const handleToggleTask = async (task: Task) => {
    const isCompleted =
      (task.status || '').toLowerCase() === 'concluída' ||
      (task.status || '').toLowerCase() === 'concluido' ||
      (task.status || '').toLowerCase() === 'concluida'

    const nextStatus = isCompleted ? 'pendente' : 'Concluída'

    try {
      await updateItem('tasks', task.id, {
        status: nextStatus,
        completed_by: nextStatus === 'Concluída' ? currentUserId || null : null,
        updatedAt: new Date().toISOString(),
      })
      toast({
        title: nextStatus === 'Concluída' ? 'Etapa concluída!' : 'Etapa reaberta',
        description: `"${task.title}" marcada como ${nextStatus.toLowerCase()}.`,
      })
    } catch (err: any) {
      toast({
        title: 'Erro ao atualizar etapa',
        description: err?.message || 'Falha ao salvar no banco.',
        variant: 'destructive',
      })
    }
  }

  const handleGenerateChecklist = async () => {
    if (isGenerating) return
    if (!canTriggerOnboarding) {
      toast({
        title: 'Permissão necessária',
        description: 'Somente administradores podem disparar o onboarding de processos antigos.',
        variant: 'destructive',
      })
      return
    }
    setIsGenerating(true)
    try {
      const generated = await generateCaseOnboardingTasks(
        caseId,
        clientId,
        caseResponsibleId,
        caseNumber,
      )
      if (generated && generated.length > 0) {
        toast({
          title: 'Checklist de processo disparado',
          description: `${generated.length} nova(s) etapa(s) de onboarding criada(s).`,
        })
      } else {
        toast({
          title: 'Checklist verificado',
          description: 'Nenhuma etapa duplicada — todas as etapas pendentes já estão ativas.',
        })
      }
    } catch (err: any) {
      toast({
        title: 'Erro ao gerar checklist',
        description: err?.message || 'Falha ao disparar tarefas.',
        variant: 'destructive',
      })
    } finally {
      setIsGenerating(false)
    }
  }

  return (
    <Card className="shadow-sm border border-indigo-200/80 bg-gradient-to-b from-indigo-50/30 to-background">
      <CardHeader className="pb-3">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <div className="space-y-1">
            <div className="flex items-center gap-2">
              <Sparkles className="h-5 w-5 text-indigo-600" />
              <CardTitle className="text-lg text-slate-900 dark:text-slate-100">
                Onboarding de Processo
              </CardTitle>
              {totalSteps > 0 && (
                <Badge
                  variant="outline"
                  className={
                    completedSteps === totalSteps
                      ? 'bg-emerald-50 text-emerald-700 border-emerald-300 font-semibold'
                      : 'bg-indigo-50 text-indigo-700 border-indigo-300 font-semibold'
                  }
                >
                  {completedSteps === totalSteps
                    ? '100% Concluído'
                    : `${completedSteps}/${totalSteps} etapas`}
                </Badge>
              )}
            </div>
            <CardDescription className="text-xs">
              Rotina guiada de processo: procuração, declaração, honorários, tratamento de
              documentos e assinaturas do caso {caseNumber}.
            </CardDescription>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            {totalSteps === 0 ? (
              canTriggerOnboarding ? (
                <Button
                  size="sm"
                  onClick={handleGenerateChecklist}
                  disabled={isGenerating}
                  className="bg-indigo-600 hover:bg-indigo-700 text-white"
                >
                  <PlusCircle className="h-4 w-4 mr-1.5" />
                  {isGenerating ? 'Gerando...' : 'Gerar Checklist de Processo'}
                </Button>
              ) : (
                <TooltipProvider>
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <span>
                        <Button
                          size="sm"
                          disabled
                          className="bg-slate-300 dark:bg-slate-800 text-slate-500 cursor-not-allowed"
                        >
                          <Lock className="h-3.5 w-3.5 mr-1.5" />
                          Gerar Checklist (Admin)
                        </Button>
                      </span>
                    </TooltipTrigger>
                    <TooltipContent>
                      <p>
                        Somente administradores podem disparar o onboarding de processos antigos.
                      </p>
                    </TooltipContent>
                  </Tooltip>
                </TooltipProvider>
              )
            ) : canTriggerOnboarding ? (
              <Button
                variant="outline"
                size="sm"
                onClick={handleGenerateChecklist}
                disabled={isGenerating}
                title="Verifica ou adiciona etapas do modelo de processo sem duplicar"
                className="text-xs text-slate-600 hover:text-slate-900"
              >
                <RotateCcw className={`h-3.5 w-3.5 mr-1 ${isGenerating ? 'animate-spin' : ''}`} />
                {isGenerating ? 'Disparando...' : 'Disparar Novamente'}
              </Button>
            ) : (
              <TooltipProvider>
                <Tooltip>
                  <TooltipTrigger asChild>
                    <span>
                      <Button
                        variant="outline"
                        size="sm"
                        disabled
                        className="text-xs opacity-50 cursor-not-allowed text-slate-400"
                      >
                        <Lock className="h-3.5 w-3.5 mr-1" />
                        Disparar Novamente
                      </Button>
                    </span>
                  </TooltipTrigger>
                  <TooltipContent>
                    <p>Somente administradores podem disparar o onboarding de processos antigos.</p>
                  </TooltipContent>
                </Tooltip>
              </TooltipProvider>
            )}

            <Button
              asChild
              variant="ghost"
              size="sm"
              className="text-xs text-indigo-600 hover:text-indigo-800"
            >
              <Link to={`/tarefas?numeroProcesso=${encodeURIComponent(caseNumber)}`}>
                Ver em Tarefas
                <ExternalLink className="h-3 w-3 ml-1" />
              </Link>
            </Button>
          </div>
        </div>

        {totalSteps > 0 && (
          <div className="space-y-1.5 pt-2">
            <div className="flex justify-between items-center text-xs font-medium text-slate-600 dark:text-slate-400">
              <span>Progresso geral do Onboarding</span>
              <span className="font-bold text-slate-800 dark:text-slate-200">
                {progressPercent}%
              </span>
            </div>
            <Progress value={progressPercent} className="h-2" />
          </div>
        )}
      </CardHeader>

      <CardContent>
        {totalSteps === 0 ? (
          <div className="rounded-lg border border-dashed border-indigo-200 bg-indigo-50/40 p-6 text-center space-y-3">
            <Clock className="h-8 w-8 text-indigo-500 mx-auto" />
            <div className="space-y-1">
              <p className="font-medium text-sm text-slate-800 dark:text-slate-200">
                Nenhum checklist de onboarding vinculado a este processo ainda.
              </p>
              <p className="text-xs text-muted-foreground max-w-md mx-auto">
                Processos cadastrados anteriormente ou sem disparo automático podem ter o checklist
                de rotina de processo gerado a qualquer momento com apenas 1 clique.
              </p>
            </div>
            {canTriggerOnboarding ? (
              <Button
                onClick={handleGenerateChecklist}
                disabled={isGenerating}
                className="bg-indigo-600 hover:bg-indigo-700 text-white"
              >
                <PlusCircle className="h-4 w-4 mr-1.5" />
                {isGenerating ? 'Gerando etapas...' : 'Gerar Checklist de Processo'}
              </Button>
            ) : (
              <TooltipProvider>
                <Tooltip>
                  <TooltipTrigger asChild>
                    <span>
                      <Button
                        disabled
                        className="bg-slate-300 dark:bg-slate-800 text-slate-500 cursor-not-allowed"
                      >
                        <Lock className="h-4 w-4 mr-1.5" />
                        Gerar Checklist (Apenas Administrador)
                      </Button>
                    </span>
                  </TooltipTrigger>
                  <TooltipContent>
                    <p>Somente administradores podem disparar o onboarding de processos antigos.</p>
                  </TooltipContent>
                </Tooltip>
              </TooltipProvider>
            )}
          </div>
        ) : (
          <div className="grid gap-2 sm:grid-cols-2">
            {onboardingTasks.map((t, idx) => {
              const isDone =
                (t.status || '').toLowerCase() === 'concluída' ||
                (t.status || '').toLowerCase() === 'concluido' ||
                (t.status || '').toLowerCase() === 'concluida'

              return (
                <div
                  key={t.id}
                  onClick={() => handleToggleTask(t)}
                  className={`flex items-start gap-3 p-3 rounded-lg border transition-all cursor-pointer select-none ${
                    isDone
                      ? 'bg-emerald-50/40 dark:bg-emerald-950/20 border-emerald-200 text-slate-600 dark:text-slate-400'
                      : 'bg-card hover:bg-indigo-50/40 border-slate-200 hover:border-indigo-300 text-slate-900 dark:text-slate-100 shadow-sm'
                  }`}
                >
                  <Checkbox
                    checked={isDone}
                    onCheckedChange={() => handleToggleTask(t)}
                    className="mt-0.5 data-[state=checked]:bg-emerald-600 data-[state=checked]:border-emerald-600"
                    onClick={(e) => e.stopPropagation()}
                  />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="text-xs font-bold text-muted-foreground">{idx + 1}.</span>
                      <span
                        className={`text-sm font-medium leading-snug truncate ${
                          isDone
                            ? 'line-through text-slate-500'
                            : 'text-slate-900 dark:text-slate-100'
                        }`}
                        title={t.title}
                      >
                        {t.title}
                      </span>
                    </div>
                    {t.description && (
                      <p className="text-[11px] text-muted-foreground mt-0.5 truncate">
                        {t.description}
                      </p>
                    )}
                  </div>

                  <div className="shrink-0 self-center">
                    {isDone ? (
                      <CheckCircle2 className="h-4 w-4 text-emerald-600" />
                    ) : (
                      <Badge
                        variant="secondary"
                        className="text-[10px] bg-amber-50 text-amber-700 border-amber-200 font-normal"
                      >
                        Pendente
                      </Badge>
                    )}
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </CardContent>
    </Card>
  )
}
