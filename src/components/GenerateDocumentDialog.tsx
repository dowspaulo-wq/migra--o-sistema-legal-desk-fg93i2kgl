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
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Checkbox } from '@/components/ui/checkbox'
import { Badge } from '@/components/ui/badge'
import { Separator } from '@/components/ui/separator'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  FileText,
  DownloadCloud,
  CheckCircle2,
  Sparkles,
  Paperclip,
  Loader2,
  AlertCircle,
  FileCheck,
} from 'lucide-react'
import { toast } from '@/hooks/use-toast'
import useLegalStore from '@/stores/useLegalStore'
import {
  DocumentTemplate,
  ManualFieldDefinition,
  fetchDocumentTemplates,
  downloadTemplateBuffer,
  buildDocumentDataMap,
  generateDocxBlob,
  triggerFileDownload,
  formatGeneratedFileName,
  saveGeneratedDocxToStorage,
} from '@/services/document-templates'
import { PlaceholdersHelpDialog } from '@/components/PlaceholdersHelpDialog'

interface GenerateDocumentDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  /**
   * Cliente vinculado (obrigatório se gerando a partir do cliente)
   */
  client?: any
  /**
   * Processo vinculado (opcional se gerando a partir de cliente sem processo)
   */
  caseItem?: any
  /**
   * Callback opcional chamado quando documentos forem gerados
   */
  onSuccess?: (generatedDocs: Array<{ name: string; path?: string }>) => void
}

