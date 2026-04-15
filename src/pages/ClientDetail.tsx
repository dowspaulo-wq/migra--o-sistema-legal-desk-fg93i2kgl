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
} from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { ClientDialog } from '@/components/ClientDialog'
import { CaseDialog } from '@/components/CaseDialog'

export default function ClientDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { state, updateItem, deleteItem, addCase } = useLegalStore()
  const [isEditOpen, setIsEditOpen] = useState(false)
  const [isCreatingCase, setIsCreatingCase] = useState(false)

  const client = state.clients.find((c) => c.id === id)
  const cases = state.cases.filter((c) => c.clientId === id && !c.parentId)

  if (!client) return <div className="p-8 text-center">Cliente não encontrado.</div>

  const handleDelete = async () => {
    await deleteItem('clients', client.id)
    navigate('/clientes')
  }

  return (
    <div className="space-y-6">
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
              <FileText className="h-5 w-5" /> Processos Vinculados ({cases.length})
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {cases.map((c) => (
                <div
                  key={c.id}
                  className="flex justify-between items-center border p-4 rounded-lg hover:bg-slate-50"
                >
                  <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-4 w-full">
                    <div>
                      <p className="text-xs text-muted-foreground mb-1">Número do Processo</p>
                      <Link
                        to={`/processos/${c.id}`}
                        className="font-bold text-primary hover:underline block truncate"
                        title={c.number}
                      >
                        {c.number}
                      </Link>
                    </div>
                    <div>
                      <p className="text-xs text-muted-foreground mb-1">Assunto / Tipo</p>
                      <p className="text-sm font-medium truncate" title={c.type}>
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
                </div>
              ))}
              {cases.length === 0 && (
                <p className="text-muted-foreground text-sm">Nenhum processo vinculado.</p>
              )}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
