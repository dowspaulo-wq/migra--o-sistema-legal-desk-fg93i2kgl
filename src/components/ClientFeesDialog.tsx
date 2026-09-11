import { useEffect } from 'react'
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
import { useClientFeesFormStore } from '@/stores/useClientFeesFormStore'
import { toast } from '@/hooks/use-toast'
import { getFeeTypeOptions, isSuccessFeeType, isNonFinancialFeeType } from '@/lib/fee-types'

export function ClientFeesDialog({
  open,
  onOpenChange,
  clientId,
  cases,
  onCancel,
}: {
  open: boolean
  onOpenChange: (v: boolean) => void
  clientId: string
  cases: any[]
  onCancel?: () => void
}) {
  const { state, addClientFee } = useLegalStore()
  const { draft, setDraft, clearDraft, activeClientId } = useClientFeesFormStore()

  const transactionCategories = (state.settings?.transactionCategories as string[]) || []
  const feeTypeOptions = getFeeTypeOptions(transactionCategories)

  // Inicializa o rascunho apenas se ainda não existir ou for de outro cliente
  useEffect(() => {
    if (open && (!draft || activeClientId !== clientId)) {
      const initialType = transactionCategories[0] || 'Honorários Contratuais'
      const isInitialSuccess = isSuccessFeeType(initialType)
      const defaultBank = state.settings?.bankAccounts?.[0] || 'ASAAS'

      setDraft({
        description: '',
        amount: '',
        date: isInitialSuccess ? '' : new Date().toISOString().split('T')[0],
        installments: '1',
        paymentMethod: 'PIX',
        bankAccount: defaultBank,
        status: isInitialSuccess ? 'Êxito' : 'Previsto',
        feeType: initialType,
        percentage: '',
        selectedCases: [],
      })
    }
  }, [
    open,
    clientId,
    activeClientId,
    draft,
    state.settings?.bankAccounts,
    transactionCategories,
    setDraft,
  ])

  const currentDraft = draft || {
    description: '',
    amount: '',
    date: new Date().toISOString().split('T')[0],
    installments: '1',
    paymentMethod: 'PIX',
    bankAccount: state.settings?.bankAccounts?.[0] || 'ASAAS',
    status: 'Previsto',
    feeType: transactionCategories[0] || 'Honorários Contratuais',
    percentage: '',
    selectedCases: [],
  }

  const isSuccessFee = isSuccessFeeType(currentDraft.feeType)
  const isNonFinancial = isNonFinancialFeeType(currentDraft.feeType)

  const bankOptions = Array.from(
    new Set([...(state.settings?.bankAccounts || ['ASAAS', 'SICOOB', 'CAIXA', 'PESSOAL'])]),
  )

  const toggleCase = (caseId: string) => {
    setDraft((prev) => ({
      ...prev,
      selectedCases: prev.selectedCases.includes(caseId)
        ? prev.selectedCases.filter((id) => id !== caseId)
        : [...prev.selectedCases, caseId],
    }))
  }

  const handleFeeTypeChange = (newFeeType: string) => {
    const isNewSuccess = isSuccessFeeType(newFeeType)
    setDraft((prev) => ({
      ...prev,
      feeType: newFeeType,
      status: isNewSuccess ? 'Êxito' : prev.status === 'Êxito' ? 'Previsto' : prev.status,
      date: isNewSuccess ? '' : !prev.date ? new Date().toISOString().split('T')[0] : prev.date,
    }))
  }

  const handleCancel = () => {
    clearDraft()
    if (onCancel) onCancel()
    onOpenChange(false)
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    if (
      !currentDraft.description ||
      !currentDraft.amount ||
      (!currentDraft.date && !isSuccessFee)
    ) {
      toast({
        title: 'Campos Obrigatórios',
        description: isSuccessFee
          ? 'Preencha descrição e valor. O vencimento é opcional para honorários de êxito.'
          : 'Preencha descrição, valor e data.',
        variant: 'destructive',
      })
      return
    }

    const parsedAmount = parseFloat(currentDraft.amount.replace(',', '.'))
    const parsedInstallments = parseInt(currentDraft.installments, 10) || 1

    await addClientFee({
      amount: parsedAmount,
      description: currentDraft.description,
      date: currentDraft.date || new Date().toISOString().split('T')[0],
      clientId,
      caseIds: currentDraft.selectedCases,
      bankAccount: currentDraft.bankAccount,
      status: currentDraft.status,
      installments: parsedInstallments,
      paymentMethod: currentDraft.paymentMethod,
      feeType: currentDraft.feeType,
      percentage: isSuccessFee
        ? parseFloat(currentDraft.percentage.replace(',', '.')) || undefined
        : undefined,
    })

    // Ao salvar com sucesso, limpa o rascunho persistido
    clearDraft()
    onOpenChange(false)
  }

  const installmentValue =
    parseFloat(currentDraft.amount.replace(',', '.')) /
    (parseInt(currentDraft.installments, 10) || 1)

  return (
    <Dialog
      open={open}
      onOpenChange={(v) => {
        if (!v) {
          // Quando o usuário fecha pelo 'X' ou backdrop, fechamos a visualização mas NÃO apagamos os dados digitados
          onOpenChange(false)
        } else {
          onOpenChange(true)
        }
      }}
    >
      <DialogContent className="max-w-md max-h-[90vh] overflow-y-auto">
        <form onSubmit={handleSubmit} className="grid gap-4">
          <DialogHeader>
            <DialogTitle>Novo Honorário</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-2">
              <Label>Tipo de Honorário *</Label>
              <Select value={currentDraft.feeType} onValueChange={handleFeeTypeChange}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {feeTypeOptions.map((t) => (
                    <SelectItem key={t} value={t}>
                      {t}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Descrição *</Label>
              <Input
                required
                placeholder="Ex: Honorários contratuais"
                value={currentDraft.description}
                onChange={(e) => setDraft({ description: e.target.value })}
              />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Valor (R$) *</Label>
                <Input
                  type="number"
                  step="0.01"
                  required
                  value={currentDraft.amount}
                  onChange={(e) => setDraft({ amount: e.target.value })}
                />
              </div>
              <div className="space-y-2">
                <Label>Parcelas</Label>
                <Input
                  type="number"
                  min="1"
                  max="120"
                  value={currentDraft.installments}
                  onChange={(e) => setDraft({ installments: e.target.value })}
                />
              </div>
            </div>
            {isSuccessFee && (
              <div className="space-y-2">
                <Label>Percentual (%)</Label>
                <Input
                  type="number"
                  step="0.01"
                  min="0"
                  max="100"
                  placeholder="Ex: 30"
                  value={currentDraft.percentage}
                  onChange={(e) => setDraft({ percentage: e.target.value })}
                />
              </div>
            )}
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Vencimento {isSuccessFee ? '(Opcional)' : '*'}</Label>
                <Input
                  type="date"
                  required={!isSuccessFee}
                  value={currentDraft.date}
                  onChange={(e) => setDraft({ date: e.target.value })}
                />
              </div>
              <div className="space-y-2">
                <Label>Forma de Pagamento</Label>
                <Select
                  value={currentDraft.paymentMethod}
                  onValueChange={(val) => setDraft({ paymentMethod: val })}
                >
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
                <Select
                  value={currentDraft.status}
                  onValueChange={(val) => setDraft({ status: val })}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Previsto">Previsto</SelectItem>
                    <SelectItem value="Realizado">Realizado</SelectItem>
                    <SelectItem value="Pago">Pago</SelectItem>
                    <SelectItem value="Pendente">Pendente</SelectItem>
                    <SelectItem value="Atrasado">Atrasado</SelectItem>
                    <SelectItem value="Êxito">Êxito</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label>Banco / Conta</Label>
                <Select
                  value={currentDraft.bankAccount}
                  onValueChange={(val) => setDraft({ bankAccount: val })}
                >
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
                        checked={currentDraft.selectedCases.includes(c.id)}
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
            {isNonFinancial && (
              <div className="bg-amber-50 border border-amber-200 rounded-md p-3 text-sm text-amber-700">
                ⚠️ Esta modalidade não gera lançamentos financeiros. O tipo será registrado apenas
                no processo.
              </div>
            )}
            {isSuccessFee && (
              <div className="bg-blue-50 border border-blue-200 rounded-md p-3 text-sm text-blue-700">
                ℹ️ Honorários de Êxito: o vencimento é opcional pois a data de recebimento é
                incerta. O status será definido como "Êxito".
                {currentDraft.percentage && (
                  <>
                    {' '}
                    Percentual de {parseFloat(currentDraft.percentage.replace(',', '.'))}% aplicado
                    sobre o valor do processo.
                  </>
                )}
              </div>
            )}
            {!isNonFinancial &&
              !isSuccessFee &&
              parseInt(currentDraft.installments, 10) > 1 &&
              !isNaN(installmentValue) && (
                <div className="bg-blue-50 border border-blue-200 rounded-md p-3 text-sm text-blue-700">
                  Serão criadas {currentDraft.installments} parcelas de R${' '}
                  {installmentValue.toLocaleString('pt-BR', {
                    minimumFractionDigits: 2,
                  })}{' '}
                  cada, com vencimentos mensais.
                </div>
              )}
          </div>
          <DialogFooter className="flex justify-between items-center w-full">
            <Button type="button" variant="outline" onClick={handleCancel}>
              Cancelar
            </Button>
            <Button type="submit">Salvar</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
