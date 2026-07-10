import { useState } from 'react'
import { useParams, Link, useNavigate } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
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
  RefreshCw,
  Send,
  Link2,
  AlertTriangle,
} from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { ClientDialog } from '@/components/ClientDialog'
import { CaseDialog } from '@/components/CaseDialog'
import { AppointmentDialog } from '@/components/AppointmentDialog'
import { syncClientWithAsaas, cancelChargeWithAsaas, syncChargeWithAsaas } from '@/services/asaas'
import { toast } from '@/hooks/use-toast'
import { ClientFeesDialog } from '@/components/ClientFeesDialog'
import { LinkTransactionToCaseDialog } from '@/components/LinkTransactionToCaseDialog'
import { formatSafeLocalDate } from '@/lib/utils'
import { supabase } from '@/lib/supabase/client'

export default function ClientDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { state, updateItem, deleteItem, addCase, addAppointment } = useLegalStore()
  const [isEditOpen, setIsEditOpen] = useState(false)
  const [isCreatingCase, setIsCreatingCase] = useState(false)
  const [isApptOpen, setIsApptOpen] = useState(false)
  const [editingAppt, setEditingAppt] = useState<any>(null)
  const [syncingAsaas, setSyncingAsaas] = useState(false)
  const [isFeeOpen, setIsFeeOpen] = useState(false)
  const [feeToDelete, setFeeToDelete] = useState<any>(null)
  const [deletingFee, setDeletingFee] = useState(false)
  const [feeDeleteError, setFeeDeleteError] = useState<string | null>(null)
  const [syncingFeeId, setSyncingFeeId] = useState<string | null>(null)
  const [bulkSyncing, setBulkSyncing] = useState(false)
  const [linkingTx, setLinkingTx] = useState<any>(null)

  const client = state.clients.find((c) => c.id === id)
  const allCases = state.cases.filter((c) => c.clientId === id)
  const mainCases = allCases.filter((c) => !c.parentId)
  const clientAppointments = state.appointments
    .filter((a) => a.clientId === id)
    .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime())

  const clientFees = state.transactions
    .filter((t) => t.clientId === id && t.category === 'Honorários Contratuais')
    .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())

  const allClientTransactions = state.transactions
    .filter((t) => t.clientId === id)
    .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())

  const isTransactionLinked = (transactionId: string, processId: string | null) => {
    if (processId) return true
    return (state.transactionCases || []).some((tc) => tc.transaction_id === transactionId)
  }

  const getTransactionLinkedCases = (transactionId: string, processId: string | null) => {
    const linkedCaseIds = (state.transactionCases || [])
      .filter((tc) => tc.transaction_id === transactionId)
      .map((tc) => tc.case_id)
    const allLinkedIds = processId ? [...linkedCaseIds, processId] : linkedCaseIds
    return state.cases.filter((c) => allLinkedIds.includes(c.id))
  }

  const unlinkedCount = allClientTransactions.filter(
    (t) => !isTransactionLinked(t.id, t.processId),
  ).length

  const getLinkedCaseNumbers = (transactionId: string) => {
    const linkedCaseIds = (state.transactionCases || [])
      .filter((tc) => tc.transaction_id === transactionId)
      .map((tc) => tc.case_id)
    return state.cases.filter((c) => linkedCaseIds.includes(c.id)).map((c) => c.number)
  }

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

  const handleAsaasSync = async () => {
    setSyncingAsaas(true)
    const { data, error } = await syncClientWithAsaas(client.id)
    setSyncingAsaas(false)
    if (error) {
      toast({
        title: 'Erro',
        description: error.message || 'Falha ao sincronizar com ASAAS.',
        variant: 'destructive',
      })
    } else {
      const unlinkedTxCount = allClientTransactions.filter(
        (t) => !isTransactionLinked(t.id, t.processId),
      ).length
      toast({
        title: 'Sucesso',
        description:
          unlinkedTxCount > 0
            ? `${data?.message || 'Cliente sincronizado com ASAAS.'} Atenção: ${unlinkedTxCount} transação(ões) sem processo vinculado.`
            : data?.message || 'Cliente sincronizado com ASAAS.',
      })
    }
  }

  const handleFeeDelete = async (forceLocal = false) => {
    if (!feeToDelete) return
    setDeletingFee(true)
    setFeeDeleteError(null)

    if (!forceLocal && feeToDelete.asaas_id) {
      const { error: asaasError } = await cancelChargeWithAsaas(feeToDelete.id)
      if (asaasError) {
        setDeletingFee(false)
        setFeeDeleteError(asaasError.message || 'Falha ao cancelar cobrança no ASAAS.')
        return
      }
    }

    await deleteItem('transactions', feeToDelete.id)
    setDeletingFee(false)
    setFeeToDelete(null)
    setFeeDeleteError(null)
    toast({ title: 'Honorário excluído com sucesso.' })
  }

  const handleFeeAsaasSync = async (transactionId: string) => {
    setSyncingFeeId(transactionId)
    const { data, error } = await syncChargeWithAsaas(transactionId)
    setSyncingFeeId(null)
    if (error) {
      toast({
        title: 'Erro',
        description: error.message || 'Falha ao enviar para ASAAS.',
        variant: 'destructive',
      })
    } else {
      if (data?.asaas_id) {
        updateItem('transactions', transactionId, { asaas_id: data.asaas_id })
      }
      toast({
        title: 'Sucesso',
        description: data?.message || 'Cobrança enviada para ASAAS.',
      })
    }
  }

  const handleBulkAsaasSync = async () => {
    const pendingFees = clientFees.filter((t) => !t.asaas_id)
    if (pendingFees.length === 0) {
      toast({ title: 'Todas as cobranças já foram sincronizadas com o ASAAS.' })
      return
    }
    setBulkSyncing(true)
    let successCount = 0
    let errorCount = 0
    let lastErrorMsg = ''
    for (const fee of pendingFees) {
      const { data, error } = await syncChargeWithAsaas(fee.id)
      if (error) {
        errorCount++
        lastErrorMsg = error.message || 'Erro desconhecido'
      } else {
        successCount++
        if (data?.asaas_id) {
          updateItem('transactions', fee.id, { asaas_id: data.asaas_id })
        }
      }
    }
    setBulkSyncing(false)
    const unlinkedTxCount = allClientTransactions.filter(
      (t) => !isTransactionLinked(t.id, t.processId),
    ).length

    if (errorCount > 0) {
      toast({
        title: 'Sincronização parcial',
        description: `${successCount} cobrança(s) enviada(s) com sucesso. ${errorCount} falha(s). Último erro: ${lastErrorMsg}`,
        variant: 'destructive',
      })
    } else if (unlinkedTxCount > 0) {
      toast({
        title: 'Sucesso',
        description: `${successCount} cobrança(s) enviada(s) para o ASAAS. Atenção: ${unlinkedTxCount} transação(ões) sem processo vinculado.`,
      })
    } else {
      toast({
        title: 'Sucesso',
        description: `${successCount} cobrança(s) enviada(s) para o ASAAS.`,
      })
    }
  }

  const handleLinkToCase = async (transactionId: string, caseId: string) => {
    const { error: tcError } = await supabase
      .from('transaction_cases')
      .upsert(
        { transaction_id: transactionId, case_id: caseId },
        { onConflict: 'transaction_id,case_id' },
      )

    if (tcError) {
      toast({
        title: 'Erro',
        description: 'Falha ao vincular processo.',
        variant: 'destructive',
      })
      return
    }

    await updateItem('transactions', transactionId, { processId: caseId })

    toast({ title: 'Sucesso', description: 'Processo vinculado com sucesso.' })
    setLinkingTx(null)
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

      <ClientFeesDialog
        open={isFeeOpen}
        onOpenChange={setIsFeeOpen}
        clientId={client.id}
        cases={allCases}
      />

      <LinkTransactionToCaseDialog
        open={!!linkingTx}
        onOpenChange={(v: boolean) => !v && setLinkingTx(null)}
        transaction={linkingTx}
        cases={allCases}
        onLink={handleLinkToCase}
      />

      <AlertDialog
        open={!!feeToDelete}
        onOpenChange={(v) => {
          if (!v) {
            setFeeToDelete(null)
            setFeeDeleteError(null)
          }
        }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Excluir Honorário?</AlertDialogTitle>
            <AlertDialogDescription>
              {feeDeleteError
                ? `Erro ao cancelar no ASAAS: ${feeDeleteError}. Deseja excluir apenas localmente?`
                : 'Esta ação é irreversível. O registro será removido e, se houver cobrança no ASAAS, será cancelada.'}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={deletingFee}>Cancelar</AlertDialogCancel>
            {feeDeleteError ? (
              <>
                <AlertDialogAction
                  onClick={() => handleFeeDelete(true)}
                  disabled={deletingFee}
                  className="bg-amber-600 hover:bg-amber-700"
                >
                  Excluir apenas local
                </AlertDialogAction>
                <AlertDialogAction onClick={() => handleFeeDelete(false)} disabled={deletingFee}>
                  Tentar novamente
                </AlertDialogAction>
              </>
            ) : (
              <AlertDialogAction
                onClick={() => handleFeeDelete(false)}
                disabled={deletingFee}
                className="bg-red-600 hover:bg-red-700"
              >
                {deletingFee ? 'Excluindo...' : 'Excluir'}
              </AlertDialogAction>
            )}
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

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
            <Button variant="outline" size="sm" onClick={handleAsaasSync} disabled={syncingAsaas}>
              <RefreshCw className={`h-4 w-4 mr-2 ${syncingAsaas ? 'animate-spin' : ''}`} />
              {syncingAsaas ? 'Sincronizando...' : 'Sincronizar com ASAAS'}
            </Button>
            {state.currentUser.role === 'Admin' && (
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
                    <AlertDialogAction
                      onClick={handleDelete}
                      className="bg-red-600 hover:bg-red-700"
                    >
                      Excluir
                    </AlertDialogAction>
                  </AlertDialogFooter>
                </AlertDialogContent>
              </AlertDialog>
            )}
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
                <MessageCircle className="h-4 w-4" /> Celular
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
                <MapPin className="h-4 w-4" /> CEP
              </p>
              <p className="font-medium text-sm">{client.cep || 'Não informado'}</p>
            </div>
            <div>
              <p className="text-sm text-muted-foreground flex items-center gap-2">
                <MapPin className="h-4 w-4" /> Rua
              </p>
              <p className="font-medium text-sm">
                {client.street || client.address || 'Não informado'}
              </p>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-sm text-muted-foreground">Número</p>
                <p className="font-medium text-sm">{client.number || 'Não informado'}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Complemento</p>
                <p className="font-medium text-sm">{client.complement || 'Não informado'}</p>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-sm text-muted-foreground">Bairro</p>
                <p className="font-medium text-sm">{client.neighborhood || 'Não informado'}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Cidade</p>
                <p className="font-medium text-sm">{client.city || 'Não informado'}</p>
              </div>
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

      <div className="grid gap-6 md:grid-cols-1">
        <Card className="shadow-sm">
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-lg flex items-center gap-2">
              <FileText className="h-5 w-5" /> HONORÁRIOS ({clientFees.length})
            </CardTitle>
            <div className="flex items-center gap-2">
              <Button
                variant="outline"
                size="sm"
                onClick={handleBulkAsaasSync}
                disabled={bulkSyncing || !clientFees.some((t) => !t.asaas_id)}
              >
                <Send className={`h-4 w-4 mr-2 ${bulkSyncing ? 'animate-pulse' : ''}`} />
                {bulkSyncing ? 'Enviando...' : 'Enviar todas para o ASSAS'}
              </Button>
              <Button variant="outline" size="sm" onClick={() => setIsFeeOpen(true)}>
                <Plus className="h-4 w-4 mr-2" /> Novo Honorário
              </Button>
            </div>
          </CardHeader>
          <CardContent>
            {clientFees.length === 0 ? (
              <p className="text-muted-foreground text-sm">
                Nenhum honorário cadastrado para este cliente.
              </p>
            ) : (
              <div className="space-y-3 mt-2">
                {clientFees.map((t) => {
                  const linkedNumbers = getLinkedCaseNumbers(t.id)
                  return (
                    <div
                      key={t.id}
                      className="flex flex-col sm:flex-row sm:items-center justify-between border p-4 rounded-lg hover:bg-slate-50 transition-colors gap-4"
                    >
                      <div className="flex flex-col gap-1">
                        <span className="font-semibold text-sm">{t.description}</span>
                        <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                          <span>Vencimento: {formatSafeLocalDate(t.date)}</span>
                          {linkedNumbers.length > 0 ? (
                            <span>• Processos: {linkedNumbers.join(', ')}</span>
                          ) : (
                            <span className="text-amber-600 font-medium">
                              • Sem processo vinculado
                            </span>
                          )}
                        </div>
                      </div>
                      <div className="flex items-center gap-3">
                        <span className="font-bold text-green-600 text-sm">
                          R$ {t.amount.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
                        </span>
                        <Badge
                          variant={
                            t.status === 'Pago' || t.status === 'Realizado'
                              ? 'secondary'
                              : 'default'
                          }
                        >
                          {t.status}
                        </Badge>
                        {t.asaas_id ? (
                          <Badge
                            variant="outline"
                            className="text-[10px] bg-blue-50 text-blue-700 border-blue-200"
                          >
                            ASAAS
                          </Badge>
                        ) : (
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-8 w-8 text-blue-500 hover:text-blue-700 hover:bg-blue-50"
                            onClick={() => handleFeeAsaasSync(t.id)}
                            disabled={syncingFeeId === t.id}
                            title="Enviar para o ASSAS"
                          >
                            <Send
                              className={`h-4 w-4 ${syncingFeeId === t.id ? 'animate-pulse' : ''}`}
                            />
                          </Button>
                        )}
                        {!isTransactionLinked(t.id, t.processId) && (
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-8 w-8 text-amber-500 hover:text-amber-700 hover:bg-amber-50"
                            onClick={() => setLinkingTx(t)}
                            title="Vincular a um Processo"
                          >
                            <Link2 className="h-4 w-4" />
                          </Button>
                        )}
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-8 w-8 text-red-500 hover:text-red-700 hover:bg-red-50"
                          onClick={() => {
                            setFeeToDelete(t)
                            setFeeDeleteError(null)
                          }}
                        >
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </div>
                    </div>
                  )
                })}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-6 md:grid-cols-1">
        <Card className="shadow-sm">
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-lg flex items-center gap-2">
              <FileText className="h-5 w-5" /> Transações Financeiras (
              {allClientTransactions.length})
              {unlinkedCount > 0 && (
                <Badge variant="destructive" className="ml-2 text-xs">
                  {unlinkedCount} sem vínculo
                </Badge>
              )}
            </CardTitle>
          </CardHeader>
          <CardContent>
            {allClientTransactions.length === 0 ? (
              <p className="text-muted-foreground text-sm">
                Nenhuma transação financeira cadastrada para este cliente.
              </p>
            ) : (
              <div className="rounded-md border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Data</TableHead>
                      <TableHead>Descrição</TableHead>
                      <TableHead>Categoria</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead className="text-right">Valor</TableHead>
                      <TableHead>Processo Vinculado</TableHead>
                      <TableHead className="w-[120px]"></TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {allClientTransactions.map((t) => {
                      const linked = isTransactionLinked(t.id, t.processId)
                      const linkedCases = getTransactionLinkedCases(t.id, t.processId)
                      return (
                        <TableRow key={t.id} className="group">
                          <TableCell className="text-sm">{formatSafeLocalDate(t.date)}</TableCell>
                          <TableCell className="font-medium text-sm">{t.description}</TableCell>
                          <TableCell className="text-sm">{t.category}</TableCell>
                          <TableCell>
                            <Badge
                              variant="outline"
                              className={
                                t.status === 'Pago' || t.status === 'Realizado'
                                  ? 'border-green-200 text-green-700 bg-green-50'
                                  : t.status === 'Atrasado'
                                    ? 'border-red-200 text-red-700 bg-red-50'
                                    : 'border-orange-200 text-orange-700 bg-orange-50'
                              }
                            >
                              {t.status}
                            </Badge>
                          </TableCell>
                          <TableCell
                            className={`text-right font-bold text-sm ${t.type === 'income' ? 'text-green-600' : 'text-red-600'}`}
                          >
                            {t.type === 'income' ? '+' : '-'} R${' '}
                            {t.amount.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
                          </TableCell>
                          <TableCell>
                            {linked ? (
                              <div className="flex flex-wrap gap-1">
                                {linkedCases.map((c) => (
                                  <Badge key={c.id} variant="secondary" className="text-[10px]">
                                    {c.number}
                                  </Badge>
                                ))}
                              </div>
                            ) : (
                              <Badge
                                variant="outline"
                                className="text-[10px] bg-amber-50 text-amber-700 border-amber-300"
                              >
                                <AlertTriangle className="h-3 w-3 mr-1" />
                                Sem vínculo
                              </Badge>
                            )}
                          </TableCell>
                          <TableCell>
                            {!linked && (
                              <Button
                                variant="outline"
                                size="sm"
                                className="text-xs h-7"
                                onClick={() => setLinkingTx(t)}
                              >
                                <Link2 className="h-3 w-3 mr-1" />
                                Vincular a um Processo
                              </Button>
                            )}
                          </TableCell>
                        </TableRow>
                      )
                    })}
                  </TableBody>
                </Table>
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
