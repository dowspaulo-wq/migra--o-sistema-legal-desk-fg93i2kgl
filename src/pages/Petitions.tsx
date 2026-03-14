import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import { Input } from '@/components/ui/input'
import { FileText, Save } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'

export default function Petitions() {
  const { state, setState, addLog } = useLegalStore()
  const [activeId, setActiveId] = useState<string | null>(null)
  const [content, setContent] = useState('')
  const [title, setTitle] = useState('')

  const activeDoc = state.petitions.find((p) => p.id === activeId)

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
    setState((prev) => ({
      ...prev,
      petitions: prev.petitions.map((p) => (p.id === activeId ? { ...p, title, content } : p)),
    }))
    addLog('Editar', 'Petição', `Petição ${title} atualizada`)
  }

  return (
    <div className="space-y-6 h-full flex flex-col">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Modelos de Petição</h1>
        <p className="text-muted-foreground">Editor de documentos Rich Text.</p>
      </div>

      <div className="flex flex-col md:flex-row gap-6 flex-1 h-full">
        <Card className="w-full md:w-64 shrink-0 h-fit">
          <CardHeader className="py-4">
            <CardTitle className="text-sm">Meus Modelos</CardTitle>
          </CardHeader>
          <CardContent className="p-2 space-y-1">
            {state.petitions.map((p) => (
              <Button
                key={p.id}
                variant={activeId === p.id ? 'default' : 'ghost'}
                className="w-full justify-start text-left text-sm"
                onClick={() => loadDoc(p.id)}
              >
                <FileText className="h-4 w-4 mr-2" /> {p.title}
              </Button>
            ))}
          </CardContent>
        </Card>

        <Card className="flex-1 flex flex-col h-[600px]">
          {activeId ? (
            <>
              <CardHeader className="py-3 border-b flex flex-row items-center gap-4 bg-slate-50">
                <Input
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  className="font-bold border-none bg-transparent shadow-none focus-visible:ring-0 px-0 h-auto"
                />
                <Button size="sm" onClick={saveDoc}>
                  <Save className="h-4 w-4 mr-2" /> Salvar
                </Button>
              </CardHeader>
              <CardContent className="p-0 flex-1 relative">
                {/* Mocking a Rich Text Editor with a simple Textarea for this demo to save lines/complexity */}
                <Textarea
                  value={content}
                  onChange={(e) => setContent(e.target.value)}
                  className="w-full h-full border-0 resize-none rounded-none p-6 font-serif text-base focus-visible:ring-0 focus-visible:ring-offset-0 leading-relaxed"
                  placeholder="Digite o conteúdo da petição aqui..."
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
  )
}
