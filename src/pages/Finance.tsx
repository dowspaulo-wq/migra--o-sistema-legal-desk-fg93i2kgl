import { useState, useMemo } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Plus,
  ArrowUpRight,
  ArrowDownRight,
  Download,
  Trash,
  Filter,
  Edit,
  Send,
} from 'lucide-react'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import { Bar, BarChart, CartesianGrid, XAxis, YAxis, ResponsiveContainer } from 'recharts'
import { ChartContainer, ChartTooltip, ChartTooltipContent } from '@/components/ui/chart'
import useLegalStore from '@/stores/useLegalStore'
import { Navigate } from 'react-router-dom'
import { downloadCSV } from '@/lib/export'
import { TransactionDialog } from '@/components/TransactionDialog'
import { formatSafeLocalDate } from '@/lib/utils'
import { SupplierDialog } from '@/components/SupplierDialog'
import { syncChargeWithAsaas, cancelChargeWithAsaas, syncHistoryWithAsaas } from '@/services/asaas'
import { LinkTransactionToCaseDialog } from '@/components/LinkTransactionToCaseDialog'
import { supabase } from '@/lib/supabase/client'
import { toast } from '@/hooks/use-toast'
import { Link2 } from 'lucide-react'
import { RecurringTransactionEditDialog } from '@/components/RecurringTransactionEditDialog'

