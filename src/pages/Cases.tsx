import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Card, CardContent } from '@/components/ui/card'
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
import { Label } from '@/components/ui/label'
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog'
import {
  Plus,
  Edit,
  Trash2,
  LayoutGrid,
  List,
  Star,
  Filter,
  ChevronDown,
  ChevronUp,
  Search,
  X,
} from 'lucide-react'
import { DatePicker } from '@/components/ui/date-picker'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'
import { CaseDialog } from '@/components/CaseDialog'
import { normalizeStr } from '@/lib/utils'

const initialFilters = {
  numero: '',
  clienteId: 'Todos',
  tipo: 'Todos',
  status: 'Todos',
  vara: '',
  comarca: '',
  estado: '',
  valorMin: '',
  valorMax: '',
  dataInicioDe: '',
  dataInicioAte: '',
  responsavelId: 'Todos',
  especial: 'Todos',
}

export default function Cases() {
  const { state, addCase, updateItem, deleteItem } = useLegalStore()
  const [filters, setFilters] = useState(initialFilters)
  const [appliedFilters, setAppliedFilters] = useState(initialFilters)
  const [quickSearch, setQuickSearch] = useState('')
  const [searchOpen, setSearchOpen] = useState(true)
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
    if (c.parentId) return false
    if (quickSearch && !normalizeStr(c.number).includes(normalizeStr(quickSearch))) return false
    const f = appliedFilters
    if (f.numero && !normalizeStr(c.number).includes(normalizeStr(f.numero))) return false
    if (f.clienteId !== 'Todos' && c.clientId !== f.clienteId) return false
    if (f.tipo !== 'Todos' && c.type !== f.tipo) return false
    if (f.status !== 'Todos' && c.status !== f.status) return false
    if (f.vara && !normalizeStr(c.court).includes(normalizeStr(f.vara))) return false
    if (f.comarca && !normalizeStr(c.comarca).includes(normalizeStr(f.comarca))) return false
    if (f.estado && !normalizeStr(c.state).includes(normalizeStr(f.estado))) return false
    if (f.valorMin !== '' && c.value < Number(f.valorMin)) return false
    if (f.valorMax !== '' && c.value > Number(f.valorMax)) return false
    if (f.dataInicioDe && (!c.startDate || c.startDate < f.dataInicioDe)) return false
    if (f.dataInicioAte && (!c.startDate || c.startDate > f.dataInicioAte)) return false
    if (f.responsavelId !== 'Todos' && c.responsibleId !== f.responsavelId) return false
    if (f.especial !== 'Todos') {
      const isEspecial = f.especial === 'Sim'
      if (!!c.isSpecial !== isEspecial) return false
    }
    return true
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
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Processos</h1>
          <p className="text-muted-foreground">Gestão de casos judiciais.</p>
        </div>
        <div className="flex flex-col sm:flex-row w-full sm:w-auto items-center gap-2">
          <div className="relative flex-1 w-full sm:w-64">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Pesquisar número..."
              className="pl-8"
              value={quickSearch}
              onChange={(e) => setQuickSearch(e.target.value)}
            />
          </div>
          <Button onClick={() => handleOpen()} className="w-full sm:w-auto shrink-0">
            <Plus className="mr-2 h-4 w-4" /> Novo Processo
          </Button>
        </div>
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

      <Collapsible
        open={searchOpen}
        onOpenChange={setSearchOpen}
        className="bg-card border rounded-lg shadow-sm"
      >
        <CollapsibleTrigger asChild>
          <div className="flex items-center justify-between p-4 cursor-pointer hover:bg-muted/50 transition-colors rounded-t-lg">
            <div className="flex items-center gap-2 font-bold text-primary">
              <Filter className="h-5 w-5" />
              Pesquisa Avançada
            </div>
            {searchOpen ? <ChevronUp className="h-5 w-5" /> : <ChevronDown className="h-5 w-5" />}
          </div>
        </CollapsibleTrigger>
        <CollapsibleContent className="px-4 pb-4">
          <div className="border-t pt-4 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">
                Número do Processo
              </Label>
              <Input
                placeholder="0000000-00.0000.0.00.0000"
                value={filters.numero}
                onChange={(e) => setFilters({ ...filters, numero: e.target.value })}
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">Cliente</Label>
              <Select
                value={filters.clienteId}
                onValueChange={(v) => setFilters({ ...filters, clienteId: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Todos os clientes" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Todos">Todos os clientes</SelectItem>
                  {sortedClients.map((c) => (
                    <SelectItem key={c.id} value={c.id}>
                      {c.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">
                Tipo de Processo
              </Label>
              <Select
                value={filters.tipo}
                onValueChange={(v) => setFilters({ ...filters, tipo: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Todos os tipos" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Todos">Todos os tipos</SelectItem>
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
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">Status</Label>
              <Select
                value={filters.status}
                onValueChange={(v) => setFilters({ ...filters, status: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Todos os status" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Todos">Todos os status</SelectItem>
                  {sortedStatuses.map((s) => (
                    <SelectItem key={s} value={s}>
                      {s}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">Vara</Label>
              <Input
                placeholder="Ex: 1ª Vara Cível"
                value={filters.vara}
                onChange={(e) => setFilters({ ...filters, vara: e.target.value })}
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">Comarca</Label>
              <Input
                placeholder="Ex: São Paulo"
                value={filters.comarca}
                onChange={(e) => setFilters({ ...filters, comarca: e.target.value })}
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">Estado</Label>
              <Input
                placeholder="Ex: SP"
                value={filters.estado}
                onChange={(e) => setFilters({ ...filters, estado: e.target.value })}
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">
                Valor da Causa (Mín)
              </Label>
              <Input
                type="number"
                placeholder="0.00"
                value={filters.valorMin}
                onChange={(e) => setFilters({ ...filters, valorMin: e.target.value })}
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">
                Valor da Causa (Máx)
              </Label>
              <Input
                type="number"
                placeholder="0.00"
                value={filters.valorMax}
                onChange={(e) => setFilters({ ...filters, valorMax: e.target.value })}
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">
                Data Início (De)
              </Label>
              <DatePicker
                value={filters.dataInicioDe}
                onChange={(v) => setFilters({ ...filters, dataInicioDe: v })}
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">
                Data Início (Até)
              </Label>
              <DatePicker
                value={filters.dataInicioAte}
                onChange={(v) => setFilters({ ...filters, dataInicioAte: v })}
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">
                Colaborador Responsável
              </Label>
              <Select
                value={filters.responsavelId}
                onValueChange={(v) => setFilters({ ...filters, responsavelId: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Todos" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Todos">Todos</SelectItem>
                  {sortedUsers.map((u) => (
                    <SelectItem key={u.id} value={u.id}>
                      {u.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">
                Processo Especial
              </Label>
              <Select
                value={filters.especial}
                onValueChange={(v) => setFilters({ ...filters, especial: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Todos" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Todos">Todos</SelectItem>
                  <SelectItem value="Sim">Sim</SelectItem>
                  <SelectItem value="Não">Não</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="flex justify-end gap-2 pt-4 mt-4 border-t">
            <Button
              variant="outline"
              onClick={() => {
                setFilters(initialFilters)
                setAppliedFilters(initialFilters)
                setQuickSearch('')
              }}
            >
              <X className="mr-2 h-4 w-4" /> Limpar Filtros
            </Button>
            <Button
              onClick={() => setAppliedFilters(filters)}
              className="bg-primary text-primary-foreground"
            >
              <Search className="mr-2 h-4 w-4" /> Pesquisar
            </Button>
          </div>
        </CollapsibleContent>
      </Collapsible>

      <Card className="shadow-sm">
        <CardContent className="p-4">
          <Tabs defaultValue="list">
            <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center mb-4 gap-2">
              <p className="text-sm font-medium text-muted-foreground">
                {filtered.length} processo(s) encontrado(s)
              </p>
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
                const resp = state.users.find((u) => u.id === c.responsibleId)

                return (
                  <div
                    key={c.id}
                    className="border p-4 rounded-lg flex flex-col md:flex-row justify-between gap-4 hover:border-primary/50 transition-colors bg-card"
                  >
                    <div className="w-full">
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
                      <div className="flex items-center gap-2 mt-2 text-xs text-muted-foreground">
                        <p>
                          Vara: {c.court} • Tramitando há {getDays(c.startDate)} dias
                        </p>
                        {resp && (
                          <span
                            className="px-2 py-0.5 rounded-full font-medium ml-auto"
                            style={{
                              backgroundColor: `${resp.color}20`,
                              color: resp.color,
                              border: `1px solid ${resp.color}40`,
                            }}
                          >
                            Resp: {resp.name.split(' ')[0]}
                          </span>
                        )}
                      </div>
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
                        <AlertDialog>
                          <AlertDialogTrigger asChild>
                            <Button
                              variant="outline"
                              size="sm"
                              className="text-red-500 hover:bg-red-50"
                              title="Excluir"
                            >
                              <Trash2 className="h-4 w-4" />
                            </Button>
                          </AlertDialogTrigger>
                          <AlertDialogContent>
                            <AlertDialogHeader>
                              <AlertDialogTitle>Excluir Processo?</AlertDialogTitle>
                              <AlertDialogDescription>
                                Esta ação não pode ser desfeita. Isso excluirá o processo
                                permanentemente, além de tarefas e compromissos atrelados.
                              </AlertDialogDescription>
                            </AlertDialogHeader>
                            <AlertDialogFooter>
                              <AlertDialogCancel>Cancelar</AlertDialogCancel>
                              <AlertDialogAction
                                className="bg-red-600 hover:bg-red-700"
                                onClick={() => deleteItem('cases', c.id)}
                              >
                                Excluir
                              </AlertDialogAction>
                            </AlertDialogFooter>
                          </AlertDialogContent>
                        </AlertDialog>
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
                        <p className="flex items-center gap-1">
                          <span className="text-muted-foreground">Resp:</span>{' '}
                          {resp ? (
                            <span
                              className="text-[10px] px-2 py-0.5 rounded-full font-medium"
                              style={{
                                backgroundColor: `${resp.color}20`,
                                color: resp.color,
                                border: `1px solid ${resp.color}40`,
                              }}
                            >
                              {resp.name}
                            </span>
                          ) : (
                            '—'
                          )}
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

                      <div className="flex gap-2 pt-2 border-t mt-3">
                        <Button
                          variant="outline"
                          size="sm"
                          className="w-full"
                          onClick={() => handleOpen(c)}
                        >
                          <Edit className="h-4 w-4 mr-2" /> Editar
                        </Button>
                        {state.currentUser.role === 'Admin' && (
                          <AlertDialog>
                            <AlertDialogTrigger asChild>
                              <Button
                                variant="outline"
                                size="sm"
                                className="text-red-500 hover:bg-red-50 shrink-0"
                                title="Excluir"
                              >
                                <Trash2 className="h-4 w-4" />
                              </Button>
                            </AlertDialogTrigger>
                            <AlertDialogContent>
                              <AlertDialogHeader>
                                <AlertDialogTitle>Excluir Processo?</AlertDialogTitle>
                                <AlertDialogDescription>
                                  Esta ação não pode ser desfeita. Isso excluirá o processo
                                  permanentemente, além de tarefas e compromissos atrelados.
                                </AlertDialogDescription>
                              </AlertDialogHeader>
                              <AlertDialogFooter>
                                <AlertDialogCancel>Cancelar</AlertDialogCancel>
                                <AlertDialogAction
                                  className="bg-red-600 hover:bg-red-700"
                                  onClick={() => deleteItem('cases', c.id)}
                                >
                                  Excluir
                                </AlertDialogAction>
                              </AlertDialogFooter>
                            </AlertDialogContent>
                          </AlertDialog>
                        )}
                      </div>
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
