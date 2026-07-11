import { useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'
import {
  ArrowLeft,
  Scale,
  Users,
  CheckSquare,
  FileText,
  Download,
  Star,
  Edit,
  Plus,
  FolderTree,
  CalendarDays,
  Calendar,
  Clock,
  Video,
  MapPin,
  AlertCircle,
  DollarSign,
  Trash,
  Check,
  Briefcase,
  FileSignature,
  FileUp,
  RefreshCw,
} from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'
import { CaseDialog } from '@/components/CaseDialog'
import { TaskDialog } from '@/components/TaskDialog'
import { AppointmentDialog } from '@/components/AppointmentDialog'
import { TransactionDialog } from '@/components/TransactionDialog'
import { formatSafeLocalDate, getDetailedDuration, normalizeStr } from '@/lib/utils'
import { createZapSignDoc, createDocFromTemplate } from '@/services/zapsign'
import { fetchDocumentTemplates } from '@/services/document-templates'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { syncCaseWithDataJud, isValidCNJNumber } from '@/services/datajud'

const getTaskTypeStyle = (type: string) => {
  const t = (type || '').toLowerCase()
  if (t.includes('petições') || t.includes('peticionar')) {
    return { bg: 'bg-blue-50', text: 'text-blue-700', border: 'border-blue-200' }
  }
  if (t.includes('redigir inicial')) {
    return { bg: 'bg-green-50', text: 'text-green-700', border: 'border-green-200' }
  }
  if (t.includes('recorrer')) {
    return { bg: 'bg-amber-50', text: 'text-amber-700', border: 'border-amber-200' }
  }
  if (t.includes('revisão/protocolo') || t.includes('revisao/protocolo')) {
    return { bg: 'bg-purple-50', text: 'text-purple-700', border: 'border-purple-200' }
  }
  return { bg: 'bg-slate-50', text: 'text-slate-700', border: 'border-slate-200' }
}

const getAlertLabel = (alert: string) => {
  const trimmed = alert.trim()
  if (trimmed === 'Cobrar astreites' || trimmed === '💸 Cobrar astreites')
    return '💸 Cobrar astreites'
  if (trimmed === 'Litigância de má-fé' || trimmed === '🛑 Litigância de má-fé')
    return '🛑 Litigância de má-fé'
  if (trimmed === 'Segredo de Justiça' || trimmed === '🕵️ Segredo de Justiça')
    return '🕵️ Segredo de Justiça'
  return trimmed
}

export default function CaseDetail() {
  const { id } = useParams<{ id: string }>()
  const { state, updateItem, deleteItem, addCase, addTask, addAppointment, addTransaction } =
    useLegalStore()
  const [selectedTpl, setSelectedTpl] = useState<string>('')
  const [isCaseOpen, setIsCaseOpen] = useState(false)

  const [editingTask, setEditingTask] = useState<any>(null)
  const [creatingTask, setCreatingTask] = useState(false)

  const [creatingSubcase, setCreatingSubcase] = useState(false)

  const [editingAppointment, setEditingAppointment] = useState<any>(null)
  const [creatingAppointment, setCreatingAppointment] = useState(false)

  const [editingTransaction, setEditingTransaction] = useState<any>(null)
  const [creatingTransaction, setCreatingTransaction] = useState(false)
  const [zapsignLoading, setZapsignLoading] = useState<string | null>(null)
  const [templateDialogOpen, setTemplateDialogOpen] = useState(false)
  const [templates, setTemplates] = useState<any[]>([])
  const [templateLoading, setTemplateLoading] = useState(false)
  const [generatingFromTemplate, setGeneratingFromTemplate] = useState<string | null>(null)
  const [datajudSyncing, setDatajudSyncing] = useState(false)

  const c = state.cases.find((x) => x.id === id)
  const client = state.clients.find((cl) => cl.id === c?.clientId)
  const tasks = state.tasks
    .filter((t) => t.relatedProcessId === id)
    .sort((a: any, b: any) => {
      const timeA = a.dueDate
        ? new Date(a.dueDate).getTime()
        : a.created_at
          ? new Date(a.created_at).getTime()
          : 0
      const timeB = b.dueDate
        ? new Date(b.dueDate).getTime()
        : b.created_at
          ? new Date(b.created_at).getTime()
          : 0
      return (Number.isNaN(timeB) ? 0 : timeB) - (Number.isNaN(timeA) ? 0 : timeA)
    })
  const subcases = state.cases.filter((sc) => sc.parentId === id)
  const processAppointments = state.appointments
    .filter((a) => a.processId === id)
    .sort((a: any, b: any) => {
      const dateA = new Date(`${a.date || '1970-01-01'}T${a.time || '00:00'}`).getTime()
      const dateB = new Date(`${b.date || '1970-01-01'}T${b.time || '00:00'}`).getTime()
      return (Number.isNaN(dateB) ? 0 : dateB) - (Number.isNaN(dateA) ? 0 : dateA)
    })
  const parentProcess = c?.parentId ? state.cases.find((x) => x.id === c.parentId) : null
  const responsibleUser = state.users.find((u) => u.id === c?.responsibleId)

  const processTransactions = state.transactions.filter((t) => t.processId === id)
  const income = processTransactions
    .filter((t) => t.type === 'income')
    .reduce((acc, t) => acc + t.amount, 0)
  const expense = processTransactions
    .filter((t) => t.type === 'expense')
    .reduce((acc, t) => acc + t.amount, 0)

  const handleDataJudSync = async () => {
    if (!c?.number || !isValidCNJNumber(c.number)) {
      toast({
        title: 'Atenção',
        description:
          'O número do processo não está no formato CNJ válido (NNNNNNN-DD.YYYY.J.TR.OOOO).',
        variant: 'destructive',
      })
      return
    }
    setDatajudSyncing(true)
    const { data, error } = await syncCaseWithDataJud(c.id, c.number)
    setDatajudSyncing(false)
    if (error) {
      toast({
        title: 'Erro',
        description: error.message || 'Falha ao sincronizar com tribunal.',
        variant: 'destructive',
      })
    } else if (data?.found) {
      updateItem('cases', c.id, {
        last_movement: data.last_movement,
        last_sync_at: data.last_sync_at,
        court_details: data.court_details,
      })
      toast({
        title: 'Sucesso',
        description: 'Movimentações sincronizadas com o tribunal.',
      })
    } else {
      updateItem('cases', c.id, {
        last_sync_at: data?.last_sync_at || new Date().toISOString(),
        court_details: data?.court_details || { not_found: true },
      })
      toast({
        title: 'Atenção',
        description: 'Processo não encontrado no DataJud/CNJ.',
        variant: 'destructive',
      })
    }
  }

  if (!c) return <div className="p-8 text-center">Processo não encontrado.</div>

  const generateDoc = () => {
    if (!selectedTpl)
      return toast({
        title: 'Atenção',
        description: 'Selecione um modelo de petição primeiro.',
        variant: 'destructive',
      })
    const tpl = state.petitions.find((p) => p.id === selectedTpl)
    if (!tpl) return

    let html = tpl.content
      .replace(/{{client_name}}/g, client?.name || '')
      .replace(/{{client_document}}/g, client?.document || '')
      .replace(/{{process_number}}/g, c.number || '')
      .replace(/{{adverse_party}}/g, c.adverseParty || '')
      .replace(/{{court}}/g, c.court || '')
      .replace(/{{comarca}}/g, c.comarca?.toUpperCase() || '')

    const docContent = `<html xmlns:o='urn:schemas-microsoft-com:office:office' xmlns:w='urn:schemas-microsoft-com:office:word' xmlns='http://www.w3.org/TR/REC-html40'><head><meta charset='utf-8'><title>${tpl.title}</title></head><body>${html}</body></html>`
    const blob = new Blob(['\ufeff', docContent], { type: 'application/msword' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `${tpl.title.replace(/\s+/g, '_')}_${c.number}.doc`
    a.click()
    URL.revokeObjectURL(url)
    toast({ title: 'Sucesso', description: 'Documento gerado e baixado.' })
  }

  const handleZapSign = async (docType: string) => {
    if (!c?.clientId) {
      toast({
        title: 'Atenção',
        description: 'Este processo não tem cliente vinculado.',
        variant: 'destructive',
      })
      return
    }
    setZapsignLoading(docType)
    const { data, error } = await createZapSignDoc(c.id, c.clientId, docType)
    setZapsignLoading(null)
    if (error) {
      toast({
        title: 'Erro',
        description: error.message || 'Falha ao criar documento.',
        variant: 'destructive',
      })
    } else {
      toast({
        title: 'Sucesso',
        description: 'Documento enviado para assinatura via ZapSign.',
      })
      if (data?.url) {
        window.open(data.url, '_blank')
      }
    }
  }

  const openTemplateDialog = async () => {
    setTemplateDialogOpen(true)
    setTemplateLoading(true)
    const { data } = await fetchDocumentTemplates()
    setTemplates(data || [])
    setTemplateLoading(false)
  }

  const handleGenerateFromTemplate = async (templateId: string) => {
    setGeneratingFromTemplate(templateId)
    const { data, error } = await createDocFromTemplate(c.id, templateId)
    setGeneratingFromTemplate(null)
    if (error) {
      toast({
        title: 'Erro',
        description: error.message || 'Falha ao gerar documento.',
        variant: 'destructive',
      })
    } else {
      toast({
        title: 'Sucesso',
        description: 'Documento gerado e enviado para assinatura.',
      })
      setTemplateDialogOpen(false)
      if (data?.url) window.open(data.url, '_blank')
    }
  }

  return (
    <div className="space-y-6">
      <CaseDialog
        open={isCaseOpen}
        onOpenChange={setIsCaseOpen}
        data={c}
        onSave={(d: any) => updateItem('cases', d.id, d)}
        users={state.users}
        clients={state.clients}
        settings={state.settings}
      />
      <CaseDialog
        open={creatingSubcase}
        onOpenChange={setCreatingSubcase}
        data={{ parentId: c.id, clientId: c.clientId, isNew: true }}
        lockedClientId={c.clientId}
        onSave={(d: any) => addCase(d)}
        users={state.users}
        clients={state.clients}
        settings={state.settings}
      />
      <TaskDialog
        open={!!editingTask}
        onOpenChange={(v: boolean) => !v && setEditingTask(null)}
        data={editingTask}
        onSave={(d: any) => updateItem('tasks', editingTask?.id || d.id, d)}
        onDelete={(id: string) => deleteItem('tasks', id)}
        users={state.users}
        currentUser={state.currentUser}
        clients={state.clients}
        cases={state.cases}
        settings={state.settings}
      />
      <TaskDialog
        open={creatingTask}
        onOpenChange={setCreatingTask}
        data={{ clientId: c.clientId, relatedProcessId: c.id, lockedProcessId: true, isNew: true }}
        onSave={(d: any) => addTask(d)}
        users={state.users}
        currentUser={state.currentUser}
        clients={state.clients}
        cases={state.cases}
        settings={state.settings}
      />
      <AppointmentDialog
        open={!!editingAppointment}
        onOpenChange={(v: boolean) => !v && setEditingAppointment(null)}
        data={editingAppointment}
        onSave={(d: any) => updateItem('appointments', editingAppointment?.id || d.id, d)}
        users={state.users}
        clients={state.clients}
        cases={state.cases}
        settings={state.settings}
      />
      <AppointmentDialog
        open={creatingAppointment}
        onOpenChange={setCreatingAppointment}
        data={{ processId: c.id, clientId: c.clientId, isNew: true }}
        onSave={(d: any) => addAppointment(d)}
        users={state.users}
        clients={state.clients}
        cases={state.cases}
        settings={state.settings}
      />
      <TransactionDialog
        open={!!editingTransaction}
        onOpenChange={(v: boolean) => !v && setEditingTransaction(null)}
        data={editingTransaction}
        onSave={(d: any) => updateItem('transactions', editingTransaction.id, d)}
      />
      <TransactionDialog
        open={creatingTransaction}
        onOpenChange={setCreatingTransaction}
        lockedProcessId={c.id}
        lockedClientId={c.clientId}
        onSave={(d: any) => addTransaction(d)}
      />

      <Dialog open={templateDialogOpen} onOpenChange={setTemplateDialogOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Gerar Documento</DialogTitle>
          </DialogHeader>
          <div className="space-y-2 max-h-96 overflow-y-auto">
            {templateLoading ? (
              <p className="text-sm text-muted-foreground text-center py-4">Carregando...</p>
            ) : templates.length === 0 ? (
              <p className="text-sm text-muted-foreground text-center py-4">
                Nenhum template disponível.
              </p>
            ) : (
              templates.map((t) => (
                <div
                  key={t.id}
                  className="flex items-center justify-between border p-3 rounded-lg hover:bg-slate-50 cursor-pointer transition-colors"
                  onClick={() => handleGenerateFromTemplate(t.id)}
                >
                  <div>
                    <p className="font-medium text-sm">{t.name}</p>
                    <Badge variant="outline" className="text-xs mt-1">
                      {t.category}
                    </Badge>
                  </div>
                  {generatingFromTemplate === t.id && (
                    <span className="text-xs text-primary animate-pulse">Gerando...</span>
                  )}
                </div>
              ))
            )}
          </div>
        </DialogContent>
      </Dialog>

      <div className="flex items-start gap-4">
        <Button variant="outline" size="icon" asChild>
          <Link to="/processos">
            <ArrowLeft className="h-4 w-4" />
          </Link>
        </Button>
        <div className="flex-1">
          <div className="flex items-center gap-3 flex-wrap" data-native-system-icon="true">
            <h1 className="text-2xl md:text-3xl font-bold tracking-tight text-primary flex items-center gap-3 break-all">
              {(() => {
                const sys = state.caseSystems?.find((s) => s.name === c.system)
                if (sys?.image_url) {
                  return (
                    <img
                      src={sys.image_url}
                      alt={sys.name}
                      className="w-8 h-8 object-contain shrink-0"
                      title={sys.name}
                    />
                  )
                }
                return null
              })()}
              {c.number}
              {c.isSpecial && (
                <Star className="h-6 w-6 fill-yellow-400 text-yellow-400" title="Especial" />
              )}
              {c.isProblematic && (
                <span className="text-2xl" title="Problemático">
                  💩
                </span>
              )}
            </h1>
            <Button variant="outline" size="sm" onClick={() => setIsCaseOpen(true)}>
              <Edit className="h-4 w-4 mr-2" /> Editar
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={handleDataJudSync}
              disabled={datajudSyncing}
              title={
                isValidCNJNumber(c.number)
                  ? 'Sincronizar movimentações com DataJud/CNJ'
                  : 'Número de processo inválido para sincronização CNJ'
              }
            >
              <RefreshCw className={cn('h-4 w-4 mr-2', datajudSyncing && 'animate-spin')} />
              {datajudSyncing ? 'Sincronizando...' : 'Sincronizar com Tribunal'}
            </Button>
          </div>

          <div
            className="flex items-center gap-2 flex-wrap text-muted-foreground mt-1 mb-4 text-sm"
            data-native-system-icon="true"
          >
            <Badge variant="outline">{c.status}</Badge>
            <Badge variant="secondary">{c.classification || 'SB'}</Badge>
            <span>•</span>
            <span className="flex items-center gap-1.5">
              Sistema:{' '}
              {(() => {
                const sys = state.caseSystems?.find((s) => s.name === c.system)
                if (sys?.image_url) {
                  return (
                    <span className="flex items-center gap-1 bg-slate-100 px-1.5 py-0.5 rounded font-medium text-slate-700">
                      <img src={sys.image_url} alt={sys.name} className="w-4 h-4 object-contain" />
                      {c.system}
                    </span>
                  )
                }
                return c.system || 'Não informado'
              })()}
            </span>
            {parentProcess && (
              <>
                <span>•</span>
                <span className="flex items-center gap-1">
                  Vinculado ao principal:
                  <Link
                    to={`/processos/${parentProcess.id}`}
                    className="font-medium text-primary hover:underline flex items-center gap-1"
                  >
                    {parentProcess.number}
                  </Link>
                </span>
              </>
            )}
          </div>

          {(c.alerts || c.description) && (
            <div className="space-y-4 mb-2 bg-slate-50/80 p-4 rounded-lg border border-slate-100 max-w-4xl">
              {c.alerts && (
                <div>
                  <span className="text-sm font-semibold text-slate-700 block mb-2 flex items-center gap-2">
                    <AlertCircle className="h-4 w-4 text-red-500" />
                    Alertas Importantes
                  </span>
                  <div className="flex flex-wrap gap-2">
                    {c.alerts
                      .split(',')
                      .filter(Boolean)
                      .map((alert, idx) => (
                        <Badge
                          key={idx}
                          variant="outline"
                          className="bg-red-50 text-red-700 border-red-200"
                        >
                          {getAlertLabel(alert)}
                        </Badge>
                      ))}
                  </div>
                </div>
              )}
              {c.description && (
                <div>
                  <span className="text-sm font-semibold text-slate-700 block mb-1">
                    Descrição do Caso
                  </span>
                  <div className="text-sm text-slate-600 whitespace-pre-wrap">{c.description}</div>
                </div>
              )}
            </div>
          )}

          {/* Context Header */}
          <div className="flex flex-col md:flex-row gap-4 mb-2 bg-slate-50/80 p-4 rounded-lg border border-slate-100 max-w-4xl">
            <div className="flex-1">
              <h3 className="text-sm font-semibold flex items-center gap-2 mb-2 text-slate-700">
                <Users className="h-4 w-4" /> Partes
              </h3>
              <div className="text-sm space-y-1">
                <p>
                  <span className="text-muted-foreground">Cliente: </span>
                  {client ? (
                    <Link
                      to={`/clientes/${client.id}`}
                      className="font-medium text-primary hover:underline"
                    >
                      {client.name}
                    </Link>
                  ) : (
                    <span className="font-medium text-muted-foreground">—</span>
                  )}
                  {c.position ? ` (${c.position})` : ''}
                </p>
                <p>
                  <span className="text-muted-foreground">Parte Adversa: </span>
                  <span className="font-medium">{c.adverseParty || '—'}</span>
                </p>
              </div>
            </div>
            <div className="hidden md:block w-px bg-slate-200"></div>
            <div className="flex-1">
              <h3 className="text-sm font-semibold flex items-center gap-2 mb-2 text-slate-700">
                <Scale className="h-4 w-4" /> Juízo
              </h3>
              <div className="text-sm space-y-1">
                <p>
                  <span className="text-muted-foreground">Vara: </span>
                  <span className="font-medium">{c.court || '—'}</span>
                </p>
                <p>
                  <span className="text-muted-foreground">Comarca / UF: </span>
                  <span className="font-medium">
                    {c.comarca
                      ? `${c.comarca.toUpperCase()}${c.state ? ` - ${c.state.toUpperCase()}` : ''}`
                      : '—'}
                  </span>
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <Tabs defaultValue="info" className="w-full">
        <TabsList className="grid w-full grid-cols-2 sm:grid-cols-3 md:grid-cols-7 h-auto max-w-4xl gap-1 p-1">
          <TabsTrigger value="info">Informações</TabsTrigger>
          <TabsTrigger value="subprocessos">Subprocessos</TabsTrigger>
          <TabsTrigger value="tasks">Tarefas</TabsTrigger>
          <TabsTrigger value="agenda">Agenda</TabsTrigger>
          <TabsTrigger value="despesas">Despesas</TabsTrigger>
          <TabsTrigger value="docs">Documentos (em construção)</TabsTrigger>
          <TabsTrigger value="assinaturas">Assinaturas (em construção)</TabsTrigger>
        </TabsList>

        <TabsContent value="info" className="mt-4 space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <Card className="shadow-sm border-slate-200">
              <CardHeader className="pb-3">
                <CardTitle className="text-lg flex items-center gap-2 text-slate-700">
                  <Briefcase className="h-5 w-5" /> Administrativo & Metadados
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-4 text-sm">
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <Label className="text-muted-foreground block mb-1">Responsável</Label>
                    <p className="font-medium text-slate-900">
                      {responsibleUser?.name || 'Não informado'}
                    </p>
                  </div>
                  <div>
                    <Label className="text-muted-foreground block mb-1">Data de Início</Label>
                    <p className="font-medium text-slate-900">
                      {c.startDate ? formatSafeLocalDate(c.startDate) : 'Não informado'}
                    </p>
                  </div>
                  <div>
                    <Label className="text-muted-foreground block mb-1">Criado em</Label>
                    <p className="font-medium text-slate-900">
                      {(c as any).created_at
                        ? new Date((c as any).created_at).toLocaleDateString('pt-BR')
                        : 'Não informado'}
                    </p>
                  </div>
                  <div>
                    <Label className="text-muted-foreground block mb-1">Última Atualização</Label>
                    <p className="font-medium text-slate-900">
                      {c.updatedAt ? formatSafeLocalDate(c.updatedAt) : 'Não informado'}
                    </p>
                  </div>
                  <div className="col-span-2 border-t border-slate-100 pt-3 mt-1">
                    <Label className="text-muted-foreground block mb-1">Duração do Processo</Label>
                    <p className="font-medium text-slate-900 uppercase text-xs tracking-wide">
                      {c.status && normalizeStr(c.status).includes('concluido')
                        ? `TRAMITOU DURANTE ${getDetailedDuration(c.startDate, c.updatedAt, c.status)}`
                        : `TRAMITANDO HÁ ${getDetailedDuration(c.startDate, c.updatedAt, c.status)}`}
                    </p>
                  </div>
                </div>
              </CardContent>
            </Card>

            <Card className="shadow-sm border-slate-200">
              <CardHeader className="pb-3">
                <CardTitle className="text-lg flex items-center gap-2 text-slate-700">
                  <RefreshCw className="h-5 w-5" /> Sincronização DataJud/CNJ
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-3 text-sm">
                <div>
                  <Label className="text-muted-foreground block mb-1">Última Sincronização</Label>
                  <p className="font-medium text-slate-900">
                    {(c as any).last_sync_at
                      ? new Date((c as any).last_sync_at).toLocaleString('pt-BR')
                      : 'Nunca sincronizado'}
                  </p>
                </div>
                <div>
                  <Label className="text-muted-foreground block mb-1">Última Movimentação</Label>
                  <p className="font-medium text-slate-900">
                    {(c as any).last_movement || 'Nenhuma movimentação registrada'}
                  </p>
                </div>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleDataJudSync}
                  disabled={datajudSyncing}
                  className="w-full"
                >
                  <RefreshCw className={cn('h-4 w-4 mr-2', datajudSyncing && 'animate-spin')} />
                  {datajudSyncing ? 'Sincronizando...' : 'Sincronizar com Tribunal'}
                </Button>
                {!isValidCNJNumber(c.number) && (
                  <p className="text-xs text-amber-600 flex items-center gap-1">
                    <AlertCircle className="h-3 w-3" />
                    Número de processo fora do padrão CNJ para sincronização.
                  </p>
                )}
              </CardContent>
            </Card>

            <Card className="shadow-sm border-slate-200">
              <CardHeader className="pb-3">
                <CardTitle className="text-lg flex items-center gap-2 text-slate-700">
                  <DollarSign className="h-5 w-5" /> Informações Financeiras
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-4 text-sm">
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <Label className="text-muted-foreground block mb-1">Valor da Causa</Label>
                    <p className="font-medium text-slate-900">
                      {c.value != null
                        ? `R$ ${Number(c.value).toLocaleString('pt-BR', { minimumFractionDigits: 2 })}`
                        : 'Não informado'}
                    </p>
                  </div>
                  <div>
                    <Label className="text-muted-foreground block mb-1">Tipo de Honorários</Label>
                    <p className="font-medium text-slate-900">
                      {(c as any).feeType || 'Não informado'}
                    </p>
                  </div>
                  <div>
                    <Label className="text-muted-foreground block mb-1">Valor dos Honorários</Label>
                    <p className="font-medium text-slate-900">
                      {(c as any).feeValue != null
                        ? `R$ ${Number((c as any).feeValue).toLocaleString('pt-BR', { minimumFractionDigits: 2 })}`
                        : 'Não informado'}
                    </p>
                  </div>
                  <div>
                    <Label className="text-muted-foreground block mb-1">Parcelas (Qtd)</Label>
                    <p className="font-medium text-slate-900">
                      {(c as any).feeInstallments || 'Não informado'}
                    </p>
                  </div>
                </div>
              </CardContent>
            </Card>
          </div>

          <Card className="shadow-sm border-slate-200">
            <CardHeader className="pb-3">
              <CardTitle className="text-lg flex items-center gap-2 text-slate-700">
                <FileText className="h-5 w-5" /> Detalhes, Notas e Alertas
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-5">
              {c.alerts && (
                <div>
                  <Label className="text-muted-foreground mb-2 block font-semibold flex items-center gap-2">
                    <AlertCircle className="h-4 w-4 text-red-500" />
                    Alertas do Processo
                  </Label>
                  <div className="flex flex-wrap gap-2">
                    {c.alerts
                      .split(',')
                      .filter(Boolean)
                      .map((alert, idx) => (
                        <Badge
                          key={idx}
                          variant="outline"
                          className="bg-red-50 text-red-700 border-red-200 px-2.5 py-1"
                        >
                          {getAlertLabel(alert)}
                        </Badge>
                      ))}
                  </div>
                </div>
              )}
              {c.description && (
                <div>
                  <Label className="text-muted-foreground mb-2 block font-semibold">
                    Descrição
                  </Label>
                  <div className="text-sm bg-muted/30 p-3.5 rounded-md border border-border/50 whitespace-pre-wrap leading-relaxed text-slate-700">
                    {c.description}
                  </div>
                </div>
              )}
              {c.internalNotes && (
                <div>
                  <Label className="text-muted-foreground mb-2 block font-semibold">
                    Notas Internas
                  </Label>
                  <div className="text-sm bg-yellow-50/40 p-3.5 rounded-md border border-yellow-200/50 whitespace-pre-wrap leading-relaxed text-slate-700">
                    {c.internalNotes}
                  </div>
                </div>
              )}
              {!c.alerts && !c.description && !c.internalNotes && (
                <p className="text-sm text-muted-foreground italic">
                  Nenhuma descrição, nota interna ou alerta cadastrado para este processo.
                </p>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="subprocessos" className="mt-4">
          <Card className="shadow-sm">
            <CardHeader className="flex flex-row items-center justify-between pb-2">
              <CardTitle className="text-lg flex items-center gap-2">
                <FolderTree className="h-5 w-5" /> Subprocessos Vinculados
              </CardTitle>
              <Button size="sm" onClick={() => setCreatingSubcase(true)}>
                <Plus className="h-4 w-4 mr-2" /> Novo Subprocesso
              </Button>
            </CardHeader>
            <CardContent>
              <div className="space-y-3 mt-2">
                {subcases.map((sc) => (
                  <div
                    key={sc.id}
                    className="border p-4 rounded-md hover:border-primary/50 transition-colors bg-white shadow-sm"
                    data-native-system-icon="true"
                  >
                    <div className="flex justify-between items-start mb-3">
                      <div className="flex items-center gap-2 flex-wrap">
                        {(() => {
                          const sys = state.caseSystems?.find((s) => s.name === sc.system)
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
                          to={`/processos/${sc.id}`}
                          className="font-bold text-base text-primary hover:underline"
                        >
                          {sc.number}
                        </Link>
                      </div>
                      <Badge variant="outline" className="bg-slate-50">
                        {sc.status}
                      </Badge>
                    </div>
                    <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-5 gap-3 text-xs text-slate-700">
                      <div>
                        <span className="font-semibold block text-slate-500 mb-0.5">Tipo</span>
                        {sc.type || '—'}
                      </div>
                      <div>
                        <span className="font-semibold block text-slate-500 mb-0.5">
                          Tribunal/Vara
                        </span>
                        {sc.court || '—'}
                      </div>
                      <div>
                        <span className="font-semibold block text-slate-500 mb-0.5">
                          Comarca/UF
                        </span>
                        {sc.comarca
                          ? `${sc.comarca.toUpperCase()}${sc.state ? ` - ${sc.state.toUpperCase()}` : ''}`
                          : '—'}
                      </div>
                      <div>
                        <span className="font-semibold block text-slate-500 mb-0.5">
                          Parte Adversa
                        </span>
                        <span className="truncate block" title={sc.adverseParty || ''}>
                          {sc.adverseParty || '—'}
                        </span>
                      </div>
                      <div>
                        <span className="font-semibold block text-slate-500 mb-0.5">Sistema</span>
                        {sc.system || '—'}
                      </div>
                      <div>
                        <span className="font-semibold block text-slate-500 mb-0.5">
                          Valor da Causa
                        </span>
                        {sc.value != null
                          ? `R$ ${Number(sc.value).toLocaleString('pt-BR', { minimumFractionDigits: 2 })}`
                          : '—'}
                      </div>
                      <div>
                        <span className="font-semibold block text-slate-500 mb-0.5">
                          Data de Início
                        </span>
                        {sc.startDate ? formatSafeLocalDate(sc.startDate) : '—'}
                      </div>
                    </div>
                  </div>
                ))}
                {subcases.length === 0 && (
                  <p className="text-sm text-muted-foreground text-center py-6 bg-muted/20 border border-dashed rounded">
                    Nenhum subprocesso vinculado (ex: Recursos, Cartas Precatórias).
                  </p>
                )}
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="tasks" className="mt-4">
          <Card className="shadow-sm">
            <CardHeader className="flex flex-row items-center justify-between pb-2">
              <CardTitle className="text-lg flex items-center gap-2">
                <CheckSquare className="h-5 w-5" /> Tarefas
              </CardTitle>
              <Button size="sm" onClick={() => setCreatingTask(true)}>
                <Plus className="h-4 w-4 mr-2" /> Incluir nova tarefa
              </Button>
            </CardHeader>
            <CardContent>
              <div className="space-y-3 mt-2">
                {tasks.map((t) => {
                  const resp = state.users.find((u) => u.id === t.responsibleId)

                  const currentUserRole = state.currentUser?.role?.toLowerCase() || ''
                  const responsibleUserRole = resp?.role?.toLowerCase() || ''
                  const isColaborador = currentUserRole === 'colaborador'
                  const isRespAdmin = responsibleUserRole === 'admin'
                  const canComplete = !(isColaborador && isRespAdmin)

                  const tStyle = getTaskTypeStyle(t.type)

                  return (
                    <div
                      key={t.id}
                      className={`flex flex-col border p-3 rounded-lg hover:border-primary/30 cursor-pointer transition-all group ${tStyle.bg} ${tStyle.border}`}
                      onClick={() => setEditingTask(t)}
                    >
                      <div className="flex justify-between items-start">
                        <div className="flex-1">
                          <p className="font-semibold text-sm group-hover:text-primary transition-colors flex items-center gap-2">
                            {t.title}
                            <Badge
                              variant="outline"
                              className={`${tStyle.bg} ${tStyle.text} border-transparent shadow-none ml-2 text-[10px]`}
                            >
                              {t.type}
                            </Badge>
                            <Edit className="h-3 w-3 opacity-0 group-hover:opacity-100 transition-opacity text-muted-foreground" />
                          </p>
                          <div className="text-xs text-muted-foreground flex items-center gap-2 mt-1">
                            <span>Vencimento: {formatSafeLocalDate(t.dueDate)}</span>
                            {resp && (
                              <span className="bg-slate-100/50 px-1.5 py-0.5 rounded text-[10px]">
                                Resp: <span className="font-medium">{resp.name.split(' ')[0]}</span>
                              </span>
                            )}
                          </div>
                        </div>
                        <div className="flex items-center gap-2 shrink-0">
                          {t.status !== 'Concluído' &&
                            (canComplete ? (
                              <Button
                                variant="outline"
                                size="sm"
                                className="h-7 px-2 text-green-600 border-green-200 hover:text-green-700 hover:bg-green-50 hover:border-green-300 transition-colors bg-white"
                                onClick={(e) => {
                                  e.stopPropagation()
                                  updateItem('tasks', t.id, { status: 'Concluído' })
                                  toast({
                                    title: 'Sucesso',
                                    description: 'Tarefa marcada como concluída.',
                                  })
                                }}
                              >
                                <Check className="h-3 w-3 mr-1" />
                                Concluir
                              </Button>
                            ) : (
                              <Tooltip>
                                <TooltipTrigger asChild>
                                  <div className="inline-block cursor-not-allowed">
                                    <Button
                                      variant="outline"
                                      size="sm"
                                      disabled
                                      className="h-7 px-2 bg-white"
                                    >
                                      <Check className="h-3 w-3 mr-1" />
                                      Concluir
                                    </Button>
                                  </div>
                                </TooltipTrigger>
                                <TooltipContent>
                                  <p>
                                    Colaboradores não podem concluir tarefas de Administradores.
                                  </p>
                                </TooltipContent>
                              </Tooltip>
                            ))}
                          <Badge
                            variant="outline"
                            className={
                              t.status === 'Concluído'
                                ? 'bg-green-50 text-green-700 border-green-200'
                                : 'bg-white'
                            }
                          >
                            {t.status}
                          </Badge>
                        </div>
                      </div>
                      {t.description && (
                        <div className="text-sm text-muted-foreground bg-white/50 p-2.5 rounded-md border border-border/20 line-clamp-3 whitespace-pre-wrap mt-2">
                          {t.description}
                        </div>
                      )}
                    </div>
                  )
                })}
                {tasks.length === 0 && (
                  <p className="text-sm text-muted-foreground text-center py-6 bg-muted/20 border border-dashed rounded">
                    Nenhuma tarefa vinculada.
                  </p>
                )}
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="agenda" className="mt-4">
          <Card className="shadow-sm">
            <CardHeader className="flex flex-row items-center justify-between pb-2">
              <CardTitle className="text-lg flex items-center gap-2">
                <CalendarDays className="h-5 w-5" /> Agenda
              </CardTitle>
              <Button size="sm" onClick={() => setCreatingAppointment(true)}>
                <Plus className="h-4 w-4 mr-2" /> Novo Compromisso
              </Button>
            </CardHeader>
            <CardContent>
              <div className="space-y-2 mt-2">
                {processAppointments.map((a) => {
                  const resp = state.users.find((u) => u.id === a.responsibleId)
                  return (
                    <div
                      key={a.id}
                      className="flex justify-between items-center border p-3 rounded hover:bg-slate-50 cursor-pointer transition-colors group"
                      onClick={() => setEditingAppointment(a)}
                    >
                      <div>
                        <p className="font-semibold text-sm group-hover:text-primary transition-colors flex items-center gap-2">
                          {a.title}
                          <Edit className="h-3 w-3 opacity-0 group-hover:opacity-100 transition-opacity text-muted-foreground" />
                        </p>
                        <div className="text-xs text-muted-foreground flex items-center gap-2 mt-1 flex-wrap">
                          <span className="flex items-center gap-1 font-medium text-slate-700">
                            <Calendar className="h-3 w-3" />
                            {formatSafeLocalDate(a.date)}
                          </span>
                          <span>•</span>
                          <span className="flex items-center gap-1">
                            <Clock className="h-3 w-3" />
                            {a.time}
                          </span>
                          <span>•</span>
                          <span>{a.type}</span>
                          {a.modality && (
                            <>
                              <span>•</span>
                              <span className="flex items-center gap-1">
                                {a.modality === 'Virtual' ? (
                                  <Video className="h-3 w-3" />
                                ) : (
                                  <MapPin className="h-3 w-3" />
                                )}
                                {a.modality}
                              </span>
                            </>
                          )}
                          {resp && (
                            <>
                              <span>•</span>
                              <span className="bg-slate-100 px-1.5 py-0.5 rounded text-[10px]">
                                Resp: <span className="font-medium">{resp.name.split(' ')[0]}</span>
                              </span>
                            </>
                          )}
                        </div>
                      </div>
                      <div className="flex items-center gap-2 shrink-0">
                        {a.status !== 'Concluído' && (
                          <Button
                            variant="outline"
                            size="sm"
                            className="h-7 px-2 text-green-600 border-green-200 hover:text-green-700 hover:bg-green-50 hover:border-green-300 transition-colors"
                            onClick={(e) => {
                              e.stopPropagation()
                              updateItem('appointments', a.id, { status: 'Concluído' })
                              toast({
                                title: 'Sucesso',
                                description: 'Compromisso marcado como concluído.',
                              })
                            }}
                          >
                            <Check className="h-3 w-3 mr-1" />
                            Concluir
                          </Button>
                        )}
                        <Badge
                          variant="outline"
                          className={
                            a.status === 'Concluído'
                              ? 'bg-green-50 text-green-700 border-green-200'
                              : ''
                          }
                        >
                          {a.status}
                        </Badge>
                      </div>
                    </div>
                  )
                })}
                {processAppointments.length === 0 && (
                  <p className="text-sm text-muted-foreground text-center py-6 bg-muted/20 border border-dashed rounded">
                    Nenhum compromisso vinculado.
                  </p>
                )}
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="despesas" className="mt-4">
          <div className="grid gap-4 md:grid-cols-3 mb-4">
            <Card className="shadow-sm bg-slate-50">
              <CardHeader className="pb-2">
                <CardTitle className="text-sm font-medium text-slate-600">
                  Saldo do Processo
                </CardTitle>
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">
                  R$ {(income - expense).toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
                </div>
              </CardContent>
            </Card>
            <Card className="shadow-sm bg-red-50 border-red-100">
              <CardHeader className="pb-2">
                <CardTitle className="text-sm font-medium text-red-800">
                  Despesas / Custas
                </CardTitle>
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold text-red-700">
                  R$ {expense.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
                </div>
              </CardContent>
            </Card>
            <Card className="shadow-sm bg-green-50 border-green-100">
              <CardHeader className="pb-2">
                <CardTitle className="text-sm font-medium text-green-800">
                  Receitas / Alvarás
                </CardTitle>
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold text-green-700">
                  R$ {income.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
                </div>
              </CardContent>
            </Card>
          </div>

          <Card className="shadow-sm">
            <CardHeader className="flex flex-row items-center justify-between pb-2">
              <CardTitle className="text-lg flex items-center gap-2">
                <DollarSign className="h-5 w-5" /> Movimentações Financeiras
              </CardTitle>
              <Button size="sm" onClick={() => setCreatingTransaction(true)}>
                <Plus className="h-4 w-4 mr-2" /> Novo Lançamento
              </Button>
            </CardHeader>
            <CardContent>
              <div className="space-y-2 mt-2">
                {processTransactions.map((t) => (
                  <div
                    key={t.id}
                    className="flex justify-between items-center border p-3 rounded hover:bg-slate-50 cursor-pointer transition-colors group"
                    onClick={() => setEditingTransaction(t)}
                  >
                    <div>
                      <p className="font-semibold text-sm group-hover:text-primary flex items-center gap-2">
                        {t.description}
                        <Edit className="h-3 w-3 opacity-0 group-hover:opacity-100 transition-opacity text-muted-foreground" />
                      </p>
                      <div className="text-xs text-muted-foreground flex items-center gap-2 mt-1">
                        <span>{formatSafeLocalDate(t.date)}</span>
                        <span>•</span>
                        <span>{t.category}</span>
                      </div>
                    </div>
                    <div className="text-right flex items-center gap-3">
                      <div className="text-right">
                        <p
                          className={`font-bold ${t.type === 'income' ? 'text-green-600' : 'text-red-600'}`}
                        >
                          {t.type === 'income' ? '+' : '-'} R${' '}
                          {t.amount.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
                        </p>
                        <Badge
                          variant="outline"
                          className={`mt-1 text-[10px] ${
                            t.status === 'Pago' || t.status === 'Realizado'
                              ? 'border-green-200 text-green-700 bg-green-50'
                              : t.status === 'Atrasado'
                                ? 'border-red-200 text-red-700 bg-red-50'
                                : 'border-orange-200 text-orange-700 bg-orange-50'
                          }`}
                        >
                          {t.status}
                        </Badge>
                      </div>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8 text-red-500 hover:text-red-700 hover:bg-red-50 shrink-0 opacity-0 group-hover:opacity-100 transition-opacity"
                        onClick={(e) => {
                          e.stopPropagation()
                          if (confirm('Deseja excluir este lançamento?')) {
                            deleteItem('transactions', t.id)
                          }
                        }}
                      >
                        <Trash className="h-4 w-4" />
                      </Button>
                    </div>
                  </div>
                ))}
                {processTransactions.length === 0 && (
                  <p className="text-sm text-muted-foreground text-center py-6 bg-muted/20 border border-dashed rounded">
                    Nenhuma movimentação financeira vinculada a este processo.
                  </p>
                )}
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="docs" className="mt-4">
          <Card className="shadow-sm border-primary/20 bg-primary/5">
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2 text-primary">
                <FileText className="h-5 w-5" /> Automação de Petições
              </CardTitle>
              <CardDescription>
                Gere documentos com variáveis preenchidas automaticamente baseadas nos dados deste
                processo.
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4 max-w-md">
              <div className="space-y-2">
                <Label>Selecionar Modelo</Label>
                <Select value={selectedTpl} onValueChange={setSelectedTpl}>
                  <SelectTrigger className="bg-white">
                    <SelectValue placeholder="Escolha um modelo..." />
                  </SelectTrigger>
                  <SelectContent>
                    {state.petitions.map((p) => (
                      <SelectItem key={p.id} value={p.id}>
                        {p.title}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <Button onClick={generateDoc} className="w-full" disabled={!selectedTpl}>
                <Download className="mr-2 h-4 w-4" /> Gerar Documento (.doc)
              </Button>
            </CardContent>
          </Card>

          <Card className="shadow-sm border-primary/20 bg-primary/5 mt-4">
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2 text-primary">
                <FileUp className="h-5 w-5" /> Gerar Documento de Template
              </CardTitle>
              <CardDescription>
                Selecione um template .docx para preenchimento automático e envio para assinatura.
              </CardDescription>
            </CardHeader>
            <CardContent className="max-w-md">
              <Button onClick={openTemplateDialog} className="w-full">
                <FileUp className="mr-2 h-4 w-4" /> Gerar Documento
              </Button>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="assinaturas" className="mt-4">
          <Card className="shadow-sm border-primary/20 bg-primary/5">
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2 text-primary">
                <FileSignature className="h-5 w-5" /> Assinaturas Digitais (ZapSign)
              </CardTitle>
              <CardDescription>
                Gere documentos legais e envie para assinatura digital do cliente.
              </CardDescription>
            </CardHeader>
            <CardContent className="grid grid-cols-1 md:grid-cols-3 gap-4 max-w-3xl">
              <Button
                variant="outline"
                className="h-auto py-6 flex flex-col gap-2"
                disabled={zapsignLoading !== null}
                onClick={() => handleZapSign('procuracao')}
              >
                <FileSignature className="h-6 w-6 text-primary" />
                <span className="font-medium">Procuração</span>
                <span className="text-xs text-muted-foreground">Procuração Ad Judicia</span>
                {zapsignLoading === 'procuracao' && (
                  <span className="text-xs text-primary animate-pulse">Gerando...</span>
                )}
              </Button>
              <Button
                variant="outline"
                className="h-auto py-6 flex flex-col gap-2"
                disabled={zapsignLoading !== null}
                onClick={() => handleZapSign('hipossuficiencia')}
              >
                <FileSignature className="h-6 w-6 text-primary" />
                <span className="font-medium">Hipossuficiência</span>
                <span className="text-xs text-muted-foreground">Declaração</span>
                {zapsignLoading === 'hipossuficiencia' && (
                  <span className="text-xs text-primary animate-pulse">Gerando...</span>
                )}
              </Button>
              <Button
                variant="outline"
                className="h-auto py-6 flex flex-col gap-2"
                disabled={zapsignLoading !== null}
                onClick={() => handleZapSign('contrato')}
              >
                <FileSignature className="h-6 w-6 text-primary" />
                <span className="font-medium">Contrato</span>
                <span className="text-xs text-muted-foreground">Honorários</span>
                {zapsignLoading === 'contrato' && (
                  <span className="text-xs text-primary animate-pulse">Gerando...</span>
                )}
              </Button>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  )
}
