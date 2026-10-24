import { useState, useMemo } from 'react'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Code2, Copy, Check, Search, HelpCircle, Sparkles } from 'lucide-react'
import { AVAILABLE_PLACEHOLDERS, PlaceholderDocumentation } from '@/services/document-templates'
import { toast } from '@/hooks/use-toast'

interface PlaceholdersHelpDialogProps {
  trigger?: React.ReactNode
}

export function PlaceholdersHelpDialog({ trigger }: PlaceholdersHelpDialogProps) {
  const [open, setOpen] = useState(false)
  const [search, setSearch] = useState('')
  const [selectedGroup, setSelectedGroup] = useState<string>('todos')
  const [copiedKey, setCopiedKey] = useState<string | null>(null)

  const groups = ['todos', 'Cliente', 'Processo', 'Escritório', 'Data / Sistema', 'Campos Manuais']

  const filtered = useMemo(() => {
    return AVAILABLE_PLACEHOLDERS.filter((item) => {
      const matchesGroup = selectedGroup === 'todos' || item.group === selectedGroup
      if (!matchesGroup) return false
      if (!search.trim()) return true
      const query = search.toLowerCase()
      return (
        item.key.toLowerCase().includes(query) ||
        item.label.toLowerCase().includes(query) ||
        (item.description && item.description.toLowerCase().includes(query)) ||
        item.example.toLowerCase().includes(query)
      )
    })
  }, [search, selectedGroup])

  const copyToClipboard = (key: string) => {
    const textToCopy = `{{${key}}}`
    navigator.clipboard.writeText(textToCopy)
    setCopiedKey(key)
    toast({
      title: 'Copiado!',
      description: `Marcador ${textToCopy} copiado para a área de transferência.`,
    })
    setTimeout(() => setCopiedKey(null), 2000)
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        {trigger || (
          <Button variant="outline" size="sm" className="gap-2">
            <Code2 className="h-4 w-4 text-primary" />
            Ver Marcadores Disponíveis
          </Button>
        )}
      </DialogTrigger>
      <DialogContent className="max-w-3xl max-h-[85vh] flex flex-col p-6">
        <DialogHeader className="pb-3 border-b">
          <div className="flex items-center gap-2">
            <div className="p-2 rounded-lg bg-primary/10 text-primary">
              <Sparkles className="h-5 w-5" />
            </div>
            <div>
              <DialogTitle className="text-xl">Marcadores / Placeholders Disponíveis</DialogTitle>
              <DialogDescription className="text-xs text-muted-foreground mt-0.5">
                Utilize estes códigos dentro dos seus arquivos .docx (ex:{' '}
                <code className="bg-muted px-1.5 py-0.5 rounded font-mono text-primary font-semibold">
                  {'{{cliente.nome}}'}
                </code>
                ). Ao gerar, o sistema substituirá os dados preservando 100% da sua formatação.
              </DialogDescription>
            </div>
          </div>
        </DialogHeader>

        <div className="space-y-3 pt-3">
          <div className="flex flex-col sm:flex-row gap-2 items-center justify-between">
            <div className="relative w-full sm:w-72">
              <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Buscar marcador (ex: nome, cpf, vara)..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="pl-8 text-xs h-9"
              />
            </div>
            <div className="text-xs text-muted-foreground flex items-center gap-1 self-start sm:self-center">
              <HelpCircle className="h-3.5 w-3.5" />
              <span>Clique em qualquer linha para copiar o marcador.</span>
            </div>
          </div>

          <Tabs value={selectedGroup} onValueChange={setSelectedGroup} className="w-full">
            <TabsList className="h-8 p-0.5 flex flex-wrap gap-1 bg-muted/60">
              {groups.map((grp) => (
                <TabsTrigger
                  key={grp}
                  value={grp}
                  className="text-xs px-2.5 py-1 capitalize data-[state=active]:bg-white data-[state=active]:shadow-xs"
                >
                  {grp}
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>
        </div>

        <div className="flex-1 overflow-y-auto mt-3 pr-1 space-y-2 border rounded-md p-2 bg-slate-50/50">
          {filtered.length === 0 ? (
            <div className="py-12 text-center text-sm text-muted-foreground">
              Nenhum marcador encontrado para "{search}".
            </div>
          ) : (
            filtered.map((item) => {
              const fullTag = `{{${item.key}}}`
              const isCopied = copiedKey === item.key

              return (
                <div
                  key={item.key}
                  onClick={() => copyToClipboard(item.key)}
                  className="flex items-center justify-between p-2.5 bg-white rounded-md border border-slate-200/80 hover:border-primary/50 hover:shadow-xs transition-all cursor-pointer group"
                >
                  <div className="space-y-1 flex-1 pr-4">
                    <div className="flex items-center gap-2 flex-wrap">
                      <code className="font-mono text-xs font-bold text-primary bg-primary/10 px-2 py-0.5 rounded border border-primary/20 group-hover:bg-primary group-hover:text-white transition-colors">
                        {fullTag}
                      </code>
                      <span className="text-xs font-semibold text-slate-800">{item.label}</span>
                      <Badge
                        variant="outline"
                        className="text-[10px] py-0 px-1.5 h-4 text-slate-500"
                      >
                        {item.group}
                      </Badge>
                    </div>
                    <div className="text-xs text-slate-500 flex items-center gap-2">
                      <span className="text-slate-400">Exemplo:</span>
                      <span className="italic text-slate-600 font-mono text-[11px] bg-slate-50 px-1 rounded">
                        {item.example}
                      </span>
                      {item.description && (
                        <span className="text-muted-foreground">· {item.description}</span>
                      )}
                    </div>
                  </div>

                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-8 px-2 text-xs shrink-0 text-slate-500 group-hover:text-primary group-hover:bg-primary/10"
                    onClick={(e) => {
                      e.stopPropagation()
                      copyToClipboard(item.key)
                    }}
                  >
                    {isCopied ? (
                      <>
                        <Check className="h-3.5 w-3.5 text-emerald-600 mr-1" />
                        <span className="text-emerald-600 font-semibold text-[11px]">Copiado</span>
                      </>
                    ) : (
                      <>
                        <Copy className="h-3.5 w-3.5 mr-1" />
                        <span className="text-[11px]">Copiar</span>
                      </>
                    )}
                  </Button>
                </div>
              )
            })
          )}
        </div>

        <div className="pt-3 border-t mt-3 flex justify-between items-center text-xs text-slate-500">
          <span>{filtered.length} marcadores listados</span>
          <Button variant="outline" size="sm" onClick={() => setOpen(false)}>
            Fechar
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}
