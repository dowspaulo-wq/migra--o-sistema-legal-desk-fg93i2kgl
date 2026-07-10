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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Button } from '@/components/ui/button'
import { Checkbox } from '@/components/ui/checkbox'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'

export function ClientFeesDialog({
  open,
  onOpenChange,
  clientId,
  cases,
}: {
  open: boolean
  onOpenChange: (v: boolean) => void
  clientId: string
  cases: any[]
}) {
  const { state, addClientFee } = useLegalStore()

  const [description, setDescription] = useState('')
  const [amount, setAmount] = useState('')
  const [date, setDate] = useState(new Date().toISOString().split('T')[0])
  const [installments, setInstallments] = useState('1')
  const [paymentMethod, setPaymentMethod] = useState('PIX')
  const [bankAccount, setBankAccount] = useState('ASAAS')
  const [status, setStatus] = useState('Previsto')
  const [selectedCases, setSelectedCases] = useState<string[]>([])

  useEffect(() => {
    if (open) {
      setDescription('')
      setAmount('')
      setDate(new Date().toISOString().split('T')[0])
      setInstallments('1')
      setPaymentMethod('PIX')
      setBankAccount(state.settings?.bankAccounts?.[0] || 'ASAAS')
      setStatus('Previsto')
      setSelectedCases([])
    }
  }, [open, state.settings])

  const bankOptions = Array.from(
    new Set([...(state.settings?.bankAccounts || ['ASAAS', 'SICOOB'])]),
  )

  const toggleCase = (caseId: string) => {
    setSelectedCases((prev) =>
      prev.includes(caseId) ? prev.filter((id) => id !== caseId) : [...prev, caseId],
    )
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!description || !amount || !date) {
      toast({
        title: 'Campos Obrigatórios',
        description: 'Preencha descrição, valor e data.',
        variant: 'destructive',
      })
      return
    }

    const parsedAmount = parseFloat(amount.replace(',', '.'))
    const parsedInstallments = parseInt(installments, 10) || 1

    await addClientFee({
      amount: parsedAmount,
      description,
      date,
      clientId,
      caseIds: selectedCases,
      bankAccount,
      status,
      installments: parsedInstallments,
      paymentMethod,
    })

    onOpenChange(false)
  }

  const installmentValue = parseFloat(amount.replace(',', '.')) / (parseInt(installments, 10) || 1)

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md max-h-[90vh] overflow-y-auto">
        <form onSubmit={handleSubmit} className="grid gap-4">
          <DialogHeader>
            <DialogTitle>Novo Honorário</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-2">
              <Label>Descrição *</Label>
              <Input
                required
                placeholder="Ex: Honorários contratuais"
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
                <Label>Parcelas</Label>
                <Input
                  type="number"
                  min="1"
                  max="120"
                  value={installments}
                  onChange={(e) => setInstallments(e.target.value)}
                />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Vencimento *</Label>
                <Input
                  type="date"
                  required
                  value={date}
                  onChange={(e) => setDate(e.target.value)}
                />
              </div>
              <div className="space-y-2">
                <Label>Forma de Pagamento</Label>
                <Select value={paymentMethod} onValueChange={setPaymentMethod}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="PIX">PIX</SelectItem>
                    <SelectItem value="BOLETO">Boleto</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Status</Label>
                <Select value={status} onValueChange={setStatus}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Previsto">Previsto</SelectItem>
                    <SelectItem value="Realizado">Realizado</SelectItem>
                    <SelectItem value="Pago">Pago</SelectItem>
                    <SelectItem value="Pendente">Pendente</SelectItem>
                    <SelectItem value="Atrasado">Atrasado</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label>Banco / Conta</Label>
                <Select value={bankAccount} onValueChange={setBankAccount}>
                  <SelectTrigger>
                    <SelectValue />
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
            {cases.length > 0 && (
              <div className="space-y-2">
                <Label>Processos Vinculados</Label>
                <div className="max-h-32 overflow-y-auto space-y-2 border rounded-md p-3">
                  {cases.map((c) => (
                    <div key={c.id} className="flex items-center space-x-2">
                      <Checkbox
                        id={`fee-case-${c.id}`}
                        checked={selectedCases.includes(c.id)}
                        onCheckedChange={() => toggleCase(c.id)}
                      />
                      <Label htmlFor={`fee-case-${c.id}`} className="text-sm cursor-pointer">
                        {c.number}
                      </Label>
                    </div>
                  ))}
                </div>
              </div>
            )}
            {parseInt(installments, 10) > 1 && !isNaN(installmentValue) && (
              <div className="bg-blue-50 border border-blue-200 rounded-md p-3 text-sm text-blue-700">
                Serão criadas {installments} parcelas de R${' '}
                {installmentValue.toLocaleString('pt-BR', { minimumFractionDigits: 2 })} cada, com
                vencimentos mensais.
              </div>
            )}
          </div>
          <DialogFooter>
            <Button type="submit">Salvar</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
