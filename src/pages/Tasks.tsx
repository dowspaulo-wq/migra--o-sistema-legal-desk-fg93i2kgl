import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
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
import { Plus, Trash, Edit, LayoutGrid, List, CheckCircle2, Circle, Filter } from 'lucide-react'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import useLegalStore from '@/stores/useLegalStore'
import { TaskDialog } from '@/components/TaskDialog'
import { FullCalendar } from '@/components/FullCalendar'
import { formatSafeLocalDate } from '@/lib/utils'

export default function Tasks() {
  const { state, updateItem, deleteItem, addTask } = useLegalStore()
  const [open, setOpen] = useState(false)
  const [editingItem, setEditingItem] = useState<any>(null)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('Todos')
  const [typeFilter, setTypeFilter] = useState('Todos')
  const [priorityFilter, setPriorityFilter] = useState('Todos')
  const [respFilter, setRespFilter] = useState('Todos')
  const [clientFilter, setClientFilter] = useState('Todos')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')

  const sortedUsers = [...state.users].sort((a, b) => a.name.localeCompare(b.name))
  const sortedClients = [...state.clients].sort((a, b) => a.name.localeCompare(b.name))
  const sortedTypes = [...(state.settings.taskTypes || [])].sort((a, b) => a.localeCompare(b))
  const sortedStatuses = [...(state.settings.taskStatuses || [])].sort((a, b) => a.localeCompare(b))

  const filtered = state.tasks.filter((t) => {
    const mSearch = t.title.toLowerCase().includes(search.toLowerCase())
    const mStatus = statusFilter === 'Todos' || t.status === statusFilter
    const mType = typeFilter === 'Todos' || t.type === typeFilter
    const mPriority = priorityFilter === 'Todos' || t.priority === priorityFilter
    const mResp = respFilter === 'Todos' || t.responsibleId === respFilter
    const mClient = clientFilter === 'Todos' || t.clientId === clientFilter

    let mDate = true
    if (dateFrom && dateTo && t.dueDate) {
      mDate = t.dueDate >= dateFrom && t.dueDate <= dateTo
    } else if (dateFrom && t.dueDate) {
      mDate = t.dueDate >= dateFrom
    } else if (dateTo && t.dueDate) {
      mDate = t.dueDate <= dateTo
    }

    return mSearch && mStatus && mType && mPriority && mResp && mClient && mDate
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

      <Card className="shadow-sm">
        <CardContent className="p-4 flex flex-col md:flex-row gap-4 justify-between items-center">
          <div className="flex gap-2 w-full max-w-md">
            <Input
              placeholder="Buscar tarefa..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="flex-1"
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
                      {sortedStatuses.map((s) => (
                        <SelectItem key={s} value={s}>
                          {s}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label className="text-xs">Tipo de Tarefa</Label>
                  <Select value={typeFilter} onValueChange={setTypeFilter}>
                    <SelectTrigger>
                      <SelectValue placeholder="Tipo" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Todos">Todos</SelectItem>
                      {sortedTypes.map((t) => (
                        <SelectItem key={t} value={t}>
                          {t}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label className="text-xs">Prioridade</Label>
                  <Select value={priorityFilter} onValueChange={setPriorityFilter}>
                    <SelectTrigger>
                      <SelectValue placeholder="Prioridade" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Todos">Todos</SelectItem>
                      <SelectItem value="Baixa">Baixa</SelectItem>
                      <SelectItem value="Média">Média</SelectItem>
                      <SelectItem value="Alta">Alta</SelectItem>
                      <SelectItem value="Urgente">Urgente</SelectItem>
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
                    <Label className="text-xs">Vencimento De</Label>
                    <Input
                      type="date"
                      value={dateFrom}
                      onChange={(e) => setDateFrom(e.target.value)}
                    />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-xs">Vencimento Até</Label>
                    <Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
                  </div>
                </div>
                <Button
                  variant="ghost"
                  size="sm"
                  className="w-full mt-2"
                  onClick={() => {
                    setStatusFilter('Todos')
                    setTypeFilter('Todos')
                    setPriorityFilter('Todos')
                    setRespFilter('Todos')
                    setClientFilter('Todos')
                    setDateFrom('')
                    setDateTo('')
                  }}
                >
                  Limpar Filtros
                </Button>
              </PopoverContent>
            </Popover>
          </div>
        </CardContent>
      </Card>

      <Tabs defaultValue="list">
        <div className="flex justify-end mb-4">
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
                  <div className="flex items-start gap-4">
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
                        Proc:{' '}
                        {c ? (
                          <Link to={`/processos/${c.id}`} className="hover:underline text-primary">
                            {c.number}
                          </Link>
                        ) : (
                          'Não vinculado'
                        )}
                      </p>
                      <div className="flex flex-wrap gap-2 text-xs mt-2 items-center">
                        <Badge variant="secondary" className="text-[10px]">
                          {t.status}
                        </Badge>
                        <Badge className="text-[10px]">{t.priority}</Badge>
                        <span className="text-muted-foreground ml-2 font-semibold">
                          Vence: {formatSafeLocalDate(t.dueDate)}
                        </span>
                        {resp && (
                          <span className="text-muted-foreground ml-auto flex items-center gap-1 bg-slate-100 px-2 py-0.5 rounded-full">
                            Resp:{' '}
                            <span className="font-medium text-slate-700">
                              {resp.name.split(' ')[0]}
                            </span>
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
                    {state.currentUser.role === 'Admin' && (
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
                    )}
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
              return (
                <div
                  key={t.id}
                  onClick={() => handleOpen(t)}
                  className="text-[10px] p-1.5 border rounded mb-1 cursor-pointer hover:border-primary/50 bg-white"
                  style={{ borderLeftWidth: '3px', borderLeftColor: resp?.color || '#000' }}
                >
                  <div className="font-bold flex justify-between items-start gap-1">
                    <span className="truncate">{t.type}</span>{' '}
                    <span
                      className="text-[8px] text-white px-1 py-0.5 rounded truncate max-w-[50px] shrink-0"
                      style={{ backgroundColor: resp?.color || '#64748b' }}
                      title={resp?.name}
                    >
                      {resp?.name.split(' ')[0] || 'N/A'}
                    </span>
                  </div>
                  <div
                    className="truncate mt-0.5 text-muted-foreground"
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
