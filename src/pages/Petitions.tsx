import { useState, useMemo } from 'react'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { FileText, Save, Info, Plus, Trash2, Copy, Check } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { useToast } from '@/hooks/use-toast'

export default function Petitions() {
  const { state, updateItem, deleteItem, addLog, addPetition } = useLegalStore()
  const { toast } = useToast()

  // Tab Modelos
  const [activeId, setActiveId] = useState<string | null>(null)
  const [content, setContent] = useState('')
  const [title, setTitle] = useState('')
  const [category, setCategory] = useState('Geral')

  // Tab Gerador
  const [selectedClientId, setSelectedClientId] = useState<string>('all')
  const [selectedCaseId, setSelectedCaseId] = useState<string>('all')
  const [selectedTemplateId, setSelectedTemplateId] = useState<string>('none')
  const [generatedText, setGeneratedContent] = useState('')
  const [copied, setCopied] = useState(false)

  const loadDoc = (id: string) => {
    const doc = state.petitions.find((p) => p.id === id)
    if (doc) {
      setActiveId(id)
      setContent(doc.content)
      setTitle(doc.title)
      setCategory(doc.category || 'Geral')
    }
  }

  const saveDoc = () => {
    if (!activeId) return
    updateItem('petitions', activeId, { title, content, category })
    addLog('Editar', 'Petição', `Modelo ${title} atualizado`)
    toast({ title: 'Modelo salvo com sucesso' })
  }

  const createDoc = () => {
    addPetition({ title: 'Novo Modelo', content: '', category: 'Geral' })
  }

  const removeDoc = () => {
    if (!activeId) return
    deleteItem('petitions', activeId)
    setActiveId(null)
    setContent('')
    setTitle('')
  }

  const selectedClient = useMemo(
    () => state.clients.find((c) => c.id === selectedClientId),
    [selectedClientId, state.clients],
  )
  const selectedCase = useMemo(
    () => state.cases.find((c) => c.id === selectedCaseId),
    [selectedCaseId, state.cases],
  )

  const sortedClients = useMemo(() => {
    return [...state.clients].sort((a, b) => (a.name || '').localeCompare(b.name || '', 'pt-BR'))
  }, [state.clients])

  const filteredCases = useMemo(() => {
    if (selectedClientId === 'all') return []
    return state.cases
      .filter((c) => c.clientId === selectedClientId)
      .sort((a, b) =>
        (a.number || '').localeCompare(b.number || '', 'pt-BR', {
          numeric: true,
          sensitivity: 'base',
        }),
      )
  }, [selectedClientId, state.cases])

  const sortedPetitions = useMemo(() => {
    return [...state.petitions].sort((a, b) =>
      (a.title || '').localeCompare(b.title || '', 'pt-BR'),
    )
  }, [state.petitions])

  const generateFromTemplate = () => {
    if (selectedTemplateId === 'none') return

    const template = state.petitions.find((p) => p.id === selectedTemplateId)
    if (!template) return

    let t = template.content || ''

    if (selectedClient) {
      t = t.replace(/\{\{client_name\}\}/g, selectedClient.name || '')
      t = t.replace(/\{\{client_document\}\}/g, selectedClient.document || '')
    }
    if (selectedCase) {
      t = t.replace(/\{\{process_number\}\}/g, selectedCase.number || '')
      t = t.replace(/\{\{adverse_party\}\}/g, selectedCase.adverseParty || '')
      t = t.replace(/\{\{court\}\}/g, selectedCase.court || '')
      t = t.replace(/\{\{comarca\}\}/g, selectedCase.comarca || '')
      t = t.replace(/\{\{state\}\}/g, selectedCase.state || '')
    }

    setGeneratedContent(t)
    toast({ title: 'Modelo aplicado com sucesso!' })
  }

  const insertPreamble = () => {
    const header = `EXCELENTÍSSIMO SENHOR DOUTOR JUIZ DE DIREITO DA ${selectedCase?.court || '___ VARA'} DA COMARCA DE ${selectedCase?.comarca || '___'}/${selectedCase?.state || '___'}\n\n`
    const processStr = selectedCase ? `Processo nº: ${selectedCase.number}\n\n` : ''
    const preamble = `${selectedClient?.name || 'NOME DO CLIENTE'}, já qualificado(a) nos autos do processo em epígrafe, que move em face de ${selectedCase?.adverseParty || 'PARTE ADVERSA'}, vem, respeitosamente, à presença de Vossa Excelência, por seu advogado que esta subscreve, requerer/expor:\n\n`

    const dateStr = new Date().toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: 'long',
      year: 'numeric',
    })
    const cityDate = `\n\nTermos em que,\nPede deferimento.\n\nBelo Horizonte, MG, ${dateStr}.`

    setGeneratedContent((prev) => header + processStr + preamble + prev + cityDate)
  }

  const copyToClipboard = () => {
    navigator.clipboard.writeText(generatedText)
    setCopied(true)
    toast({ title: 'Copiado para a área de transferência!' })
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <div className="space-y-6 h-full flex flex-col">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Petições</h1>
        <p className="text-muted-foreground">
          Gerador de petições e gerenciamento de modelos padrão.
        </p>
      </div>

      <Tabs defaultValue="gerador" className="flex-1 flex flex-col min-h-0">
        <TabsList className="w-fit mb-4">
          <TabsTrigger value="gerador">Gerador de Petição</TabsTrigger>
          <TabsTrigger value="modelos">Meus Modelos</TabsTrigger>
        </TabsList>

        <TabsContent value="gerador" className="flex-1 flex flex-col min-h-0 m-0 space-y-4">
          <Card>
            <CardHeader className="py-4">
              <CardTitle className="text-lg">Dados da Petição</CardTitle>
              <CardDescription>
                Selecione o cliente, processo e modelo para gerar o documento automaticamente.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-4">
                <div className="space-y-2">
                  <Label>Cliente</Label>
                  <Select
                    value={selectedClientId}
                    onValueChange={(val) => {
                      setSelectedClientId(val)
                      setSelectedCaseId('all')
                    }}
                  >
                    <SelectTrigger>
                      <SelectValue placeholder="Selecione um cliente" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">Nenhum selecionado</SelectItem>
                      {sortedClients.map((c) => (
                        <SelectItem key={c.id} value={c.id}>
                          {c.name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>

                <div className="space-y-2">
                  <Label>Processo</Label>
                  <Select
                    value={selectedCaseId}
                    onValueChange={setSelectedCaseId}
                    disabled={selectedClientId === 'all' || filteredCases.length === 0}
                  >
                    <SelectTrigger>
                      <SelectValue placeholder="Selecione um processo" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">Nenhum selecionado</SelectItem>
                      {filteredCases.map((c) => (
                        <SelectItem key={c.id} value={c.id}>
                          {c.number} {c.adverseParty ? `- ${c.adverseParty}` : ''}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>

                <div className="space-y-2">
                  <Label>Modelo Padrão</Label>
                  <Select value={selectedTemplateId} onValueChange={setSelectedTemplateId}>
                    <SelectTrigger>
                      <SelectValue placeholder="Escolha um modelo..." />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">Nenhum modelo</SelectItem>
                      {sortedPetitions.map((p) => (
                        <SelectItem key={p.id} value={p.id}>
                          {p.title}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              </div>

              <div className="flex justify-end gap-2">
                <Button variant="secondary" onClick={insertPreamble}>
                  Inserir Cabeçalho/Preâmbulo Padrão
                </Button>
                <Button onClick={generateFromTemplate} disabled={selectedTemplateId === 'none'}>
                  Aplicar Modelo Selecionado
                </Button>
              </div>
            </CardContent>
          </Card>

          <Card className="flex-1 flex flex-col min-h-0">
            <CardHeader className="py-3 border-b flex flex-row items-center justify-between bg-slate-50">
              <CardTitle className="text-sm font-medium text-muted-foreground">
                Editor da Petição
              </CardTitle>
              <Button size="sm" onClick={copyToClipboard} disabled={!generatedText}>
                {copied ? <Check className="h-4 w-4 mr-2" /> : <Copy className="h-4 w-4 mr-2" />}
                {copied ? 'Copiado!' : 'Copiar Texto para o Word'}
              </Button>
            </CardHeader>
            <CardContent className="p-0 flex-1 relative">
              <Textarea
                value={generatedText}
                onChange={(e) => setGeneratedContent(e.target.value)}
                placeholder="O conteúdo da sua petição aparecerá aqui. Você pode editá-lo livremente antes de copiar..."
                className="w-full h-full border-0 resize-none rounded-none p-6 font-serif text-base focus-visible:ring-0 focus-visible:ring-offset-0 leading-relaxed min-h-[400px]"
              />
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="modelos" className="flex-1 flex flex-col md:flex-row gap-6 min-h-0 m-0">
          <Card className="w-full md:w-64 shrink-0 h-fit">
            <CardHeader className="py-4 flex flex-row items-center justify-between">
              <CardTitle className="text-sm">Meus Modelos</CardTitle>
              <Button size="icon" variant="ghost" className="h-8 w-8" onClick={createDoc}>
                <Plus className="h-4 w-4" />
              </Button>
            </CardHeader>
            <CardContent className="p-2 space-y-1">
              {sortedPetitions.map((p) => (
                <Button
                  key={p.id}
                  variant={activeId === p.id ? 'default' : 'ghost'}
                  className="w-full justify-start text-left text-sm truncate"
                  onClick={() => loadDoc(p.id)}
                >
                  <FileText className="h-4 w-4 mr-2 shrink-0" /> {p.title}
                </Button>
              ))}
              {sortedPetitions.length === 0 && (
                <div className="p-4 text-center text-xs text-muted-foreground">
                  Nenhum modelo cadastrado.
                </div>
              )}
            </CardContent>
          </Card>

          <div className="flex-1 flex flex-col gap-4 h-full">
            <Card className="bg-primary/10 border-primary/20 shrink-0">
              <CardContent className="p-4 flex items-start gap-3">
                <Info className="h-5 w-5 text-primary mt-0.5" />
                <div className="text-sm text-primary space-y-1">
                  <p>
                    <strong>Variáveis disponíveis:</strong>
                  </p>
                  <p className="font-mono text-xs">
                    {'{{client_name}}'}, {'{{client_document}}'}, {'{{process_number}}'},{' '}
                    {'{{adverse_party}}'}, {'{{court}}'}, {'{{comarca}}'}, {'{{state}}'}
                  </p>
                </div>
              </CardContent>
            </Card>

            <Card className="flex-1 flex flex-col min-h-0">
              {activeId ? (
                <>
                  <CardHeader className="py-3 border-b flex flex-col sm:flex-row sm:items-center gap-4 bg-slate-50 justify-between">
                    <Input
                      value={title}
                      onChange={(e) => setTitle(e.target.value)}
                      className="font-bold border-none bg-transparent shadow-none focus-visible:ring-0 px-0 h-auto text-lg flex-1"
                      placeholder="Nome do Modelo"
                    />
                    <div className="flex items-center gap-2 self-end sm:self-auto">
                      <Button
                        size="icon"
                        variant="outline"
                        className="text-red-500 hover:text-red-700 hover:bg-red-50"
                        onClick={removeDoc}
                      >
                        <Trash2 className="h-4 w-4" />
                      </Button>
                      <Button size="sm" onClick={saveDoc}>
                        <Save className="h-4 w-4 mr-2" /> Salvar Modelo
                      </Button>
                    </div>
                  </CardHeader>
                  <CardContent className="p-0 flex-1 relative">
                    <Textarea
                      value={content}
                      onChange={(e) => setContent(e.target.value)}
                      placeholder="Digite o conteúdo do seu modelo usando as variáveis acima..."
                      className="w-full h-full border-0 resize-none rounded-none p-6 font-serif text-base focus-visible:ring-0 focus-visible:ring-offset-0 leading-relaxed min-h-[400px]"
                    />
                  </CardContent>
                </>
              ) : (
                <div className="flex-1 flex items-center justify-center text-muted-foreground flex-col gap-4">
                  <FileText className="h-16 w-16 opacity-20" />
                  <p>Selecione ou crie um modelo ao lado para editar.</p>
                </div>
              )}
            </Card>
          </div>
        </TabsContent>
      </Tabs>
    </div>
  )
}
