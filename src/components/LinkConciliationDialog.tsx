import { useState, useEffect, useMemo } from 'react'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from '@/components/ui/command'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Check, ChevronsUpDown, Loader2 } from 'lucide-react'
import { cn } from '@/lib/utils'

interface LinkConciliationDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  transaction: any | null
  clients: any[]
  cases: any[]
  suppliers?: any[]
  onSaveLink: (
    transactionId: string,
    clientId: string | null,
    processId: string | null,
    supplierId?: string | null,
  ) => Promise<void>
  onIgnore: (transactionId: string) => Promise<void>
}

export function LinkConciliationDialog({
  open,
  onOpenChange,
  transaction,
  clients,
  cases,
  suppliers = [],
  onSaveLink,
  onIgnore,
}: LinkConciliationDialogProps) {
  const [selectedClientId, setSelectedClientId] = useState<string>('')
  const [selectedCaseId, setSelectedCaseId] = useState<string>('none')
  const [selectedSupplierId, setSelectedSupplierId] = useState<string>('')
  const [clientSearchOpen, setClientSearchOpen] = useState(false)
  const [supplierSearchOpen, setSupplierSearchOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [ignoring, setIgnoring] = useState(false)

  useEffect(() => {
    if (open && transaction) {
      setSelectedClientId(transaction.clientId || '')
      setSelectedCaseId(transaction.processId || 'none')
      setSelectedSupplierId(transaction.supplierId || '')
      setClientSearchOpen(false)
      setSupplierSearchOpen(false)
    } else {
      setSelectedClientId('')
      setSelectedCaseId('none')
      setSelectedSupplierId('')
      setClientSearchOpen(false)
      setSupplierSearchOpen(false)
    }
  }, [open, transaction])

  const selectedClient = useMemo(() => {
    return clients.find((c) => c.id === selectedClientId)
  }, [clients, selectedClientId])

  const sortedSuppliers = useMemo(() => {
    return [...suppliers].sort((a, b) => (a.name || '').localeCompare(b.name || '', 'pt-BR'))
  }, [suppliers])

  const selectedSupplier = useMemo(() => {
    return suppliers.find((s) => s.id === selectedSupplierId)
  }, [suppliers, selectedSupplierId])

  const clientCases = useMemo(() => {
    if (!selectedClientId) return []
    return cases.filter((c) => c.clientId === selectedClientId)
  }, [cases, selectedClientId])

  const handleClientSelect = (clientId: string) => {
    setSelectedClientId(clientId)
    setSelectedCaseId('none')
    setClientSearchOpen(false)
  }

  const handleSupplierSelect = (supplierId: string) => {
    setSelectedSupplierId(supplierId)
    setSupplierSearchOpen(false)
  }

  const isExpense = transaction?.type === 'expense'
  const isClientRepassExpense = isExpense && transaction?.category === 'Repasse ao cliente'

  const handleSave = async () => {
    if (!transaction) return
    if (isExpense) {
      if (isClientRepassExpense) {
        if (!selectedClientId) return
        try {
          setSaving(true)
          await onSaveLink(transaction.id, selectedClientId, null)
          onOpenChange(false)
        } finally {
          setSaving(false)
        }
      } else {
        if (!selectedSupplierId) return
        try {
          setSaving(true)
          await onSaveLink(transaction.id, null, null, selectedSupplierId)
          onOpenChange(false)
        } finally {
          setSaving(false)
        }
      }
    } else {
      if (!selectedClientId) return
      try {
        setSaving(true)
        const processIdToSave = selectedCaseId && selectedCaseId !== 'none' ? selectedCaseId : null
        await onSaveLink(transaction.id, selectedClientId, processIdToSave)
        onOpenChange(false)
      } finally {
        setSaving(false)
      }
    }
  }

  const handleIgnore = async () => {
    if (!transaction) return
    try {
      setIgnoring(true)
      await onIgnore(transaction.id)
      onOpenChange(false)
    } finally {
      setIgnoring(false)
    }
  }

  if (!transaction) return null

  const isIncome = transaction.type === 'income'
  const originLabel =
    transaction.origem === 'ASAAS_WEBHOOK'
      ? 'Asaas'
      : transaction.origem === 'IMPORT_SICOOB'
        ? 'SICOOB'
        : transaction.origem || 'Manual'

  return (
    <Dialog open={open} onOpenChange={(v) => !saving && !ignoring && onOpenChange(v)}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Vincular Lançamento</DialogTitle>
          <DialogDescription>
            {isExpense
              ? isClientRepassExpense
                ? 'Selecione o cliente para conciliar este lançamento.'
                : 'Selecione o fornecedor para conciliar este lançamento.'
              : 'Selecione o cliente e, se aplicável, o processo judicial para conciliar este lançamento.'}
          </DialogDescription>
        </DialogHeader>

        {/* Card de detalhes do lançamento */}
        <div className="rounded-lg border bg-slate-50/70 p-3 space-y-2 text-sm">
          <div className="flex items-center justify-between">
            <span className="font-semibold text-slate-800">{transaction.description}</span>
            <Badge variant="outline" className="text-xs">
              {originLabel}
            </Badge>
          </div>
          <div className="flex items-center justify-between text-xs text-muted-foreground">
            <span>Data: {transaction.date || '-'}</span>
            <span className={cn('font-bold text-sm', isIncome ? 'text-green-600' : 'text-red-600')}>
              {isIncome ? '+ ' : '- '}
              R${' '}
              {Number(transaction.amount || 0).toLocaleString('pt-BR', {
                minimumFractionDigits: 2,
              })}
            </span>
          </div>
          {transaction.category && (
            <div className="text-xs text-muted-foreground">
              Categoria: <span className="font-medium text-slate-700">{transaction.category}</span>
            </div>
          )}
        </div>

        <div className="space-y-4 py-2">
          {isExpense ? (
            isClientRepassExpense ? (
              /* Campo de Cliente com Busca para Repasse ao cliente */
              <div className="space-y-1.5">
                <Label className="text-xs font-semibold">Cliente *</Label>
                <Popover open={clientSearchOpen} onOpenChange={setClientSearchOpen}>
                  <PopoverTrigger asChild>
                    <Button
                      variant="outline"
                      role="combobox"
                      aria-expanded={clientSearchOpen}
                      className="w-full justify-between font-normal bg-white"
                    >
                      <span className="truncate">
                        {selectedClient ? selectedClient.name : 'Selecione ou busque um cliente...'}
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
                          {clients.map((client) => (
                            <CommandItem
                              key={client.id}
                              value={client.name}
                              onSelect={() => handleClientSelect(client.id)}
                            >
                              <Check
                                className={cn(
                                  'mr-2 h-4 w-4',
                                  selectedClientId === client.id ? 'opacity-100' : 'opacity-0',
                                )}
                              />
                              <span className="truncate">{client.name}</span>
                            </CommandItem>
                          ))}
                        </CommandGroup>
                      </CommandList>
                    </Command>
                  </PopoverContent>
                </Popover>
              </div>
            ) : (
              /* Campo de Fornecedor com Busca */
              <div className="space-y-1.5">
                <Label className="text-xs font-semibold">Fornecedor *</Label>
                <Popover open={supplierSearchOpen} onOpenChange={setSupplierSearchOpen}>
                  <PopoverTrigger asChild>
                    <Button
                      variant="outline"
                      role="combobox"
                      aria-expanded={supplierSearchOpen}
                      className="w-full justify-between font-normal bg-white"
                    >
                      <span className="truncate">
                        {selectedSupplier
                          ? selectedSupplier.name
                          : 'Selecione ou busque um fornecedor...'}
                      </span>
                      <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
                    </Button>
                  </PopoverTrigger>
                  <PopoverContent className="w-[--radix-popover-trigger-width] p-0" align="start">
                    <Command>
                      <CommandInput placeholder="Buscar fornecedor por nome..." />
                      <CommandList className="max-h-60">
                        <CommandEmpty>Nenhum fornecedor encontrado.</CommandEmpty>
                        <CommandGroup>
                          {sortedSuppliers.map((supplier) => (
                            <CommandItem
                              key={supplier.id}
                              value={supplier.name}
                              onSelect={() => handleSupplierSelect(supplier.id)}
                            >
                              <Check
                                className={cn(
                                  'mr-2 h-4 w-4',
                                  selectedSupplierId === supplier.id ? 'opacity-100' : 'opacity-0',
                                )}
                              />
                              <span className="truncate">{supplier.name}</span>
                            </CommandItem>
                          ))}
                        </CommandGroup>
                      </CommandList>
                    </Command>
                  </PopoverContent>
                </Popover>
              </div>
            )
          ) : (
            <>
              {/* Select de Cliente com Busca */}
              <div className="space-y-1.5">
                <Label className="text-xs font-semibold">Cliente *</Label>
                <Popover open={clientSearchOpen} onOpenChange={setClientSearchOpen}>
                  <PopoverTrigger asChild>
                    <Button
                      variant="outline"
                      role="combobox"
                      aria-expanded={clientSearchOpen}
                      className="w-full justify-between font-normal bg-white"
                    >
                      <span className="truncate">
                        {selectedClient ? selectedClient.name : 'Selecione ou busque um cliente...'}
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
                          {clients.map((client) => (
                            <CommandItem
                              key={client.id}
                              value={client.name}
                              onSelect={() => handleClientSelect(client.id)}
                            >
                              <Check
                                className={cn(
                                  'mr-2 h-4 w-4',
                                  selectedClientId === client.id ? 'opacity-100' : 'opacity-0',
                                )}
                              />
                              <span className="truncate">{client.name}</span>
                            </CommandItem>
                          ))}
                        </CommandGroup>
                      </CommandList>
                    </Command>
                  </PopoverContent>
                </Popover>
              </div>

              {/* Select de Processo */}
              <div className="space-y-1.5">
                <Label className="text-xs font-semibold">Processo</Label>
                <Select
                  value={selectedCaseId}
                  onValueChange={setSelectedCaseId}
                  disabled={!selectedClientId}
                >
                  <SelectTrigger className="bg-white">
                    <SelectValue
                      placeholder={
                        selectedClientId ? 'Selecione o processo' : 'Selecione primeiro o cliente'
                      }
                    />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="none">Sem processo</SelectItem>
                    {clientCases.map((c) => {
                      const label = c.process_name ? `${c.number} (${c.process_name})` : c.number
                      return (
                        <SelectItem key={c.id} value={c.id}>
                          {label}
                        </SelectItem>
                      )
                    })}
                  </SelectContent>
                </Select>
                {selectedClientId && clientCases.length === 0 && (
                  <p className="text-[11px] text-muted-foreground">
                    Nenhum processo vinculado a este cliente. A opção "Sem processo" será mantida.
                  </p>
                )}
              </div>
            </>
          )}
        </div>

        <DialogFooter className="flex flex-col-reverse sm:flex-row sm:justify-between gap-2 pt-2">
          <Button
            type="button"
            variant="ghost"
            onClick={handleIgnore}
            disabled={saving || ignoring}
            className="text-slate-600 hover:text-slate-900"
          >
            {ignoring ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : null}
            Ignorar (sem vínculo)
          </Button>
          <div className="flex gap-2 justify-end">
            <Button
              type="button"
              variant="outline"
              onClick={() => onOpenChange(false)}
              disabled={saving || ignoring}
            >
              Cancelar
            </Button>
            <Button
              type="button"
              onClick={handleSave}
              disabled={
                (isExpense
                  ? isClientRepassExpense
                    ? !selectedClientId
                    : !selectedSupplierId
                  : !selectedClientId) ||
                saving ||
                ignoring
              }
            >
              {saving ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : null}
              Salvar vínculo
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
