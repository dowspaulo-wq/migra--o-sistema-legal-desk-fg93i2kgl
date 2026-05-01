import { useState } from 'react'
import { useParams, Link, useNavigate } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog'
import {
  ArrowLeft,
  User,
  MapPin,
  Mail,
  MessageCircle,
  FileText,
  Trash2,
  Edit,
  Plus,
  Star,
  Calendar,
} from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { ClientDialog } from '@/components/ClientDialog'
import { CaseDialog } from '@/components/CaseDialog'
import { AppointmentDialog } from '@/components/AppointmentDialog'

export default function ClientDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { state, updateItem, deleteItem, addCase, addAppointment } = useLegalStore()
  const [isEditOpen, setIsEditOpen] = useState(false)
  const [isCreatingCase, setIsCreatingCase] = useState(false)
  const [isApptOpen, setIsApptOpen] = useState(false)
  const [editingAppt, setEditingAppt] = useState<any>(null)

  const client = state.clients.find((c) => c.id === id)
  const allCases = state.cases.filter((c) => c.clientId === id)
  const mainCases = allCases.filter((c) => !c.parentId)
  const clientAppointments = state.appointments
    .filter((a) => a.clientId === id)
    .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime())

  if (!client) return <div className="p-8 text-center">Cliente não encontrado.</div>

  const handleDelete = async () => {
    await deleteItem('clients', client.id)
    navigate('/clientes')
  }

  const handleApptSave = (fd: any) => {
    if (editingAppt?.id) updateItem('appointments', editingAppt.id, fd)
    else addAppointment(fd)
  }

  const handleApptDelete = (item: any) => {
    deleteItem('appointments', item.id)
  }

  return (
    <div className="space-y-6">
      <AppointmentDialog
        open={isApptOpen}
        onOpenChange={setIsApptOpen}
        data={editingAppt}
        onSave={handleApptSave}
        onDelete={handleApptDelete}
        users={state.users}
        clients={state.clients}
        cases={state.cases}
        settings={state.settings}
      />

      <ClientDialog
        open={isEditOpen}
        onOpenChange={setIsEditOpen}
        client={client}
        onSave={(d: any) => updateItem('clients', d.id, d)}
        users={state.users}
        settings={state.settings}
      />

      <CaseDialog
        open={isCreatingCase}
        onOpenChange={setIsCreatingCase}
        data={{ clientId: client.id, isNew: true }}
        lockedClientId={client.id}
        onSave={(d: any) => addCase(d)}
        users={state.users}
        clients={state.clients}
        settings={state.settings}
      />

      <div className="flex items-start gap-4">
        <Button variant="outline" size="icon" asChild>
          <Link to="/clientes">
            <ArrowLeft className="h-4 w-4" />
          </Link>
        </Button>
        <div className="flex-1">
          <div className="flex items-center flex-wrap gap-3">
            <h1 className="text-3xl font-bold tracking-tight flex items-center gap-2 text-slate-800 dark:text-slate-100">
              {client.name} {client.isSpecial && <span className="text-yellow-400">★</span>}
            </h1>
            <Button variant="outline" size="sm" onClick={() => setIsEditOpen(true)}>
              <Edit className="h-4 w-4 mr-2" /> Editar
            </Button>
            <Button variant="default" size="sm" onClick={() => setIsCreatingCase(true)}>
              <Plus className="h-4 w-4 mr-2" /> Cadastrar novo processo
            </Button>
            <AlertDialog>
              <AlertDialogTrigger asChild>
                <Button variant="destructive" size="sm">
                  <Trash2 className="h-4 w-4 mr-2" /> Excluir
                </Button>
              </AlertDialogTrigger>
              <AlertDialogContent>
                <AlertDialogHeader>
                  <AlertDialogTitle>Excluir Cliente?</AlertDialogTitle>
                  <AlertDialogDescription>
                    Esta ação é irreversível. Isso removerá o cliente e todo o seu histórico
                    (processos, tarefas e agendamentos).
                  </AlertDialogDescription>
                </AlertDialogHeader>
                <AlertDialogFooter>
                  <AlertDialogCancel>Cancelar</AlertDialogCancel>
                  <AlertDialogAction onClick={handleDelete} className="bg-red-600 hover:bg-red-700">
                    Excluir
                  </AlertDialogAction>
                </AlertDialogFooter>
              </AlertDialogContent>
            </AlertDialog>
          </div>
          <p className="text-muted-foreground flex items-center gap-2 mt-1">
            <Badge variant={client.status === 'Ativo' ? 'default' : 'secondary'}>
              {client.status}
            </Badge>
            {client.type} - {client.document}
          </p>
        </div>
      </div>

      <div className="grid gap-6 md:grid-cols-3">
        <Card className="md:col-span-1 shadow-sm">
          <CardHeader>
            <CardTitle className="text-lg flex items-center gap-2">
              <User className="h-5 w-5" /> Informações
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div>
              <p className="text-sm text-muted-foreground flex items-center gap-2">
                <Mail className="h-4 w-4" /> Email
              </p>
              <p className="font-medium text-sm">{client.email || 'Não informado'}</p>
            </div>
            <div>
              <p className="text-sm text-muted-foreground flex items-center gap-2">
                <MessageCircle className="h-4 w-4" /> Telefone
              </p>
              <p className="font-medium flex items-center gap-2 text-sm">
                {client.phone || 'Não informado'}
                {client.phone && (
                  <a
                    href={`https://wa.me/${client.phone.replace(/\D/g, '')}`}
                    target="_blank"
                    className="text-green-500 hover:scale-110 transition-transform"
                    rel="noreferrer"
                  >
                    <MessageCircle className="h-4 w-4" />
                  </a>
                )}
              </p>
            </div>
            <div>
              <p className="text-sm text-muted-foreground flex items-center gap-2">
                <MapPin className="h-4 w-4" /> Endereço
              </p>
              <p className="font-medium text-sm">{client.address || 'Não informado'}</p>
            </div>
          </CardContent>
        </Card>

        <Card className="md:col-span-2 shadow-sm">
          <CardHeader>
            <CardTitle className="text-lg flex items-center gap-2">
              <FileText className="h-5 w-5" /> Processos Vinculados ({mainCases.length})
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {mainCases.map((c) => {
                const subCases = allCases.filter((sub) => sub.parentId === c.id)
                return (
                  <div key={c.id} className="space-y-2">
                    <div className="flex flex-col border p-4 rounded-lg hover:bg-slate-50 gap-3 transition-colors bg-white">
                      <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-5 gap-4 w-full">
                        <div>
                          <p className="text-xs text-muted-foreground mb-1">Número do Processo</p>
                          <div className="flex items-center gap-1">
                            <Link
                              to={`/processos/${c.id}`}
                              className="font-bold text-primary hover:underline block truncate"
                              title={c.number}
                            >
                              {c.number}
                            </Link>
                            {c.isSpecial && (
                              <Star
                                className="h-4 w-4 fill-yellow-400 text-yellow-400 shrink-0"
                                title="Especial"
                              />
                            )}
                          </div>
                        </div>
                        <div>
                          <p className="text-xs text-muted-foreground mb-1">Parte Adversa</p>
                          <p className="text-sm font-medium truncate" title={c.adverseParty || ''}>
                            {c.adverseParty || 'Não informada'}
                          </p>
                        </div>
                        <div>
                          <p className="text-xs text-muted-foreground mb-1">Assunto / Tipo</p>
                          <p className="text-sm font-medium truncate" title={c.type || ''}>
                            {c.type || 'Não informado'}
                          </p>
                        </div>
                        <div>
                          <p className="text-xs text-muted-foreground mb-1">Status</p>
                          <Badge variant="outline">{c.status}</Badge>
                        </div>
                        <div>
                          <p className="text-xs text-muted-foreground mb-1">Classificação</p>
                          <Badge variant="secondary">{c.classification || 'SB'}</Badge>
                        </div>
                      </div>
                      {c.alerts && (
                        <div className="flex gap-1 flex-wrap pt-2 border-t border-slate-100">
                          {c.alerts.split(',').map((a) => (
                            <Badge
                              key={a}
                              variant="secondary"
                              className="text-[10px] bg-red-50 text-red-700 border-red-200"
                            >
                              {a.trim()}
                            </Badge>
                          ))}
                        </div>
                      )}
                    </div>

                    {subCases.length > 0 && (
                      <div className="pl-8 space-y-2 relative before:absolute before:inset-y-0 before:left-4 before:w-px before:bg-slate-200">
                        {subCases.map((sub) => (
                          <div
                            key={sub.id}
                            className="flex flex-col border border-slate-100 p-3 rounded-lg hover:bg-slate-50 gap-2 transition-colors bg-slate-50/50 relative"
                          >
                            <div className="absolute top-1/2 -left-4 w-4 h-px bg-slate-200" />
                            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-4 w-full">
                              <div>
                                <p className="text-[10px] text-muted-foreground mb-1">
                                  Nº do Subprocesso
                                </p>
                                <div className="flex items-center gap-1">
                                  <Link
                                    to={`/processos/${sub.id}`}
                                    className="font-bold text-sm text-primary hover:underline block truncate"
                                    title={sub.number}
                                  >
                                    {sub.number}
                                  </Link>
                                  {sub.isSpecial && (
                                    <Star
                                      className="h-3 w-3 fill-yellow-400 text-yellow-400 shrink-0"
                                      title="Especial"
                                    />
                                  )}
                                </div>
                              </div>
                              <div>
                                <p className="text-[10px] text-muted-foreground mb-1">Tipo</p>
                                <p className="text-sm font-medium truncate" title={sub.type || ''}>
                                  {sub.type || 'Não informado'}
                                </p>
                              </div>
                              <div>
                                <p className="text-[10px] text-muted-foreground mb-1">Status</p>
                                <Badge variant="outline" className="text-[10px]">
                                  {sub.status}
                                </Badge>
                              </div>
                              <div>
                                <p className="text-[10px] text-muted-foreground mb-1">
                                  Classificação
                                </p>
                                <Badge variant="secondary" className="text-[10px]">
                                  {sub.classification || 'SB'}
                                </Badge>
                              </div>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                )
              })}
              {mainCases.length === 0 && (
                <p className="text-muted-foreground text-sm">Nenhum processo vinculado.</p>
              )}
            </div>
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-6 md:grid-cols-1">
        <Card className="shadow-sm">
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-lg flex items-center gap-2">
              <Calendar className="h-5 w-5" /> Compromissos ({clientAppointments.length})
            </CardTitle>
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                setEditingAppt({
                  title: '',
                  date: new Date().toISOString().split('T')[0],
                  time: '10:00',
                  type: '',
                  priority: '',
                  responsibleId: '',
                  clientId: client.id,
                  processId: '',
                  description: '',
                  modality: '',
                  status: 'Pendente',
                })
                setIsApptOpen(true)
              }}
            >
              <Plus className="h-4 w-4 mr-2" /> Novo Compromisso
            </Button>
          </CardHeader>
          <CardContent>
            {clientAppointments.length === 0 ? (
              <p className="text-muted-foreground text-sm">
                Nenhum compromisso agendado para este cliente.
              </p>
            ) : (
              <div className="space-y-3 mt-2">
                {clientAppointments.map((a) => (
                  <div
                    key={a.id}
                    className="flex flex-col sm:flex-row sm:items-center justify-between border p-4 rounded-lg hover:bg-slate-50 transition-colors gap-4"
                  >
                    <div className="flex flex-col gap-1">
                      <span className="font-semibold text-sm">{a.title}</span>
                      <span className="text-xs text-muted-foreground">
                        {a.date.split('T')[0].split('-').reverse().join('/')} às {a.time} - {a.type}
                      </span>
                    </div>
                    <div className="flex items-center gap-3">
                      <Badge variant={a.status === 'Concluído' ? 'secondary' : 'default'}>
                        {a.status}
                      </Badge>
                      <Button
                        variant="ghost"
                        size="icon"
                        onClick={() => {
                          setEditingAppt(a)
                          setIsApptOpen(true)
                        }}
                      >
                        <Edit className="h-4 w-4" />
                      </Button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
