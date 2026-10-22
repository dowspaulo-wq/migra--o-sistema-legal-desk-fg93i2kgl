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
import { toast } from '@/hooks/use-toast'
import { Checkbox } from '@/components/ui/checkbox'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from '@/components/ui/command'
import { Check, ChevronsUpDown } from 'lucide-react'
import { cn } from '@/lib/utils'
import useLegalStore from '@/stores/useLegalStore'
import {
  isSuccessFeeType,
  capitalizeFirstLetter,
  getFeeTypeOptions,
  getClientExpenseOptions,
  getOfficeExpenseOptions,
} from '@/lib/fee-types'
import { syncChargeWithAsaas } from '@/services/asaas'

const DEFAULT_CATEGORIES = [
  'Acordo',
  'Alvará / Condenação',
  'Custas Finais',
  'Custas Iniciais',
  'Depósito Recursal',
  'Diligência',
  'Honorários Contratuais',
  'Honorários de Êxito',
  'Honorários de Permuta',
  'Honorários Periciais',
  'Honorários Sucumbenciais',
  'Outros',
]

export function TransactionDialog({
  open,
  onOpenChange,
  data,
  onSave,
  onCancel,
  lockedProcessId,
  lockedClientId,
}: any) {
  const { state } = useLegalStore() as any

  const rawCategories = (state?.settings?.transactionCategories as string[]) || DEFAULT_CATEGORIES
  const feeCategories = getFeeTypeOptions(rawCategories, false)
  const expenseCategories = getClientExpenseOptions(rawCategories)
  const officeExpenseCategories = getOfficeExpenseOptions(state?.settings?.expenseTypes)

  const bankOptions = Array.from(
    new Set([
      ...(state?.settings?.bankAccounts || ['ASAAS', 'SICOOB', 'CAIXA', 'PESSOAL']),
      ...(data?.bankAccount ? [data.bankAccount] : []),
    ]),
  )

  const paymentMethodOptions = Array.from(
    new Set([
      'PIX',
      'Boleto',
      'Cartão',
      'Transferência',
      'Dinheiro',
      ...(data?.payment_method ? [data.payment_method] : []),
    ]),
  )

  const isCategorySuccessFee = (cat: string) => isSuccessFeeType(cat)

  const currentYear = new Date().getFullYear()
  const defaultSuccessDueDate = `${currentYear}-12-31`

  const detectIsOffice = (item: any) => {
    if (!item) return false
    if (item.origem === 'OFFICE' || item.type === 'office_expense') return true
    if (
      (item.type === 'expense' || !item.type) &&
      !item.clientId &&
      (Boolean(item.supplierId) || officeExpenseCategories.includes(item.category))
    ) {
      return true
    }
    return false
  }

  const resolveClientId = (item: any) => {
    if (!item) return lockedClientId || ''
    if (item.clientId) return item.clientId
    if (lockedClientId) return lockedClientId
    if (item.processId) {
      const foundCase = (state?.cases || []).find((c: any) => c.id === item.processId)
      if (foundCase?.clientId) return foundCase.clientId
    }
    return ''
  }

  const getInitial = () => ({
    description: '',
    amount: '',
    type: 'expense',
    category: 'Custas Iniciais',
    status: 'Previsto',
    date: new Date().toISOString().split('T')[0],
    clientId: lockedClientId || '',
    processId: lockedProcessId || '',
    sendToFinance: true,
    bankAccount: state?.settings?.bankAccounts?.[0] || 'ASAAS',
    supplierId: '',
    supplier_group: '',
    percentage: '',
    payment_method: 'PIX',
    origem: 'MANUAL',
  })

  const [fd, setFd] = useState(() => {
    if (!data) return getInitial()
    const isOffice = detectIsOffice(data)
    const initialType = isOffice ? 'office_expense' : data.type || 'expense'
    const initialCategory =
      data.category && isSuccessFeeType(data.category)
        ? 'Honorários de Êxito'
        : data.category ||
          (initialType === 'income'
            ? 'Honorários Contratuais'
            : initialType === 'office_expense'
              ? officeExpenseCategories[0] || 'Aluguel'
              : 'Custas Iniciais')
    return {
      ...data,
      type: initialType,
      category: initialCategory,
      amount: data.amount != null ? data.amount.toString() : '',
      date: data.date ?? '',
      clientId: resolveClientId(data),
      processId: data.processId || lockedProcessId || '',
      sendToFinance: data.sendToFinance !== false,
      bankAccount: data.bankAccount || state?.settings?.bankAccounts?.[0] || 'ASAAS',
      supplierId: data.supplierId || '',
      supplier_group: (data as any).supplier_group || '',
      percentage: data.percentage != null ? data.percentage.toString() : '',
      payment_method: data.payment_method || 'PIX',
      origem: isOffice ? 'OFFICE' : (data as any).origem || 'MANUAL',
    }
  })

  const [isRecurring, setIsRecurring] = useState(false)
  const [installments, setInstallments] = useState('2')
  const [clientSearchOpen, setClientSearchOpen] = useState(false)

  const lastInitializedIdRef = useState<{ id: string | null }>({ id: null })[0]

  useEffect(() => {
    if (open) {
      const dataId = data?.id || '__new__'
      // Só sobrescreve os dados se o item mudou (ex: abriu outro registro) ou se ainda não foi inicializado
      if (lastInitializedIdRef.id !== dataId) {
        lastInitializedIdRef.id = dataId
        const isOffice = detectIsOffice(data)
        const initialType = isOffice ? 'office_expense' : data?.type || 'expense'
        const initialStatus =
          data?.status === 'Realizado' || data?.status === 'Êxito'
            ? data?.amount > 0
              ? 'Pago'
              : 'Previsto'
            : data?.status || 'Previsto'

        const initialCategory =
          data?.category && isSuccessFeeType(data.category)
            ? 'Honorários de Êxito'
            : data?.category ||
              (initialType === 'income'
                ? 'Honorários Contratuais'
                : initialType === 'office_expense'
                  ? officeExpenseCategories[0] || 'Aluguel'
                  : 'Custas Iniciais')

        setFd(
          data
            ? {
                ...data,
                type: initialType,
                status: initialStatus,
                category: initialCategory,
                amount: data.amount != null ? data.amount.toString() : '',
                date: data.date ?? '',
                clientId: resolveClientId(data),
                processId: data.processId || lockedProcessId || '',
                sendToFinance: data.sendToFinance !== false,
                bankAccount: data.bankAccount || 'ASAAS',
                supplierId: data.supplierId || '',
                supplier_group: (data as any).supplier_group || '',
                percentage: data.percentage != null ? data.percentage.toString() : '',
                payment_method: data.payment_method || 'PIX',
                origem: isOffice ? 'OFFICE' : (data as any).origem || 'MANUAL',
              }
            : getInitial(),
        )
        setIsRecurring(false)
        setInstallments('2')
      }
    } else {
      // Quando fechar, se for cancelamento explícito, o chamador limpa
    }
  }, [data, open, lockedProcessId, lockedClientId, state?.cases])

  const isSuccessFee = isCategorySuccessFee(fd.category)
  const currentCategoryList =
    fd.type === 'income'
      ? feeCategories
      : fd.type === 'office_expense'
        ? officeExpenseCategories
        : expenseCategories

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()

    if (fd.type === 'office_expense' && (!fd.category || !fd.category.trim())) {
      toast({
        title: 'Campo Obrigatório',
        description: 'O Tipo de Despesa é obrigatório para despesas do escritório.',
        variant: 'destructive',
      })
      return
    }

    if (
      !fd.description ||
      (!fd.amount && !isSuccessFee) ||
      !fd.type ||
      !fd.category ||
      !fd.status ||
      !fd.date
    ) {
      toast({
        title: 'Campos Obrigatórios',
        description: 'Por favor, preencha todos os campos obrigatórios.',
        variant: 'destructive',
      })
      return
    }

    // Regra específica para Honorários Avulsos: ou tem processo vinculado, ou tem cliente
    if (fd.category === 'Honorários Avulsos') {
      const hasClient = Boolean(fd.clientId && fd.clientId !== 'none')
      const hasProcess = Boolean(fd.processId && fd.processId !== 'none')
      if (!hasClient && !hasProcess) {
        toast({
          title: 'Vínculo Obrigatório',
          description: 'Para Honorários Avulsos, selecione um Cliente ou vincule a um Processo.',
          variant: 'destructive',
        })
        return
      }
    }

    const finalDescription = capitalizeFirstLetter(fd.description)
    const isOffice = fd.type === 'office_expense'
    const payload: any = {
      ...fd,
      type: isOffice ? 'expense' : fd.type,
      origem: isOffice ? 'OFFICE' : fd.origem || 'MANUAL',
      description: finalDescription,
      amount: fd.amount ? parseFloat(fd.amount.toString().replace(',', '.')) : 0,
      date: fd.date && fd.date.trim() !== '' ? fd.date : null,
    }

    if (isSuccessFee && fd.percentage) {
      payload.percentage = parseFloat(fd.percentage.toString().replace(',', '.'))
    } else if (!isSuccessFee) {
      payload.percentage = null
    }

    if (!payload.supplierId || payload.supplierId === 'none') {
      payload.supplierId = null
      payload.supplier_group = null
    } else {
      // Se tiver fornecedor selecionado, garante que o supplier_group esteja populado
      if (!payload.supplier_group) {
        const foundSup = state.suppliers.find((s) => s.id === payload.supplierId)
        if (foundSup?.group_name) {
          payload.supplier_group = foundSup.group_name
        }
      }
    }
    if (isOffice) {
      payload.clientId = null
      payload.processId = null
    } else {
      if (!payload.clientId || payload.clientId === 'none') {
        payload.clientId = null
      }
      if (!payload.processId || payload.processId === 'none') {
        payload.processId = null
      }
    }

    onSave(payload, isRecurring, parseInt(installments, 10))
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md max-h-[90vh] overflow-y-auto">
        <form onSubmit={handleSubmit} className="grid gap-4">
          <DialogHeader>
            <DialogTitle>{data ? 'Editar' : 'Novo'} Lançamento</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Tipo *</Label>
                <Select
                  value={fd.type}
                  onValueChange={(v) => {
                    let newDefaultCat = 'Custas Iniciais'
                    if (v === 'income') {
                      newDefaultCat = 'Honorários Contratuais'
                    } else if (v === 'office_expense') {
                      newDefaultCat = officeExpenseCategories[0] || 'Aluguel'
                    }
                    setFd({ ...fd, type: v, category: newDefaultCat })
                  }}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Tipo" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="expense">Despesa do Cliente / Custa</SelectItem>
                    <SelectItem value="office_expense">Despesas do escritório</SelectItem>
                    <SelectItem value="income">Honorário / Receita</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label>Valor (R$) {isSuccessFee ? '(Opcional se %)' : '*'}</Label>
                <Input
                  type="number"
                  step="0.01"
                  required={!isSuccessFee}
                  placeholder={isSuccessFee ? 'A apurar ou informe R$' : '0,00'}
                  value={fd.amount}
                  onChange={(e) => setFd({ ...fd, amount: e.target.value })}
                />
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>{fd.type === 'income' ? 'Tipo de Honorário *' : 'Tipo de Despesa *'}</Label>
                <Select
                  value={fd.category}
                  onValueChange={(v) => {
                    const isSucc = isCategorySuccessFee(v)
                    setFd((prev: any) => ({
                      ...prev,
                      category: v,
                      date: isSucc ? prev.date || defaultSuccessDueDate : prev.date,
                    }))
                  }}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Selecione" />
                  </SelectTrigger>
                  <SelectContent>
                    {currentCategoryList.map((c) => (
                      <SelectItem key={c} value={c}>
                        {c}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label>Data / Vencimento {isSuccessFee ? '(Padrão 31/12)' : '*'}</Label>
                <Input
                  type="date"
                  required
                  value={fd.date || ''}
                  onChange={(e) => setFd({ ...fd, date: e.target.value })}
                />
              </div>
            </div>

            {/* Seletor de Cliente com busca para Honorários Avulsos */}
            {fd.category === 'Honorários Avulsos' && (
              <div className="space-y-2 bg-blue-50/50 p-3 rounded-lg border border-blue-200">
                <Label className="text-blue-950 font-semibold">Cliente *</Label>
                <Popover open={clientSearchOpen} onOpenChange={setClientSearchOpen}>
                  <PopoverTrigger asChild>
                    <Button
                      type="button"
                      variant="outline"
                      role="combobox"
                      aria-expanded={clientSearchOpen}
                      disabled={Boolean(lockedClientId)}
                      className="w-full justify-between font-normal bg-white"
                    >
                      <span className="truncate">
                        {(() => {
                          const selected = (state?.clients || []).find(
                            (c: any) => c.id === fd.clientId,
                          )
                          return selected ? selected.name : 'Selecione ou busque um cliente...'
                        })()}
                      </span>
                      <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
                    </Button>
                  </PopoverTrigger>
                  <PopoverContent className="w-[--radix-popover-trigger-width] p-0" align="start">
                    <Command>
                      <CommandInput placeholder="Buscar cliente por nome..." />
                      <CommandList className="max-h-60">
                        <CommandEmpty>Nenhum cliente encontrado.</CommandEmpty>
                        <CommandGroup>
                          {[...(state?.clients || [])]
                            .sort((a: any, b: any) =>
                              (a.name || '').localeCompare(b.name || '', 'pt-BR'),
                            )
                            .map((client: any) => (
                              <CommandItem
                                key={client.id}
                                value={client.name}
                                onSelect={() => {
                                  setFd((prev: any) => ({ ...prev, clientId: client.id }))
                                  setClientSearchOpen(false)
                                }}
                              >
                                <Check
                                  className={cn(
                                    'mr-2 h-4 w-4',
                                    fd.clientId === client.id ? 'opacity-100' : 'opacity-0',
                                  )}
                                />
                                <span className="truncate">{client.name}</span>
                                {client.document && (
                                  <span className="ml-2 text-xs text-muted-foreground">
                                    ({client.document})
                                  </span>
                                )}
                              </CommandItem>
                            ))}
                        </CommandGroup>
                      </CommandList>
                    </Command>
                  </PopoverContent>
                </Popover>
                {fd.processId && (
                  <p className="text-[11px] text-muted-foreground">
                    Processo vinculado:{' '}
                    {(state?.cases || []).find((c: any) => c.id === fd.processId)?.number ||
                      fd.processId}
                  </p>
                )}
              </div>
            )}

            <div className="space-y-2">
              <Label>
                {fd.category === 'Honorários Avulsos' ? 'Descrição do serviço *' : 'Descrição *'}
              </Label>
              <Input
                required
                placeholder={
                  fd.category === 'Honorários Avulsos'
                    ? 'Ex: Redação de contrato à parte'
                    : 'Ex: Honorários contratuais ou Guia de custas'
                }
                value={fd.description}
                onChange={(e) =>
                  setFd({ ...fd, description: capitalizeFirstLetter(e.target.value) })
                }
              />
            </div>

            {isSuccessFee && (
              <div className="space-y-2">
                <Label>Percentual (%) (Opcional)</Label>
                <Input
                  type="number"
                  step="0.01"
                  min="0"
                  max="100"
                  placeholder="Ex: 30"
                  value={fd.percentage || ''}
                  onChange={(e) => setFd({ ...fd, percentage: e.target.value })}
                />
              </div>
            )}

            <div className="space-y-2">
              <Label>Fornecedor (Opcional)</Label>
              <Select
                value={fd.supplierId || 'none'}
                onValueChange={(v) => {
                  if (v === 'none') {
                    setFd({ ...fd, supplierId: null, supplier_group: null })
                  } else {
                    const sup = state.suppliers.find((s) => s.id === v)
                    setFd({
                      ...fd,
                      supplierId: v,
                      supplier_group: sup?.group_name || null,
                    })
                  }
                }}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Selecione um fornecedor" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">Nenhum</SelectItem>
                  {[...(state.suppliers || [])]
                    .filter((s: any) => s.status === 'Ativo')
                    .sort((a: any, b: any) => (a.name || '').localeCompare(b.name || '', 'pt-BR'))
                    .map((s: any) => (
                      <SelectItem key={s.id} value={s.id}>
                        {s.name} {s.group_name ? `(${s.group_name})` : ''}
                      </SelectItem>
                    ))}
                </SelectContent>
              </Select>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Status *</Label>
                <Select value={fd.status} onValueChange={(v) => setFd({ ...fd, status: v })}>
                  <SelectTrigger>
                    <SelectValue placeholder="Status" />
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
                  value={fd.bankAccount}
                  onValueChange={(v) => setFd({ ...fd, bankAccount: v })}
                >
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
              <Label>Forma de Pagamento</Label>
              <Select
                value={fd.payment_method || 'PIX'}
                onValueChange={(v) => setFd({ ...fd, payment_method: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Forma de Pagamento" />
                </SelectTrigger>
                <SelectContent>
                  {paymentMethodOptions.map((m) => (
                    <SelectItem key={m} value={m}>
                      {m}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {lockedProcessId && (
              <div className="flex items-center space-x-2 pt-3 border-t mt-2">
                <Checkbox
                  id="sendToFinance"
                  checked={fd.sendToFinance}
                  onCheckedChange={(v) => setFd({ ...fd, sendToFinance: !!v })}
                />
                <Label htmlFor="sendToFinance" className="text-sm font-medium cursor-pointer">
                  Lançar também no Módulo Financeiro Global
                </Label>
              </div>
            )}

            {!data && (
              <div className="pt-3 border-t mt-2 space-y-4">
                <div className="flex items-center space-x-2">
                  <Checkbox
                    id="isRecurring"
                    checked={isRecurring}
                    onCheckedChange={(v) => setIsRecurring(!!v)}
                  />
                  <Label htmlFor="isRecurring" className="text-sm font-medium cursor-pointer">
                    Lançamento Recorrente / Parcelado
                  </Label>
                </div>
                {isRecurring && (
                  <div className="space-y-2">
                    <Label>Quantidade de Meses/Parcelas</Label>
                    <Input
                      type="number"
                      min="2"
                      max="120"
                      value={installments}
                      onChange={(e) => setInstallments(e.target.value)}
                    />
                  </div>
                )}
              </div>
            )}
          </div>
          <DialogFooter className="flex justify-between items-center w-full">
            <div className="flex items-center gap-2">
              <Button
                type="button"
                variant="outline"
                onClick={() => {
                  lastInitializedIdRef.id = null
                  if (onCancel) onCancel()
                  onOpenChange(false)
                }}
              >
                Cancelar
              </Button>
              {data?.id && (
                <Button
                  type="button"
                  variant="outline"
                  className="border-blue-300 text-blue-700 hover:bg-blue-50"
                  onClick={async () => {
                    try {
                      toast({ title: 'Sincronizando com Asaas...' })
                      const { data: syncRes, error } = await syncChargeWithAsaas(data.id)
                      if (error) {
                        toast({
                          title: 'Erro na cobrança Asaas',
                          description: error.message || 'Falha ao sincronizar com Asaas',
                          variant: 'destructive',
                        })
                      } else {
                        const asaasTxId = (syncRes as any)?.asaas_id
                        toast({
                          title: 'Sucesso',
                          description: asaasTxId
                            ? `Cobrança sincronizada com Asaas com sucesso! (ID: ${asaasTxId})`
                            : syncRes?.message || 'Cobrança sincronizada com Asaas com sucesso.',
                        })
                        onOpenChange(false)
                      }
                    } catch (err: any) {
                      toast({
                        title: 'Erro',
                        description: err.message || 'Falha ao sincronizar com Asaas',
                        variant: 'destructive',
                      })
                    }
                  }}
                >
                  Sincronizar com Asaas
                </Button>
              )}
            </div>
            <Button type="submit">Salvar</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