export default function Finance() {
  const { state, updateItem, deleteItem, addTransaction, addSupplier } = useLegalStore() as any

  const now = new Date()
  const firstDay = new Date(now.getFullYear(), now.getMonth(), 1)
  const lastDay = new Date(now.getFullYear(), now.getMonth() + 1, 0)
  const pad = (n: number) => n.toString().padStart(2, '0')
  const formatYYYYMMDD = (d: Date) =>
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`

  const [activeTab, setActiveTab] = useState('geral')
  const [filterStatus, setFilterStatus] = useState('Todos')
  const [filterBank, setFilterBank] = useState('Todos')
  const [filterCategory, setFilterCategory] = useState('Todas')
  const [filterSupplier, setFilterSupplier] = useState('Todos')
  const [filterStartDate, setFilterStartDate] = useState(formatYYYYMMDD(firstDay))
  const [filterEndDate, setFilterEndDate] = useState(formatYYYYMMDD(lastDay))

  const monthShortcuts = useMemo(() => {
    const months = [
      'jan',
      'fev',
      'mar',
      'abr',
      'mai',
      'jun',
      'jul',
      'ago',
      'set',
      'out',
      'nov',
      'dez',
    ]
    const now = new Date()
    return [-1, 0, 1].map((offset) => {
      const target = new Date(now.getFullYear(), now.getMonth() + offset, 1)
      return {
        label: `${months[target.getMonth()]}/${target.getFullYear().toString().slice(2)}`,
        offset,
      }
    })
  }, [])

  const setMonthRange = (offset: number) => {
    const now = new Date()
    const target = new Date(now.getFullYear(), now.getMonth() + offset, 1)
    const first = new Date(target.getFullYear(), target.getMonth(), 1)
    const last = new Date(target.getFullYear(), target.getMonth() + 1, 0)
    setFilterStartDate(formatYYYYMMDD(first))
    setFilterEndDate(formatYYYYMMDD(last))
  }

  const [editingTransaction, setEditingTransaction] = useState<any>(null)
  const [creatingTransaction, setCreatingTransaction] = useState(false)

  const [editingSupplier, setEditingSupplier] = useState<any>(null)
  const [creatingSupplier, setCreatingSupplier] = useState(false)
  const [syncingAsaasId, setSyncingAsaasId] = useState<string | null>(null)
  const [syncingHistory, setSyncingHistory] = useState(false)
  const [linkingTx, setLinkingTx] = useState<any>(null)
  const [txToDelete, setTxToDelete] = useState<any>(null)
  const [deletingTx, setDeletingTx] = useState(false)
  const [txDeleteError, setTxDeleteError] = useState<string | null>(null)
  const [recurringEditData, setRecurringEditData] = useState<{
    id: string
    changes: any
    recurring_id: string
    currentDate: string
  } | null>(null)

  const baseTransactions = useMemo(() => {
    // Only show transactions sent to finance
    return state.transactions.filter((t) => t.sendToFinance !== false)
  }, [state.transactions])

  const filtered = useMemo(() => {
    let list = baseTransactions

    if (activeTab === 'honorarios') {
      list = list.filter((t) => t.category.toLowerCase().includes('honorário'))
    }

    return list.filter((t) => {
      const matchStatus = filterStatus === 'Todos' || t.status === filterStatus
      const matchBank = filterBank === 'Todos' || t.bankAccount === filterBank
      const matchCategory = filterCategory === 'Todas' || t.category === filterCategory
      const matchSupplier = filterSupplier === 'Todos' || t.supplierId === filterSupplier

      let matchStart = true
      let matchEnd = true
      if (filterStartDate) matchStart = t.date >= filterStartDate
      if (filterEndDate) matchEnd = t.date <= filterEndDate

      return matchStatus && matchBank && matchCategory && matchSupplier && matchStart && matchEnd
    })
  }, [
    baseTransactions,
    activeTab,
    filterStatus,
    filterBank,
    filterCategory,
    filterSupplier,
    filterStartDate,
    filterEndDate,
  ])

  const chartData = useMemo(() => {
    const dataByDate: Record<string, { date: string; income: number; expense: number }> = {}

    filtered.forEach((t) => {
      if (!dataByDate[t.date]) {
        dataByDate[t.date] = { date: t.date, income: 0, expense: 0 }
      }
      if (t.type === 'income') {
        dataByDate[t.date].income += t.amount
      } else {
        dataByDate[t.date].expense += t.amount
      }
    })

    return Object.values(dataByDate).sort((a, b) => a.date.localeCompare(b.date))
  }, [filtered])

  const categories = useMemo(() => {
    const cats = new Set(baseTransactions.map((t) => t.category).filter(Boolean))
    return Array.from(cats).sort()
  }, [baseTransactions])

  const bankOptions = useMemo(() => {
    const banks = new Set<string>(state.settings?.bankAccounts || ['ASAAS', 'SICOOB'])
    baseTransactions.forEach((t) => t.bankAccount && banks.add(t.bankAccount))
    return Array.from(banks).sort()
  }, [baseTransactions, state.settings?.bankAccounts])

  const handleAsaasChargeSync = async (transactionId: string) => {
    setSyncingAsaasId(transactionId)
    const { data, error } = await syncChargeWithAsaas(transactionId)
    setSyncingAsaasId(null)
    if (error) {
      toast({
        title: 'Erro',
        description: error.message || 'Falha ao enviar para ASAAS.',
        variant: 'destructive',
      })
    } else {
      toast({
        title: 'Sucesso',
        description: data?.message || 'Cobrança enviada para ASAAS.',
      })
    }
  }

  const handleSyncHistory = async () => {
    setSyncingHistory(true)
    const { data, error } = await syncHistoryWithAsaas()
    setSyncingHistory(false)
    if (error) {
      toast({
        title: 'Erro',
        description: error.message || 'Falha ao sincronizar histórico do ASAAS.',
        variant: 'destructive',
      })
    } else {
      toast({
        title: 'Sucesso',
        description: data?.message || 'Histórico sincronizado com ASAAS.',
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

  const handleTxDelete = async (forceLocal = false) => {
    if (!txToDelete) return
    setDeletingTx(true)
    setTxDeleteError(null)

    if (!forceLocal && txToDelete.asaas_id) {
      const { error: asaasError } = await cancelChargeWithAsaas(txToDelete.id)
      if (asaasError) {
        setDeletingTx(false)
        setTxDeleteError(asaasError.message || 'Falha ao cancelar cobrança no ASAAS.')
        return
      }
    }

    await deleteItem('transactions', txToDelete.id)
    setDeletingTx(false)
    setTxToDelete(null)
    setTxDeleteError(null)
    toast({ title: 'Lançamento excluído com sucesso.' })
  }

  if (!state.currentUser.canViewFinance) return <Navigate to="/" replace />

  const income = filtered.filter((t) => t.type === 'income').reduce((a, b) => a + b.amount, 0)
  const expense = filtered.filter((t) => t.type === 'expense').reduce((a, b) => a + b.amount, 0)
  const balance = income - expense

  return (
    <div className="space-y-6">
      <TransactionDialog
        open={!!editingTransaction}
        onOpenChange={(v: boolean) => !v && setEditingTransaction(null)}
        data={editingTransaction}
        onSave={(d: any) => {
          if (editingTransaction?.recurring_id) {
            setRecurringEditData({
              id: editingTransaction.id,
              changes: d,
              recurring_id: editingTransaction.recurring_id,
              currentDate: editingTransaction.date,
            })
          } else {
            updateItem('transactions', editingTransaction.id, d)
          }
        }}
      />
      <TransactionDialog
        open={creatingTransaction}
        onOpenChange={setCreatingTransaction}
        onSave={(d: any, isRecurring?: boolean, installments?: number) => {
          if (isRecurring && installments && installments > 1) {
            const recurringId = crypto.randomUUID()
            const baseDateStr = d.date
            const [y, m, day] = baseDateStr.split('-')
            const baseDate = new Date(parseInt(y, 10), parseInt(m, 10) - 1, parseInt(day, 10))

            const toInsert = []
            for (let i = 0; i < installments; i++) {
              const currentDate = new Date(baseDate)
              currentDate.setMonth(currentDate.getMonth() + i)
              const dateStr = currentDate.toISOString().split('T')[0]
              toInsert.push({
                ...d,
                date: dateStr,
                description: `${d.description} (${i + 1}/${installments})`,
                recurring_id: recurringId,
              })
            }
            addTransaction(toInsert)
          } else {
            addTransaction(d)
          }
        }}
      />
      <SupplierDialog
        open={!!editingSupplier}
        onOpenChange={(v: boolean) => !v && setEditingSupplier(null)}
        data={editingSupplier}
        onSave={(d: any) => updateItem('suppliers', editingSupplier.id, d)}
      />
      <SupplierDialog
        open={creatingSupplier}
        onOpenChange={setCreatingSupplier}
        onSave={(d: any) => addSupplier(d)}
      />

      <LinkTransactionToCaseDialog
        open={!!linkingTx}
        onOpenChange={(v: boolean) => !v && setLinkingTx(null)}
        transaction={linkingTx}
        cases={state.cases}
        onLink={handleLinkToCase}
      />

      <RecurringTransactionEditDialog
        open={!!recurringEditData}
        onOpenChange={(v: boolean) => !v && setRecurringEditData(null)}
        onChoose={async (choice: 'single' | 'future') => {
          if (!recurringEditData) return
          const { id, changes, recurring_id, currentDate } = recurringEditData

          if (choice === 'single') {
            await updateItem('transactions', id, changes)
          } else {
            await updateItem('transactions', id, changes)

            const today = new Date().toISOString().split('T')[0]
            const { data: futureTxns } = await supabase
              .from('transactions')
              .select('id, date, status')
              .eq('recurring_id', recurring_id)
              .gt('date', currentDate)

            const toUpdate = (futureTxns || []).filter(
              (t: any) =>
                t.date >= today && !['Pago', 'pago', 'Realizado', 'realizado'].includes(t.status),
            )

            const { date: _d, description: _desc, recurring_id: _r, ...sharedChanges } = changes

            for (const t of toUpdate) {
              await updateItem('transactions', t.id, sharedChanges)
            }
          }

          setRecurringEditData(null)
          setEditingTransaction(null)
          toast({
            title: 'Sucesso',
            description:
              choice === 'single'
                ? 'Lançamento atualizado.'
                : 'Lançamento e próximos vinculados atualizados.',
          })
        }}
      />

      <AlertDialog
        open={!!txToDelete}
        onOpenChange={(v) => {
          if (!v) {
            setTxToDelete(null)
            setTxDeleteError(null)
          }
        }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Excluir Lançamento?</AlertDialogTitle>
            <AlertDialogDescription>
              {txDeleteError
                ? `Erro ao cancelar no ASAAS: ${txDeleteError}. Deseja excluir apenas localmente?`
                : 'Esta ação é irreversível. O registro será removido e, se houver cobrança no ASAAS, será cancelada.'}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={deletingTx}>Cancelar</AlertDialogCancel>
            {txDeleteError ? (
              <>
                <AlertDialogAction
                  onClick={() => handleTxDelete(true)}
                  disabled={deletingTx}
                  className="bg-amber-600 hover:bg-amber-700"
                >
                  Excluir apenas local
                </AlertDialogAction>
                <AlertDialogAction onClick={() => handleTxDelete(false)} disabled={deletingTx}>
                  Tentar novamente
                </AlertDialogAction>
              </>
            ) : (
              <AlertDialogAction
                onClick={() => handleTxDelete(false)}
                disabled={deletingTx}
                className="bg-red-600 hover:bg-red-700"
              >
                {deletingTx ? 'Excluindo...' : 'Excluir'}
              </AlertDialogAction>
            )}
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <div className="flex flex-col md:flex-row md:justify-between md:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Financeiro</h1>
          <p className="text-muted-foreground">Controle de honorários e despesas.</p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={handleSyncHistory} disabled={syncingHistory}>
            <Send className={`mr-2 h-4 w-4 ${syncingHistory ? 'animate-pulse' : ''}`} />
            {syncingHistory ? 'Sincronizando...' : 'Sincronizar com Asaas'}
          </Button>
          <Button
            variant="outline"
            onClick={() => {
              const exportData = filtered.map((t) => ({
                Data: t.date,
                Descrição: t.description,
                Categoria: t.category,
                Banco: t.bankAccount || '-',
                Status: t.status,
                Tipo: t.type === 'income' ? 'Entrada' : 'Saída',
                Valor: t.amount,
              }))
              downloadCSV(exportData, 'financeiro.csv')
            }}
          >
            <Download className="mr-2 h-4 w-4" /> Exportar
          </Button>
          <Button onClick={() => setCreatingTransaction(true)}>
            <Plus className="mr-2 h-4 w-4" /> Novo Lançamento
          </Button>
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <Card className="bg-green-50 border-green-200">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-green-800">Entradas</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-green-700 flex items-center">
              <ArrowUpRight className="mr-2" /> R${' '}
              {income.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
            </div>
          </CardContent>
        </Card>
        <Card className="bg-red-50 border-red-200">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-red-800">Saídas</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-red-700 flex items-center">
              <ArrowDownRight className="mr-2" /> R${' '}
              {expense.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
            </div>
          </CardContent>
        </Card>
        <Card className="bg-slate-800 text-white">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-slate-300">Saldo Visível</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              R$ {balance.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
            </div>
          </CardContent>
        </Card>
      </div>

      <Tabs value={activeTab} onValueChange={setActiveTab} className="w-full">
        <TabsList className="grid w-full max-w-3xl grid-cols-3">
          <TabsTrigger value="geral">Visão Geral</TabsTrigger>
          <TabsTrigger value="honorarios">Honorários</TabsTrigger>
          <TabsTrigger value="fornecedores">Fornecedores</TabsTrigger>
        </TabsList>

        {activeTab !== 'fornecedores' && (
          <Card className="mt-4">
            <CardHeader className="pb-4">
              <div className="flex flex-col gap-4">
                <div className="flex flex-col gap-3">
                  <div className="flex items-center gap-2 text-lg font-semibold">
                    <Filter className="h-5 w-5 text-muted-foreground" />
                    Filtros
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-sm text-muted-foreground">Atalhos por Mês:</span>
                    {monthShortcuts.map((m) => (
                      <Button
                        key={m.offset}
                        variant="outline"
                        size="sm"
                        className="h-7 text-xs"
                        onClick={() => setMonthRange(m.offset)}
                      >
                        {m.label}
                      </Button>
                    ))}
                  </div>
                </div>
                <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-6 gap-4">
                  <div className="space-y-1.5">
                    <Label>Status</Label>
                    <Select value={filterStatus} onValueChange={setFilterStatus}>
                      <SelectTrigger className="bg-white">
                        <SelectValue placeholder="Status" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="Todos">Todos</SelectItem>
                        <SelectItem value="Previsto">Previsto</SelectItem>
                        <SelectItem value="Realizado">Realizado / Pago</SelectItem>
                        <SelectItem value="Pago">Pago</SelectItem>
                        <SelectItem value="Pendente">Pendente</SelectItem>
                        <SelectItem value="Atrasado">Atrasado</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="space-y-1.5">
                    <Label>Banco / Conta</Label>
                    <Select value={filterBank} onValueChange={setFilterBank}>
                      <SelectTrigger className="bg-white">
                        <SelectValue placeholder="Banco" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="Todos">Todos</SelectItem>
                        {bankOptions.map((b) => (
                          <SelectItem key={b} value={b}>
                            {b}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="space-y-1.5">
                    <Label>Categoria</Label>
                    <Select value={filterCategory} onValueChange={setFilterCategory}>
                      <SelectTrigger className="bg-white">
                        <SelectValue placeholder="Categoria" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="Todas">Todas</SelectItem>
                        {categories.map((c) => (
                          <SelectItem key={c} value={c}>
                            {c}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="space-y-1.5">
                    <Label>Fornecedor</Label>
                    <Select value={filterSupplier} onValueChange={setFilterSupplier}>
                      <SelectTrigger className="bg-white">
                        <SelectValue placeholder="Fornecedor" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="Todos">Todos</SelectItem>
                        {state.suppliers?.map((s: any) => (
                          <SelectItem key={s.id} value={s.id}>
                            {s.name}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="space-y-1.5">
                    <Label>Data Inicial</Label>
                    <Input
                      type="date"
                      value={filterStartDate}
                      onChange={(e) => setFilterStartDate(e.target.value)}
                    />
                  </div>
                  <div className="space-y-1.5">
                    <Label>Data Final</Label>
                    <Input
                      type="date"
                      value={filterEndDate}
                      onChange={(e) => setFilterEndDate(e.target.value)}
                    />
                  </div>
                </div>
              </div>
            </CardHeader>
            <CardContent>
              {chartData.length > 0 && (
                <div className="mb-8">
                  <h3 className="text-lg font-medium mb-4">Evolução Financeira no Período</h3>
                  <ChartContainer
                    config={{
                      income: { label: 'Entradas', color: '#22c55e' },
                      expense: { label: 'Saídas', color: '#ef4444' },
                    }}
                    className="h-[250px] w-full"
                  >
                    <BarChart data={chartData} margin={{ top: 10, right: 10, left: 10, bottom: 0 }}>
                      <CartesianGrid strokeDasharray="3 3" vertical={false} />
                      <XAxis
                        dataKey="date"
                        tickFormatter={(value) => {
                          const parts = value.split('-')
                          return `${parts[2]}/${parts[1]}`
                        }}
                        tickLine={false}
                        axisLine={false}
                      />
                      <YAxis
                        tickFormatter={(value) => `R$ ${value}`}
                        tickLine={false}
                        axisLine={false}
                        width={80}
                      />
                      <ChartTooltip content={<ChartTooltipContent />} />
                      <Bar
                        dataKey="income"
                        fill="var(--color-income)"
                        radius={[4, 4, 0, 0]}
                        maxBarSize={40}
                      />
                      <Bar
                        dataKey="expense"
                        fill="var(--color-expense)"
                        radius={[4, 4, 0, 0]}
                        maxBarSize={40}
                      />
                    </BarChart>
                  </ChartContainer>
                </div>
              )}
              <div className="rounded-md border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Data</TableHead>
                      <TableHead>Descrição</TableHead>
                      <TableHead>Categoria</TableHead>
                      <TableHead>Conta</TableHead>
                      <TableHead>Processos</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead className="text-right">Valor</TableHead>
                      <TableHead className="w-[50px]"></TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {filtered.map((t) => (
                      <TableRow
                        key={t.id}
                        className="cursor-pointer hover:bg-slate-50 group"
                        onClick={() => setEditingTransaction(t)}
                      >
                        <TableCell>{formatSafeLocalDate(t.date)}</TableCell>
                        <TableCell className="font-medium">{t.description}</TableCell>
                        <TableCell>{t.category}</TableCell>
                        <TableCell>{t.bankAccount || '-'}</TableCell>
                        <TableCell>
                          {(() => {
                            const linkedIds = (state.transactionCases || [])
                              .filter((tc: any) => tc.transaction_id === t.id)
                              .map((tc: any) => tc.case_id)
                            const linkedCases = state.cases.filter((c) => linkedIds.includes(c.id))
                            if (linkedCases.length > 0) {
                              return (
                                <div className="flex flex-wrap gap-1">
                                  {linkedCases.map((c) => (
                                    <Badge key={c.id} variant="secondary" className="text-[10px]">
                                      {c.number}
                                    </Badge>
                                  ))}
                                </div>
                              )
                            }
                            if (t.processId) {
                              const directCase = state.cases.find((c) => c.id === t.processId)
                              return directCase ? (
                                <Badge variant="secondary" className="text-[10px]">
                                  {directCase.number}
                                </Badge>
                              ) : (
                                '-'
                              )
                            }
                            return '-'
                          })()}
                        </TableCell>
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
                          className={`text-right font-bold ${t.type === 'income' ? 'text-green-600' : 'text-red-600'}`}
                        >
                          {t.type === 'income' ? '+' : '-'} R${' '}
                          {t.amount.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
                        </TableCell>
                        <TableCell>
                          <div className="flex items-center justify-end gap-1">
                            <Button
                              variant="ghost"
                              size="icon"
                              className="h-8 w-8 text-purple-500 hover:text-purple-700 hover:bg-purple-50 opacity-0 group-hover:opacity-100 transition-opacity"
                              onClick={(e) => {
                                e.stopPropagation()
                                setLinkingTx(t)
                              }}
                              title="Vincular a Processo"
                            >
                              <Link2 className="h-4 w-4" />
                            </Button>
                            <Button
                              variant="ghost"
                              size="icon"
                              className="h-8 w-8 text-blue-500 hover:text-blue-700 hover:bg-blue-50 opacity-0 group-hover:opacity-100 transition-opacity"
                              onClick={(e) => {
                                e.stopPropagation()
                                handleAsaasChargeSync(t.id)
                              }}
                              disabled={syncingAsaasId === t.id}
                              title="Enviar para ASAAS"
                            >
                              <Send
                                className={`h-4 w-4 ${syncingAsaasId === t.id ? 'animate-pulse' : ''}`}
                              />
                            </Button>
                            <Button
                              variant="ghost"
                              size="icon"
                              className="h-8 w-8 text-red-500 hover:text-red-700 hover:bg-red-50 opacity-0 group-hover:opacity-100 transition-opacity"
                              onClick={(e) => {
                                e.stopPropagation()
                                setTxToDelete(t)
                                setTxDeleteError(null)
                              }}
                            >
                              <Trash className="h-4 w-4" />
                            </Button>
                          </div>
                        </TableCell>
                      </TableRow>
                    ))}
                    {filtered.length === 0 && (
                      <TableRow>
                        <TableCell colSpan={8} className="text-center py-8 text-muted-foreground">
                          Nenhum lançamento encontrado.
                        </TableCell>
                      </TableRow>
                    )}
                  </TableBody>
                </Table>
              </div>
            </CardContent>
          </Card>
        )}

        {activeTab === 'fornecedores' && (
          <Card className="mt-4">
            <CardHeader className="pb-4 flex flex-row items-center justify-between">
              <div className="flex items-center gap-2 text-lg font-semibold">
                Fornecedores Cadastrados
              </div>
              <Button size="sm" onClick={() => setCreatingSupplier(true)}>
                <Plus className="mr-2 h-4 w-4" /> Novo Fornecedor
              </Button>
            </CardHeader>
            <CardContent>
              <div className="rounded-md border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Nome</TableHead>
                      <TableHead>Documento</TableHead>
                      <TableHead>Email</TableHead>
                      <TableHead>Telefone</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead className="w-[100px]"></TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {(state.suppliers || []).map((s: any) => (
                      <TableRow key={s.id}>
                        <TableCell className="font-medium">{s.name}</TableCell>
                        <TableCell>{s.document || '-'}</TableCell>
                        <TableCell>{s.email || '-'}</TableCell>
                        <TableCell>{s.phone || '-'}</TableCell>
                        <TableCell>
                          <Badge
                            variant="outline"
                            className={
                              s.status === 'Ativo'
                                ? 'bg-green-50 text-green-700 border-green-200'
                                : 'bg-slate-50 text-slate-700 border-slate-200'
                            }
                          >
                            {s.status}
                          </Badge>
                        </TableCell>
                        <TableCell>
                          <div className="flex items-center justify-end gap-2">
                            <Button
                              variant="ghost"
                              size="icon"
                              className="h-8 w-8 text-slate-500 hover:text-slate-700"
                              onClick={() => setEditingSupplier(s)}
                            >
                              <Edit className="h-4 w-4" />
                            </Button>
                            <Button
                              variant="ghost"
                              size="icon"
                              className="h-8 w-8 text-red-500 hover:text-red-700 hover:bg-red-50"
                              onClick={() => {
                                if (confirm('Deseja excluir este fornecedor?')) {
                                  deleteItem('suppliers', s.id)
                                }
                              }}
                            >
                              <Trash className="h-4 w-4" />
                            </Button>
                          </div>
                        </TableCell>
                      </TableRow>
                    ))}
                    {(!state.suppliers || state.suppliers.length === 0) && (
                      <TableRow>
                        <TableCell colSpan={6} className="text-center py-8 text-muted-foreground">
                          Nenhum fornecedor encontrado.
                        </TableCell>
                      </TableRow>
                    )}
                  </TableBody>
                </Table>
              </div>
            </CardContent>
          </Card>
        )}
      </Tabs>
    </div>
  )
}
