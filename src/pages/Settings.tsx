import { useState } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Upload, Download, FileJson, FileSpreadsheet } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'

export default function Settings() {
  const { importData } = useLegalStore()
  const [fileName, setFileName] = useState<string | null>(null)

  const handleFileUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    setFileName(file.name)

    const reader = new FileReader()
    reader.onload = (event) => {
      try {
        const text = event.target?.result as string
        if (file.name.endsWith('.json')) {
          const data = JSON.parse(text)
          if (Array.isArray(data)) importData(data)
        } else if (file.name.endsWith('.csv')) {
          const lines = text.split('\n')
          const headers = lines[0].split(',')
          const data = lines
            .slice(1)
            .filter((l) => l.trim())
            .map((line) => {
              const values = line.split(',')
              return headers.reduce((obj, header, index) => {
                obj[header.trim()] = values[index]?.trim() || ''
                return obj
              }, {} as any)
            })
          importData(data)
        }
      } catch (err) {
        toast({
          title: 'Erro na importação',
          description: 'O formato do arquivo é inválido.',
          variant: 'destructive',
        })
      }
    }
    reader.readAsText(file)
    e.target.value = '' // reset input
  }

  const downloadTemplate = () => {
    const csv =
      'name,document,email,phone\nCliente Exemplo,123.456.789-00,exemplo@email.com,11999999999'
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'template_clientes.csv'
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-6 max-w-4xl">
      <div>
        <h1 className="text-3xl font-bold tracking-tight text-slate-800 dark:text-slate-100">
          Configurações & Importação
        </h1>
        <p className="text-muted-foreground mt-1">
          Migre seus dados de outros sistemas facilmente.
        </p>
      </div>

      <Card className="shadow-sm">
        <CardHeader>
          <CardTitle>Importar Dados de Clientes</CardTitle>
          <CardDescription>
            Faça upload de um arquivo CSV ou JSON para povoar seu banco de dados.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-6">
          <div className="flex gap-4">
            <Button variant="outline" onClick={downloadTemplate}>
              <Download className="mr-2 h-4 w-4" /> Baixar Template CSV
            </Button>
          </div>

          <div className="border-2 border-dashed border-slate-200 rounded-lg p-10 flex flex-col items-center justify-center text-center bg-slate-50 transition-colors hover:bg-slate-100">
            <div className="flex gap-2 mb-4">
              <FileSpreadsheet className="h-8 w-8 text-emerald-500" />
              <FileJson className="h-8 w-8 text-amber-500" />
            </div>
            <h3 className="font-semibold text-lg mb-1">Arraste e solte seu arquivo aqui</h3>
            <p className="text-sm text-muted-foreground mb-4">
              ou clique para selecionar um arquivo do seu computador
            </p>

            <div className="relative">
              <Input
                type="file"
                accept=".csv,.json"
                className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
                onChange={handleFileUpload}
              />
              <Button>
                <Upload className="mr-2 h-4 w-4" /> Selecionar Arquivo
              </Button>
            </div>
            {fileName && (
              <p className="mt-4 text-sm font-medium text-primary">
                Arquivo selecionado: {fileName}
              </p>
            )}
          </div>

          <div className="bg-blue-50 text-blue-800 p-4 rounded-md text-sm">
            <strong className="block mb-1">Dica de formatação CSV:</strong>
            Os cabeçalhos necessários são: <code>name</code>, <code>document</code>,{' '}
            <code>email</code>, <code>phone</code>.
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
