import { useState, useMemo } from 'react'
import { Navigate } from 'react-router-dom'
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
import { Link2, Wallet, AlertTriangle } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { LinkTransactionToCaseDialog } from '@/components/LinkTransactionToCaseDialog'
import { supabase } from '@/lib/supabase/client'
import { toast } from '@/hooks/use-toast'
import { formatSafeLocalDate } from '@/lib/utils'

export default function FinancialDashboard() {
  const { state, updateItem } = useLegalStore()
  const [linkingTx, setLinkingTx] = useState<any>(null)

  const pendingTransactions = useMemo(() => {
    const linkedTxIds = new Set((state.transactionCases || []).map((tc: any) => tc.transaction_id))
    return state.transactions.filter(
      (t: any) => !t.processId && t.clientId && !linkedTxIds.has(t.id),
    )
  }, [state.transactions, state.transactionCases])

  const incomePending = pendingTransactions
    .filter((t: any) => t.type === 'income')
    .reduce((s: number, t: any) => s + (t.amount || 0), 0)
  const expensePending = pendingTransactions
    .filter((t: any) => t.type === 'expense')
    .reduce((s: number, t: any) => s + (t.amount || 0), 0)

  const casesWithoutFees = useMemo(() => {
    return state.cases.filter((c: any) => !c.feeValue || c.feeValue === 0)
  }, [state.cases])

  const nonFinancialCases = useMemo(() => {
    return state.cases.filter(
      (c: any) => c.feeType === 'apenas quota littis' || c.feeType === 'pro bono',
    )
  }, [state.cases])

  const getClientName = (clientId: string) =>
    state.clients.find((c) => c.id === clientId)?.name || 'Cliente não encontrado'

  const linkingCases = linkingTx ? state.cases.filter((c) => c.clientId === linkingTx.clientId) : []

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

    toast({
      title: 'Sucesso',
      description: 'Transação vinculada ao processo com sucesso.',
    })
    setLinkingTx(null)
  }

  if (!state.currentUser.canViewFinance && state.currentUser.role !== 'Admin') {
    return <Navigate to="/" replace />
  }

  return (
    <div className="space-y-6">
      <LinkTransactionToCaseDialog
        open={!!linkingTx}
        onOpenChange={(v: boolean) => !v && setLinkingTx(null)}
        transaction={linkingTx}
        cases={linkingCases}
        onLink={handleLinkToCase}
      />

      <div>
        <h1 className="text-3xl font-bold tracking-tight flex items-center gap-3">
          <Wallet className="h-8 w-8 text-primary" />
          Dashboard Financeiro
        </h1>
        <p className="text-muted-foreground mt-1">
          Centralize e organize cobranças não vinculadas a processos.
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <Card className="bg-amber-50 border-amber-200">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-amber-800 flex items-center gap-2">
              <AlertTriangle className="h-4 w-4" /> Pendências Totais
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-amber-700">{pendingTransactions.length}</div>
            <p className="text-xs text-amber-600 mt-1">transação(ões) sem processo</p>
          </CardContent>
        </Card>
        <Card className="bg-green-50 border-green-200">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-green-800">Receitas Pendentes</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-green-700">
              R$ {incomePending.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
            </div>
          </CardContent>
        </Card>
        <Card className="bg-red-50 border-red-200">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-red-800">Despesas Pendentes</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-red-700">
              R$ {expensePending.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
            </div>
          </CardContent>
        </Card>
      </div>

      {casesWithoutFees.length > 0 && (
        <Card className="bg-orange-50 border-orange-200">
          <CardHeader>
            <CardTitle className="text-lg flex items-center gap-2">
              <AlertTriangle className="h-5 w-5 text-orange-500" />
              Processos sem honorários lançados ({casesWithoutFees.length})
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="rounded-md border bg-white">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Nº do Processo</TableHead>
                    <TableHead>Cliente</TableHead>
                    <TableHead>Tipo</TableHead>
                    <TableHead>Status</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {casesWithoutFees.slice(0, 10).map((c: any) => (
                    <TableRow key={c.id}>
                      <TableCell className="font-medium">{c.number}</TableCell>
                      <TableCell>{getClientName(c.clientId)}</TableCell>
                      <TableCell>{c.type || '-'}</TableCell>
                      <TableCell>{c.status || '-'}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
            {casesWithoutFees.length > 10 && (
              <p className="text-xs text-orange-600 mt-2">
                E mais {casesWithoutFees.length - 10} processo(s) sem honorários. Acesse a lista de
                processos para regularizar.
              </p>
            )}
          </CardContent>
        </Card>
      )}

      {nonFinancialCases.length > 0 && (
        <Card className="bg-purple-50 border-purple-200">
          <CardHeader>
            <CardTitle className="text-lg flex items-center gap-2">
              <Wallet className="h-5 w-5 text-purple-500" />
              Honorários Não Financeiros ({nonFinancialCases.length})
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="rounded-md border bg-white">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Nº do Processo</TableHead>
                    <TableHead>Cliente</TableHead>
                    <TableHead>Tipo de Honorário</TableHead>
                    <TableHead>Valor</TableHead>
                    <TableHead>Status</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {nonFinancialCases.map((c: any) => (
                    <TableRow key={c.id}>
                      <TableCell className="font-medium">{c.number}</TableCell>
                      <TableCell>{getClientName(c.clientId)}</TableCell>
                      <TableCell>
                        <Badge
                          variant="outline"
                          className="bg-purple-50 text-purple-700 border-purple-200"
                        >
                          {c.feeType}
                        </Badge>
                      </TableCell>
                      <TableCell>
                        {c.feeValue
                          ? `R$ ${Number(c.feeValue).toLocaleString('pt-BR', { minimumFractionDigits: 2 })}`
                          : '—'}
                      </TableCell>
                      <TableCell>{c.status || '—'}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle className="text-lg flex items-center gap-2">
            <AlertTriangle className="h-5 w-5 text-amber-500" />
            Pendências Financeiras ({pendingTransactions.length})
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="rounded-md border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Cliente</TableHead>
                  <TableHead>Descrição</TableHead>
                  <TableHead>Data</TableHead>
                  <TableHead className="text-right">Valor</TableHead>
                  <TableHead>Asaas ID</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="w-[140px]"></TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {pendingTransactions.map((t: any) => (
                  <TableRow key={t.id} className="group">
                    <TableCell className="font-medium">{getClientName(t.clientId)}</TableCell>
                    <TableCell>{t.description}</TableCell>
                    <TableCell>{formatSafeLocalDate(t.date)}</TableCell>
                    <TableCell
                      className={`text-right font-bold ${t.type === 'income' ? 'text-green-600' : 'text-red-600'}`}
                    >
                      {t.type === 'income' ? '+' : '-'} R${' '}
                      {t.amount.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
                    </TableCell>
                    <TableCell>
                      {t.asaas_id ? (
                        <Badge
                          variant="outline"
                          className="text-[10px] bg-blue-50 text-blue-700 border-blue-200"
                        >
                          {t.asaas_id.slice(0, 12)}…
                        </Badge>
                      ) : (
                        <span className="text-muted-foreground text-sm">—</span>
                      )}
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
                    <TableCell>
                      <Button
                        variant="outline"
                        size="sm"
                        className="text-xs h-8"
                        onClick={() => setLinkingTx(t)}
                      >
                        <Link2 className="h-3 w-3 mr-1" />
                        Vincular Processo
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
                {pendingTransactions.length === 0 && (
                  <TableRow>
                    <TableCell colSpan={7} className="text-center py-8 text-muted-foreground">
                      Nenhuma pendência financeira encontrada. Todas as transações estão vinculadas
                      a processos.
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
