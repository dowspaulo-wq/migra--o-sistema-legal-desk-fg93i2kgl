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
import { Plus, ArrowUpRight, ArrowDownRight, Download, Trash, Filter } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { Navigate } from 'react-router-dom'
import { downloadCSV } from '@/lib/export'
import { TransactionDialog } from '@/components/TransactionDialog'
import { formatSafeLocalDate } from '@/lib/utils'

export default function Finance() {
  const { state, updateItem, deleteItem, addTransaction } = useLegalStore()

  const [activeTab, setActiveTab] = useState('geral')
  const [filterStatus, setFilterStatus] = useState('Todos')
  const [filterBank, setFilterBank] = useState('Todos')
  const [filterStartDate, setFilterStartDate] = useState('')
  const [filterEndDate, setFilterEndDate] = useState('')

  const [editingTransaction, setEditingTransaction] = useState<any>(null)
  const [creatingTransaction, setCreatingTransaction] = useState(false)

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

      let matchStart = true
      let matchEnd = true
      if (filterStartDate) matchStart = t.date >= filterStartDate
      if (filterEndDate) matchEnd = t.date <= filterEndDate

      return matchStatus && matchBank && matchStart && matchEnd
    })
  }, [baseTransactions, activeTab, filterStatus, filterBank, filterStartDate, filterEndDate])

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
        onSave={(d: any) => updateItem('transactions', editingTransaction.id, d)}
      />
      <TransactionDialog
        open={creatingTransaction}
        onOpenChange={setCreatingTransaction}
        onSave={(d: any) => addTransaction(d)}
      />

      <div className="flex flex-col md:flex-row md:justify-between md:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Financeiro</h1>
          <p className="text-muted-foreground">Controle de honorários e despesas.</p>
        </div>
        <div className="flex gap-2">
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
        <TabsList className="grid w-full max-w-md grid-cols-2">
          <TabsTrigger value="geral">Visão Geral</TabsTrigger>
          <TabsTrigger value="honorarios">Honorários</TabsTrigger>
        </TabsList>

        <Card className="mt-4">
          <CardHeader className="pb-4">
            <div className="flex flex-col gap-4">
              <div className="flex items-center gap-2 text-lg font-semibold">
                <Filter className="h-5 w-5 text-muted-foreground" />
                Filtros
              </div>
              <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
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
                      <SelectItem value="ASAAS">ASAAS</SelectItem>
                      <SelectItem value="SICOOB">SICOOB</SelectItem>
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
            <div className="rounded-md border">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Data</TableHead>
                    <TableHead>Descrição</TableHead>
                    <TableHead>Categoria</TableHead>
                    <TableHead>Conta</TableHead>
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
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-8 w-8 text-red-500 hover:text-red-700 hover:bg-red-50 opacity-0 group-hover:opacity-100 transition-opacity"
                          onClick={(e) => {
                            e.stopPropagation()
                            if (confirm('Deseja excluir este lançamento?')) {
                              deleteItem('transactions', t.id)
                            }
                          }}
                        >
                          <Trash className="h-4 w-4" />
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))}
                  {filtered.length === 0 && (
                    <TableRow>
                      <TableCell colSpan={7} className="text-center py-8 text-muted-foreground">
                        Nenhum lançamento encontrado.
                      </TableCell>
                    </TableRow>
                  )}
                </TableBody>
              </Table>
            </div>
          </CardContent>
        </Card>
      </Tabs>
    </div>
  )
}
