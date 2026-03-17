import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
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
  Trash,
  Edit,
  LayoutGrid,
  List,
  CheckCircle2,
  Circle,
  Filter,
  ChevronDown,
  ChevronUp,
  Search,
  X,
} from 'lucide-react'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import useLegalStore from '@/stores/useLegalStore'
import { TaskDialog } from '@/components/TaskDialog'
import { FullCalendar } from '@/components/FullCalendar'
import { formatSafeLocalDate, getPriorityColorClass, normalizeStr } from '@/lib/utils'
import { DatePicker } from '@/components/ui/date-picker'
import { MultiSelect } from '@/components/ui/multi-select'

const initialFilters = {
  titulo: '',
  status: [] as string[],
  prioridade: 'Todos',
  tipo: 'Todos',
  responsavelId: 'Todos',
  clienteId: 'Todos',
  numeroProcesso: '',
  dataVencimentoDe: '',
  dataVencimentoAte: '',
}

export default function Tasks() {
  const { state, updateItem, deleteItem, addTask } = useLegalStore()
  const [filters, setFilters] = useState(initialFilters)
  const [appliedFilters, setAppliedFilters] = useState(initialFilters)
  const [searchOpen, setSearchOpen] = useState(false)
  const [open, setOpen] = useState(false)
  const [editingItem, setEditingItem] = useState<any>(null)

  const sortedUsers = [...state.users].sort((a, b) => a.name.localeCompare(b.name))
  const sortedClients = [...state.clients].sort((a, b) => a.name.localeCompare(b.name))
  const sortedTypes = [...(state.settings.taskTypes || [])].sort((a, b) => a.localeCompare(b))
  const sortedStatuses = [...(state.settings.taskStatuses || [])].sort((a, b) => a.localeCompare(b))

  const filtered = state.tasks.filter((t) => {
    const f = appliedFilters
    if (f.titulo && !normalizeStr(t.title).includes(normalizeStr(f.titulo))) return false
    if (f.status.length > 0 && !f.status.includes(t.status)) return false
    if (f.prioridade !== 'Todos' && t.priority !== f.prioridade) return false
    if (f.tipo !== 'Todos' && t.type !== f.tipo) return false
    if (f.responsavelId !== 'Todos' && t.responsibleId !== f.responsavelId) return false
    if (f.clienteId !== 'Todos' && t.clientId !== f.clienteId) return false
    if (f.numeroProcesso) {
      const c = state.cases.find((x) => x.id === t.relatedProcessId)
      if (!c || !normalizeStr(c.number).includes(normalizeStr(f.numeroProcesso))) return false
    }
    if (f.dataVencimentoDe && (!t.dueDate || t.dueDate < f.dataVencimentoDe)) return false
    if (f.dataVencimentoAte && (!t.dueDate || t.dueDate > f.dataVencimentoAte)) return false
    return true
  })

  const handleOpen = (item?: any) => {
    setEditingItem(item || null)
    setOpen(true)
  }
  const handleSave = (fd: any) => {
    if (editingItem) updateItem('tasks', editingItem.id, fd)
    else addTask(fd)
  }

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Tarefas</h1>
          <p className="text-muted-foreground">Controle de atividades e prazos.</p>
        </div>
        <Button onClick={() => handleOpen()}>
          <Plus className="mr-2 h-4 w-4" /> Nova Tarefa
        </Button>
      </div>

      <TaskDialog
        open={open}
        onOpenChange={setOpen}
        data={editingItem}
        onSave={handleSave}
        users={state.users}
        clients={state.clients}
        cases={state.cases}
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
                Título da Tarefa
              </Label>
              <Input
                placeholder="Buscar por título..."
                value={filters.titulo}
                onChange={(e) => setFilters({ ...filters, titulo: e.target.value })}
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">Status</Label>
              <MultiSelect
                options={sortedStatuses}
                values={filters.status}
                onChange={(v) => setFilters({ ...filters, status: v })}
                placeholder="Todos os status"
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">Prioridade</Label>
              <Select
                value={filters.prioridade}
                onValueChange={(v) => setFilters({ ...filters, prioridade: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Todas" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Todos">Todas</SelectItem>
                  <SelectItem value="Baixa">Baixa</SelectItem>
                  <SelectItem value="Média">Média</SelectItem>
                  <SelectItem value="Alta">Alta</SelectItem>
                  <SelectItem value="Urgente">Urgente</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">Tipo de Tarefa</Label>
              <Select
                value={filters.tipo}
                onValueChange={(v) => setFilters({ ...filters, tipo: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Todos os tipos" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Todos">Todos os tipos</SelectItem>
                  {sortedTypes.map((t) => (
                    <SelectItem key={t} value={t}>
                      {t}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
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
                Número do Processo
              </Label>
              <Input
                placeholder="0000000-00.0000.0.00.0000"
                value={filters.numeroProcesso}
                onChange={(e) => setFilters({ ...filters, numeroProcesso: e.target.value })}
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">
                Data de Vencimento (De)
              </Label>
              <DatePicker
                value={filters.dataVencimentoDe}
                onChange={(v) => setFilters({ ...filters, dataVencimentoDe: v })}
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">
                Data de Vencimento (Até)
              </Label>
              <DatePicker
                value={filters.dataVencimentoAte}
                onChange={(v) => setFilters({ ...filters, dataVencimentoAte: v })}
              />
            </div>
          </div>
          <div className="flex justify-end gap-2 pt-4 mt-4 border-t">
            <Button
              variant="outline"
              onClick={() => {
                setFilters(initialFilters)
                setAppliedFilters(initialFilters)
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

      <Tabs defaultValue="list">
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center mb-4 gap-2">
          <p className="text-sm font-medium text-muted-foreground">
            {filtered.length} tarefa(s) encontrada(s)
          </p>
          <TabsList>
            <TabsTrigger value="list">
              <List className="h-4 w-4 mr-2" /> Lista
            </TabsTrigger>
            <TabsTrigger value="calendar">
              <LayoutGrid className="h-4 w-4 mr-2" /> Calendário
            </TabsTrigger>
          </TabsList>
        </div>

        <TabsContent value="list" className="grid gap-3">
          {filtered.map((t) => {
            const client = state.clients.find((c) => c.id === t.clientId)
            const c = state.cases.find((x) => x.id === t.relatedProcessId)
            const resp = state.users.find((u) => u.id === t.responsibleId)
            const isDone = t.status.toLowerCase() === 'concluída'
            return (
              <Card
                key={t.id}
                className={`shadow-sm border-l-4 ${isDone ? 'opacity-60 border-l-green-500' : 'border-l-primary'}`}
              >
                <CardContent className="p-4 flex items-center justify-between gap-4">
                  <div className="flex items-start gap-4 w-full">
                    <button
                      onClick={() =>
                        updateItem('tasks', t.id, { status: isDone ? 'pendente' : 'Concluída' })
                      }
                      className="mt-1 text-muted-foreground hover:text-primary transition-colors"
                    >
                      {isDone ? (
                        <CheckCircle2 className="h-5 w-5 text-green-500" />
                      ) : (
                        <Circle className="h-5 w-5" />
                      )}
                    </button>
                    <div className="flex-1 w-full">
                      <p
                        className={`font-bold ${isDone ? 'line-through text-muted-foreground' : ''}`}
                      >
                        {t.title}{' '}
                        <Badge variant="outline" className="ml-2 text-[10px]">
                          {t.type}
                        </Badge>
                      </p>
                      <p className="text-xs text-muted-foreground mt-1">
                        Cliente:{' '}
                        <span className="font-medium">{client?.name || 'Não vinculado'}</span> •
                        Processo:{' '}
                        {c ? (
                          <Link
                            to={`/processos/${c.id}`}
                            className="text-primary hover:underline font-semibold ml-1"
                            onClick={(e) => e.stopPropagation()}
                          >
                            {c.number}
                          </Link>
                        ) : (
                          <span className="italic ml-1">Não vinculado</span>
                        )}
                      </p>
                      <div className="flex flex-wrap gap-2 text-xs mt-2 items-center">
                        <Badge variant="secondary" className="text-[10px]">
                          {t.status}
                        </Badge>
                        <Badge
                          variant="outline"
                          className={`text-[10px] ${getPriorityColorClass(t.priority)}`}
                        >
                          {t.priority || 'Sem prioridade'}
                        </Badge>
                        <span className="text-muted-foreground ml-2 font-semibold">
                          Vence: {formatSafeLocalDate(t.dueDate)}
                        </span>
                        {resp && (
                          <span
                            className="ml-auto flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium"
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
                    </div>
                  </div>
                  <div className="flex gap-2">
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => handleOpen(t)}
                      title="Editar"
                    >
                      <Edit className="h-4 w-4" />
                    </Button>
                    <AlertDialog>
                      <AlertDialogTrigger asChild>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="text-red-500"
                          title="Excluir"
                        >
                          <Trash className="h-4 w-4" />
                        </Button>
                      </AlertDialogTrigger>
                      <AlertDialogContent>
                        <AlertDialogHeader>
                          <AlertDialogTitle>Excluir Tarefa?</AlertDialogTitle>
                          <AlertDialogDescription>
                            Esta ação removerá a tarefa permanentemente do sistema.
                          </AlertDialogDescription>
                        </AlertDialogHeader>
                        <AlertDialogFooter>
                          <AlertDialogCancel>Cancelar</AlertDialogCancel>
                          <AlertDialogAction
                            className="bg-red-600 hover:bg-red-700"
                            onClick={() => deleteItem('tasks', t.id)}
                          >
                            Excluir
                          </AlertDialogAction>
                        </AlertDialogFooter>
                      </AlertDialogContent>
                    </AlertDialog>
                  </div>
                </CardContent>
              </Card>
            )
          })}
        </TabsContent>
        <TabsContent value="calendar">
          <FullCalendar
            items={filtered.map((x) => ({ ...x, date: x.dueDate || '' }))}
            renderItem={(t) => {
              const resp = state.users.find((u) => u.id === t.responsibleId)
              const c = state.cases.find((x) => x.id === t.relatedProcessId)
              const isDone = t.status.toLowerCase() === 'concluída'
              const bgColor = resp?.color || '#cbd5e1'

              return (
                <div
                  key={t.id}
                  onClick={() => handleOpen(t)}
                  className={`text-[10px] p-1.5 border rounded mb-1 cursor-pointer hover:opacity-90 bg-white ${isDone ? 'opacity-50' : ''}`}
                  style={{
                    backgroundColor: `${bgColor}20`,
                    borderLeftWidth: '3px',
                    borderLeftColor: bgColor,
                    borderColor: `${bgColor}40`,
                  }}
                >
                  <div className="font-bold flex justify-between items-start gap-1">
                    <span
                      className={`truncate ${isDone ? 'line-through text-muted-foreground' : ''}`}
                    >
                      {t.type}
                    </span>{' '}
                    {resp && (
                      <span
                        className="text-[8px] px-1 py-0.5 rounded truncate max-w-[50px] shrink-0"
                        style={{ backgroundColor: bgColor, color: '#fff' }}
                        title={resp.name}
                      >
                        {resp.name.split(' ')[0]}
                      </span>
                    )}
                  </div>
                  <div
                    className={`truncate mt-0.5 font-medium ${isDone ? 'line-through text-muted-foreground' : 'text-muted-foreground'}`}
                    title={c?.number || t.title}
                  >
                    {c?.number || t.title}
                  </div>
                </div>
              )
            }}
          />
        </TabsContent>
      </Tabs>
    </div>
  )
}