export function GenerateDocumentDialog({
  open,
  onOpenChange,
  client: directClient,
  caseItem: directCase,
  onSuccess,
}: GenerateDocumentDialogProps) {
  const { state, updateItem, addLog } = useLegalStore()

  // Se veio direto, usa; senão tenta resolver caso tenha vindo apenas um
  const [selectedCaseId, setSelectedCaseId] = useState<string>(directCase?.id || '')
  const [allTemplates, setAllTemplates] = useState<DocumentTemplate[]>([])
  const [loadingTemplates, setLoadingTemplates] = useState(false)

  // Modelos selecionados (IDs)
  const [selectedTemplateIds, setSelectedTemplateIds] = useState<string[]>([])

  // Valores manuais coletados: { [fieldKey]: string }
  const [manualValues, setManualValues] = useState<Record<string, string>>({})

  // Opção de salvar anexo no processo
  const [attachToCase, setAttachToCase] = useState<boolean>(true)

  // Status de geração
  const [isGenerating, setIsGenerating] = useState<boolean>(false)
  const [generationProgress, setGenerationProgress] = useState<string>('')

  // Marcadores não resolvidos encontrados na última geração (para aviso visual)
  const [unresolvedWarnings, setUnresolvedWarnings] = useState<
    Array<{ templateName: string; placeholders: string[] }>
  >([])

  // Resolve processo e cliente finais
  const currentCase = useMemo(() => {
    if (directCase) return directCase
    if (selectedCaseId) {
      return state.cases.find((c: any) => c.id === selectedCaseId) || null
    }
    return null
  }, [directCase, selectedCaseId, state.cases])

  const currentClient = useMemo(() => {
    if (directClient) return directClient
    if (currentCase?.clientId) {
      return state.clients.find((cl: any) => cl.id === currentCase.clientId) || null
    }
    return null
  }, [directClient, currentCase, state.clients])

  // Casos do cliente (caso o modal seja aberto na ficha do cliente)
  const clientCases = useMemo(() => {
    if (!directClient?.id) return []
    return state.cases.filter((c: any) => c.clientId === directClient.id)
  }, [directClient, state.cases])

  // Carrega modelos disponíveis
  useEffect(() => {
    if (!open) return
    let isMounted = true
    setLoadingTemplates(true)
    fetchDocumentTemplates().then(({ data }) => {
      if (isMounted) {
        setAllTemplates(data || [])
        setLoadingTemplates(false)
        // Se houver apenas 1 ou nenhum selecionado, reseta
        setSelectedTemplateIds([])
      }
    })
    return () => {
      isMounted = false
    }
  }, [open])

  // Atualiza case selecionado se mudar prop
  useEffect(() => {
    if (directCase?.id) {
      setSelectedCaseId(directCase.id)
    } else if (clientCases.length > 0 && !selectedCaseId) {
      setSelectedCaseId(clientCases[0].id)
    }
  }, [directCase, clientCases])

  // Modelos selecionados completos
  const selectedTemplates = useMemo(() => {
    return allTemplates.filter((t) => selectedTemplateIds.includes(t.id))
  }, [allTemplates, selectedTemplateIds])

  // Agrupa todos os campos manuais únicos requeridos pelos modelos selecionados
  const requiredManualFields = useMemo(() => {
    const map = new Map<string, ManualFieldDefinition>()
    selectedTemplates.forEach((tpl) => {
      ;(tpl.manual_fields || []).forEach((field) => {
        if (!map.has(field.key)) {
          map.set(field.key, field)
        }
      })
    })
    return Array.from(map.values())
  }, [selectedTemplates])

  // Pré-popula campos manuais inteligentes se o processo já tiver dados cadastrados
  useEffect(() => {
    if (!open) return
    const initial: Record<string, string> = { ...manualValues }

    if (currentCase) {
      if (!initial.valorHonorarios && currentCase.feeValue) {
        initial.valorHonorarios = `R$ ${Number(currentCase.feeValue).toLocaleString('pt-BR', { minimumFractionDigits: 2 })}`
      }
      if (!initial.percentualExito && currentCase.feePercentage) {
        initial.percentualExito = `${currentCase.feePercentage}%`
      }
      if (!initial.nomeAcao && (currentCase.process_name || currentCase.type)) {
        initial.nomeAcao = currentCase.process_name || currentCase.type || ''
      }
      if (!initial.formaPagamento && currentCase.feeInstallments) {
        initial.formaPagamento = `${currentCase.feeInstallments} parcelas mensais`
      }
    }

    setManualValues(initial)
  }, [open, currentCase, requiredManualFields.length])

  const toggleTemplateSelection = (id: string) => {
    setSelectedTemplateIds((prev) =>
      prev.includes(id) ? prev.filter((item) => item !== id) : [...prev, id],
    )
  }

  const selectAllTemplates = () => {
    if (selectedTemplateIds.length === allTemplates.length) {
      setSelectedTemplateIds([])
    } else {
      setSelectedTemplateIds(allTemplates.map((t) => t.id))
    }
  }

  const handleManualValueChange = (key: string, val: string) => {
    setManualValues((prev) => ({ ...prev, [key]: val }))
  }

  // Executa a geração de todos os documentos selecionados
  const handleGenerate = async () => {
    if (selectedTemplates.length === 0) {
      toast({
        title: 'Nenhum modelo selecionado',
        description: 'Selecione pelo menos um modelo de documento.',
        variant: 'destructive',
      })
      return
    }

    setIsGenerating(true)
    setUnresolvedWarnings([])
    const generatedResults: Array<{ name: string; path?: string }> = []
    const total = selectedTemplates.length
    const collectedWarnings: Array<{ templateName: string; placeholders: string[] }> = []

    try {
      // 1. Constrói o mapa de dados
      const dataMap = buildDocumentDataMap({
        client: currentClient,
        caseItem: currentCase,
        settings: state.settings,
        manualValues,
        paymentPlans: state.paymentPlans,
        transactions: state.transactions,
        transactionCases: (state as any).transactionCases,
      })

      // 2. Loop para preenchimento e download de cada modelo selecionado
      for (let i = 0; i < total; i++) {
        const tpl = selectedTemplates[i]
        setGenerationProgress(`Processando (${i + 1}/${total}): ${tpl.name}...`)

        // Baixa o buffer do arquivo original no Storage
        const templateBuffer = await downloadTemplateBuffer(tpl.file_path)

        // Preenche client-side com docxtemplater preservando 100% da formatação
        const { blob: docxBlob, unresolvedPlaceholders } = await generateDocxBlob(
          templateBuffer,
          dataMap,
        )

        if (unresolvedPlaceholders && unresolvedPlaceholders.length > 0) {
          collectedWarnings.push({
            templateName: tpl.name,
            placeholders: unresolvedPlaceholders,
          })
        }

        // Nome padronizado automático
        const finalFileName = formatGeneratedFileName(tpl.name, currentClient?.name || 'Cliente')

        // Dispara o download imediato no computador do advogado
        triggerFileDownload(docxBlob, finalFileName)

        let savedPath: string | undefined

        // Se o usuário solicitou e temos um processo, salva no storage e anexa aos documentos do caso
        if (attachToCase && currentCase?.id) {
          const { path: storagePath, error: saveErr } = await saveGeneratedDocxToStorage(
            docxBlob,
            finalFileName,
          )

          if (!saveErr && storagePath) {
            savedPath = storagePath
            // Anexa aos documents do caso seguindo a estrutura padrão
            const existingDocs = Array.isArray(currentCase.documents)
              ? [...currentCase.documents]
              : []
            const newDocEntry = {
              name: finalFileName,
              url: storagePath,
              created_at: new Date().toISOString(),
              category: tpl.category || 'Contrato/Procuração',
            }

            const updatedDocs = [...existingDocs, newDocEntry]
            updateItem('cases', currentCase.id, {
              documents: updatedDocs,
            })
          }
        }

        generatedResults.push({ name: finalFileName, path: savedPath })
      }

      addLog(
        'Documentos',
        'Geração em Lote',
        `Gerados ${total} documento(s) para cliente ${currentClient?.name || '—'}`,
      )

      if (collectedWarnings.length > 0) {
        setUnresolvedWarnings(collectedWarnings)

        const totalUnresolved = collectedWarnings.reduce(
          (sum, item) => sum + item.placeholders.length,
          0,
        )
        const sampleTags = Array.from(
          new Set(collectedWarnings.flatMap((w) => w.placeholders)),
        ).slice(0, 3)
        const sampleText = sampleTags.map((t) => `{{${t}}}`).join(', ')

        toast({
          title: `${total} documento(s) gerado(s) com atenção!`,
          description: `${totalUnresolved} marcador(es) não encontrado(s) (ex: ${sampleText}). Eles saíram marcados como [PREENCHER: ...] no .docx. Revise no painel abaixo.`,
          duration: 9000,
        })
      } else {
        toast({
          title: `${total} documento(s) gerado(s) com sucesso!`,
          description:
            attachToCase && currentCase
              ? 'Os arquivos .docx foram baixados e vinculados ao processo.'
              : 'Os arquivos .docx foram baixados preservando 100% da sua formatação.',
        })
      }

      if (onSuccess) {
        onSuccess(generatedResults)
      }

      // Se houver avisos de campos não resolvidos, mantemos o modal aberto mostrando o painel de alerta amigável
      // para o usuário copiar/conferir, mas oferecendo o botão de fechar. Se não houver avisos, fecha automaticamente.
      if (collectedWarnings.length === 0) {
        onOpenChange(false)
      }
    } catch (err: any) {
      const errorMessage =
        (typeof err?.message === 'string' && err.message.trim()) ||
        'Ocorreu um erro ao preencher o modelo .docx.'

      toast({
        title: 'Erro na geração de documento',
        description: errorMessage,
        variant: 'destructive',
      })
    } finally {
      setIsGenerating(false)
      setGenerationProgress('')
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] flex flex-col p-6">
        <DialogHeader className="pb-3 border-b">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <div className="p-2 rounded-lg bg-blue-50 text-blue-600 border border-blue-200">
                <FileCheck className="h-5 w-5" />
              </div>
              <div>
                <DialogTitle className="text-lg">Gerador de Documentos (.docx)</DialogTitle>
                <DialogDescription className="text-xs text-muted-foreground mt-0.5">
                  Gere contratos, procurações e termos a partir dos seus modelos com 1 clique.
                </DialogDescription>
              </div>
            </div>
            <PlaceholdersHelpDialog />
          </div>
        </DialogHeader>

        <div className="flex-1 overflow-y-auto pr-1 space-y-4 pt-2">
          {/* Painel de Alerta Amigável: Marcadores Não Resolvidos */}
          {unresolvedWarnings.length > 0 && (
            <div className="p-3.5 bg-amber-50 border border-amber-300 rounded-lg text-xs space-y-2 text-amber-900 animate-in fade-in">
              <div className="flex items-start gap-2">
                <AlertCircle className="h-5 w-5 text-amber-600 shrink-0 mt-0.5" />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-bold text-amber-950 text-sm">
                      Atenção: Marcadores não resolvidos no modelo
                    </span>
                    <Badge
                      variant="outline"
                      className="border-amber-400 bg-amber-100 text-amber-800 text-[10px]"
                    >
                      Baixado com [PREENCHER: ...]
                    </Badge>
                  </div>
                  <p className="text-[11px] text-amber-800 mt-0.5">
                    Os documentos foram gerados e baixados com sucesso! Porém, os marcadores abaixo
                    não tinham dados correspondentes no sistema e foram preenchidos como{' '}
                    <strong>[PREENCHER: nome_do_marcador]</strong> no arquivo .docx para não
                    passarem despercebidos.
                  </p>
                </div>
              </div>

              <div className="space-y-1.5 pt-1 border-t border-amber-200">
                {unresolvedWarnings.map((item, idx) => (
                  <div
                    key={idx}
                    className="bg-white/80 p-2 rounded border border-amber-200 text-[11px]"
                  >
                    <div className="font-semibold text-slate-800 mb-1 flex items-center gap-1.5">
                      <FileText className="h-3.5 w-3.5 text-amber-600" />
                      <span>{item.templateName}:</span>
                    </div>
                    <div className="flex flex-wrap gap-1">
                      {item.placeholders.map((tag, tIdx) => (
                        <code
                          key={tIdx}
                          className="font-mono text-[10px] font-bold bg-amber-100/90 text-amber-900 px-1.5 py-0.5 rounded border border-amber-300"
                        >
                          {'{{' + tag + '}}'}
                        </code>
                      ))}
                    </div>
                  </div>
                ))}
              </div>

              <div className="flex items-center justify-between pt-1 text-[11px] text-amber-800">
                <span>
                  💡 Dica: Verifique a lista de <strong>Marcadores Disponíveis</strong> acima para
                  usar a grafia correta ou adicionar os dados no cadastro.
                </span>
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={() => setUnresolvedWarnings([])}
                  className="h-6 text-[11px] text-amber-900 hover:bg-amber-100/80 px-2"
                >
                  Dispensar aviso
                </Button>
              </div>
            </div>
          )}
          {/* Dados Vinculados (Cliente e Processo) */}
          <div className="p-3 bg-slate-50 border rounded-lg text-xs space-y-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div>
                <span className="text-slate-500 font-semibold block text-[11px]">CLIENTE:</span>
                <span className="font-bold text-slate-800 text-sm">
                  {currentClient?.name || 'Nenhum cliente selecionado'}
                </span>
                {currentClient?.document && (
                  <span className="text-muted-foreground ml-2 font-mono">
                    ({currentClient.document})
                  </span>
                )}
              </div>

              {/* Se estiver no cliente e houver mais de um processo, permite escolher */}
              {!directCase && clientCases.length > 0 && (
                <div className="w-full sm:w-60">
                  <Label className="text-[10px] text-slate-500 font-semibold block mb-0.5">
                    VINCULAR AO PROCESSO:
                  </Label>
                  <Select value={selectedCaseId} onValueChange={setSelectedCaseId}>
                    <SelectTrigger className="h-7 text-xs bg-white">
                      <SelectValue placeholder="Selecione o processo..." />
                    </SelectTrigger>
                    <SelectContent>
                      {clientCases.map((c: any) => (
                        <SelectItem key={c.id} value={c.id} className="text-xs">
                          {c.number || c.process_name || 'Processo sem número'} ({c.type || 'Geral'}
                          )
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              )}
            </div>

            {currentCase && (
              <div className="pt-2 border-t border-slate-200/80 grid grid-cols-2 sm:grid-cols-3 gap-2 text-[11px]">
                <div>
                  <span className="text-slate-500">Número: </span>
                  <span className="font-mono font-medium text-slate-800">
                    {currentCase.number || 'A distribuir'}
                  </span>
                </div>
                <div>
                  <span className="text-slate-500">Ação: </span>
                  <span className="font-medium text-slate-800">
                    {currentCase.process_name || currentCase.type || '—'}
                  </span>
                </div>
                <div>
                  <span className="text-slate-500">Vara / Comarca: </span>
                  <span className="font-medium text-slate-800">
                    {currentCase.court ? `${currentCase.court}` : ''}
                    {currentCase.comarca ? ` / ${currentCase.comarca}` : ''}
                    {!currentCase.court && !currentCase.comarca ? '—' : ''}
                  </span>
                </div>
              </div>
            )}
          </div>

          {/* 1. Seleção de Modelos (Geração em lote) */}
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <Label className="text-xs font-bold text-slate-800 flex items-center gap-1.5">
                <FileText className="h-3.5 w-3.5 text-primary" />
                1. Selecione os Modelos para Gerar em Lote
              </Label>
              {allTemplates.length > 0 && (
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={selectAllTemplates}
                  className="h-6 text-[11px] text-primary hover:bg-primary/10"
                >
                  {selectedTemplateIds.length === allTemplates.length
                    ? 'Desmarcar todos'
                    : 'Marcar todos'}
                </Button>
              )}
            </div>

            {loadingTemplates ? (
              <div className="p-6 text-center text-xs text-muted-foreground flex items-center justify-center gap-2">
                <Loader2 className="h-4 w-4 animate-spin text-primary" />
                Carregando modelos disponíveis...
              </div>
            ) : allTemplates.length === 0 ? (
              <div className="p-4 border border-dashed rounded-md bg-amber-50/50 text-amber-800 text-xs text-center space-y-1">
                <AlertCircle className="h-4 w-4 mx-auto text-amber-600" />
                <p className="font-semibold">Nenhum modelo .docx cadastrado.</p>
                <p className="text-[11px] text-amber-700">
                  Acesse <strong>Configurações → Modelos de Documentos</strong> para cadastrar seus
                  modelos.
                </p>
              </div>
            ) : (
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 max-h-48 overflow-y-auto p-1 border rounded-md bg-white">
                {allTemplates.map((tpl) => {
                  const isChecked = selectedTemplateIds.includes(tpl.id)
                  const manualCount = tpl.manual_fields?.length || 0

                  return (
                    <div
                      key={tpl.id}
                      onClick={() => toggleTemplateSelection(tpl.id)}
                      className={`flex items-start gap-2.5 p-2 rounded-md border text-xs cursor-pointer transition-all ${
                        isChecked
                          ? 'border-primary bg-primary/5 shadow-xs'
                          : 'border-slate-200 hover:border-slate-300'
                      }`}
                    >
                      <Checkbox
                        checked={isChecked}
                        onCheckedChange={() => toggleTemplateSelection(tpl.id)}
                        className="mt-0.5"
                      />
                      <div className="space-y-0.5 flex-1 min-w-0">
                        <div className="flex items-center justify-between gap-1">
                          <span className="font-semibold text-slate-800 truncate" title={tpl.name}>
                            {tpl.name}
                          </span>
                        </div>
                        <div className="flex items-center gap-1.5 flex-wrap">
                          <Badge variant="outline" className="text-[10px] py-0 px-1 bg-slate-50">
                            {tpl.category || 'Geral'}
                          </Badge>
                          {manualCount > 0 ? (
                            <span className="text-[10px] text-blue-600 font-medium">
                              {manualCount} campo(s) manual(is)
                            </span>
                          ) : (
                            <span className="text-[10px] text-emerald-600 font-medium">
                              100% automático
                            </span>
                          )}
                        </div>
                      </div>
                    </div>
                  )
                })}
              </div>
            )}
          </div>

          {/* 2. Campos Manuais Coletados (apenas se os modelos selecionados exigirem) */}
          {selectedTemplates.length > 0 && requiredManualFields.length > 0 && (
            <div className="space-y-2 pt-1">
              <div className="flex items-center justify-between">
                <Label className="text-xs font-bold text-slate-800 flex items-center gap-1.5">
                  <Sparkles className="h-3.5 w-3.5 text-primary" />
                  2. Campos Manuais Desta Geração
                </Label>
                <span className="text-[10px] text-muted-foreground">
                  Preenchidos uma vez para todos os modelos selecionados
                </span>
              </div>

              <div className="p-3 bg-blue-50/50 border border-blue-100 rounded-md grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs">
                {requiredManualFields.map((field) => (
                  <div key={field.key} className="space-y-1">
                    <Label className="text-xs font-medium text-slate-700 flex items-center justify-between">
                      <span>{field.label || field.key}</span>
                      <code className="text-[10px] font-mono text-muted-foreground">
                        {'{{' + field.key + '}}'}
                      </code>
                    </Label>
                    <Input
                      value={manualValues[field.key] ?? ''}
                      onChange={(e) => handleManualValueChange(field.key, e.target.value)}
                      placeholder={
                        field.type === 'currency'
                          ? 'Ex: R$ 5.000,00'
                          : field.type === 'percentage'
                            ? 'Ex: 30%'
                            : 'Digite o valor...'
                      }
                      className="h-8 text-xs bg-white"
                    />
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* 3. Opção de Anexar ao Processo */}
          {currentCase && (
            <div className="pt-1">
              <label className="flex items-center gap-2 text-xs font-medium text-slate-700 cursor-pointer p-2 bg-slate-50 border rounded-md hover:bg-slate-100/60 transition-colors">
                <Checkbox
                  checked={attachToCase}
                  onCheckedChange={(checked) => setAttachToCase(Boolean(checked))}
                />
                <Paperclip className="h-3.5 w-3.5 text-primary" />
                <span>
                  Vincular e anexar automaticamente os documentos gerados à ficha deste processo
                </span>
              </label>
            </div>
          )}
        </div>

        <DialogFooter className="pt-3 border-t flex flex-col sm:flex-row items-center justify-between gap-2">
          <div className="text-xs text-muted-foreground">
            {selectedTemplates.length > 0 ? (
              <span className="font-semibold text-slate-800">
                {selectedTemplates.length} modelo(s) pronto(s) para gerar
              </span>
            ) : (
              <span>Nenhum modelo selecionado</span>
            )}
          </div>

          <div className="flex gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => onOpenChange(false)}
              disabled={isGenerating}
            >
              Cancelar
            </Button>
            <Button
              size="sm"
              onClick={handleGenerate}
              disabled={isGenerating || selectedTemplates.length === 0}
              className="gap-2 bg-blue-600 hover:bg-blue-700 text-white font-medium"
            >
              {isGenerating ? (
                <>
                  <Loader2 className="h-4 w-4 animate-spin" />
                  {generationProgress || 'Gerando .docx...'}
                </>
              ) : (
                <>
                  <DownloadCloud className="h-4 w-4" />
                  {selectedTemplates.length > 1
                    ? `Gerar ${selectedTemplates.length} Documentos`
                    : 'Gerar Documento .docx'}
                </>
              )}
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
