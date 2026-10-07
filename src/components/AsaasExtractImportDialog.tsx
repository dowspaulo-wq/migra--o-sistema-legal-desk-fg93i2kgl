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
import { Loader2, Download, AlertCircle, CheckCircle2 } from 'lucide-react'
import { importAsaasExtract } from '@/services/asaas'
import { toast } from '@/hooks/use-toast'

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
  const firstDay = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-01`
  const lastDay = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate())}`

  const [startDate, setStartDate] = useState(firstDay)
  const [finishDate, setFinishDate] = useState(lastDay)
  const [loading, setLoading] = useState(false)
  const [resultSummary, setResultSummary] = useState<{
    totalFetched: number
    insertedCount: number
    preReconciledCount: number
    pendingReviewCount: number
    skippedExistingCount: number
    message?: string
  } | null>(null)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  const handleImport = async () => {
    if (!startDate || !finishDate) {
      toast({
        title: 'Período obrigatório',
        description: 'Selecione a data inicial e final para importar o extrato.',
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

    setLoading(true)
    setErrorMessage(null)
    setResultSummary(null)

    try {
      const { data, error } = await importAsaasExtract(startDate, finishDate)

      if (error) {
        throw error
      }

      if (data?.error) {
        throw new Error(data.error)
      }

      setResultSummary({
        totalFetched: data?.totalFetched ?? 0,
        insertedCount: data?.insertedCount ?? 0,
        preReconciledCount: data?.preReconciledCount ?? 0,
        pendingReviewCount: data?.pendingReviewCount ?? 0,
        skippedExistingCount: data?.skippedExistingCount ?? 0,
        message: data?.message,
      })

      await onSuccess()

      toast({
        title: 'Extrato Asaas Importado!',
        description: `${data?.insertedCount ?? 0} novos lançamentos inseridos na fila de conciliação.`,
      })
    } catch (err: any) {
      const msg = err.message || 'Falha ao importar extrato do Asaas.'
      setErrorMessage(msg)
      toast({
        title: 'Erro na importação',
        description: msg,
        variant: 'destructive',
      })
    } finally {
      setLoading(false)
    }
  }

  const handleClose = () => {
    if (loading) return
    setErrorMessage(null)
    setResultSummary(null)
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Download className="h-5 w-5 text-blue-600" />
            Importar Extrato do Asaas
          </DialogTitle>
          <DialogDescription>
            Puxa entradas e saídas (contas a pagar) do Asaas no período escolhido e joga diretamente
            na fila de conciliação. Sem custos, sem IA.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 py-2">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="asaas-start-date">Data Inicial</Label>
              <Input
                id="asaas-start-date"
                type="date"
                value={startDate}
                onChange={(e) => setStartDate(e.target.value)}
                disabled={loading}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="asaas-finish-date">Data Final</Label>
              <Input
                id="asaas-finish-date"
                type="date"
                value={finishDate}
                onChange={(e) => setFinishDate(e.target.value)}
                disabled={loading}
              />
            </div>
          </div>

          <div className="rounded-lg bg-blue-50/70 p-3 border border-blue-200 text-xs text-blue-900 space-y-1">
            <p className="font-semibold">Como funciona a conciliação manual por regras:</p>
            <ul className="list-disc list-inside space-y-0.5 text-blue-800">
              <li>
                Lançamentos com cliente/fornecedor ou valor coincidente entram pré-conciliados.
              </li>
              <li>
                Lançamentos não identificados ficam marcados para sua conferência na aba
                Conciliação.
              </li>
              <li>
                Lançamentos já importados anteriormente são ignorados para evitar duplicidades.
              </li>
            </ul>
          </div>

          {errorMessage && (
            <div className="rounded-lg bg-red-50 p-3 border border-red-200 text-xs text-red-800 flex items-start gap-2">
              <AlertCircle className="h-4 w-4 shrink-0 text-red-600 mt-0.5" />
              <div>
                <p className="font-semibold">Não foi possível importar:</p>
                <p>{errorMessage}</p>
                {errorMessage.includes('ASAAS_API_KEY') && (
                  <p className="mt-1 text-slate-700">
                    Dica: Configure a variável{' '}
                    <code className="font-mono bg-red-100 px-1 rounded">ASAAS_API_KEY</code> no
                    EasyPanel do VPS e execute o script de implantação.
                  </p>
                )}
              </div>
            </div>
          )}

          {resultSummary && (
            <div className="rounded-lg bg-green-50 p-3 border border-green-200 text-xs text-green-900 space-y-1.5">
              <div className="flex items-center gap-1.5 font-semibold text-green-800">
                <CheckCircle2 className="h-4 w-4 text-green-600" />
                Resumo da Importação
              </div>
              <div className="grid grid-cols-2 gap-2 pt-1">
                <div>
                  Total no Asaas: <span className="font-bold">{resultSummary.totalFetched}</span>
                </div>
                <div>
                  Novos inseridos:{' '}
                  <span className="font-bold text-green-700">{resultSummary.insertedCount}</span>
                </div>
                <div>
                  Pré-conciliados:{' '}
                  <span className="font-bold text-blue-700">
                    {resultSummary.preReconciledCount}
                  </span>
                </div>
                <div>
                  Para revisão:{' '}
                  <span className="font-bold text-amber-700">
                    {resultSummary.pendingReviewCount}
                  </span>
                </div>
              </div>
              {resultSummary.skippedExistingCount > 0 && (
                <p className="text-[11px] text-slate-600">
                  {resultSummary.skippedExistingCount} item(s) já estavam no sistema e foram
                  pulados.
                </p>
              )}
            </div>
          )}
        </div>

        <DialogFooter className="flex gap-2 justify-end">
          <Button variant="outline" onClick={handleClose} disabled={loading}>
            {resultSummary ? 'Fechar' : 'Cancelar'}
          </Button>
          <Button
            onClick={handleImport}
            disabled={loading}
            className="gap-2 bg-blue-600 hover:bg-blue-700"
          >
            {loading ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <Download className="h-4 w-4" />
            )}
            {loading ? 'Consultando Asaas...' : 'Importar Extrato'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
