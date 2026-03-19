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
} from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'
import { CaseDialog } from '@/components/CaseDialog'
import { TaskDialog } from '@/components/TaskDialog'
import { AppointmentDialog } from '@/components/AppointmentDialog'
import { formatSafeLocalDate } from '@/lib/utils'

export default function CaseDetail() {
  const { id } = useParams<{ id: string }>()
  const { state, updateItem, addCase, addTask, addAppointment } = useLegalStore()
  const [selectedTpl, setSelectedTpl] = useState<string>('')
  const [isCaseOpen, setIsCaseOpen] = useState(false)
  const [editingTask, setEditingTask] = useState<any>(null)
  const [creatingTask, setCreatingTask] = useState(false)
  const [creatingSubcase, setCreatingSubcase] = useState(false)

  const [editingAppointment, setEditingAppointment] = useState<any>(null)
  const [creatingAppointment, setCreatingAppointment] = useState(false)

  const c = state.cases.find((x) => x.id === id)
  const client = state.clients.find((cl) => cl.id === c?.clientId)
  const tasks = state.tasks.filter((t) => t.relatedProcessId === id)
  const subcases = state.cases.filter((sc) => sc.parentId === id)
  const processAppointments = state.appointments.filter((a) => a.processId === id)

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
      .replace(/{{comarca}}/g, c.comarca || '')

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
        onSave={(d: any) => updateItem('tasks', d.id, d)}
        users={state.users}
        clients={state.clients}
        cases={state.cases}
        settings={state.settings}
      />
      <TaskDialog
        open={creatingTask}
        onOpenChange={setCreatingTask}
        data={{ clientId: c.clientId, isNew: true }}
        lockedProcessId={c.id}
        onSave={(d: any) => addTask(d)}
        users={state.users}
        clients={state.clients}
        cases={state.cases}
        settings={state.settings}
      />
      <AppointmentDialog
        open={!!editingAppointment}
        onOpenChange={(v: boolean) => !v && setEditingAppointment(null)}
        data={editingAppointment}
        onSave={(d: any) => updateItem('appointments', d.id, d)}
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

      <div className="flex items-start gap-4">
        <Button variant="outline" size="icon" asChild>
          <Link to="/processos">
            <ArrowLeft className="h-4 w-4" />
          </Link>
        </Button>
        <div>
          <div className="flex items-center gap-3 flex-wrap">
            <h1 className="text-2xl md:text-3xl font-bold tracking-tight text-primary flex items-center gap-3 break-all">
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
          </div>
          <p className="text-muted-foreground mt-1">
            <Badge variant="outline">{c.status}</Badge> • Sistema: {c.system}
          </p>
        </div>
      </div>

      <Tabs defaultValue="info" className="w-full">
        <TabsList className="grid w-full grid-cols-2 sm:grid-cols-3 md:grid-cols-5 h-auto max-w-3xl gap-1 p-1">
          <TabsTrigger value="info">Informações</TabsTrigger>
          <TabsTrigger value="subprocessos">Subprocessos</TabsTrigger>
          <TabsTrigger value="tasks">Tarefas</TabsTrigger>
          <TabsTrigger value="agenda">Agenda</TabsTrigger>
          <TabsTrigger value="docs">Documentos</TabsTrigger>
        </TabsList>

        <TabsContent value="info" className="mt-4 grid gap-6 md:grid-cols-2">
          <Card className="shadow-sm">
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <Users className="h-5 w-5" /> Partes
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div>
                <p className="text-sm text-muted-foreground">Cliente ({c.position})</p>
                {client ? (
                  <Link
                    to={`/clientes/${client.id}`}
                    className="font-medium text-primary hover:underline"
                  >
                    {client.name}
                  </Link>
                ) : (
                  <p className="font-medium text-muted-foreground">—</p>
                )}
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Parte Adversa</p>
                <p className="font-medium">{c.adverseParty}</p>
              </div>
            </CardContent>
          </Card>
          <Card className="shadow-sm">
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <Scale className="h-5 w-5" /> Juízo
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div>
                <p className="text-sm text-muted-foreground">Vara</p>
                <p className="font-medium">{c.court}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Comarca / UF</p>
                <p className="font-medium">
                  {c.comarca} - {c.state}
                </p>
              </div>
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
              <div className="space-y-2 mt-2">
                {subcases.map((sc) => (
                  <div
                    key={sc.id}
                    className="flex justify-between items-center border p-3 rounded hover:bg-slate-50 transition-colors"
                  >
                    <div>
                      <Link
                        to={`/processos/${sc.id}`}
                        className="font-semibold text-primary hover:underline flex items-center gap-2"
                      >
                        {sc.number}
                      </Link>
                      <div className="text-xs text-muted-foreground mt-1 flex gap-2">
                        <span>{sc.type}</span>
                        <span>•</span>
                        <span>{sc.court}</span>
                      </div>
                    </div>
                    <Badge variant="outline">{sc.status}</Badge>
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
                  return (
                    <div
                      key={t.id}
                      className="flex flex-col border p-3 rounded-lg hover:bg-slate-50 hover:border-primary/30 cursor-pointer transition-all group"
                      onClick={() => setEditingTask(t)}
                    >
                      <div className="flex justify-between items-start">
                        <div>
                          <p className="font-semibold text-sm group-hover:text-primary transition-colors flex items-center gap-2">
                            {t.title}
                            <Edit className="h-3 w-3 opacity-0 group-hover:opacity-100 transition-opacity text-muted-foreground" />
                          </p>
                          <div className="text-xs text-muted-foreground flex items-center gap-2 mt-1">
                            <span>Vencimento: {formatSafeLocalDate(t.dueDate)}</span>
                            {resp && (
                              <span className="bg-slate-100 px-1.5 py-0.5 rounded text-[10px]">
                                Resp: <span className="font-medium">{resp.name.split(' ')[0]}</span>
                              </span>
                            )}
                          </div>
                        </div>
                        <Badge variant="outline" className="shrink-0">
                          {t.status}
                        </Badge>
                      </div>
                      {t.description && (
                        <div className="text-sm text-muted-foreground bg-muted/30 p-2.5 rounded-md border border-border/50 line-clamp-3 whitespace-pre-wrap mt-2">
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
                      <Badge variant="outline">{a.status}</Badge>
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

        <TabsContent value="docs" className="mt-4">
          <Card className="shadow-sm border-blue-200 bg-blue-50/30">
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2 text-blue-800">
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
        </TabsContent>
      </Tabs>
    </div>
  )
}
