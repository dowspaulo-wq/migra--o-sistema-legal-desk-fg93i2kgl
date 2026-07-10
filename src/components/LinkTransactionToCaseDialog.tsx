import { useState, useEffect } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'

export function LinkTransactionToCaseDialog({
  open,
  onOpenChange,
  transaction,
  cases,
  onLink,
}: {
  open: boolean
  onOpenChange: (v: boolean) => void
  transaction: any
  cases: any[]
  onLink: (transactionId: string, caseId: string) => void
}) {
  const [selectedCaseId, setSelectedCaseId] = useState('')

  useEffect(() => {
    if (open) {
      setSelectedCaseId('')
    }
  }, [open])

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!selectedCaseId || !transaction) return
    onLink(transaction.id, selectedCaseId)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <form onSubmit={handleSubmit} className="grid gap-4">
          <DialogHeader>
            <DialogTitle>Vincular a um Processo</DialogTitle>
          </DialogHeader>
          {transaction && (
            <div className="text-sm text-muted-foreground bg-slate-50 rounded-md p-3">
              <span className="font-medium text-slate-700">{transaction.description}</span>
              <br />
              <span>
                R$ {transaction.amount?.toLocaleString('pt-BR', { minimumFractionDigits: 2 })} •{' '}
                {transaction.category}
              </span>
            </div>
          )}
          <div className="space-y-2">
            <Label>Selecione o processo</Label>
            <Select value={selectedCaseId} onValueChange={setSelectedCaseId}>
              <SelectTrigger>
                <SelectValue placeholder="Selecione um processo" />
              </SelectTrigger>
              <SelectContent>
                {cases.length === 0 && (
                  <SelectItem value="none" disabled>
                    Nenhum processo encontrado
                  </SelectItem>
                )}
                {cases.map((c) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.number}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
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
