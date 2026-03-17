import { useState } from 'react'
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
import { Plus, ArrowUpRight, ArrowDownRight } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { Navigate } from 'react-router-dom'

export default function Finance() {
  const { state } = useLegalStore()
  const [filterStatus, setFilterStatus] = useState('Todos')

  if (!state.currentUser.canViewFinance) return <Navigate to="/" replace />

  const filtered = state.transactions.filter(
    (t) =>
      filterStatus === 'Todos' ||
      (filterStatus === 'Vazio' ? !t.status : t.status === filterStatus),
  )

  const income = state.transactions
    .filter((t) => t.type === 'income')
    .reduce((a, b) => a + b.amount, 0)
  const expense = state.transactions
    .filter((t) => t.type === 'expense')
    .reduce((a, b) => a + b.amount, 0)
  const balance = income - expense

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Financeiro</h1>
          <p className="text-muted-foreground">Controle de honorários e despesas.</p>
        </div>
        <Button>
          <Plus className="mr-2 h-4 w-4" /> Novo Lançamento
        </Button>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <Card className="bg-green-50 border-green-200">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-green-800">Entradas Totais</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-green-700 flex items-center">
              <ArrowUpRight className="mr-2" /> R$ {income.toLocaleString('pt-BR')}
            </div>
          </CardContent>
        </Card>
        <Card className="bg-red-50 border-red-200">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-red-800">Saídas Totais</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-red-700 flex items-center">
              <ArrowDownRight className="mr-2" /> R$ {expense.toLocaleString('pt-BR')}
            </div>
          </CardContent>
        </Card>
        <Card className="bg-slate-800 text-white">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-slate-300">Saldo Geral</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">R$ {balance.toLocaleString('pt-BR')}</div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between pb-2">
          <CardTitle>Lançamentos</CardTitle>
          <Select value={filterStatus} onValueChange={setFilterStatus}>
            <SelectTrigger className="w-[200px] bg-white">
              <SelectValue placeholder="Filtrar Status" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="Todos">Todos os Status</SelectItem>
              <SelectItem value="Vazio">Não Informado (Vazio)</SelectItem>
              <SelectItem value="Pago">Pago</SelectItem>
              <SelectItem value="Pendente">Pendente</SelectItem>
              <SelectItem value="Atrasado">Atrasado</SelectItem>
            </SelectContent>
          </Select>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Data</TableHead>
                <TableHead>Descrição</TableHead>
                <TableHead>Categoria</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="text-right">Valor</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {filtered.map((t) => (
                <TableRow key={t.id}>
                  <TableCell>{new Date(t.date).toLocaleDateString('pt-BR')}</TableCell>
                  <TableCell className="font-medium">{t.description}</TableCell>
                  <TableCell>{t.category}</TableCell>
                  <TableCell>
                    <Badge
                      variant={
                        t.status === 'Pago'
                          ? 'default'
                          : t.status === 'Atrasado'
                            ? 'destructive'
                            : 'secondary'
                      }
                    >
                      {t.status}
                    </Badge>
                  </TableCell>
                  <TableCell
                    className={`text-right font-bold ${t.type === 'income' ? 'text-green-600' : 'text-red-600'}`}
                  >
                    {t.type === 'income' ? '+' : '-'} R$ {t.amount.toLocaleString('pt-BR')}
                  </TableCell>
                </TableRow>
              ))}
              {filtered.length === 0 && (
                <TableRow>
                  <TableCell colSpan={5} className="text-center py-8">
                    Nenhum lançamento encontrado.
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  )
}
