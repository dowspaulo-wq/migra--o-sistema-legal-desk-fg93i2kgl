import { useState, useEffect } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
import { Label } from '@/components/ui/label'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Checkbox } from '@/components/ui/checkbox'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { ScrollArea } from '@/components/ui/scroll-area'
import { toast } from '@/hooks/use-toast'
import useLegalStore from '@/stores/useLegalStore'

interface FeeCase {
  id: string
  number: string
  type?: string | null
}

export function ClientFeesDialog({
  open,
  onOpenChange,
  clientId,
  cases,
}: {
  open: boolean
  onOpenChange: (v: boolean) => void
  clientId: string
  cases: FeeCase[]
}) {
  const { state, addClientFee } = useLegalStore() as any

  const bankOptions = Array.from(
    new Set([...(state?.settings?.bankAccounts || ['ASAAS', 'SICOOB'])]),
  )

  const [amount, setAmount] = useState('')
  const [description, setDescription] = useState('')
  const [dueDate, setDueDate] = useState(new Date().toISOString().split('T')[0])
  const [selectedCaseIds, setSelectedCaseIds] = useState<string[]>([])
  const [status, setStatus] = useState('Previsto')
  const [bankAccount, setBankAccount] = useState('ASAAS')

  useEffect(() => {
    if (open) {
      setAmount('')
      setDescription('')
      setDueDate(new Date().toISOString().split('T')[0])
      setSelectedCaseIds([])
      setStatus('Previsto')
      setBankAccount(state?.settings?.bankAccounts?.[0] || 'ASAAS')
    }
  }, [open, state?.settings])

  const toggleCase = (caseId: string) => {
    setSelectedCaseIds((prev) =>
      prev.includes(caseId) ? prev.filter((id) => id !== caseId) : [...prev, caseId],
    )
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    const parsedAmount = parseFloat(amount.replace(',', '.'))
    if (!amount || isNaN(parsedAmount) || parsedAmount <= 0) {
      toast({ title: 'Erro', description: 'Informe um valor válido.', variant: 'destructive' })
      return
    }
    if (!description) {
      toast({ title: 'Erro', description: 'Informe uma descrição.', variant: 'destructive' })
      return
    }
    if (selectedCaseIds.length === 0) {
      toast({
        title: 'Erro',
        description: 'Selecione ao menos um processo.',
        variant: 'destructive',
      })
      return
    }

    await addClientFee({
      amount: parsedAmount,
      description,
      date: dueDate,
      clientId,
      caseIds: selectedCaseIds,
      bankAccount,
      status,
    })

    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <form onSubmit={handleSubmit} className="grid gap-4">
          <DialogHeader>
            <DialogTitle>Novo Honorário</DialogTitle>
          </DialogHeader>

          <div className="space-y-2">
            <Label>Descrição *</Label>
            <Input
              required
              placeholder="Ex: Honorários contratuais - Acordo"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>Valor (R$) *</Label>
              <Input
                type="number"
                step="0.01"
                required
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label>Data de Vencimento *</Label>
              <Input
                type="date"
                required
                value={dueDate}
                onChange={(e) => setDueDate(e.target.value)}
              />
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>Status *</Label>
              <Select value={status} onValueChange={setStatus}>
                <SelectTrigger>
                  <SelectValue placeholder="Status" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Previsto">Previsto</SelectItem>
                  <SelectItem value="Realizado">Realizado</SelectItem>
                  <SelectItem value="Pago">Pago / Recebido</SelectItem>
                  <SelectItem value="Pendente">Pendente</SelectItem>
                  <SelectItem value="Atrasado">Atrasado</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Banco / Conta</Label>
              <Select value={bankAccount} onValueChange={setBankAccount}>
                <SelectTrigger>
                  <SelectValue placeholder="Conta" />
                </SelectTrigger>
                <SelectContent>
                  {bankOptions.map((b) => (
                    <SelectItem key={b} value={b}>
                      {b}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="space-y-2">
            <Label>
              Processos Vinculados ({selectedCaseIds.length} selecionado
              {selectedCaseIds.length !== 1 ? 's' : ''}) *
            </Label>
            <ScrollArea className="h-[200px] rounded-md border p-3">
              <div className="space-y-2">
                {cases.length === 0 && (
                  <p className="text-sm text-muted-foreground">Nenhum processo encontrado.</p>
                )}
                {cases.map((c) => (
                  <div key={c.id} className="flex items-center space-x-2">
                    <Checkbox
                      id={`fee-case-${c.id}`}
                      checked={selectedCaseIds.includes(c.id)}
                      onCheckedChange={() => toggleCase(c.id)}
                    />
                    <Label
                      htmlFor={`fee-case-${c.id}`}
                      className="text-sm font-normal cursor-pointer"
                    >
                      {c.number}
                      {c.type ? ` — ${c.type}` : ''}
                    </Label>
                  </div>
                ))}
              </div>
            </ScrollArea>
          </div>

          <DialogFooter>
            <Button type="submit">Salvar Honorário</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
