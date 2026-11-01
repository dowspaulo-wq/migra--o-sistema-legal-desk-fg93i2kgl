import { useState, useEffect } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
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
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Checkbox } from '@/components/ui/checkbox'
import useLegalStore from '@/stores/useLegalStore'
import { useClientFeesFormStore } from '@/stores/useClientFeesFormStore'
import { toast } from '@/hooks/use-toast'
import {
  getFeeTypeOptions,
  isSuccessFeeType,
  isNonFinancialFeeType,
  capitalizeFirstLetter,
} from '@/lib/fee-types'
import { findDuplicateTransaction } from '@/lib/anti-duplicate'
import { formatSafeLocalDate } from '@/lib/utils'
import type { Transaction } from '@/lib/mockData'

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
  // Apenas honorários (sem despesas), em ordem alfabética
  const feeTypeOptions = getFeeTypeOptions(transactionCategories, false)

  // Alternância R$ ou % para honorários de êxito
  const [valueMode, setValueMode] = useState<'fixed' | 'percent'>('fixed')
  const [duplicateWarning, setDuplicateWarning] = useState<{
    matched: Transaction
    pendingFee: any
  } | null>(null)

  const currentYear = new Date().getFullYear()
  const defaultSuccessDueDate = `${currentYear}-12-31`

  // Inicializa o rascunho apenas se ainda não existir ou for de outro cliente
  useEffect(() => {
    if (open && (!draft || activeClientId !== clientId)) {
      const initialType = 'Honorários Contratuais'
      const isInitialSuccess = isSuccessFeeType(initialType)
      const defaultBank = state.settings?.bankAccounts?.[0] || 'ASAAS'

      setValueMode('fixed')
      setDraft({
        description: '',
        amount: '',
        date: isInitialSuccess ? defaultSuccessDueDate : new Date().toISOString().split('T')[0],
        installments: '1',
        paymentMethod: 'PIX',
        bankAccount: defaultBank,
        status: 'Previsto',
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
    setDraft,
    defaultSuccessDueDate,
  ])

  const currentDraft = draft || {
    description: '',
    amount: '',
    date: new Date().toISOString().split('T')[0],
    installments: '1',
    paymentMethod: 'PIX',
    bankAccount: state.settings?.bankAccounts?.[0] || 'ASAAS',
    status: 'Previsto',
    feeType: 'Honorários Contratuais',
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
      status: 'Previsto',
      date: isNewSuccess
        ? prev.date || defaultSuccessDueDate
        : prev.date || new Date().toISOString().split('T')[0],
    }))
    if (!isNewSuccess) {
      setValueMode('fixed')
    }
  }

  const handleCancel = () => {
    clearDraft()
    if (onCancel) onCancel()
    onOpenChange(false)
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    const rawDescription = currentDraft.description.trim()
    if (!rawDescription) {
      toast({
        title: 'Campo Obrigatório',
        description: 'Preencha a descrição do honorário.',
        variant: 'destructive',
      })
      return
    }

    if (!isSuccessFee && !currentDraft.amount) {
      toast({
        title: 'Valor Obrigatório',
        description: 'Informe o valor dos honorários.',
        variant: 'destructive',
      })
      return
    }

    if (
      isSuccessFee &&
      valueMode === 'percent' &&
      !currentDraft.percentage &&
      !currentDraft.amount
    ) {
      toast({
        title: 'Valor ou Percentual Obrigatório',
        description: 'Informe a porcentagem do êxito ou o valor em R$.',
        variant: 'destructive',
      })
      return
    }

    const parsedAmount = currentDraft.amount ? parseFloat(currentDraft.amount.replace(',', '.')) : 0
    const parsedPercent = currentDraft.percentage
      ? parseFloat(currentDraft.percentage.replace(',', '.'))
      : undefined
    const parsedInstallments = parseInt(currentDraft.installments, 10) || 1
    const finalDescription = capitalizeFirstLetter(rawDescription)

    const targetDate =
      currentDraft.date ||
      (isSuccessFee ? defaultSuccessDueDate : new Date().toISOString().split('T')[0])

    const feePayload = {
      amount: parsedAmount,
      description: finalDescription,
      date: targetDate,
      clientId,
      caseIds: currentDraft.selectedCases,
      bankAccount: currentDraft.bankAccount,
      status: currentDraft.status || 'Previsto',
      installments: parsedInstallments,
      paymentMethod: currentDraft.paymentMethod,
      feeType: currentDraft.feeType,
      percentage: isSuccessFee ? parsedPercent : undefined,
    }

    // Se for honorário que gera lançamento financeiro, verifica se já existe duplicado
    if (!isNonFinancial && parsedAmount > 0) {
      const existingList = (state?.transactions || []) as Transaction[]
      const duplicateMatch = findDuplicateTransaction(
        {
          date: targetDate,
          amount: parsedInstallments > 1 ? parsedAmount / parsedInstallments : parsedAmount,
          description:
            parsedInstallments > 1
              ? `${finalDescription} (1/${parsedInstallments})`
              : finalDescription,
          bankAccount: currentDraft.bankAccount,
          clientId,
        },
        existingList,
      )

      if (duplicateMatch) {
        setDuplicateWarning({
          matched: duplicateMatch,
          pendingFee: feePayload,
        })
        return
      }
    }

    await addClientFee(feePayload)
    clearDraft()
    onOpenChange(false)
  }

  const handleConfirmDuplicateSave = async () => {
    if (!duplicateWarning) return
    const { pendingFee } = duplicateWarning
    setDuplicateWarning(null)
    await addClientFee(pendingFee)
    clearDraft()
    onOpenChange(false)
  }

  const installmentValue =
    (parseFloat(currentDraft.amount.replace(',', '.')) || 0) /
    (parseInt(currentDraft.installments, 10) || 1)

  return (
    <>
      <Dialog
        open={open}
        onOpenChange={(v) => {
          if (!v) {
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
                  onChange={(e) => setDraft({ description: capitalizeFirstLetter(e.target.value) })}
                />
              </div>

              {/* Alternância R$ ou % para honorários de êxito */}
              {isSuccessFee && (
                <div className="space-y-2 bg-blue-50/70 p-3 rounded-md border border-blue-100">
                  <Label className="text-xs font-semibold text-blue-900 block mb-1">
                    Forma de Cobrança do Êxito
                  </Label>
                  <div className="flex gap-2">
                    <Button
                      type="button"
                      size="sm"
                      variant={valueMode === 'fixed' ? 'default' : 'outline'}
                      className="flex-1 h-8 text-xs"
                      onClick={() => setValueMode('fixed')}
                    >
                      Valor em R$
                    </Button>
                    <Button
                      type="button"
                      size="sm"
                      variant={valueMode === 'percent' ? 'default' : 'outline'}
                      className="flex-1 h-8 text-xs"
                      onClick={() => setValueMode('percent')}
                    >
                      Porcentagem (%)
                    </Button>
                  </div>
                </div>
              )}

              <div className="grid grid-cols-2 gap-4">
                {isSuccessFee && valueMode === 'percent' ? (
                  <div className="space-y-2">
                    <Label>Percentual (%) *</Label>
                    <Input
                      type="number"
                      step="0.01"
                      min="0"
                      max="100"
                      required
                      placeholder="Ex: 30"
                      value={currentDraft.percentage}
                      onChange={(e) => setDraft({ percentage: e.target.value })}
                    />
                    <span className="text-[11px] text-muted-foreground block">
                      Valor ficará como &quot;A apurar&quot;
                    </span>
                  </div>
                ) : (
                  <div className="space-y-2">
                    <Label>Valor (R$) {isSuccessFee ? '(Opcional se a apurar)' : '*'}</Label>
                    <Input
                      type="number"
                      step="0.01"
                      required={!isSuccessFee}
                      placeholder="0,00"
                      value={currentDraft.amount}
                      onChange={(e) => setDraft({ amount: e.target.value })}
                    />
                  </div>
                )}
                <div className="space-y-2">
                  <Label>Parcelas</Label>
                  <Input
                    type="number"
                    min="1"
                    max="120"
                    disabled={isSuccessFee && valueMode === 'percent'}
                    value={currentDraft.installments}
                    onChange={(e) => setDraft({ installments: e.target.value })}
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Vencimento {isSuccessFee ? '(Padrão 31/12)' : '*'}</Label>
                  <Input
                    type="date"
                    required
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
                      <SelectItem value="Pago">Pago</SelectItem>
                      <SelectItem value="Pendente">Pendente</SelectItem>
                      <SelectItem value="Atrasado">Atrasado</SelectItem>
                      <SelectItem value="Cancelado">Cancelado</SelectItem>
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
                <div className="bg-blue-50 border border-blue-200 rounded-md p-3 text-xs text-blue-700 space-y-1">
                  <p className="font-semibold">ℹ️ Honorários de Êxito:</p>
                  <p>
                    Vencimento padrão em 31/12 do ano corrente. Status &quot;Previsto&quot;. Caso a
                    ação seja ganha, altere para &quot;Pago&quot; com o valor apurado.
                  </p>
                  {valueMode === 'percent' && currentDraft.percentage && (
                    <p className="font-medium text-blue-800">
                      Percentual: {currentDraft.percentage}% (Valor exibido: &quot;A apurar&quot;)
                    </p>
                  )}
                </div>
              )}

              {!isNonFinancial &&
                !isSuccessFee &&
                parseInt(currentDraft.installments, 10) > 1 &&
                !isNaN(installmentValue) &&
                installmentValue > 0 && (
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

      {/* Modal de aviso de provável duplicado para Honorários */}
      <AlertDialog
        open={Boolean(duplicateWarning)}
        onOpenChange={(v) => {
          if (!v) setDuplicateWarning(null)
        }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle className="text-amber-800 flex items-center gap-2">
              ⚠️ Provável honorário duplicado detectado
            </AlertDialogTitle>
            <AlertDialogDescription className="space-y-3 text-slate-700">
              <p>
                Já existe um lançamento financeiro no sistema com a mesma data, valor, descrição e
                conta para este cliente:
              </p>
              {duplicateWarning?.matched && (
                <div className="bg-amber-50/80 border border-amber-200 rounded-lg p-3 text-xs space-y-1 font-sans text-slate-800">
                  <p>
                    <strong className="text-slate-900">Data:</strong>{' '}
                    {formatSafeLocalDate(duplicateWarning.matched.date)}
                  </p>
                  <p>
                    <strong className="text-slate-900">Descrição:</strong>{' '}
                    {duplicateWarning.matched.description}
                  </p>
                  <p>
                    <strong className="text-slate-900">Valor:</strong> R${' '}
                    {Number(duplicateWarning.matched.amount || 0).toLocaleString('pt-BR', {
                      minimumFractionDigits: 2,
                    })}
                  </p>
                  <p>
                    <strong className="text-slate-900">Conta / Origem:</strong>{' '}
                    {duplicateWarning.matched.bankAccount || 'Não informada'}
                  </p>
                  {duplicateWarning.matched.status && (
                    <p>
                      <strong className="text-slate-900">Status atual:</strong>{' '}
                      {duplicateWarning.matched.status}
                    </p>
                  )}
                </div>
              )}
              <p className="text-xs text-muted-foreground">
                Deseja salvar este honorário mesmo assim ou cancelar?
              </p>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel onClick={() => setDuplicateWarning(null)}>
              Cancelar
            </AlertDialogCancel>
            <AlertDialogAction
              onClick={handleConfirmDuplicateSave}
              className="bg-amber-600 hover:bg-amber-700 text-white"
            >
              Salvar mesmo assim
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  )
}
