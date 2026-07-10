import { useState, useEffect, useMemo } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
import { Label } from '@/components/ui/label'
import { Button } from '@/components/ui/button'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Badge } from '@/components/ui/badge'
import { Link2 } from 'lucide-react'

export function LinkTransactionToCaseDialog({
  open,
  onOpenChange,
  transaction,
  cases,
  onLink,
}: any) {
  const [selectedCaseId, setSelectedCaseId] = useState('')

  const clientCases = useMemo(() => {
    if (!transaction?.clientId) return []
    return (cases || [])
      .filter((c: any) => c.clientId === transaction.clientId)
      .sort((a: any, b: any) => (a.number || '').localeCompare(b.number || ''))
  }, [transaction, cases])

  useEffect(() => {
    if (open && transaction) {
      setSelectedCaseId(transaction.processId || '')
    }
  }, [open, transaction])

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!selectedCaseId || !transaction) return
    onLink(transaction.id, selectedCaseId)
    onOpenChange(false)
  }

  const clientName = useMemo(() => {
    if (!transaction?.clientId) return null
    return null
  }, [transaction])

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <form onSubmit={handleSubmit} className="grid gap-4">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Link2 className="h-5 w-5 text-purple-600" />
              Vincular a Processo
            </DialogTitle>
          </DialogHeader>

          {transaction && (
            <div className="space-y-3">
              <div className="rounded-lg border bg-slate-50 p-3 space-y-1">
                <p className="text-sm font-medium">{transaction.description}</p>
                <div className="flex items-center gap-2 flex-wrap">
                  <Badge variant="outline" className="text-xs">
                    R${' '}
                    {Number(transaction.amount).toLocaleString('pt-BR', {
                      minimumFractionDigits: 2,
                    })}
                  </Badge>
                  <Badge variant="secondary" className="text-xs">
                    {transaction.status}
                  </Badge>
                  {transaction.asaas_id && (
                    <Badge variant="outline" className="text-xs text-blue-600">
                      ASAAS
                    </Badge>
                  )}
                </div>
              </div>

              <div className="space-y-2">
                <Label>Selecione o Processo *</Label>
                {clientCases.length === 0 ? (
                  <p className="text-sm text-muted-foreground p-3 border rounded-lg bg-amber-50 border-amber-200">
                    Nenhum processo encontrado para o cliente desta transação.
                  </p>
                ) : (
                  <Select value={selectedCaseId} onValueChange={setSelectedCaseId}>
                    <SelectTrigger>
                      <SelectValue placeholder="Selecione um processo" />
                    </SelectTrigger>
                    <SelectContent>
                      {clientCases.map((c: any) => (
                        <SelectItem key={c.id} value={c.id}>
                          {c.number} {c.type ? `— ${c.type}` : ''}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                )}
              </div>
            </div>
          )}

          <DialogFooter>
            <Button type="submit" disabled={!selectedCaseId}>
              Vincular
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
