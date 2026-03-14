import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Badge } from '@/components/ui/badge'
import { Search, Plus, LayoutList, Columns } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'

const KANBAN_STAGES = ['Análise', 'Petição Inicial', 'Em Andamento', 'Sentença']

export default function Cases() {
  const { state } = useLegalStore()
  const [searchTerm, setSearchTerm] = useState('')

  const filteredCases = state.cases.filter(
    (c) =>
      c.number.includes(searchTerm) || c.title.toLowerCase().includes(searchTerm.toLowerCase()),
  )

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'Análise':
        return 'bg-slate-500'
      case 'Petição Inicial':
        return 'bg-amber-500'
      case 'Em Andamento':
        return 'bg-blue-500'
      case 'Sentença':
        return 'bg-emerald-500'
      default:
        return 'bg-gray-500'
    }
  }

  return (
    <div className="space-y-6 h-full flex flex-col">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight text-slate-800 dark:text-slate-100">
            Processos
          </h1>
          <p className="text-muted-foreground mt-1">Acompanhamento e gestão de casos.</p>
        </div>
        <Button>
          <Plus className="mr-2 h-4 w-4" /> Novo Processo
        </Button>
      </div>

      <Tabs defaultValue="kanban" className="flex-1 flex flex-col">
        <div className="flex justify-between items-center mb-4">
          <div className="relative w-full max-w-sm">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
            <Input
              type="search"
              placeholder="Buscar número ou título..."
              className="pl-9 bg-white"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
          </div>
          <TabsList>
            <TabsTrigger value="kanban">
              <Columns className="h-4 w-4 mr-2" /> Kanban
            </TabsTrigger>
            <TabsTrigger value="list">
              <LayoutList className="h-4 w-4 mr-2" /> Lista
            </TabsTrigger>
          </TabsList>
        </div>

        <TabsContent value="kanban" className="flex-1 mt-0">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 h-full">
            {KANBAN_STAGES.map((stage) => (
              <div
                key={stage}
                className="bg-slate-100 dark:bg-slate-800/50 rounded-lg p-4 flex flex-col min-h-[500px]"
              >
                <h3 className="font-semibold text-slate-700 dark:text-slate-200 mb-4 flex items-center justify-between">
                  {stage}
                  <Badge variant="secondary">
                    {filteredCases.filter((c) => c.status === stage).length}
                  </Badge>
                </h3>
                <div className="space-y-3 flex-1">
                  {filteredCases
                    .filter((c) => c.status === stage)
                    .map((c) => {
                      const client = state.clients.find((cl) => cl.id === c.clientId)
                      return (
                        <Card
                          key={c.id}
                          className="cursor-pointer hover:border-primary/50 transition-colors shadow-sm"
                        >
                          <CardContent className="p-4">
                            <p className="text-xs text-muted-foreground mb-1">{c.number}</p>
                            <p className="font-medium text-sm leading-tight mb-2">{c.title}</p>
                            <p className="text-xs text-slate-500 mb-3">
                              {client?.name || 'Cliente Desconhecido'}
                            </p>
                            <div className="flex justify-between items-center mt-auto">
                              <span className="text-[10px] text-muted-foreground">
                                Atualizado: {c.updatedAt}
                              </span>
                              <div className={`h-2 w-2 rounded-full ${getStatusColor(c.status)}`} />
                            </div>
                          </CardContent>
                        </Card>
                      )
                    })}
                </div>
              </div>
            ))}
          </div>
        </TabsContent>

        <TabsContent value="list" className="mt-0">
          <Card className="shadow-sm">
            <CardContent className="p-0">
              <div className="divide-y">
                {filteredCases.map((c) => {
                  const client = state.clients.find((cl) => cl.id === c.clientId)
                  return (
                    <div
                      key={c.id}
                      className="p-4 hover:bg-slate-50 flex items-center justify-between"
                    >
                      <div>
                        <p className="font-medium text-primary">{c.number}</p>
                        <p className="text-sm font-medium">{c.title}</p>
                        <p className="text-xs text-muted-foreground mt-1">
                          Cliente: {client?.name} • Atualizado em {c.updatedAt}
                        </p>
                      </div>
                      <Badge
                        className={`${getStatusColor(c.status)} text-white hover:${getStatusColor(c.status)} border-transparent`}
                      >
                        {c.status}
                      </Badge>
                    </div>
                  )
                })}
                {filteredCases.length === 0 && (
                  <div className="p-8 text-center text-muted-foreground">
                    Nenhum processo encontrado.
                  </div>
                )}
              </div>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  )
}
