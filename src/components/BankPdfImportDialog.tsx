import { useState } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { Checkbox } from '@/components/ui/checkbox'
import { Textarea } from '@/components/ui/textarea'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  FileUp,
  Loader2,
  AlertCircle,
  CheckCircle2,
  FileText,
  ArrowUpRight,
  ArrowDownRight,
} from 'lucide-react'
import {
  extractTextFromPdf,
  parseBankStatementText,
  ParsedBankStatementItem,
} from '@/lib/bank-statement-parser'
import { supabase } from '@/lib/supabase/client'
import { toast } from '@/hooks/use-toast'
import { formatSafeLocalDate, cn } from '@/lib/utils'
import useLegalStore from '@/stores/useLegalStore'
import {
  findDuplicateTransaction,
  findCrossOriginDuplicateTransaction,
  normalizeStr,
} from '@/lib/anti-duplicate'
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
import type { Transaction } from '@/lib/mockData'

interface BankPdfImportDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  onSuccess: () => Promise<void> | void
  bankAccounts?: string[]
  onImportCompleted?: (timestamp: string, account: string) => Promise<void> | void
}

export function BankPdfImportDialog({
  open,
  onOpenChange,
  onSuccess,
  bankAccounts = ['SICOOB', 'CAIXA', 'PESSOAL', 'Crédito Santander Aline'],
  onImportCompleted,
}: BankPdfImportDialogProps) {
  const [selectedBank, setSelectedBank] = useState<string>('SICOOB')
  const [parsing, setParsing] = useState(false)
  const [saving, setSaving] = useState(false)
  const [parsedItems, setParsedItems] = useState<ParsedBankStatementItem[]>([])
  const [fileName, setFileName] = useState<string | null>(null)
  const [rawTextFallback, setRawTextFallback] = useState('')
  const [showTextFallback, setShowTextFallback] = useState(false)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const { state } = useLegalStore()

  const [crossOriginWarning, setCrossOriginWarning] = useState<{
    item: ParsedBankStatementItem
    matched: Transaction
    clientName: string
  } | null>(null)

  // Função auxiliar para tentar deduzir o cliente a partir do texto da descrição do extrato
  const detectClientFromDescription = (description: string): any | null => {
    const clients = (state?.clients || []) as any[]
    if (!description || clients.length === 0) return null

    const normDesc = normalizeStr(description).toLowerCase()

    // 1. Tenta correspondência com nome completo (ao menos 4 caracteres)
    let bestMatch: any = null
    let longestMatchLen = 0

    for (const c of clients) {
      if (!c.name || c.name.trim().length < 4) continue
      const normName = normalizeStr(c.name).toLowerCase().trim()
      if (normDesc.includes(normName)) {
        if (normName.length > longestMatchLen) {
          longestMatchLen = normName.length
          bestMatch = c
        }
      }
    }

    if (bestMatch) return bestMatch

    // 2. Se a descrição for "Recebimento Pix — NOME", tenta extrair o nome após o travessão/hífen
    const parts = description.split(/—|-|–/)
    if (parts.length > 1) {
      const candidateName = normalizeStr(parts[parts.length - 1])
        .toLowerCase()
        .trim()
      if (candidateName.length >= 4) {
        for (const c of clients) {
          if (!c.name) continue
          const normName = normalizeStr(c.name).toLowerCase().trim()
          if (
            normName === candidateName ||
            normName.includes(candidateName) ||
            candidateName.includes(normName)
          ) {
            return c
          }
        }
      }
    }

    return null
  }

  const markDuplicatesOnItems = (items: ParsedBankStatementItem[], bank: string) => {
    const existingList = (state?.transactions || []) as Transaction[]
    const clients = (state?.clients || []) as any[]

    return items.map((item) => {
      // 1. Duplicado exato (mesma data, valor, descrição e conta)
      const duplicate = findDuplicateTransaction(
        {
          date: item.date,
          amount: item.amount,
          description: item.description,
          bankAccount: bank,
        },
        existingList,
      )
      if (duplicate) {
        return {
          ...item,
          selected: false, // Desmarca automaticamente para não importar duplicado
          isDuplicate: true,
          matchedDuplicate: duplicate,
        }
      }

      // 2. Duplicado entre origens (Asaas x Extrato Sicoob/Outro)
      // Tenta identificar o cliente do extrato ou testar contra transações Asaas de clientes
      const matchedClient = detectClientFromDescription(item.description)

      let crossOriginDup: Transaction | null = null
      let resolvedClientName = matchedClient?.name || ''

      if (matchedClient) {
        crossOriginDup = findCrossOriginDuplicateTransaction(
          {
            clientId: matchedClient.id,
            amount: item.amount,
            date: item.date,
            origem: bank === 'SICOOB' ? 'IMPORT_SICOOB' : 'MANUAL',
          },
          existingList,
        )
      } else {
        // Se o nome não foi identificado diretamente na descrição, varre se existe transação
        // Asaas paga com mesmo valor e data próxima (<= 5 dias) em que a descrição do Asaas ou
        // o nome do cliente esteja contido na descrição do extrato
        const normDesc = normalizeStr(item.description).toLowerCase()
        const asaasTxs = existingList.filter(
          (t) =>
            (t.origem === 'ASAAS_WEBHOOK' || t.origem === 'ASAAS') &&
            (t.status === 'Pago' || (t.status as string) === 'Realizado') &&
            t.clientId,
        )

        for (const atx of asaasTxs) {
          const candMatch = findCrossOriginDuplicateTransaction(
            {
              clientId: atx.clientId,
              amount: item.amount,
              date: item.date,
              origem: bank === 'SICOOB' ? 'IMPORT_SICOOB' : 'MANUAL',
            },
            [atx],
          )
          if (candMatch) {
            const clientObj = clients.find((c) => c.id === atx.clientId)
            const cName = clientObj?.name ? normalizeStr(clientObj.name).toLowerCase() : ''
            // Se o nome do cliente ou parte relevante bate com o extrato
            if (cName && normDesc.includes(cName)) {
              crossOriginDup = candMatch
              resolvedClientName = clientObj?.name || ''
              break
            }
          }
        }
      }

      if (crossOriginDup) {
        return {
          ...item,
          selected: false, // Desmarca automaticamente por segurança
          isCrossOriginDuplicate: true,
          matchedCrossOrigin: crossOriginDup,
          crossOriginClientName: resolvedClientName,
        }
      }

      return item
    })
  }

  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return

    setFileName(file.name)
    setErrorMessage(null)
    setParsing(true)

    try {
      const text = await extractTextFromPdf(file)
      setRawTextFallback(text)
      const items = parseBankStatementText(text)

      if (items.length === 0) {
        setErrorMessage(
          'Nenhum lançamento foi reconhecido automaticamente no PDF. Você pode visualizar o texto extraído abaixo ou colar o texto do extrato.',
        )
        setShowTextFallback(true)
      } else {
        const checkedItems = markDuplicatesOnItems(items, selectedBank)
        setParsedItems(checkedItems)
      }
    } catch (err: any) {
      console.error('Erro ao ler PDF:', err)
      setErrorMessage(
        err.message || 'Falha ao extrair texto do PDF. Tente colar o texto do extrato diretamente.',
      )
      setShowTextFallback(true)
    } finally {
      setParsing(false)
    }
  }

  const handleReparseText = () => {
    if (!rawTextFallback.trim()) {
      toast({
        title: 'Texto vazio',
        description: 'Cole o texto do extrato para realizar a leitura.',
        variant: 'destructive',
      })
      return
    }

    const items = parseBankStatementText(rawTextFallback)
    if (items.length === 0) {
      toast({
        title: 'Nenhum lançamento identificado',
        description:
          'Verifique se o texto contém linhas com data (dd/mm/aaaa) e valores monetários.',
        variant: 'destructive',
      })
    } else {
      const checkedItems = markDuplicatesOnItems(items, selectedBank)
      setParsedItems(checkedItems)
      setShowTextFallback(false)
      setErrorMessage(null)
      toast({
        title: 'Leitura concluída',
        description: `${items.length} lançamentos encontrados no texto.`,
      })
    }
  }

  const toggleSelectItem = (id: string) => {
    setParsedItems((prev) =>
      prev.map((it) => (it.id === id ? { ...it, selected: !it.selected } : it)),
    )
  }

  const toggleSelectAll = (select: boolean) => {
    setParsedItems((prev) =>
      prev.map((it) => {
        // Se estiver marcando todos mas o item for duplicado existente ou de origem Asaas, não seleciona
        if (select && ((it as any).isDuplicate || (it as any).isCrossOriginDuplicate)) {
          return it
        }
        return { ...it, selected: select }
      }),
    )
  }

  const handleCheckboxClick = (item: ParsedBankStatementItem) => {
    const itAny = item as any
    // Se o usuário tentar marcar um item identificado como duplicado entre origens (Asaas),
    // exibir o AlertDialog de aviso com opção de vincular ou marcar mesmo assim
    if (!item.selected && itAny.isCrossOriginDuplicate && itAny.matchedCrossOrigin) {
      setCrossOriginWarning({
        item,
        matched: itAny.matchedCrossOrigin,
        clientName: itAny.crossOriginClientName || 'Cliente identificado',
      })
      return
    }
    toggleSelectItem(item.id)
  }

  const handleConfirmIncludeCrossOriginItem = () => {
    if (!crossOriginWarning) return
    const idToSelect = crossOriginWarning.item.id
    setParsedItems((prev) =>
      prev.map((it) => (it.id === idToSelect ? { ...it, selected: true } : it)),
    )
    setCrossOriginWarning(null)
  }

  const handleLinkToExisting = () => {
    if (!crossOriginWarning) return
    const idToSkip = crossOriginWarning.item.id
    // Garante que a linha fica desmarcada com badge "Pagamento já registrado via Asaas"
    setParsedItems((prev) =>
      prev.map((it) =>
        it.id === idToSkip ? { ...it, selected: false, isLinkedToAsaas: true } : it,
      ),
    )
    toast({
      title: 'Vinculado ao lançamento Asaas',
      description:
        'Lançamento Asaas mantido. O item do extrato não será importado para evitar duplicidade.',
    })
    setCrossOriginWarning(null)
  }

  const selectedCount = parsedItems.filter((it) => it.selected).length
  const duplicateCount = parsedItems.filter(
    (it: any) => it.isDuplicate || it.isCrossOriginDuplicate,
  ).length
  const highConfidenceCount = parsedItems.filter((it) => it.confidence === 'high').length
  const lowConfidenceCount = parsedItems.filter((it) => it.confidence !== 'high').length

  const handleImportToConciliation = async () => {
    const itemsToImport = parsedItems.filter((it) => it.selected)
    if (itemsToImport.length === 0) {
      toast({
        title: 'Nenhum item selecionado',
        description: 'Selecione ao menos um lançamento para importar.',
        variant: 'destructive',
      })
      return
    }

    setSaving(true)
    try {
      // Se for fatura de cartão de crédito (Santander Aline, Inter, etc), a forma de pagamento é CARTÃO DE CRÉDITO
      const isCreditCard =
        selectedBank.toLowerCase().includes('crédito') ||
        selectedBank.toLowerCase().includes('credito') ||
        selectedBank.toLowerCase().includes('cartão') ||
        selectedBank.toLowerCase().includes('cartao')

      const originTag =
        selectedBank === 'SICOOB'
          ? 'IMPORT_SICOOB'
          : `EXTRATO_${selectedBank.toUpperCase().replace(/\s+/g, '_')}`

      const records = itemsToImport.map((it) => ({
        description: it.description,
        amount: it.amount,
        type: it.type,
        category:
          it.categorySuggestion ||
          (it.type === 'income'
            ? 'Honorários Contratuais'
            : isCreditCard
              ? 'Despesas Gerais'
              : 'Despesas Gerais'),
        status: 'Pago',
        date: it.date,
        clientId: null,
        supplierId: null,
        processId: null,
        sendToFinance: true,
        bankAccount: selectedBank,
        payment_method: isCreditCard ? 'CARTÃO DE CRÉDITO' : 'OUTRO',
        pendente_vinculo: true, // Entra na fila de conciliação para conferência manual
        origem: originTag,
      }))

      const { error } = await supabase.from('transactions').insert(records)
      if (error) throw error

      const nowIso = new Date().toISOString()
      if (onImportCompleted) {
        await onImportCompleted(nowIso, selectedBank)
      }

      await onSuccess()

      toast({
        title: 'Extrato Importado com Sucesso!',
        description: `${records.length} lançamentos da conta '${selectedBank}' enviados para o Financeiro.`,
      })

      handleReset()
      onOpenChange(false)
    } catch (err: any) {
      toast({
        title: 'Erro ao salvar lançamentos',
        description: err.message || 'Falha ao gravar transações no banco.',
        variant: 'destructive',
      })
    } finally {
      setSaving(false)
    }
  }

  const handleReset = () => {
    setParsedItems([])
    setFileName(null)
    setRawTextFallback('')
    setShowTextFallback(false)
    setErrorMessage(null)
  }

  return (
    <>
      <Dialog
        open={open}
        onOpenChange={(v) => {
          if (!parsing && !saving) {
            if (!v) handleReset()
            onOpenChange(v)
          }
        }}
      >
        <DialogContent className="max-w-3xl max-h-[90vh] flex flex-col">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <FileUp className="h-5 w-5 text-emerald-600" />
              Importar Extrato Bancário ou de Cartão (PDF ou Texto)
            </DialogTitle>
            <DialogDescription>
              Envie o extrato em PDF da conta SICOOB, ou faturas dos seus cartões de crédito
              (Crédito Santander Aline, Cartão Inter, etc.). O sistema lê os lançamentos e vincula à
              conta/cartão selecionado. Despesas com GoogleAds/MetaAds são automaticamente
              categorizadas como Marketing do escritório.
            </DialogDescription>
          </DialogHeader>

          <div className="flex-1 overflow-y-auto space-y-4 py-2 pr-1">
            {/* Configuração de Conta / Cartão de Origem */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 items-end">
              <div className="space-y-1.5">
                <Label className="font-semibold text-slate-800">Conta / Cartão de Origem</Label>
                <Select value={selectedBank} onValueChange={setSelectedBank}>
                  <SelectTrigger className="bg-white">
                    <SelectValue placeholder="Selecione a conta ou cartão" />
                  </SelectTrigger>
                  <SelectContent>
                    {/* Lista vinda das contas cadastradas nas configurações */}
                    {Array.from(
                      new Set([
                        ...bankAccounts,
                        'SICOOB',
                        'Crédito Santander Aline',
                        'Cartão Inter',
                      ]),
                    ).map((b) => (
                      <SelectItem key={b} value={b}>
                        {b}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              {/* Input de Upload */}
              <div className="space-y-1.5">
                <Label>Arquivo PDF do Extrato</Label>
                <div className="flex items-center gap-2">
                  <Input
                    type="file"
                    accept="application/pdf"
                    onChange={handleFileUpload}
                    disabled={parsing || saving}
                    className="bg-white cursor-pointer file:cursor-pointer"
                  />
                </div>
              </div>
            </div>

            {parsing && (
              <div className="flex items-center justify-center gap-2 py-8 text-sm text-slate-600 bg-slate-50 rounded-lg border">
                <Loader2 className="h-5 w-5 animate-spin text-emerald-600" />
                <span>
                  Processando PDF localmente no navegador (sem envio a servidores de terceiros)...
                </span>
              </div>
            )}

            {errorMessage && (
              <div className="rounded-lg bg-amber-50 p-3 border border-amber-200 text-xs text-amber-900 flex items-start gap-2">
                <AlertCircle className="h-4 w-4 shrink-0 text-amber-600 mt-0.5" />
                <div className="flex-1">
                  <p className="font-semibold">Aviso de Leitura:</p>
                  <p>{errorMessage}</p>
                  <Button
                    variant="link"
                    className="p-0 h-auto text-xs text-amber-800 underline mt-1"
                    onClick={() => setShowTextFallback(!showTextFallback)}
                  >
                    {showTextFallback
                      ? 'Ocultar caixa de texto'
                      : 'Colar ou editar texto do extrato manualmente'}
                  </Button>
                </div>
              </div>
            )}

            {/* Fallback de Texto / Edição manual */}
            {showTextFallback && (
              <div className="space-y-2 p-3 bg-slate-50 border rounded-lg">
                <div className="flex items-center justify-between">
                  <Label className="text-xs font-semibold flex items-center gap-1.5">
                    <FileText className="h-3.5 w-3.5 text-slate-500" />
                    Texto bruto extraído do extrato (copie e cole aqui se preferir):
                  </Label>
                  <Button
                    size="sm"
                    variant="outline"
                    className="h-7 text-xs"
                    onClick={handleReparseText}
                  >
                    Reconhecer Lançamentos
                  </Button>
                </div>
                <Textarea
                  rows={6}
                  value={rawTextFallback}
                  onChange={(e) => setRawTextFallback(e.target.value)}
                  placeholder="Exemplo:&#10;02/03/2026 PIX ENVIADO FORNECEDOR ABC -150,00&#10;05/03/2026 RECEBIMENTO HONORARIOS 1.500,00 C"
                  className="font-mono text-xs bg-white"
                />
              </div>
            )}

            {/* Pré-visualização das linhas reconhecidas */}
            {parsedItems.length > 0 && (
              <div className="space-y-3">
                <div className="flex flex-wrap items-center justify-between gap-2 bg-slate-50 p-3 rounded-lg border">
                  <div className="flex items-center gap-2">
                    <CheckCircle2 className="h-4 w-4 text-emerald-600" />
                    <span className="text-sm font-semibold text-slate-800">
                      Pré-visualização: {parsedItems.length} lançamentos detectados
                    </span>
                    {fileName && (
                      <Badge variant="outline" className="text-xs bg-white text-slate-600">
                        {fileName}
                      </Badge>
                    )}
                  </div>
                  <div className="flex items-center gap-2 text-xs">
                    <Badge
                      variant="outline"
                      className="bg-emerald-50 text-emerald-700 border-emerald-200"
                    >
                      {highConfidenceCount} claros
                    </Badge>
                    {lowConfidenceCount > 0 && (
                      <Badge
                        variant="outline"
                        className="bg-amber-50 text-amber-700 border-amber-200"
                      >
                        {lowConfidenceCount} para conferir
                      </Badge>
                    )}
                    {duplicateCount > 0 && (
                      <Badge variant="outline" className="bg-red-50 text-red-700 border-red-200">
                        {duplicateCount} duplicados (pulados)
                      </Badge>
                    )}
                    <div className="flex gap-1 ml-2">
                      <Button
                        size="sm"
                        variant="ghost"
                        className="h-6 px-2 text-xs"
                        onClick={() => toggleSelectAll(true)}
                      >
                        Marcar todos
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        className="h-6 px-2 text-xs text-muted-foreground"
                        onClick={() => toggleSelectAll(false)}
                      >
                        Desmarcar
                      </Button>
                    </div>
                  </div>
                </div>

                <div className="border rounded-md max-h-[300px] overflow-y-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead className="w-[40px]"></TableHead>
                        <TableHead className="w-[100px]">Data</TableHead>
                        <TableHead>Descrição Identificada</TableHead>
                        <TableHead className="w-[100px]">Tipo</TableHead>
                        <TableHead className="text-right w-[120px]">Valor</TableHead>
                        <TableHead className="w-[110px]">Conferência</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {parsedItems.map((item) => {
                        const isIncome = item.type === 'income'
                        return (
                          <TableRow
                            key={item.id}
                            className={cn(
                              'hover:bg-slate-50',
                              !item.selected && 'opacity-50 bg-slate-50/50',
                            )}
                          >
                            <TableCell>
                              <Checkbox
                                checked={item.selected}
                                onCheckedChange={() => handleCheckboxClick(item)}
                              />
                            </TableCell>
                            <TableCell className="font-mono text-xs">
                              {formatSafeLocalDate(item.date)}
                            </TableCell>
                            <TableCell>
                              <div className="font-medium text-xs text-slate-800">
                                {item.description}
                              </div>
                              <div className="text-[11px] text-muted-foreground">
                                {item.categorySuggestion}
                              </div>
                            </TableCell>
                            <TableCell>
                              <Badge
                                variant="outline"
                                className={cn(
                                  'text-[10px]',
                                  isIncome
                                    ? 'bg-green-50 text-green-700 border-green-200'
                                    : 'bg-red-50 text-red-700 border-red-200',
                                )}
                              >
                                {isIncome ? (
                                  <ArrowUpRight className="h-3 w-3 mr-0.5 inline" />
                                ) : (
                                  <ArrowDownRight className="h-3 w-3 mr-0.5 inline" />
                                )}
                                {isIncome ? 'Entrada' : 'Saída'}
                              </Badge>
                            </TableCell>
                            <TableCell
                              className={cn(
                                'text-right font-bold text-xs',
                                isIncome ? 'text-green-600' : 'text-red-600',
                              )}
                            >
                              {isIncome ? '+' : '-'} R${' '}
                              {item.amount.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
                            </TableCell>
                            <TableCell>
                              {(item as any).isDuplicate ? (
                                <Badge
                                  variant="outline"
                                  className="bg-red-50 text-[10px] text-red-700 border-red-200 whitespace-nowrap"
                                  title="Lançamento com mesma data, valor, descrição e conta já existe no sistema"
                                >
                                  Já existe
                                </Badge>
                              ) : (item as any).isLinkedToAsaas ||
                                (item as any).isCrossOriginDuplicate ? (
                                <Badge
                                  variant="outline"
                                  className="bg-amber-50 text-[10px] text-amber-800 border-amber-300 font-medium whitespace-nowrap cursor-pointer hover:bg-amber-100"
                                  title="Cobrança correspondente encontrada no Asaas (mesmo cliente, valor e data próxima)"
                                  onClick={() => {
                                    const itAny = item as any
                                    if (itAny.matchedCrossOrigin) {
                                      setCrossOriginWarning({
                                        item,
                                        matched: itAny.matchedCrossOrigin,
                                        clientName: itAny.crossOriginClientName || 'Cliente',
                                      })
                                    }
                                  }}
                                >
                                  Pagamento já registrado via Asaas
                                </Badge>
                              ) : item.confidence === 'high' ? (
                                <Badge
                                  variant="outline"
                                  className="bg-slate-50 text-[10px] text-slate-600 whitespace-nowrap"
                                >
                                  Automático
                                </Badge>
                              ) : (
                                <Badge
                                  variant="outline"
                                  className="bg-amber-50 text-[10px] text-amber-700 border-amber-200 whitespace-nowrap"
                                >
                                  Revisar
                                </Badge>
                              )}
                            </TableCell>
                          </TableRow>
                        )
                      })}
                    </TableBody>
                  </Table>
                </div>

                <p className="text-[11px] text-muted-foreground">
                  * Todos os itens selecionados entrarão na fila de Conciliação com a origem marcada
                  como <span className="font-semibold">{selectedBank}</span> para você vincular ao
                  cliente ou fornecedor com 1 clique.
                </p>
              </div>
            )}
          </div>

          <DialogFooter className="flex flex-col-reverse sm:flex-row sm:justify-between gap-2 pt-2 border-t">
            <Button
              variant="ghost"
              onClick={() => setShowTextFallback(!showTextFallback)}
              className="text-xs text-slate-600"
            >
              {showTextFallback ? 'Fechar texto manual' : 'Colar texto / CSV manualmente'}
            </Button>

            <div className="flex gap-2 justify-end">
              <Button
                variant="outline"
                onClick={() => onOpenChange(false)}
                disabled={parsing || saving}
              >
                Cancelar
              </Button>
              <Button
                onClick={handleImportToConciliation}
                disabled={parsing || saving || selectedCount === 0}
                className="gap-2 bg-emerald-600 hover:bg-emerald-700"
              >
                {saving ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <FileUp className="h-4 w-4" />
                )}
                {saving ? 'Importando...' : `Importar Selecionados (${selectedCount})`}
              </Button>
            </div>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* AlertDialog de aviso de provável duplicado entre origens (Extrato x Asaas) */}
      <AlertDialog
        open={Boolean(crossOriginWarning)}
        onOpenChange={(v) => {
          if (!v) setCrossOriginWarning(null)
        }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle className="text-amber-800 flex items-center gap-2">
              ⚠️ Provável pagamento duplicado entre origens
            </AlertDialogTitle>
            <AlertDialogDescription className="space-y-3 text-slate-700">
              <p>
                Este lançamento do extrato bancário coincide com um pagamento já registrado via{' '}
                <strong>Asaas</strong> para{' '}
                <strong className="text-slate-900">{crossOriginWarning?.clientName}</strong>:
              </p>
              {crossOriginWarning?.matched && (
                <div className="bg-amber-50/80 border border-amber-200 rounded-lg p-3 text-xs space-y-1 font-sans text-slate-800">
                  <p>
                    <strong className="text-slate-900">Lançamento Asaas existente:</strong>
                  </p>
                  <p>
                    <strong>Data:</strong> {formatSafeLocalDate(crossOriginWarning.matched.date)}
                  </p>
                  <p>
                    <strong>Valor:</strong> R${' '}
                    {Number(crossOriginWarning.matched.amount || 0).toLocaleString('pt-BR', {
                      minimumFractionDigits: 2,
                    })}
                  </p>
                  <p>
                    <strong>Descrição:</strong> {crossOriginWarning.matched.description}
                  </p>
                  <p>
                    <strong>Status:</strong> {crossOriginWarning.matched.status || 'Pago'}
                  </p>
                  <div className="pt-1.5 border-t border-amber-200/60 mt-1.5">
                    <p>
                      <strong className="text-slate-900">Linha atual do extrato:</strong>
                    </p>
                    <p>
                      {formatSafeLocalDate(crossOriginWarning.item.date)} —{' '}
                      {crossOriginWarning.item.description} (R${' '}
                      {crossOriginWarning.item.amount.toLocaleString('pt-BR', {
                        minimumFractionDigits: 2,
                      })}
                      )
                    </p>
                  </div>
                </div>
              )}
              <p className="text-xs text-muted-foreground">
                Para evitar cobrança e saldo duplicados no financeiro, recomendamos vincular ao
                lançamento do Asaas existente (desmarcando esta linha do extrato).
              </p>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter className="flex-col sm:flex-row gap-2">
            <AlertDialogCancel onClick={() => setCrossOriginWarning(null)}>
              Cancelar
            </AlertDialogCancel>
            <Button
              type="button"
              variant="outline"
              className="border-emerald-600 text-emerald-700 hover:bg-emerald-50"
              onClick={handleLinkToExisting}
            >
              Vincular ao existente (não lançar de novo)
            </Button>
            <AlertDialogAction
              onClick={handleConfirmIncludeCrossOriginItem}
              className="bg-amber-600 hover:bg-amber-700 text-white"
            >
              Lançar mesmo assim
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  )
}
