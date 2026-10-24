import { useState, useEffect } from 'react'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
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
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Badge } from '@/components/ui/badge'
import {
  Upload,
  Trash2,
  FileText,
  Edit,
  Plus,
  SlidersHorizontal,
  FileCheck2,
  DownloadCloud,
  Layers,
  Sparkles,
} from 'lucide-react'
import { toast } from '@/hooks/use-toast'
import {
  DocumentTemplate,
  ManualFieldDefinition,
  fetchDocumentTemplates,
  uploadDocumentTemplate,
  updateDocumentTemplate,
  deleteDocumentTemplate,
  downloadTemplateBuffer,
  triggerFileDownload,
} from '@/services/document-templates'
import { PlaceholdersHelpDialog } from '@/components/PlaceholdersHelpDialog'

export function DocumentTemplatesTab() {
  const [templates, setTemplates] = useState<DocumentTemplate[]>([])
  const [loading, setLoading] = useState(true)
  const [uploading, setUploading] = useState(false)
  const [category, setCategory] = useState('')
  const [description, setDescription] = useState('')
  const [selectedFile, setSelectedFile] = useState<File | null>(null)

  // Estado para campos manuais no upload de novo modelo
  const [newManualFields, setNewManualFields] = useState<ManualFieldDefinition[]>([])

  // Estado para edição de modelo existente
  const [editingTemplate, setEditingTemplate] = useState<DocumentTemplate | null>(null)
  const [editName, setEditName] = useState('')
  const [editCategory, setEditCategory] = useState('')
  const [editDescription, setEditDescription] = useState('')
  const [editManualFields, setEditManualFields] = useState<ManualFieldDefinition[]>([])
  const [savingEdit, setSavingEdit] = useState(false)

  const loadTemplates = async () => {
    setLoading(true)
    const { data, error } = await fetchDocumentTemplates()
    if (error) {
      toast({
        title: 'Erro ao carregar modelos',
        description: error.message || 'Verifique sua conexão.',
        variant: 'destructive',
      })
    } else {
      setTemplates(data || [])
    }
    setLoading(false)
  }

  useEffect(() => {
    loadTemplates()
  }, [])

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    const ext = file.name.split('.').pop()?.toLowerCase()
    if (ext !== 'docx') {
      toast({
        title: 'Formato inválido',
        description: 'Utilize apenas arquivos .docx.',
        variant: 'destructive',
      })
      e.target.value = ''
      return
    }
    setSelectedFile(file)
  }

  const addManualFieldToNew = () => {
    setNewManualFields((prev) => [
      ...prev,
      {
        key: `campo_${prev.length + 1}`,
        label: `Campo ${prev.length + 1}`,
        type: 'text',
      },
    ])
  }

  const removeManualFieldFromNew = (index: number) => {
    setNewManualFields((prev) => prev.filter((_, idx) => idx !== index))
  }

  const updateNewManualField = (index: number, key: keyof ManualFieldDefinition, value: any) => {
    setNewManualFields((prev) => prev.map((f, idx) => (idx === index ? { ...f, [key]: value } : f)))
  }

  const handleUpload = async () => {
    if (!selectedFile) {
      toast({
        title: 'Atenção',
        description: 'Selecione um arquivo .docx.',
        variant: 'destructive',
      })
      return
    }

    setUploading(true)
    const { error } = await uploadDocumentTemplate(
      selectedFile,
      category || 'Geral',
      newManualFields,
      description,
    )
    setUploading(false)

    if (error) {
      toast({
        title: 'Erro ao enviar modelo',
        description: error.message || 'Falha ao salvar no storage.',
        variant: 'destructive',
      })
    } else {
      toast({
        title: 'Modelo cadastrado com sucesso!',
        description: `O modelo "${selectedFile.name}" já está pronto para uso.`,
      })
      setSelectedFile(null)
      setCategory('')
      setDescription('')
      setNewManualFields([])
      loadTemplates()
    }
  }

  const openEditDialog = (t: DocumentTemplate) => {
    setEditingTemplate(t)
    setEditName(t.name)
    setEditCategory(t.category || 'Geral')
    setEditDescription(t.description || '')
    setEditManualFields(t.manual_fields || [])
  }

  const handleSaveEdit = async () => {
    if (!editingTemplate) return
    setSavingEdit(true)
    const { error } = await updateDocumentTemplate(editingTemplate.id, {
      name: editName,
      category: editCategory,
      description: editDescription,
      manual_fields: editManualFields,
    })
    setSavingEdit(false)

    if (error) {
      toast({
        title: 'Erro ao atualizar',
        description: error.message,
        variant: 'destructive',
      })
    } else {
      toast({ title: 'Modelo atualizado com sucesso!' })
      setEditingTemplate(null)
      loadTemplates()
    }
  }

  const handleDelete = async (t: DocumentTemplate) => {
    if (!confirm(`Deseja realmente excluir o modelo "${t.name}"?`)) return
    const { error } = await deleteDocumentTemplate(t.id, t.file_path)
    if (error) {
      toast({ title: 'Erro ao excluir', description: error.message, variant: 'destructive' })
    } else {
      toast({ title: 'Modelo excluído com sucesso.' })
      loadTemplates()
    }
  }

  const handleDownloadOriginal = async (t: DocumentTemplate) => {
    try {
      toast({ title: 'Baixando modelo original...', description: 'Aguarde um instante.' })
      const buffer = await downloadTemplateBuffer(t.file_path)
      const blob = new Blob([buffer], {
        type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      })
      triggerFileDownload(blob, `${t.name}.docx`)
    } catch (err: any) {
      toast({
        title: 'Erro no download',
        description: err.message || 'Não foi possível baixar o modelo.',
        variant: 'destructive',
      })
    }
  }

  // Predefinições rápidas de campos manuais comuns para o advogado adicionar com 1 clique
  const addPresetField = (type: 'honorarios' | 'pagamento' | 'exito' | 'acao') => {
    const presets: Record<string, ManualFieldDefinition> = {
      honorarios: { key: 'valorHonorarios', label: 'Valor dos Honorários (R$)', type: 'currency' },
      pagamento: { key: 'formaPagamento', label: 'Forma de Pagamento (Texto)', type: 'text' },
      exito: { key: 'percentualExito', label: 'Percentual de Êxito (%)', type: 'percentage' },
      acao: { key: 'nomeAcao', label: 'Nome Específico da Ação', type: 'text' },
    }
    const preset = presets[type]
    if (preset) {
      if (editingTemplate) {
        if (!editManualFields.some((f) => f.key === preset.key)) {
          setEditManualFields((prev) => [...prev, preset])
        }
      } else {
        if (!newManualFields.some((f) => f.key === preset.key)) {
          setNewManualFields((prev) => [...prev, preset])
        }
      }
    }
  }

  return (
    <div className="space-y-6">
      {/* Top Banner & Ações */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 p-4 bg-gradient-to-r from-blue-50/80 via-indigo-50/40 to-slate-50 border border-blue-100 rounded-lg">
        <div>
          <h2 className="text-xl font-bold text-slate-800 flex items-center gap-2">
            <Layers className="h-5 w-5 text-primary" />
            Modelos de Documentos (.docx)
          </h2>
          <p className="text-xs text-muted-foreground mt-0.5">
            Cadastre contratos, procurações e termos formatados no seu Word. A formatação original
            do seu arquivo é 100% preservada.
          </p>
        </div>
        <PlaceholdersHelpDialog />
      </div>

      {/* Card de Upload de Novo Modelo */}
      <Card className="shadow-xs border-slate-200">
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2 text-slate-800">
            <Upload className="h-4 w-4 text-primary" />
            Cadastrar Novo Modelo .docx
          </CardTitle>
          <CardDescription className="text-xs">
            Suba um modelo pré-formatado pelo seu escritório com logotipo, cabeçalho e marcadores
            entre chaves duplas (ex: {'{{cliente.nome}}'}).
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4 text-xs">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div className="space-y-1.5 md:col-span-2">
              <Label className="text-xs font-semibold">Arquivo do Modelo (.docx)</Label>
              <Input
                type="file"
                accept=".docx"
                onChange={handleFileChange}
                className="text-xs h-9"
              />
              {selectedFile && (
                <p className="text-[11px] text-emerald-700 font-medium">
                  ✓ Selecionado: {selectedFile.name} ({(selectedFile.size / 1024).toFixed(0)} KB)
                </p>
              )}
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold">Categoria</Label>
              <Input
                placeholder="Ex: Contratos, Procurações, Notificações..."
                value={category}
                onChange={(e) => setCategory(e.target.value)}
                className="text-xs h-9"
              />
            </div>
          </div>

          <div className="space-y-1.5">
            <Label className="text-xs font-semibold">Descrição / Observações (opcional)</Label>
            <Input
              placeholder="Ex: Contrato padrão para ações indenizatórias contra bancos com cláusula de êxito."
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              className="text-xs h-9"
            />
          </div>

          {/* Configuração de Campos Manuais do Modelo */}
          <div className="p-3.5 bg-slate-50 border border-slate-200/70 rounded-lg space-y-3">
            <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-2">
              <div>
                <Label className="text-xs font-bold text-slate-800 flex items-center gap-1.5">
                  <SlidersHorizontal className="h-3.5 w-3.5 text-primary" />
                  Campos Manuais Deste Modelo
                </Label>
                <p className="text-[11px] text-muted-foreground">
                  Campos que você precisa digitar a cada geração (ex: valor dos honorários, forma de
                  pagamento, % de êxito).
                </p>
              </div>

              <div className="flex items-center gap-1.5 flex-wrap">
                <span className="text-[10px] text-slate-500 font-medium">Atalhos rápidos:</span>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => addPresetField('honorarios')}
                  className="h-6 text-[10px] px-2 bg-white"
                >
                  + Honorários (R$)
                </Button>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => addPresetField('pagamento')}
                  className="h-6 text-[10px] px-2 bg-white"
                >
                  + Forma de Pagamento
                </Button>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => addPresetField('exito')}
                  className="h-6 text-[10px] px-2 bg-white"
                >
                  + % Êxito
                </Button>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => addPresetField('acao')}
                  className="h-6 text-[10px] px-2 bg-white"
                >
                  + Nome da Ação
                </Button>
              </div>
            </div>

            {newManualFields.length > 0 && (
              <div className="space-y-2 pt-1">
                {newManualFields.map((field, idx) => (
                  <div
                    key={idx}
                    className="flex flex-col sm:flex-row items-center gap-2 bg-white p-2 border rounded-md"
                  >
                    <div className="w-full sm:w-1/3">
                      <Label className="text-[10px] text-slate-500 block mb-0.5">
                        Marcador no .docx (chave)
                      </Label>
                      <div className="flex items-center font-mono text-xs">
                        <span className="text-slate-400">{'{{'}</span>
                        <Input
                          value={field.key}
                          onChange={(e) =>
                            updateNewManualField(
                              idx,
                              'key',
                              e.target.value.replace(/[^a-zA-Z0-9_.]/g, ''),
                            )
                          }
                          placeholder="chaveDoCampo"
                          className="h-7 text-xs font-mono px-1.5 border-0 focus-visible:ring-0 focus-visible:bg-slate-50"
                        />
                        <span className="text-slate-400">{'}}'}</span>
                      </div>
                    </div>

                    <div className="w-full sm:w-1/3">
                      <Label className="text-[10px] text-slate-500 block mb-0.5">
                        Rótulo exibido na geração
                      </Label>
                      <Input
                        value={field.label}
                        onChange={(e) => updateNewManualField(idx, 'label', e.target.value)}
                        placeholder="Ex: Valor dos Honorários"
                        className="h-7 text-xs"
                      />
                    </div>

                    <div className="w-full sm:w-1/4">
                      <Label className="text-[10px] text-slate-500 block mb-0.5">
                        Tipo do Campo
                      </Label>
                      <Select
                        value={field.type}
                        onValueChange={(val: any) => updateNewManualField(idx, 'type', val)}
                      >
                        <SelectTrigger className="h-7 text-xs bg-white">
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="text">Texto livre</SelectItem>
                          <SelectItem value="currency">Valor em R$ (moeda)</SelectItem>
                          <SelectItem value="percentage">Percentual (%)</SelectItem>
                          <SelectItem value="date">Data</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>

                    <Button
                      type="button"
                      variant="ghost"
                      size="icon"
                      onClick={() => removeManualFieldFromNew(idx)}
                      className="h-7 w-7 text-red-500 hover:text-red-700 hover:bg-red-50 shrink-0 self-end sm:self-center"
                      title="Remover campo"
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </Button>
                  </div>
                ))}
              </div>
            )}

            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={addManualFieldToNew}
              className="text-xs h-7 gap-1"
            >
              <Plus className="h-3 w-3" />
              Adicionar Campo Manual Customizado
            </Button>
          </div>

          <div className="flex justify-end pt-2">
            <Button onClick={handleUpload} disabled={uploading || !selectedFile} className="gap-2">
              <Upload className="h-4 w-4" />
              {uploading ? 'Salvando Modelo...' : 'Salvar Modelo .docx'}
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Lista de Modelos Cadastrados */}
      <Card className="shadow-xs border-slate-200">
        <CardHeader className="pb-3 flex flex-row items-center justify-between">
          <div>
            <CardTitle className="text-base flex items-center gap-2 text-slate-800">
              <FileCheck2 className="h-4 w-4 text-primary" />
              Modelos Prontos Cadastrados ({templates.length})
            </CardTitle>
            <CardDescription className="text-xs">
              Modelos disponíveis para geração direta a partir da ficha do cliente ou processo.
            </CardDescription>
          </div>
          <Button variant="ghost" size="sm" onClick={loadTemplates} className="text-xs">
            Atualizar lista
          </Button>
        </CardHeader>
        <CardContent>
          {loading ? (
            <p className="text-xs text-muted-foreground text-center py-8">Carregando modelos...</p>
          ) : templates.length === 0 ? (
            <div className="py-10 text-center border border-dashed rounded-lg bg-slate-50/50 space-y-2">
              <FileText className="h-8 w-8 text-slate-300 mx-auto" />
              <p className="text-xs font-medium text-slate-600">
                Nenhum modelo .docx cadastrado ainda.
              </p>
              <p className="text-[11px] text-muted-foreground">
                Faça o upload do seu primeiro contrato ou procuração no formulário acima.
              </p>
            </div>
          ) : (
            <div className="rounded-md border overflow-hidden">
              <Table>
                <TableHeader className="bg-slate-50">
                  <TableRow>
                    <TableHead className="text-xs font-semibold">Nome do Modelo</TableHead>
                    <TableHead className="text-xs font-semibold">Categoria</TableHead>
                    <TableHead className="text-xs font-semibold">Campos Manuais</TableHead>
                    <TableHead className="text-xs font-semibold">Data</TableHead>
                    <TableHead className="text-xs font-semibold text-right">Ações</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {templates.map((tpl) => (
                    <TableRow key={tpl.id} className="hover:bg-slate-50/80">
                      <TableCell className="font-medium text-xs">
                        <div className="space-y-0.5">
                          <span className="font-semibold text-slate-800 flex items-center gap-1.5">
                            <FileText className="h-3.5 w-3.5 text-blue-600 shrink-0" />
                            {tpl.name}
                          </span>
                          {tpl.description && (
                            <p className="text-[11px] text-muted-foreground line-clamp-1">
                              {tpl.description}
                            </p>
                          )}
                        </div>
                      </TableCell>
                      <TableCell>
                        <Badge variant="outline" className="text-[11px] bg-slate-50 font-normal">
                          {tpl.category || 'Geral'}
                        </Badge>
                      </TableCell>
                      <TableCell>
                        {tpl.manual_fields && tpl.manual_fields.length > 0 ? (
                          <div className="flex flex-wrap gap-1 max-w-xs">
                            {tpl.manual_fields.map((f, i) => (
                              <Badge
                                key={i}
                                variant="secondary"
                                className="text-[10px] font-mono bg-blue-50 text-blue-700 border-blue-200"
                              >
                                {f.label || f.key}
                              </Badge>
                            ))}
                          </div>
                        ) : (
                          <span className="text-[11px] text-muted-foreground italic">
                            100% automático
                          </span>
                        )}
                      </TableCell>
                      <TableCell className="text-xs text-muted-foreground">
                        {new Date(tpl.created_at).toLocaleDateString('pt-BR')}
                      </TableCell>
                      <TableCell className="text-right">
                        <div className="flex items-center justify-end gap-1">
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-7 w-7 text-slate-500 hover:text-slate-800"
                            onClick={() => handleDownloadOriginal(tpl)}
                            title="Baixar arquivo .docx do modelo"
                          >
                            <DownloadCloud className="h-3.5 w-3.5" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-7 w-7 text-slate-500 hover:text-slate-800"
                            onClick={() => openEditDialog(tpl)}
                            title="Editar metadados e campos manuais"
                          >
                            <Edit className="h-3.5 w-3.5" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-7 w-7 text-red-500 hover:bg-red-50"
                            onClick={() => handleDelete(tpl)}
                            title="Excluir modelo"
                          >
                            <Trash2 className="h-3.5 w-3.5" />
                          </Button>
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Modal de Edição de Modelo Existente */}
      {editingTemplate && (
        <Dialog open={!!editingTemplate} onOpenChange={(v) => !v && setEditingTemplate(null)}>
          <DialogContent className="max-w-2xl max-h-[85vh] flex flex-col p-6">
            <DialogHeader className="pb-2 border-b">
              <DialogTitle className="text-lg flex items-center gap-2">
                <Edit className="h-4 w-4 text-primary" />
                Editar Modelo: {editingTemplate.name}
              </DialogTitle>
              <DialogDescription className="text-xs">
                Ajuste o nome, categoria e a lista de campos manuais coletados a cada geração.
              </DialogDescription>
            </DialogHeader>

            <div className="space-y-4 pt-3 overflow-y-auto pr-1">
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div className="space-y-1">
                  <Label className="text-xs font-semibold">Nome de Exibição</Label>
                  <Input
                    value={editName}
                    onChange={(e) => setEditName(e.target.value)}
                    className="text-xs h-8"
                  />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs font-semibold">Categoria</Label>
                  <Input
                    value={editCategory}
                    onChange={(e) => setEditCategory(e.target.value)}
                    className="text-xs h-8"
                  />
                </div>
              </div>

              <div className="space-y-1">
                <Label className="text-xs font-semibold">Descrição</Label>
                <Textarea
                  value={editDescription}
                  onChange={(e) => setEditDescription(e.target.value)}
                  rows={2}
                  className="text-xs"
                />
              </div>

              <div className="p-3 bg-slate-50 border rounded-lg space-y-2.5">
                <div className="flex justify-between items-center">
                  <Label className="text-xs font-bold text-slate-800">
                    Campos Manuais Definidos por Este Modelo
                  </Label>
                  <div className="flex gap-1">
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      onClick={() => addPresetField('honorarios')}
                      className="h-6 text-[10px] px-1.5"
                    >
                      + Honorários
                    </Button>
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      onClick={() => addPresetField('pagamento')}
                      className="h-6 text-[10px] px-1.5"
                    >
                      + Pagamento
                    </Button>
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      onClick={() => addPresetField('exito')}
                      className="h-6 text-[10px] px-1.5"
                    >
                      + % Êxito
                    </Button>
                  </div>
                </div>

                {editManualFields.map((field, idx) => (
                  <div
                    key={idx}
                    className="flex flex-col sm:flex-row items-center gap-2 bg-white p-2 border rounded-md"
                  >
                    <div className="w-full sm:w-1/3">
                      <Label className="text-[10px] text-slate-500 block mb-0.5">Marcador</Label>
                      <Input
                        value={field.key}
                        onChange={(e) =>
                          setEditManualFields((prev) =>
                            prev.map((f, i) =>
                              i === idx
                                ? { ...f, key: e.target.value.replace(/[^a-zA-Z0-9_.]/g, '') }
                                : f,
                            ),
                          )
                        }
                        className="h-7 text-xs font-mono"
                      />
                    </div>
                    <div className="w-full sm:w-1/3">
                      <Label className="text-[10px] text-slate-500 block mb-0.5">Rótulo</Label>
                      <Input
                        value={field.label}
                        onChange={(e) =>
                          setEditManualFields((prev) =>
                            prev.map((f, i) => (i === idx ? { ...f, label: e.target.value } : f)),
                          )
                        }
                        className="h-7 text-xs"
                      />
                    </div>
                    <div className="w-full sm:w-1/4">
                      <Label className="text-[10px] text-slate-500 block mb-0.5">Tipo</Label>
                      <Select
                        value={field.type}
                        onValueChange={(val: any) =>
                          setEditManualFields((prev) =>
                            prev.map((f, i) => (i === idx ? { ...f, type: val } : f)),
                          )
                        }
                      >
                        <SelectTrigger className="h-7 text-xs">
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="text">Texto livre</SelectItem>
                          <SelectItem value="currency">Valor R$</SelectItem>
                          <SelectItem value="percentage">Percentual (%)</SelectItem>
                          <SelectItem value="date">Data</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                    <Button
                      type="button"
                      variant="ghost"
                      size="icon"
                      onClick={() =>
                        setEditManualFields((prev) => prev.filter((_, i) => i !== idx))
                      }
                      className="h-7 w-7 text-red-500 self-end sm:self-center"
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </Button>
                  </div>
                ))}

                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() =>
                    setEditManualFields((prev) => [
                      ...prev,
                      {
                        key: `campo_${prev.length + 1}`,
                        label: `Campo ${prev.length + 1}`,
                        type: 'text',
                      },
                    ])
                  }
                  className="h-7 text-xs"
                >
                  <Plus className="h-3 w-3 mr-1" />
                  Novo Campo Manual
                </Button>
              </div>
            </div>

            <DialogFooter className="pt-3 border-t">
              <Button variant="outline" size="sm" onClick={() => setEditingTemplate(null)}>
                Cancelar
              </Button>
              <Button size="sm" onClick={handleSaveEdit} disabled={savingEdit}>
                {savingEdit ? 'Salvando...' : 'Salvar Alterações'}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      )}
    </div>
  )
}
