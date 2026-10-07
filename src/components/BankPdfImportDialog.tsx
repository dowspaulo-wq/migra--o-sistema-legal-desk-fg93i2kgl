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

interface BankPdfImportDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  onSuccess: () => Promise<void> | void
  bankAccounts?: string[]
}

export function BankPdfImportDialog({
  open,
  onOpenChange,
  onSuccess,
  bankAccounts = ['SICOOB', 'CAIXA', 'PESSOAL', 'OUTRO'],
}: BankPdfImportDialogProps) {
  const [selectedBank, setSelectedBank] = useState<string>('SICOOB')
  const [parsing, setParsing] = useState(false)
  const [saving, setSaving] = useState(false)
  const [parsedItems, setParsedItems] = useState<ParsedBankStatementItem[]>([])
  const [fileName, setFileName] = useState<string | null>(null)
  const [rawTextFallback, setRawTextFallback] = useState('')
  const [showTextFallback, setShowTextFallback] = useState(false)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

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
        setParsedItems(items)
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
      setParsedItems(items)
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
    setParsedItems((prev) => prev.map((it) => ({ ...it, selected: select })))
  }

  const selectedCount = parsedItems.filter((it) => it.selected).length
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
      const records = itemsToImport.map((it) => ({
        description: it.description,
        amount: it.amount,
        type: it.type,
        category:
          it.categorySuggestion ||
          (it.type === 'income' ? 'Honorários Contratuais' : 'Despesas Gerais'),
        status: 'Pago',
        date: it.date,
        clientId: null,
        supplierId: null,
        processId: null,
        sendToFinance: true,
        bankAccount: selectedBank,
        payment_method: 'OUTRO',
        pendente_vinculo: true, // Sempre entra na fila de conciliação para conferência
        origem:
          selectedBank === 'SICOOB' ? 'IMPORT_SICOOB' : `EXTRATO_${selectedBank.toUpperCase()}`,
      }))

      const { error } = await supabase.from('transactions').insert(records)
      if (error) throw error

      await onSuccess()

      toast({
        title: 'Extrato Importado!',
        description: `${records.length} lançamentos enviados para a fila de conciliação para conferência.`,
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
            Importar Extrato Bancário (PDF ou Texto)
          </DialogTitle>
          <DialogDescription>
            Envie o extrato em PDF da sua conta bancária (Sicoob, Caixa, BB, etc.). O sistema lê as
            linhas no seu navegador e joga na fila de conciliação para conferência manual.
          </DialogDescription>
        </DialogHeader>

        <div className="flex-1 overflow-y-auto space-y-4 py-2 pr-1">
          {/* Configuração de Banco */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 items-end">
            <div className="space-y-1.5">
              <Label>Conta Bancária de Origem</Label>
              <Select value={selectedBank} onValueChange={setSelectedBank}>
                <SelectTrigger className="bg-white">
                  <SelectValue placeholder="Selecione o banco" />
                </SelectTrigger>
                <SelectContent>
                  {bankAccounts.map((b) => (
                    <SelectItem key={b} value={b}>
                      {b}
                    </SelectItem>
                  ))}
                  {!bankAccounts.includes('SICOOB') && (
                    <SelectItem value="SICOOB">SICOOB</SelectItem>
                  )}
                  {!bankAccounts.includes('CAIXA') && <SelectItem value="CAIXA">CAIXA</SelectItem>}
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
                              onCheckedChange={() => toggleSelectItem(item.id)}
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
                            {item.confidence === 'high' ? (
                              <Badge
                                variant="outline"
                                className="bg-slate-50 text-[10px] text-slate-600"
                              >
                                Automático
                              </Badge>
                            ) : (
                              <Badge
                                variant="outline"
                                className="bg-amber-50 text-[10px] text-amber-700 border-amber-200"
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
  )
}
