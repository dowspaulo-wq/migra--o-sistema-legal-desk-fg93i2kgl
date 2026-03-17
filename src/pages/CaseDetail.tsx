import { useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { ArrowLeft, Scale, Users, CheckSquare, FileText, Download, Star } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'

export default function CaseDetail() {
  const { id } = useParams<{ id: string }>()
  const { state } = useLegalStore()
  const [selectedTpl, setSelectedTpl] = useState<string>('')

  const c = state.cases.find((x) => x.id === id)
  const client = state.clients.find((cl) => cl.id === c?.clientId)
  const tasks = state.tasks.filter((t) => t.relatedProcessId === id)

  if (!c) return <div className="p-8 text-center">Processo não encontrado.</div>

  const generateDoc = () => {
    if (!selectedTpl)
      return toast({
        title: 'Atenção',
        description: 'Selecione um modelo de petição primeiro.',
        variant: 'destructive',
      })
    const tpl = state.petitions.find((p) => p.id === selectedTpl)
    if (!tpl) return

    let html = tpl.content
      .replace(/{{client_name}}/g, client?.name || '')
      .replace(/{{client_document}}/g, client?.document || '')
      .replace(/{{process_number}}/g, c?.number || '')
      .replace(/{{adverse_party}}/g, c?.adverseParty || '')
      .replace(/{{court}}/g, c?.court || '')
      .replace(/{{comarca}}/g, c?.comarca || '')

    const docContent = `<html xmlns:o='urn:schemas-microsoft-com:office:office' xmlns:w='urn:schemas-microsoft-com:office:word' xmlns='http://www.w3.org/TR/REC-html40'><head><meta charset='utf-8'><title>${tpl.title}</title></head><body>${html}</body></html>`
    const blob = new Blob(['\ufeff', docContent], { type: 'application/msword' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `${tpl.title.replace(/\s+/g, '_')}_${c.number}.doc`
    a.click()
    URL.revokeObjectURL(url)
    toast({ title: 'Sucesso', description: 'Documento gerado e baixado.' })
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-4">
        <Button variant="outline" size="icon" asChild>
          <Link to="/processos">
            <ArrowLeft className="h-4 w-4" />
          </Link>
        </Button>
        <div>
          <h1 className="text-2xl md:text-3xl font-bold tracking-tight text-primary flex items-center gap-3">
            {c.number}
            {c.isSpecial && (
              <Star className="h-6 w-6 fill-yellow-400 text-yellow-400" title="Especial" />
            )}
            {c.isProblematic && (
              <span className="text-2xl" title="Problemático">
                💩
              </span>
            )}
          </h1>
          <p className="text-muted-foreground mt-1">
            <Badge variant="outline">{c.status}</Badge> • Sistema: {c.system}
          </p>
        </div>
      </div>

      <Tabs defaultValue="info" className="w-full">
        <TabsList className="grid w-full grid-cols-3 max-w-xl">
          <TabsTrigger value="info">Informações</TabsTrigger>
          <TabsTrigger value="tasks">Tarefas</TabsTrigger>
          <TabsTrigger value="docs">Documentos (Automação)</TabsTrigger>
        </TabsList>

        <TabsContent value="info" className="mt-4 grid gap-6 md:grid-cols-2">
          <Card className="shadow-sm">
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <Users className="h-5 w-5" /> Partes
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div>
                <p className="text-sm text-muted-foreground">Cliente ({c.position})</p>
                {client ? (
                  <Link
                    to={`/clientes/${client.id}`}
                    className="font-medium text-primary hover:underline"
                  >
                    {client.name}
                  </Link>
                ) : (
                  <p className="font-medium text-muted-foreground">—</p>
                )}
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Parte Adversa</p>
                <p className="font-medium">{c.adverseParty}</p>
              </div>
            </CardContent>
          </Card>
          <Card className="shadow-sm">
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <Scale className="h-5 w-5" /> Juízo
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div>
                <p className="text-sm text-muted-foreground">Vara</p>
                <p className="font-medium">{c.court}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Comarca / UF</p>
                <p className="font-medium">
                  {c.comarca} - {c.state}
                </p>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="tasks" className="mt-4">
          <Card className="shadow-sm">
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <CheckSquare className="h-5 w-5" /> Tarefas
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-2">
                {tasks.map((t) => (
                  <div
                    key={t.id}
                    className="flex justify-between items-center border p-3 rounded hover:bg-slate-50"
                  >
                    <div>
                      <p className="font-semibold text-sm">{t.title}</p>
                      <p className="text-xs text-muted-foreground">Vencimento: {t.dueDate}</p>
                    </div>
                    <Badge variant="outline">{t.status}</Badge>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="docs" className="mt-4">
          <Card className="shadow-sm border-blue-200 bg-blue-50/30">
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2 text-blue-800">
                <FileText className="h-5 w-5" /> Automação de Petições
              </CardTitle>
              <CardDescription>
                Gere documentos com variáveis preenchidas automaticamente baseadas nos dados deste
                processo.
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4 max-w-md">
              <div className="space-y-2">
                <Label>Selecionar Modelo</Label>
                <Select value={selectedTpl} onValueChange={setSelectedTpl}>
                  <SelectTrigger className="bg-white">
                    <SelectValue placeholder="Escolha um modelo..." />
                  </SelectTrigger>
                  <SelectContent>
                    {state.petitions.map((p) => (
                      <SelectItem key={p.id} value={p.id}>
                        {p.title}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <Button onClick={generateDoc} className="w-full" disabled={!selectedTpl}>
                <Download className="mr-2 h-4 w-4" /> Gerar Documento (.doc)
              </Button>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  )
}
