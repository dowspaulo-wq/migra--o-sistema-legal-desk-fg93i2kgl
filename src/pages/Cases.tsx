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
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { Label } from '@/components/ui/label'
import { Search, Plus, Edit, Trash2, LayoutGrid, List, Star, Filter } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'
import { CaseDialog } from '@/components/CaseDialog'

export default function Cases() {
  const { state, addCase, updateItem, deleteItem } = useLegalStore()
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('Todos')
  const [typeFilter, setTypeFilter] = useState('Todos')
  const [respFilter, setRespFilter] = useState('Todos')
  const [clientFilter, setClientFilter] = useState('Todos')
  const [minVal, setMinVal] = useState('')
  const [maxVal, setMaxVal] = useState('')
  const [open, setOpen] = useState(false)
  const [editingCase, setEditingCase] = useState<any>(null)

  const sortedUsers = [...state.users].sort((a, b) => a.name.localeCompare(b.name))
  const sortedClients = [...state.clients].sort((a, b) => a.name.localeCompare(b.name))

  const caseTypesSettings = state.settings.caseTypes || []
  const sortedTypes = [...caseTypesSettings].sort((a: any, b: any) => {
    const labelA = typeof a === 'string' ? a : a.label
    const labelB = typeof b === 'string' ? b : b.label
    return labelA.localeCompare(labelB)
  })

  const sortedStatuses = [...(state.settings.caseStatuses || [])].sort((a, b) => a.localeCompare(b))

  const filtered = state.cases.filter((c) => {
    const client = state.clients.find((cl) => cl.id === c.clientId)
    const clientName = client ? client.name.toLowerCase() : ''

    const mSearch =
      (c.number || '').toString().toLowerCase().includes(search.toLowerCase()) ||
      (c.adverseParty || '').toLowerCase().includes(search.toLowerCase()) ||
      clientName.includes(search.toLowerCase())
    const mStatus =
      statusFilter === 'Todos' || (statusFilter === 'Vazio' ? !c.status : c.status === statusFilter)
    const mType =
      typeFilter === 'Todos' || (typeFilter === 'Vazio' ? !c.type : c.type === typeFilter)
    const mResp =
      respFilter === 'Todos' ||
      (respFilter === 'Vazio' ? !c.responsibleId : c.responsibleId === respFilter)
    const mClient =
      clientFilter === 'Todos' ||
      (clientFilter === 'Vazio' ? !c.clientId : c.clientId === clientFilter)
    const mMin = minVal === '' || (c.value || 0) >= Number(minVal)
    const mMax = maxVal === '' || (c.value || 0) <= Number(maxVal)
    return mSearch && mStatus && mType && mResp && mClient && mMin && mMax
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

  const getTypeColor = (type: string) => {
    const t = caseTypesSettings.find(
      (x: any) => (typeof x === 'string' ? x : x.label) === type,
    ) as any
    return typeof t === 'object' ? t.color : '#94a3b8'
  }

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
          <div className="flex gap-2 w-full max-w-md">
            <Input
              type="search"
              placeholder="Buscar por número, cliente ou parte adversa..."
              className="flex-1"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
            <Popover>
              <PopoverTrigger asChild>
                <Button variant="outline" className="flex items-center gap-2">
                  <Filter className="h-4 w-4" /> Filtros
                </Button>
              </PopoverTrigger>
              <PopoverContent className="w-80 max-h-[80vh] overflow-y-auto space-y-4">
                <h4 className="font-medium text-sm border-b pb-2">Filtros Avançados</h4>
                <div className="space-y-2">
                  <Label className="text-xs">Status</Label>
                  <Select value={statusFilter} onValueChange={setStatusFilter}>
                    <SelectTrigger>
                      <SelectValue placeholder="Status" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Todos">Todos</SelectItem>
                      <SelectItem value="Vazio">Não Informado (Vazio)</SelectItem>
                      {sortedStatuses.map((s) => (
                        <SelectItem key={s} value={s}>
                          {s}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label className="text-xs">Tipo de Ação</Label>
                  <Select value={typeFilter} onValueChange={setTypeFilter}>
                    <SelectTrigger>
                      <SelectValue placeholder="Tipo" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Todos">Todos</SelectItem>
                      <SelectItem value="Vazio">Não Informado (Vazio)</SelectItem>
                      {sortedTypes.map((t: any) => {
                        const label = typeof t === 'string' ? t : t.label
                        return (
                          <SelectItem key={label} value={label}>
                            {label}
                          </SelectItem>
                        )
                      })}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label className="text-xs">Responsável</Label>
                  <Select value={respFilter} onValueChange={setRespFilter}>
                    <SelectTrigger>
                      <SelectValue placeholder="Responsável" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Todos">Todos</SelectItem>
                      <SelectItem value="Vazio">Não Atribuído (Vazio)</SelectItem>
                      {sortedUsers.map((u) => (
                        <SelectItem key={u.id} value={u.id}>
                          {u.name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label className="text-xs">Cliente</Label>
                  <Select value={clientFilter} onValueChange={setClientFilter}>
                    <SelectTrigger>
                      <SelectValue placeholder="Cliente" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Todos">Todos</SelectItem>
                      <SelectItem value="Vazio">Sem Cliente (Vazio)</SelectItem>
                      {sortedClients.map((c) => (
                        <SelectItem key={c.id} value={c.id}>
                          {c.name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="grid grid-cols-2 gap-2">
                  <div className="space-y-2">
                    <Label className="text-xs">Valor Mínimo (R$)</Label>
                    <Input
                      type="number"
                      value={minVal}
                      onChange={(e) => setMinVal(e.target.value)}
                    />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-xs">Valor Máximo (R$)</Label>
                    <Input
                      type="number"
                      value={maxVal}
                      onChange={(e) => setMaxVal(e.target.value)}
                    />
                  </div>
                </div>
                <Button
                  variant="ghost"
                  size="sm"
                  className="w-full mt-2"
                  onClick={() => {
                    setStatusFilter('Todos')
                    setTypeFilter('Todos')
                    setRespFilter('Todos')
                    setClientFilter('Todos')
                    setMinVal('')
                    setMaxVal('')
                  }}
                >
                  Limpar Filtros
                </Button>
              </PopoverContent>
            </Popover>
          </div>
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
                      <div className="flex items-center gap-2 mb-1">
                        <Link
                          to={`/processos/${c.id}`}
                          className="text-lg font-bold text-primary hover:underline"
                        >
                          {c.number}
                        </Link>{' '}
                        {c.isSpecial && (
                          <Star className="h-4 w-4 fill-yellow-400 text-yellow-400" />
                        )}
                        {c.isProblematic && (
                          <span className="text-base leading-none" title="Problemático">
                            💩
                          </span>
                        )}
                        <Badge variant="outline">{c.status}</Badge>
                        <Badge
                          style={{ backgroundColor: getTypeColor(c.type) }}
                          className="text-white border-0 hover:opacity-90"
                        >
                          {c.type}
                        </Badge>
                      </div>
                      <p className="text-sm font-medium mt-1">
                        {client ? (
                          <Link
                            to={`/clientes/${client.id}`}
                            className="hover:underline text-primary"
                          >
                            {client.name}
                          </Link>
                        ) : (
                          '—'
                        )}{' '}
                        <span className="text-muted-foreground text-xs">({c.position})</span> x{' '}
                        {c.adverseParty}
                      </p>
                      <p className="text-xs text-muted-foreground mt-1">
                        Vara: {c.court} • Tramitando há {getDays(c.startDate)} dias
                      </p>
                      {c.alerts && (
                        <div className="flex gap-1 flex-wrap mt-2">
                          {c.alerts.split(',').map((a) => (
                            <Badge
                              key={a}
                              variant="secondary"
                              className="text-[10px] bg-red-50 text-red-700 border-red-200"
                            >
                              {a}
                            </Badge>
                          ))}
                        </div>
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
                const typeColor = getTypeColor(c.type)

                return (
                  <Card key={c.id} className="relative overflow-hidden group">
                    <div
                      className="absolute top-0 left-0 w-full h-1"
                      style={{ backgroundColor: typeColor }}
                    />
                    <CardContent className="p-4 pt-5 space-y-3">
                      <div className="flex justify-between items-start gap-2">
                        <Link
                          to={`/processos/${c.id}`}
                          className="font-bold text-primary hover:underline text-sm break-all"
                        >
                          {c.number}
                        </Link>
                        <div className="flex items-center gap-1 shrink-0">
                          {c.isProblematic && (
                            <span className="text-base leading-none" title="Problemático">
                              💩
                            </span>
                          )}
                          {c.isSpecial && (
                            <Star className="h-4 w-4 fill-yellow-400 text-yellow-400" />
                          )}
                        </div>
                      </div>
                      <div className="flex gap-2 flex-wrap">
                        <Badge>{c.status}</Badge>
                        <Badge
                          style={{ backgroundColor: typeColor }}
                          className="text-white border-0 hover:opacity-90"
                        >
                          {c.type}
                        </Badge>
                      </div>
                      <div className="text-sm space-y-1">
                        <p>
                          <span className="text-muted-foreground">Cliente:</span>{' '}
                          {client ? (
                            <Link
                              to={`/clientes/${client.id}`}
                              className="hover:underline text-primary"
                            >
                              {client.name}
                            </Link>
                          ) : (
                            '—'
                          )}
                        </p>
                        <p>
                          <span className="text-muted-foreground">Adversa:</span> {c.adverseParty}
                        </p>
                        <p>
                          <span className="text-muted-foreground">Resp:</span> {resp?.name || '—'}
                        </p>
                        <p>
                          <span className="text-muted-foreground">Duração:</span>{' '}
                          {getDays(c.startDate)} dias
                        </p>
                      </div>
                      {c.alerts && (
                        <div className="flex gap-1 flex-wrap pt-1">
                          {c.alerts.split(',').map((a) => (
                            <Badge
                              key={a}
                              variant="secondary"
                              className="text-[10px] bg-red-50 text-red-700 border-red-200"
                            >
                              {a}
                            </Badge>
                          ))}
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
