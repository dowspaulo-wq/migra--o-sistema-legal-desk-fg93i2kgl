import React, { useState, useEffect } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
  DialogDescription,
} from '@/components/ui/dialog'
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
import { Textarea } from '@/components/ui/textarea'
import { Badge } from '@/components/ui/badge'
import { Calculator, Calendar, Percent, DollarSign, AlertCircle, ArrowRight } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'
import { useFinancePermissions } from '@/hooks/use-finance-permissions'

interface PaymentPlanDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  defaultClientId?: string
  defaultProcessId?: string
}

export function PaymentPlanDialog({
  open,
  onOpenChange,
  defaultClientId,
  defaultProcessId,
}: PaymentPlanDialogProps) {
  const { state, addPaymentPlan } = useLegalStore()
  const { canManagePaymentPlans } = useFinancePermissions()

  const [clientId, setClientId] = useState<string>(defaultClientId || '')
  const [processId, setProcessId] = useState<string>(defaultProcessId || '')
  const [title, setTitle] = useState<string>('')
  const [installmentAmount, setInstallmentAmount] = useState<number>(500)
  const [installmentsCount, setInstallmentsCount] = useState<number>(18)
  const [periodicity, setPeriodicity] = useState<string>('mensal')
  const [firstDueDate, setFirstDueDate] = useState<string>(
    () => new Date().toISOString().split('T')[0],
  )
  const [feePercentage, setFeePercentage] = useState<number>(30)
  const [bankAccount, setBankAccount] = useState<string>('ASAAS')
  const [paymentMethod, setPaymentMethod] = useState<string>('PIX')
  const [notes, setNotes] = useState<string>('')
  const [isSubmitting, setIsSubmitting] = useState(false)

  // Lista dinâmica de contas bancárias de settings.bankAccounts com fallback "Dinheiro Físico"
  const availableBankAccounts = React.useMemo(() => {
    const configured = (state?.settings?.bankAccounts || []).filter(
      (b): b is string => typeof b === 'string' && b.trim().length > 0,
    )
    if (configured.length > 0) {
      return configured
    }
    return ['Dinheiro Físico']
  }, [state?.settings?.bankAccounts])

  // Fecha imediatamente o diálogo se colaborador tentar abrir
  useEffect(() => {
    if (open && !canManagePaymentPlans) {
      toast({
        title: 'Acesso negado',
        description:
          'Usuários colaboradores não têm permissão para criar ou gerenciar parcelamentos.',
        variant: 'destructive',
      })
      onOpenChange(false)
    }
  }, [open, canManagePaymentPlans, onOpenChange])

  // Garante que a conta selecionada seja válida dentro da lista disponível
  useEffect(() => {
    if (availableBankAccounts.length > 0 && !availableBankAccounts.includes(bankAccount)) {
      setBankAccount(availableBankAccounts[0])
    }
  }, [availableBankAccounts, bankAccount])

  // Atualiza defaultClientId e defaultProcessId quando o modal abrir
  useEffect(() => {
    if (open) {
      if (defaultClientId) setClientId(defaultClientId)
      if (defaultProcessId) setProcessId(defaultProcessId)
      if (!title) {
        const client = state.clients.find((c) => c.id === defaultClientId)
        setTitle(
          client
            ? `Parcelamento com Repasse - ${client.name}`
            : 'Parcelamento com Repasse ao Cliente',
        )
      }
    }
  }, [open, defaultClientId, defaultProcessId, state.clients])

  // Casos do cliente selecionado
  const availableCases = React.useMemo(() => {
    if (!clientId) return []
    return state.cases.filter((c) => c.clientId === clientId)
  }, [clientId, state.cases])

  // Cálculos matemáticos em tempo real
  const feePct = Math.max(0, Math.min(100, Number(feePercentage) || 0))
  const clientPct = 100 - feePct
  const instAmt = Math.max(0, Number(installmentAmount) || 0)
  const count = Math.max(1, parseInt(String(installmentsCount), 10) || 1)

  const feeInstallment = Math.round(instAmt * (feePct / 100) * 100) / 100
  const clientInstallment = Math.round((instAmt - feeInstallment) * 100) / 100

  const totalFull = Math.round(instAmt * count * 100) / 100
  const totalFee = Math.round(feeInstallment * count * 100) / 100
  const totalClient = Math.round(clientInstallment * count * 100) / 100

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!canManagePaymentPlans) {
      toast({
        title: 'Acesso negado',
        description: 'Ação de parcelamento bloqueada para colaborador.',
        variant: 'destructive',
      })
      onOpenChange(false)
      return
    }

    if (!clientId) {
      toast({
        title: 'Selecione um cliente',
        description: 'Todo parcelamento precisa estar vinculado a um cliente.',
        variant: 'destructive',
      })
      return
    }

    if (instAmt <= 0) {
      toast({
        title: 'Valor inválido',
        description: 'O valor da parcela deve ser maior que zero.',
        variant: 'destructive',
      })
      return
    }

    if (count <= 0) {
      toast({
        title: 'Número de parcelas inválido',
        description: 'O parcelamento deve ter pelo menos 1 parcela.',
        variant: 'destructive',
      })
      return
    }

    if (!firstDueDate) {
      toast({
        title: 'Data da 1ª parcela',
        description: 'Informe a data de vencimento da primeira parcela.',
        variant: 'destructive',
      })
      return
    }

    setIsSubmitting(true)
    try {
      const result = await addPaymentPlan({
        clientId,
        processId: processId || null,
        title: title.trim() || `Parcelamento (${count}x de R$ ${instAmt})`,
        installmentAmount: instAmt,
        installmentsCount: count,
        periodicity,
        firstDueDate,
        feePercentage: feePct,
        bankAccount,
        paymentMethod,
        notes: notes.trim() || undefined,
      })

      if (result) {
        onOpenChange(false)
      }
    } finally {
      setIsSubmitting(false)
    }
  }

  if (!canManagePaymentPlans) {
    return null
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <div className="flex items-center gap-2">
            <div className="p-2 bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300 rounded-lg">
              <Calculator className="w-5 h-5" />
            </div>
            <div>
              <DialogTitle className="text-xl">
                Novo Parcelamento com Repasse ao Cliente
              </DialogTitle>
              <DialogDescription className="text-sm text-muted-foreground">
                Cria o plano contratual e gera automaticamente os pares de lançamentos (Honorário e
                Repasse).
              </DialogDescription>
            </div>
          </div>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-5 pt-2">
          {/* Cliente e Processo */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <Label htmlFor="plan-client">Cliente *</Label>
              <Select
                value={clientId}
                onValueChange={(val) => {
                  setClientId(val)
                  setProcessId('')
                }}
              >
                <SelectTrigger id="plan-client">
                  <SelectValue placeholder="Selecione o cliente" />
                </SelectTrigger>
                <SelectContent>
                  {state.clients.map((c) => (
                    <SelectItem key={c.id} value={c.id}>
                      {c.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="plan-process">Processo (opcional)</Label>
              <Select
                value={processId || 'none'}
                onValueChange={(val) => setProcessId(val === 'none' ? '' : val)}
              >
                <SelectTrigger id="plan-process">
                  <SelectValue
                    placeholder={
                      availableCases.length > 0
                        ? 'Vincular a processo'
                        : 'Nenhum processo cadastrado'
                    }
                  />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">Nenhum / Geral do cliente</SelectItem>
                  {availableCases.map((cs) => (
                    <SelectItem key={cs.id} value={cs.id}>
                      {cs.number || 'Processo'}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          {/* Título / Identificação */}
          <div className="space-y-1.5">
            <Label htmlFor="plan-title">Título / Identificação do Parcelamento</Label>
            <Input
              id="plan-title"
              placeholder="Ex: Acordo 18x - Ação Trabalhista"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
            />
          </div>

          {/* Parâmetros do Parcelamento */}
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div className="space-y-1.5">
              <Label htmlFor="plan-installment-amount">Valor da Parcela (R$) *</Label>
              <div className="relative">
                <span className="absolute left-3 top-2.5 text-xs text-muted-foreground">R$</span>
                <Input
                  id="plan-installment-amount"
                  type="number"
                  step="0.01"
                  min="0"
                  className="pl-8"
                  value={installmentAmount}
                  onChange={(e) => setInstallmentAmount(parseFloat(e.target.value) || 0)}
                  required
                />
              </div>
              <p className="text-[11px] text-muted-foreground">
                Valor cheio cobrado do pagador (ex: Asaas)
              </p>
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="plan-count">Nº de Parcelas *</Label>
              <Input
                id="plan-count"
                type="number"
                min="1"
                max="120"
                value={installmentsCount}
                onChange={(e) => setInstallmentsCount(parseInt(e.target.value, 10) || 1)}
                required
              />
              <p className="text-[11px] text-muted-foreground">Ex: 18 parcelas mensais</p>
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="plan-fee-pct">% do Honorário *</Label>
              <div className="relative">
                <Input
                  id="plan-fee-pct"
                  type="number"
                  step="0.1"
                  min="0"
                  max="100"
                  className="pr-7"
                  value={feePercentage}
                  onChange={(e) => setFeePercentage(parseFloat(e.target.value) || 0)}
                  required
                />
                <Percent className="w-3.5 h-3.5 absolute right-2.5 top-3 text-muted-foreground" />
              </div>
              <p className="text-[11px] text-muted-foreground">Fixo para todo o plano (ex: 30%)</p>
            </div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div className="space-y-1.5">
              <Label htmlFor="plan-periodicity">Periodicidade</Label>
              <Select value={periodicity} onValueChange={setPeriodicity}>
                <SelectTrigger id="plan-periodicity">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="mensal">Mensal (padrão)</SelectItem>
                  <SelectItem value="semanal">Semanal</SelectItem>
                  <SelectItem value="anual">Anual</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="plan-first-date">Vencimento da 1ª Parcela *</Label>
              <Input
                id="plan-first-date"
                type="date"
                value={firstDueDate}
                onChange={(e) => setFirstDueDate(e.target.value)}
                required
              />
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="plan-bank">Conta de Entrada / Saída</Label>
              <Select value={bankAccount} onValueChange={setBankAccount}>
                <SelectTrigger id="plan-bank">
                  <SelectValue placeholder="Selecione a conta" />
                </SelectTrigger>
                <SelectContent>
                  {availableBankAccounts.map((acc) => (
                    <SelectItem key={acc} value={acc}>
                      {acc}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          {/* CARD DE SIMULAÇÃO VISUAL E MATEMÁTICA */}
          <div className="rounded-xl border border-blue-200 bg-blue-50/60 dark:border-blue-900/60 dark:bg-blue-950/20 p-4 space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-blue-900 dark:text-blue-300">
                <Calculator className="w-3.5 h-3.5" />
                Simulação da Distribuição Financeira
              </div>
              <Badge
                variant="outline"
                className="text-xs bg-white/70 dark:bg-slate-900/70 border-blue-300 dark:border-blue-800"
              >
                {count} pares ({count * 2} lançamentos)
              </Badge>
            </div>

            {/* Divisão por Parcela */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-3 text-sm">
              <div className="bg-white dark:bg-slate-900 p-3 rounded-lg border shadow-sm">
                <span className="text-[11px] text-muted-foreground uppercase font-medium">
                  Cobrança Cheia (por mês)
                </span>
                <div className="text-lg font-bold text-slate-900 dark:text-slate-100 mt-0.5">
                  R${' '}
                  {instAmt.toLocaleString('pt-BR', {
                    minimumFractionDigits: 2,
                    maximumFractionDigits: 2,
                  })}
                </div>
                <div className="text-[11px] text-muted-foreground mt-1">
                  Valor cobrado do pagador
                </div>
              </div>

              <div className="bg-emerald-50 dark:bg-emerald-950/30 p-3 rounded-lg border border-emerald-200 dark:border-emerald-800 shadow-sm">
                <div className="flex items-center justify-between">
                  <span className="text-[11px] text-emerald-800 dark:text-emerald-300 uppercase font-medium">
                    Honorário ({feePct}%)
                  </span>
                  <Badge
                    variant="outline"
                    className="text-[10px] px-1.5 py-0 bg-emerald-100 text-emerald-800 border-emerald-300 dark:bg-emerald-900/60 dark:text-emerald-300"
                  >
                    Receita
                  </Badge>
                </div>
                <div className="text-lg font-bold text-emerald-700 dark:text-emerald-400 mt-0.5">
                  R${' '}
                  {feeInstallment.toLocaleString('pt-BR', {
                    minimumFractionDigits: 2,
                    maximumFractionDigits: 2,
                  })}
                </div>
                <div className="text-[11px] text-emerald-600 dark:text-emerald-400 mt-1">
                  Sua receita líquida do mês
                </div>
              </div>

              <div className="bg-amber-50 dark:bg-amber-950/30 p-3 rounded-lg border border-amber-200 dark:border-amber-800 shadow-sm">
                <div className="flex items-center justify-between">
                  <span className="text-[11px] text-amber-800 dark:text-amber-300 uppercase font-medium">
                    Repasse ({clientPct}%)
                  </span>
                  <Badge
                    variant="outline"
                    className="text-[10px] px-1.5 py-0 bg-amber-100 text-amber-800 border-amber-300 dark:bg-amber-900/60 dark:text-amber-300"
                  >
                    Despesa Real
                  </Badge>
                </div>
                <div className="text-lg font-bold text-amber-700 dark:text-amber-400 mt-0.5">
                  R${' '}
                  {clientInstallment.toLocaleString('pt-BR', {
                    minimumFractionDigits: 2,
                    maximumFractionDigits: 2,
                  })}
                </div>
                <div className="text-[11px] text-amber-600 dark:text-amber-400 mt-1">
                  Sai do caixa para o cliente
                </div>
              </div>
            </div>

            {/* Totais do Contrato */}
            <div className="pt-2 border-t border-blue-200/80 dark:border-blue-900/80 flex flex-wrap items-center justify-between text-xs text-muted-foreground gap-2">
              <div>
                Total do contrato ({count}x):{' '}
                <strong className="text-foreground">
                  R$ {totalFull.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
                </strong>
              </div>
              <div>
                Total Honorários:{' '}
                <strong className="text-emerald-600 dark:text-emerald-400">
                  R$ {totalFee.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
                </strong>
              </div>
              <div>
                Total Repasse Cliente:{' '}
                <strong className="text-amber-600 dark:text-amber-400">
                  R$ {totalClient.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
                </strong>
              </div>
            </div>
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="plan-notes">Observações do Acordo</Label>
            <Textarea
              id="plan-notes"
              rows={2}
              placeholder="Informações adicionais do parcelamento, conta do cliente para repasse PIX, etc."
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
            />
          </div>

          <DialogFooter className="gap-2 sm:gap-0">
            <Button
              type="button"
              variant="outline"
              onClick={() => onOpenChange(false)}
              disabled={isSubmitting}
            >
              Cancelar
            </Button>
            <Button
              type="submit"
              disabled={isSubmitting}
              className="bg-blue-600 hover:bg-blue-700 text-white"
            >
              {isSubmitting ? 'Gerando parcelamento...' : `Criar Parcelamento (${count} pares)`}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
