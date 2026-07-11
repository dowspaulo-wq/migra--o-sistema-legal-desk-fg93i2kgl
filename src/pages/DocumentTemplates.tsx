import { useState, useEffect } from 'react'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Badge } from '@/components/ui/badge'
import { Upload, Trash2, FileText } from 'lucide-react'
import { toast } from '@/hooks/use-toast'
import {
  fetchDocumentTemplates,
  uploadDocumentTemplate,
  deleteDocumentTemplate,
} from '@/services/document-templates'

export default function DocumentTemplates() {
  const [templates, setTemplates] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [uploading, setUploading] = useState(false)
  const [category, setCategory] = useState('')
  const [selectedFile, setSelectedFile] = useState<File | null>(null)

  const load = async () => {
    setLoading(true)
    const { data } = await fetchDocumentTemplates()
    setTemplates(data || [])
    setLoading(false)
  }

  useEffect(() => {
    load()
  }, [])

  const handleUpload = async () => {
    if (!selectedFile) {
      toast({ title: 'Atenção', description: 'Selecione um arquivo.', variant: 'destructive' })
      return
    }
    setUploading(true)
    const { error } = await uploadDocumentTemplate(selectedFile, category || 'Geral')
    setUploading(false)
    if (error) {
      toast({ title: 'Erro', description: error.message, variant: 'destructive' })
    } else {
      toast({ title: 'Sucesso', description: 'Template enviado com sucesso.' })
      setSelectedFile(null)
      setCategory('')
      load()
    }
  }

  const handleDelete = async (id: string, filePath: string) => {
    const { error } = await deleteDocumentTemplate(id, filePath)
    if (error) {
      toast({ title: 'Erro', description: 'Falha ao excluir.', variant: 'destructive' })
    } else {
      toast({ title: 'Sucesso', description: 'Template excluído.' })
      load()
    }
  }

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    const ext = file.name.split('.').pop()?.toLowerCase()
    if (ext !== 'docx') {
      toast({
        title: 'Erro',
        description: 'Formato não suportado. Utilize apenas arquivos .docx',
        variant: 'destructive',
      })
      e.target.value = ''
      return
    }
    setSelectedFile(file)
  }

  return (
    <div className="space-y-6 max-w-5xl">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Modelos de Documentos</h1>
        <p className="text-muted-foreground">Gerencie templates .docx para geração automática.</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-lg flex items-center gap-2">
            <Upload className="h-5 w-5" /> Enviar Novo Template
          </CardTitle>
          <CardDescription>Apenas arquivos .docx são aceitos.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex flex-col sm:flex-row gap-4">
            <div className="flex-1 space-y-1.5">
              <Label>Arquivo .docx</Label>
              <Input type="file" accept=".docx" onChange={handleFileChange} />
            </div>
            <div className="sm:w-64 space-y-1.5">
              <Label>Categoria</Label>
              <Input
                placeholder="Ex: Procuração, Contrato..."
                value={category}
                onChange={(e) => setCategory(e.target.value)}
              />
            </div>
          </div>
          <Button onClick={handleUpload} disabled={uploading || !selectedFile}>
            {uploading ? 'Enviando...' : 'Enviar Template'}
          </Button>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-lg flex items-center gap-2">
            <FileText className="h-5 w-5" /> Templates Cadastrados
          </CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <p className="text-sm text-muted-foreground text-center py-6">Carregando...</p>
          ) : templates.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-6 bg-muted/20 border border-dashed rounded">
              Nenhum template cadastrado.
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Nome</TableHead>
                  <TableHead>Categoria</TableHead>
                  <TableHead>Criado em</TableHead>
                  <TableHead className="text-right">Ações</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {templates.map((t) => (
                  <TableRow key={t.id}>
                    <TableCell className="font-medium">{t.name}</TableCell>
                    <TableCell>
                      <Badge variant="outline">{t.category}</Badge>
                    </TableCell>
                    <TableCell>{new Date(t.created_at).toLocaleDateString('pt-BR')}</TableCell>
                    <TableCell className="text-right">
                      <Button
                        variant="ghost"
                        size="icon"
                        className="text-red-500 hover:bg-red-50"
                        onClick={() => handleDelete(t.id, t.file_path)}
                      >
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
