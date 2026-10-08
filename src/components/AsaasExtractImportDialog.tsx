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
import { Label } from '@/components/ui/label'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Checkbox } from '@/components/ui/checkbox'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import {
  Loader2,
  Download,
  AlertCircle,
  CheckCircle2,
  Search,
  CheckSquare,
  Square,
  ArrowUpRight,
  ArrowDownRight,
  RefreshCw,
} from 'lucide-react'
import { fetchAsaasExtractPreview, importSelectedAsaasItems } from '@/services/asaas'
import { formatSafeLocalDate } from '@/lib/utils'
import { toast } from '@/hooks/use-toast'

export interface AsaasPreviewItem {
  id: string
  date: string
  description: string
  amount: number
  type: 'income' | 'expense'
  rawType?: string
  status: string
  alreadyImported: boolean
  suggestedClientId?: string | null
  suggestedClientName?: string | null
  suggestedSupplierId?: string | null
  suggestedSupplierName?: string | null
  matchedTransactionId?: string | null
  matchedTransactionDesc?: string | null
  paymentMethod?: string
}

interface AsaasExtractImportDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  onSuccess: () => Promise<void> | void
}

export function AsaasExtractImportDialog({
  open,
  onOpenChange,
  onSuccess,
}: AsaasExtractImportDialogProps) {
  const pad = (n: number) => n.toString().padStart(2, '0')
  const now = new Date()

  const setShortcutDays = (days: number) => {
    const end = new Date()
    const start = new Date()
    start.setDate(end.getDate() - days)
    setStartDate(`${start.getFullYear()}-${pad(start.getMonth() + 1)}-${pad(start.getDate())}`)
    setFinishDate(`${end.getFullYear()}-${pad(end.getMonth() + 1)}-${pad(end.getDate())}`)
  }

  const [startDate, setStartDate] = useState(() => {
    const d = new Date()
    d.setDate(d.getDate() - 30)
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
  })
  const [finishDate, setFinishDate] = useState(
    `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`,
  )

  const [loadingPreview, setLoadingPreview] = useState(false)
  const [loadingImport, setLoadingImport] = useState(false)
  const [previewItems, setPreviewItems] = useState<AsaasPreviewItem[] | null>(null)
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [importResult, setImportResult] = useState<{
    insertedCount: number
    updatedMatchedCount: number
    skippedExistingCount: number
    message?: string
  } | null>(null)

  const handleFetchPreview = async () => {
    if (!startDate || !finishDate) {
      toast({
        title: 'Período obrigatório',
        description: 'Selecione a data inicial e final para consultar o extrato.',
        variant: 'destructive',
      })
      return
    }

    if (startDate > finishDate) {
      toast({
        title: 'Período inválido',
        description: 'A data inicial não pode ser posterior à data final.',
        variant: 'destructive',
      })
      return
    }

    setLoadingPreview(true)
    setErrorMessage(null)
    setImportResult(null)

    try {
      const { data, error } = await fetchAsaasExtractPreview(startDate, finishDate)

      if (error) throw error
      if (data?.error) throw new Error(data.error)

      const items: AsaasPreviewItem[] = data?.items || []
      setPreviewItems(items)

      // Por padrão, marcar todos os itens que ainda NÃO foram importados
      const initialSelected = new Set<string>()
      items.forEach((item) => {
        if (!item.alreadyImported) {
          initialSelected.add(item.id)
        }
      })
      setSelectedIds(initialSelected)

      if (items.length === 0) {
        toast({
          title: 'Nenhuma movimentação encontrada',
          description: 'Nenhum lançamento no Asaas foi retornado para o período selecionado.',
        })
      }
    } catch (err: any) {
      const msg = err.message || 'Falha ao buscar pré-visualização do extrato.'
      setErrorMessage(msg)
      toast({
        title: 'Erro ao consultar Asaas',
        description: msg,
        variant: 'destructive',
      })
    } finally {
      setLoadingPreview(false)
    }
  }

  const toggleSelectAll = () => {
    if (!previewItems) return
    const selectable = previewItems.filter((i) => !i.alreadyImported)
    if (selectedIds.size === selectable.length) {
      setSelectedIds(new Set())
    } else {
      setSelectedIds(new Set(selectable.map((i) => i.id)))
    }
  }

  const toggleItem = (id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  const handleConfirmImport = async () => {
    if (!previewItems || selectedIds.size === 0) {
      toast({
        title: 'Nenhum item selecionado',
        description: 'Selecione pelo menos uma movimentação para importar.',
        variant: 'destructive',
      })
      return
    }

    const itemsToImport = previewItems
      .filter((i) => selectedIds.has(i.id))
      .map((i) => ({
        id: i.id,
        date: i.date,
        description: i.description,
        amount: i.amount,
        type: i.type,
        rawType: i.rawType,
        clientId: i.suggestedClientId || null,
        supplierId: i.suggestedSupplierId || null,
        matchedTransactionId: i.matchedTransactionId || null,
        paymentMethod: i.paymentMethod || 'PIX',
      }))

    setLoadingImport(true)
    setErrorMessage(null)

    try {
      const { data, error } = await importSelectedAsaasItems(itemsToImport)

      if (error) throw error
      if (data?.error) throw new Error(data.error)

      setImportResult({
        insertedCount: data?.insertedCount ?? 0,
        updatedMatchedCount: data?.updatedMatchedCount ?? 0,
        skippedExistingCount: data?.skippedExistingCount ?? 0,
        message: data?.message,
      })

      await onSuccess()

      toast({
        title: 'Extrato Importado com Sucesso!',
        description: `${data?.insertedCount ?? 0} novos lançamentos e ${data?.updatedMatchedCount ?? 0} conciliados.`,
      })

      // Atualiza os itens da prévia marcando como importados
      setPreviewItems((prev) =>
        prev
          ? prev.map((item) =>
              selectedIds.has(item.id) ? { ...item, alreadyImported: true } : item,
            )
          : null,
      )
      setSelectedIds(new Set())
    } catch (err: any) {
      const msg = err.message || 'Falha ao importar itens selecionados.'
      setErrorMessage(msg)
      toast({
        title: 'Erro na importação',
        description: msg,
        variant: 'destructive',
      })
    } finally {
      setLoadingImport(false)
    }
  }

  const handleClose = () => {
    if (loadingPreview || loadingImport) return
    setErrorMessage(null)
    setImportResult(null)
    onOpenChange(false)
  }

  const newSelectableCount = previewItems
    ? previewItems.filter((i) => !i.alreadyImported).length
    : 0

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent className="max-w-4xl max-h-[90vh] flex flex-col">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Download className="h-5 w-5 text-blue-600" />
            Importar Extrato do Asaas
          </DialogTitle>
          <DialogDescription>
            Consulte entradas e saídas do Asaas com pré-visualização, correspondência automática com
            lançamentos do sistema e conciliação idempotente.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 py-2 flex-1 overflow-y-auto pr-1">
          {/* Seleção de período e atalhos 30/60/90 dias */}
          <div className="bg-slate-50 p-3 rounded-lg border space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <span className="text-xs font-semibold text-slate-700">Atalhos rápidos:</span>
              <div className="flex gap-1.5">
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  className="h-7 text-xs bg-white"
                  onClick={() => setShortcutDays(30)}
                  disabled={loadingPreview || loadingImport}
                >
                  Últimos 30 dias
                </Button>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  className="h-7 text-xs bg-white"
                  onClick={() => setShortcutDays(60)}
                  disabled={loadingPreview || loadingImport}
                >
                  Últimos 60 dias
                </Button>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  className="h-7 text-xs bg-white"
                  onClick={() => setShortcutDays(90)}
                  disabled={loadingPreview || loadingImport}
                >
                  Últimos 90 dias
                </Button>
              </div>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 items-end">
              <div className="space-y-1">
                <Label htmlFor="asaas-start-date" className="text-xs">
                  Data Inicial
                </Label>
                <Input
                  id="asaas-start-date"
                  type="date"
                  value={startDate}
                  onChange={(e) => setStartDate(e.target.value)}
                  disabled={loadingPreview || loadingImport}
                  className="bg-white h-9 text-xs"
                />
              </div>
              <div className="space-y-1">
                <Label htmlFor="asaas-finish-date" className="text-xs">
                  Data Final
                </Label>
                <Input
                  id="asaas-finish-date"
                  type="date"
                  value={finishDate}
                  onChange={(e) => setFinishDate(e.target.value)}
                  disabled={loadingPreview || loadingImport}
                  className="bg-white h-9 text-xs"
                />
              </div>
              <div>
                <Button
                  onClick={handleFetchPreview}
                  disabled={loadingPreview || loadingImport}
                  className="w-full gap-2 bg-blue-600 hover:bg-blue-700 h-9 text-xs"
                >
                  {loadingPreview ? (
                    <Loader2 className="h-4 w-4 animate-spin" />
                  ) : (
                    <Search className="h-4 w-4" />
                  )}
                  {loadingPreview ? 'Consultando...' : 'Buscar Extrato'}
                </Button>
              </div>
            </div>
          </div>

          {/* Alertas de erro */}
          {errorMessage && (
            <div className="rounded-lg bg-red-50 p-3 border border-red-200 text-xs text-red-800 flex items-start gap-2">
              <AlertCircle className="h-4 w-4 shrink-0 text-red-600 mt-0.5" />
              <div>
                <p className="font-semibold">Erro na consulta do Asaas:</p>
                <p>{errorMessage}</p>
              </div>
            </div>
          )}

          {/* Resumo da importação concluída */}
          {importResult && (
            <div className="rounded-lg bg-emerald-50 p-3 border border-emerald-200 text-xs text-emerald-900 space-y-1">
              <div className="flex items-center gap-1.5 font-semibold text-emerald-800">
                <CheckCircle2 className="h-4 w-4 text-emerald-600" />
                Resultado da Importação:
              </div>
              <p>{importResult.message}</p>
            </div>
          )}

          {/* Tabela de Pré-visualização Linha a Linha */}
          {previewItems !== null && (
            <div className="space-y-2">
              <div className="flex flex-wrap items-center justify-between gap-2 text-xs text-slate-600 px-1">
                <div className="flex items-center gap-2">
                  <span className="font-semibold text-slate-800">
                    {previewItems.length} movimentações no período
                  </span>
                  <span>•</span>
                  <span>
                    <strong className="text-blue-700">{selectedIds.size}</strong> selecionadas
                  </span>
                  {previewItems.some((i) => i.alreadyImported) && (
                    <>
                      <span>•</span>
                      <span className="text-slate-500">
                        {previewItems.filter((i) => i.alreadyImported).length} já no sistema
                      </span>
                    </>
                  )}
                </div>

                {newSelectableCount > 0 && (
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    className="h-7 text-xs gap-1 text-slate-700 hover:text-slate-900"
                    onClick={toggleSelectAll}
                    disabled={loadingImport}
                  >
                    {selectedIds.size === newSelectableCount ? (
                      <>
                        <Square className="h-3.5 w-3.5" /> Desmarcar Todas
                      </>
                    ) : (
                      <>
                        <CheckSquare className="h-3.5 w-3.5 text-blue-600" /> Marcar Todas Novas
                      </>
                    )}
                  </Button>
                )}
              </div>

              <div className="rounded-md border max-h-[360px] overflow-y-auto">
                <Table>
                  <TableHeader className="bg-slate-50 sticky top-0 z-10 shadow-sm">
                    <TableRow>
                      <TableHead className="w-[40px] text-center"></TableHead>
                      <TableHead className="w-[90px]">Data</TableHead>
                      <TableHead>Descrição Asaas</TableHead>
                      <TableHead>Correspondência / Sugestão</TableHead>
                      <TableHead className="w-[90px]">Status</TableHead>
                      <TableHead className="text-right w-[110px]">Valor</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {previewItems.map((item) => {
                      const isSelected = selectedIds.has(item.id)
                      const isIncome = item.type === 'income'

                      return (
                        <TableRow
                          key={item.id}
                          className={`text-xs ${item.alreadyImported ? 'bg-slate-50/70 opacity-60' : isSelected ? 'bg-blue-50/40' : ''}`}
                        >
                          <TableCell className="text-center p-2">
                            {item.alreadyImported ? (
                              <span
                                title="Lançamento já existente no sistema (idempotência)"
                                className="inline-block text-[10px] text-slate-400 font-mono"
                              >
                                —
                              </span>
                            ) : (
                              <Checkbox
                                checked={isSelected}
                                onCheckedChange={() => toggleItem(item.id)}
                                disabled={loadingImport}
                              />
                            )}
                          </TableCell>
                          <TableCell className="font-mono text-[11px] whitespace-nowrap">
                            {formatSafeLocalDate(item.date)}
                          </TableCell>
                          <TableCell>
                            <div className="font-medium text-slate-900">{item.description}</div>
                            <div className="text-[10px] text-slate-500 font-mono">
                              ID: {item.id} {item.rawType ? `• ${item.rawType}` : ''}
                            </div>
                          </TableCell>
                          <TableCell>
                            {item.matchedTransactionId ? (
                              <div className="flex flex-col">
                                <Badge
                                  variant="outline"
                                  className="border-emerald-300 bg-emerald-50 text-emerald-800 text-[10px] w-fit"
                                >
                                  Casará com lançamento existente
                                </Badge>
                                <span className="text-[10px] text-slate-600 truncate max-w-[200px] mt-0.5">
                                  {item.matchedTransactionDesc || 'Lançamento com mesmo valor/data'}
                                </span>
                              </div>
                            ) : item.suggestedClientName ? (
                              <div className="flex flex-col">
                                <Badge
                                  variant="outline"
                                  className="border-blue-300 bg-blue-50 text-blue-800 text-[10px] w-fit"
                                >
                                  Cliente identificado
                                </Badge>
                                <span className="text-[10px] text-slate-700 truncate max-w-[200px] mt-0.5">
                                  {item.suggestedClientName}
                                </span>
                              </div>
                            ) : item.suggestedSupplierName ? (
                              <div className="flex flex-col">
                                <Badge
                                  variant="outline"
                                  className="border-purple-300 bg-purple-50 text-purple-800 text-[10px] w-fit"
                                >
                                  Fornecedor identificado
                                </Badge>
                                <span className="text-[10px] text-slate-700 truncate max-w-[200px] mt-0.5">
                                  {item.suggestedSupplierName}
                                </span>
                              </div>
                            ) : (
                              <span className="text-[10px] text-amber-700 italic">
                                Entrará na fila de conciliação
                              </span>
                            )}
                          </TableCell>
                          <TableCell>
                            {item.alreadyImported ? (
                              <Badge
                                variant="outline"
                                className="bg-slate-100 text-slate-600 border-slate-300 text-[10px]"
                              >
                                Já no banco
                              </Badge>
                            ) : (
                              <Badge
                                variant="outline"
                                className="bg-green-50 text-green-700 border-green-200 text-[10px]"
                              >
                                {item.status}
                              </Badge>
                            )}
                          </TableCell>
                          <TableCell
                            className={`text-right font-semibold whitespace-nowrap ${isIncome ? 'text-green-600' : 'text-red-600'}`}
                          >
                            <span className="inline-flex items-center">
                              {isIncome ? (
                                <ArrowUpRight className="h-3 w-3 mr-0.5 inline" />
                              ) : (
                                <ArrowDownRight className="h-3 w-3 mr-0.5 inline" />
                              )}
                              R$ {item.amount.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
                            </span>
                          </TableCell>
                        </TableRow>
                      )
                    })}

                    {previewItems.length === 0 && (
                      <TableRow>
                        <TableCell colSpan={6} className="text-center py-8 text-muted-foreground">
                          Nenhuma movimentação retornada pelo Asaas para o período informado.
                        </TableCell>
                      </TableRow>
                    )}
                  </TableBody>
                </Table>
              </div>
            </div>
          )}
        </div>

        <DialogFooter className="flex flex-col sm:flex-row gap-2 sm:justify-between items-center pt-2 border-t mt-2">
          <div className="text-xs text-muted-foreground">
            {selectedIds.size > 0 ? (
              <span>
                <strong>{selectedIds.size}</strong> item(s) selecionado(s) para gravação segura.
              </span>
            ) : previewItems !== null ? (
              <span>Nenhum item selecionado.</span>
            ) : (
              <span>Selecione as datas e clique em &quot;Buscar Extrato&quot;.</span>
            )}
          </div>

          <div className="flex gap-2 justify-end w-full sm:w-auto">
            <Button
              variant="outline"
              onClick={handleClose}
              disabled={loadingPreview || loadingImport}
            >
              Fechar
            </Button>
            {previewItems !== null && (
              <Button
                onClick={handleConfirmImport}
                disabled={loadingPreview || loadingImport || selectedIds.size === 0}
                className="gap-2 bg-blue-600 hover:bg-blue-700"
              >
                {loadingImport ? (
                  <RefreshCw className="h-4 w-4 animate-spin" />
                ) : (
                  <Download className="h-4 w-4" />
                )}
                {loadingImport ? 'Importando...' : `Confirmar e Importar (${selectedIds.size})`}
              </Button>
            )}
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
