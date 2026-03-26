import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import { Input } from '@/components/ui/input'
import { FileText, Save, Info } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'

export default function Petitions() {
  const { state, updateItem, addLog } = useLegalStore()
  const [activeId, setActiveId] = useState<string | null>(null)
  const [content, setContent] = useState('')
  const [title, setTitle] = useState('')

  const loadDoc = (id: string) => {
    const doc = state.petitions.find((p) => p.id === id)
    if (doc) {
      setActiveId(id)
      setContent(doc.content)
      setTitle(doc.title)
    }
  }

  const saveDoc = () => {
    if (!activeId) return
    updateItem('petitions', activeId, { title, content })
    addLog('Editar', 'Petição', `Modelo ${title} atualizado`)
  }

  return (
    <div className="space-y-6 h-full flex flex-col">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Modelos de Petição (Templates)</h1>
        <p className="text-muted-foreground">
          Editor para automação. Use as variáveis para preenchimento dinâmico nos processos.
        </p>
      </div>

      <div className="flex flex-col md:flex-row gap-6 flex-1 h-[600px]">
        <Card className="w-full md:w-64 shrink-0 h-fit">
          <CardHeader className="py-4">
            <CardTitle className="text-sm">Meus Modelos</CardTitle>
          </CardHeader>
          <CardContent className="p-2 space-y-1">
            {state.petitions.map((p) => (
              <Button
                key={p.id}
                variant={activeId === p.id ? 'default' : 'ghost'}
                className="w-full justify-start text-left text-sm truncate"
                onClick={() => loadDoc(p.id)}
              >
                <FileText className="h-4 w-4 mr-2 shrink-0" /> {p.title}
              </Button>
            ))}
          </CardContent>
        </Card>

        <div className="flex-1 flex flex-col gap-4 h-full">
          <Card className="bg-primary/10 border-primary/20">
            <CardContent className="p-4 flex items-start gap-3">
              <Info className="h-5 w-5 text-primary mt-0.5" />
              <div className="text-sm text-primary space-y-1">
                <p>
                  <strong>Variáveis disponíveis:</strong>
                </p>
                <p className="font-mono text-xs">
                  {'{{client_name}}'}, {'{{client_document}}'}, {'{{process_number}}'},{' '}
                  {'{{adverse_party}}'}, {'{{court}}'}, {'{{comarca}}'}
                </p>
              </div>
            </CardContent>
          </Card>

          <Card className="flex-1 flex flex-col min-h-0">
            {activeId ? (
              <>
                <CardHeader className="py-3 border-b flex flex-row items-center gap-4 bg-slate-50">
                  <Input
                    value={title}
                    onChange={(e) => setTitle(e.target.value)}
                    className="font-bold border-none bg-transparent shadow-none focus-visible:ring-0 px-0 h-auto"
                  />
                  <Button size="sm" onClick={saveDoc}>
                    <Save className="h-4 w-4 mr-2" /> Salvar Modelo
                  </Button>
                </CardHeader>
                <CardContent className="p-0 flex-1 relative">
                  <Textarea
                    value={content}
                    onChange={(e) => setContent(e.target.value)}
                    className="w-full h-full border-0 resize-none rounded-none p-6 font-serif text-base focus-visible:ring-0 focus-visible:ring-offset-0 leading-relaxed min-h-[400px]"
                  />
                </CardContent>
              </>
            ) : (
              <div className="flex-1 flex items-center justify-center text-muted-foreground flex-col gap-4">
                <FileText className="h-16 w-16 opacity-20" />
                <p>Selecione um modelo ao lado para editar.</p>
              </div>
            )}
          </Card>
        </div>
      </div>
    </div>
  )
}
