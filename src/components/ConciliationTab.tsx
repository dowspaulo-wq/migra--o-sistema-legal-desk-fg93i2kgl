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
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { ArrowUpRight, ArrowDownRight, Filter, Link2, Inbox, Clock, RotateCcw } from 'lucide-react'
import { formatSafeLocalDate, cn } from '@/lib/utils'
import { LinkConciliationDialog } from '@/components/LinkConciliationDialog'
import { supabase } from '@/lib/supabase/client'
import { toast } from '@/hooks/use-toast'

interface ConciliationTabProps {
  transactions: any[]
  clients: any[]
  cases: any[]
  onUpdateTransaction: (id: string, changes: any) => Promise<void> | void
}

export function ConciliationTab({
  transactions,
  clients,
  cases,
  onUpdateTransaction,
}: ConciliationTabProps) {
  // Filtros
  const [filterOrigin, setFilterOrigin] = useState<string>('Todas')
  const [filterStartDate, setFilterStartDate] = useState<string>('')
  const [filterEndDate, setFilterEndDate] = useState<string>('')

  // Modal de vínculo
  const [linkingTransaction, setLinkingTransaction] = useState<any | null>(null)

  // 1. Filtrar transações pendentes de vínculo ordenadas por data decrescente
  const pendingTransactions = useMemo(() => {
    return transactions
      .filter((t) => Boolean(t.pendente_vinculo))
      .sort((a, b) => new Date(b.date || 0).getTime() - new Date(a.date || 0).getTime())
  }, [transactions])

  // Resumo global de pendentes (sempre reflete todos os pendentes)
  const summary = useMemo(() => {
    const totalCount = pendingTransactions.length
    const incomeTotal = pendingTransactions
      .filter((t) => t.type === 'income')
      .reduce((sum, t) => sum + Number(t.amount || 0), 0)
    const expenseTotal = pendingTransactions
      .filter((t) => t.type === 'expense')
      .reduce((sum, t) => sum + Number(t.amount || 0), 0)

    return {
      totalCount,
      incomeTotal,
      expenseTotal,
    }
  }, [pendingTransactions])

  // Lançamentos filtrados
  const filteredList = useMemo(() => {
    return pendingTransactions.filter((t) => {
      // Filtro de Origem
      if (filterOrigin === 'Asaas') {
        if (t.origem !== 'ASAAS_WEBHOOK' && t.origem !== 'ASAAS') return false
      } else if (filterOrigin === 'SICOOB') {
        if (t.origem !== 'IMPORT_SICOOB' && t.origem !== 'SICOOB') return false
      }

      // Filtro de Período
      if (filterStartDate && t.date && t.date < filterStartDate) return false
      if (filterEndDate && t.date && t.date > filterEndDate) return false

      return true
    })
  }, [pendingTransactions, filterOrigin, filterStartDate, filterEndDate])

  // Função para renderizar o Badge de Origem
  const renderOriginBadge = (origem: string | null | undefined) => {
    if (!origem) return <Badge variant="outline">Manual</Badge>
    const upper = origem.toUpperCase()

    if (upper === 'ASAAS_WEBHOOK' || upper === 'ASAAS') {
      return (
        <Badge
          variant="outline"
          className="bg-blue-50 text-blue-700 border-blue-200 hover:bg-blue-100 font-medium"
        >
          Asaas
        </Badge>
      )
    }

    if (upper === 'IMPORT_SICOOB' || upper === 'SICOOB') {
      return (
        <Badge
          variant="outline"
          className="bg-emerald-50 text-emerald-700 border-emerald-200 hover:bg-emerald-100 font-medium"
        >
          SICOOB
        </Badge>
      )
    }

    return (
      <Badge variant="outline" className="text-slate-600">
        {origem}
      </Badge>
    )
  }

  // Ação: Salvar Vínculo (PATCH em transactions setando clientId/processId e pendente_vinculo = false)
  const handleSaveLink = async (
    transactionId: string,
    clientId: string,
    processId: string | null,
  ) => {
    const changes: Record<string, any> = {
      clientId,
      processId,
      pendente_vinculo: false,
    }

    const { error } = await supabase.from('transactions').update(changes).eq('id', transactionId)

    if (error) {
      toast({
        title: 'Erro',
        description: error.message || 'Falha ao vincular lançamento.',
        variant: 'destructive',
      })
      throw error
    }

    // Se houver processo, vincula também em transaction_cases para manter consistência
    if (processId) {
      await supabase
        .from('transaction_cases')
        .upsert(
          { transaction_id: transactionId, case_id: processId },
          { onConflict: 'transaction_id,case_id' },
        )
    }

    await onUpdateTransaction(transactionId, changes)

    toast({
      title: 'Sucesso',
      description: 'Lançamento vinculado e conciliação concluída!',
    })
  }

  // Ação: Ignorar (PATCH setando pendente_vinculo = false, sem alterar clientId/processId)
  const handleIgnore = async (transactionId: string) => {
    const changes = {
      pendente_vinculo: false,
    }

    const { error } = await supabase.from('transactions').update(changes).eq('id', transactionId)

    if (error) {
      toast({
        title: 'Erro',
        description: error.message || 'Falha ao ignorar lançamento.',
        variant: 'destructive',
      })
      throw error
    }

    await onUpdateTransaction(transactionId, changes)

    toast({
      title: 'Lançamento ignorado',
      description: 'O lançamento foi removido da fila de conciliação.',
    })
  }

  const clearFilters = () => {
    setFilterOrigin('Todas')
    setFilterStartDate('')
    setFilterEndDate('')
  }

  const hasActiveFilters = filterOrigin !== 'Todas' || !!filterStartDate || !!filterEndDate

  return (
    <div className="space-y-4">
      {/* 1. Resumo no topo */}
      <div className="grid gap-4 md:grid-cols-3">
        <Card className="bg-amber-50/70 border-amber-200">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-amber-900 flex items-center justify-between">
              <span>Lançamentos Pendentes</span>
              <Clock className="h-4 w-4 text-amber-600" />
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-amber-800">
              {summary.totalCount}{' '}
              <span className="text-sm font-normal text-amber-700">
                {summary.totalCount === 1 ? 'pendência' : 'pendências'}
              </span>
            </div>
            <p className="text-xs text-amber-700/80 mt-1">
              Aguardando vinculação de cliente/processo
            </p>
          </CardContent>
        </Card>

        <Card className="bg-green-50 border-green-200">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-green-800 flex items-center justify-between">
              <span>Receitas Pendentes</span>
              <ArrowUpRight className="h-4 w-4 text-green-600" />
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-green-700">
              R$ {summary.incomeTotal.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
            </div>
            <p className="text-xs text-green-700/80 mt-1">Total em entradas a conciliar</p>
          </CardContent>
        </Card>

        <Card className="bg-red-50 border-red-200">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-red-800 flex items-center justify-between">
              <span>Despesas Pendentes</span>
              <ArrowDownRight className="h-4 w-4 text-red-600" />
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-red-700">
              R$ {summary.expenseTotal.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
            </div>
            <p className="text-xs text-red-700/80 mt-1">Total em saídas a conciliar</p>
          </CardContent>
        </Card>
      </div>

      {/* 4. Filtros acima da tabela */}
      <Card>
        <CardHeader className="pb-4">
          <div className="flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2 text-lg font-semibold">
                <Filter className="h-5 w-5 text-muted-foreground" />
                Filtros de Conciliação
              </div>
              {hasActiveFilters && (
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={clearFilters}
                  className="h-8 text-xs text-muted-foreground hover:text-slate-800"
                >
                  <RotateCcw className="mr-1.5 h-3.5 w-3.5" />
                  Limpar filtros
                </Button>
              )}
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              {/* Filtro: Origem */}
              <div className="space-y-1.5">
                <Label>Origem</Label>
                <Select value={filterOrigin} onValueChange={setFilterOrigin}>
                  <SelectTrigger className="bg-white">
                    <SelectValue placeholder="Origem" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Todas">Todas</SelectItem>
                    <SelectItem value="Asaas">Asaas</SelectItem>
                    <SelectItem value="SICOOB">SICOOB</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              {/* Filtro: Data Inicial */}
              <div className="space-y-1.5">
                <Label>Data Inicial</Label>
                <Input
                  type="date"
                  value={filterStartDate}
                  onChange={(e) => setFilterStartDate(e.target.value)}
                  className="bg-white"
                />
              </div>

              {/* Filtro: Data Final */}
              <div className="space-y-1.5">
                <Label>Data Final</Label>
                <Input
                  type="date"
                  value={filterEndDate}
                  onChange={(e) => setFilterEndDate(e.target.value)}
                  className="bg-white"
                />
              </div>
            </div>
          </div>
        </CardHeader>

        {/* 2. Tabela de lançamentos pendentes */}
        <CardContent>
          <div className="rounded-md border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-[110px]">Data</TableHead>
                  <TableHead>Descrição</TableHead>
                  <TableHead className="w-[120px]">Tipo</TableHead>
                  <TableHead className="w-[120px]">Origem</TableHead>
                  <TableHead className="w-[120px]">Status</TableHead>
                  <TableHead className="text-right w-[140px]">Valor</TableHead>
                  <TableHead className="text-right w-[110px]">Ação</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filteredList.map((t) => {
                  const isIncome = t.type === 'income'
                  return (
                    <TableRow key={t.id} className="hover:bg-slate-50">
                      <TableCell className="font-mono text-xs">
                        {formatSafeLocalDate(t.date)}
                      </TableCell>
                      <TableCell>
                        <div className="font-medium text-slate-800">{t.description}</div>
                        {t.category && (
                          <div className="text-xs text-muted-foreground">{t.category}</div>
                        )}
                      </TableCell>
                      <TableCell>
                        <Badge
                          variant="outline"
                          className={cn(
                            'text-xs',
                            isIncome
                              ? 'border-green-200 text-green-700 bg-green-50'
                              : 'border-red-200 text-red-700 bg-red-50',
                          )}
                        >
                          {isIncome ? 'Receita' : 'Despesa'}
                        </Badge>
                      </TableCell>
                      <TableCell>{renderOriginBadge(t.origem)}</TableCell>
                      <TableCell>
                        <Badge
                          variant="outline"
                          className={cn(
                            'text-xs',
                            t.status === 'Pago' || t.status === 'Realizado'
                              ? 'border-green-200 text-green-700 bg-green-50'
                              : t.status === 'Atrasado'
                                ? 'border-red-200 text-red-700 bg-red-50'
                                : 'border-amber-200 text-amber-700 bg-amber-50',
                          )}
                        >
                          {t.status || 'Previsto'}
                        </Badge>
                      </TableCell>
                      <TableCell
                        className={cn(
                          'text-right font-bold',
                          isIncome ? 'text-green-600' : 'text-red-600',
                        )}
                      >
                        {isIncome ? '+' : '-'} R${' '}
                        {Number(t.amount || 0).toLocaleString('pt-BR', {
                          minimumFractionDigits: 2,
                        })}
                      </TableCell>
                      <TableCell className="text-right">
                        <Button
                          size="sm"
                          variant="default"
                          className="h-8 gap-1.5"
                          onClick={() => setLinkingTransaction(t)}
                        >
                          <Link2 className="h-3.5 w-3.5" />
                          Vincular
                        </Button>
                      </TableCell>
                    </TableRow>
                  )
                })}

                {filteredList.length === 0 && (
                  <TableRow>
                    <TableCell colSpan={7} className="text-center py-12 text-muted-foreground">
                      <div className="flex flex-col items-center justify-center gap-2">
                        <Inbox className="h-8 w-8 text-slate-400 stroke-1" />
                        <span className="font-medium">
                          {pendingTransactions.length === 0
                            ? 'Nenhum lançamento pendente de vínculo.'
                            : 'Nenhum lançamento pendente corresponde aos filtros aplicados.'}
                        </span>
                        {pendingTransactions.length === 0 && (
                          <span className="text-xs text-slate-400">
                            Novos lançamentos automáticos do Asaas ou SICOOB aparecerão aqui.
                          </span>
                        )}
                      </div>
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      {/* 3. Dialog de vínculo */}
      <LinkConciliationDialog
        open={!!linkingTransaction}
        onOpenChange={(v) => !v && setLinkingTransaction(null)}
        transaction={linkingTransaction}
        clients={clients}
        cases={cases}
        onSaveLink={handleSaveLink}
        onIgnore={handleIgnore}
      />
    </div>
  )
}
