import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Card, CardContent, CardHeader } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Search, Plus, Edit, Trash2, LayoutGrid, List, Star } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'
import { CaseDialog } from '@/components/CaseDialog'

export default function Cases() {
  const { state, addCase, updateItem, deleteItem } = useLegalStore()
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('Todos')
  const [open, setOpen] = useState(false)
  const [editingCase, setEditingCase] = useState<any>(null)

  const filtered = state.cases.filter((c) => {
    const mSearch =
      c.number.includes(search) ||
      (c.adverseParty || '').toLowerCase().includes(search.toLowerCase())
    const mStatus = statusFilter === 'Todos' || c.status === statusFilter
    return mSearch && mStatus
  })

  const handleOpen = (c?: any) => {
    setEditingCase(c || null)
    setOpen(true)
  }

  const handleSave = (fd: any) => {
    if (editingCase) {
      updateItem('cases', editingCase.id, fd)
      toast({ title: 'Atualizado' })
    } else {
      if (state.cases.some((c) => c.number === fd.number))
        return toast({ title: 'Erro', description: 'Número já existe', variant: 'destructive' })
      addCase(fd)
    }
  }

  const getDays = (start: string) =>
    start ? Math.floor((new Date().getTime() - new Date(start).getTime()) / (1000 * 3600 * 24)) : 0

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Processos</h1>
          <p className="text-muted-foreground">Gestão de casos judiciais.</p>
        </div>
        <Button onClick={() => handleOpen()}>
          <Plus className="mr-2 h-4 w-4" /> Novo Processo
        </Button>
      </div>

      <CaseDialog
        open={open}
        onOpenChange={setOpen}
        data={editingCase}
        onSave={handleSave}
        users={state.users}
        clients={state.clients}
        settings={state.settings}
      />

      <Card className="shadow-sm">
        <CardHeader className="py-4 flex flex-col md:flex-row gap-4">
          <Input
            type="search"
            placeholder="Buscar número ou parte..."
            className="max-w-sm"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <Select value={statusFilter} onValueChange={setStatusFilter}>
            <SelectTrigger className="max-w-[150px]">
              <SelectValue placeholder="Status" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="Todos">Todos</SelectItem>
              {state.settings.caseStatuses?.map((s: string) => (
                <SelectItem key={s} value={s}>
                  {s}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </CardHeader>
        <CardContent>
          <Tabs defaultValue="list">
            <div className="flex justify-end mb-4">
              <TabsList>
                <TabsTrigger value="list">
                  <List className="h-4 w-4 mr-2" /> Lista
                </TabsTrigger>
                <TabsTrigger value="grid">
                  <LayoutGrid className="h-4 w-4 mr-2" /> Grade
                </TabsTrigger>
              </TabsList>
            </div>
            <TabsContent value="list" className="grid gap-3">
              {filtered.map((c) => {
                const client = state.clients.find((cl) => cl.id === c.clientId)
                return (
                  <div
                    key={c.id}
                    className="border p-4 rounded-lg flex flex-col md:flex-row justify-between gap-4 hover:border-primary/50 transition-colors bg-card"
                  >
                    <div>
                      <div className="flex items-center gap-2">
                        <Link
                          to={`/processos/${c.id}`}
                          className="text-lg font-bold text-primary hover:underline"
                        >
                          {c.number}
                        </Link>{' '}
                        {c.isSpecial && (
                          <Star className="h-4 w-4 fill-yellow-400 text-yellow-400" />
                        )}{' '}
                        <Badge variant="outline">{c.status}</Badge>
                      </div>
                      <p className="text-sm font-medium mt-1">
                        {client?.name}{' '}
                        <span className="text-muted-foreground text-xs">({c.position})</span> x{' '}
                        {c.adverseParty}
                      </p>
                      <p className="text-xs text-muted-foreground mt-1">
                        Vara: {c.court} • Tipo: {c.type} • Tramitando há {getDays(c.startDate)} dias
                      </p>
                      {c.alerts && (
                        <p className="text-xs mt-2 p-1 bg-red-50 text-red-700 rounded border border-red-100 inline-block">
                          {c.alerts}
                        </p>
                      )}
                    </div>
                    <div className="flex items-center gap-2">
                      <Button variant="outline" size="sm" onClick={() => handleOpen(c)}>
                        <Edit className="h-4 w-4" />
                      </Button>
                      {state.currentUser.role === 'Admin' && (
                        <Button
                          variant="outline"
                          size="sm"
                          className="text-red-500 hover:bg-red-50"
                          onClick={() => {
                            if (confirm('Excluir?')) deleteItem('cases', c.id)
                          }}
                        >
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      )}
                    </div>
                  </div>
                )
              })}
            </TabsContent>
            <TabsContent
              value="grid"
              className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4"
            >
              {filtered.map((c) => {
                const client = state.clients.find((cl) => cl.id === c.clientId)
                const resp = state.users.find((u) => u.id === c.responsibleId)
                return (
                  <Card key={c.id} className="relative overflow-hidden group">
                    <div className="absolute top-0 left-0 w-full h-1 bg-primary" />
                    <CardContent className="p-4 pt-5 space-y-3">
                      <div className="flex justify-between items-start">
                        <Link
                          to={`/processos/${c.id}`}
                          className="font-bold text-primary hover:underline text-sm break-all"
                        >
                          {c.number}
                        </Link>
                        {c.isSpecial && (
                          <Star className="h-4 w-4 fill-yellow-400 text-yellow-400 shrink-0" />
                        )}
                      </div>
                      <Badge>{c.status}</Badge>
                      <div className="text-sm space-y-1">
                        <p>
                          <span className="text-muted-foreground">Cliente:</span> {client?.name}
                        </p>
                        <p>
                          <span className="text-muted-foreground">Adversa:</span> {c.adverseParty}
                        </p>
                        <p>
                          <span className="text-muted-foreground">Resp:</span> {resp?.name}
                        </p>
                        <p>
                          <span className="text-muted-foreground">Duração:</span>{' '}
                          {getDays(c.startDate)} dias
                        </p>
                      </div>
                      {c.alerts && (
                        <div className="text-xs p-1.5 bg-red-50 text-red-700 rounded border border-red-100">
                          {c.alerts}
                        </div>
                      )}
                    </CardContent>
                  </Card>
                )
              })}
            </TabsContent>
          </Tabs>
        </CardContent>
      </Card>
    </div>
  )
}
