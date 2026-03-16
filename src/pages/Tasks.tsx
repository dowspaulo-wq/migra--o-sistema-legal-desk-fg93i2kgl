import { useState } from 'react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Plus, Trash, Edit, LayoutGrid, List, CheckCircle2, Circle } from 'lucide-react'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import useLegalStore from '@/stores/useLegalStore'
import { TaskDialog } from '@/components/TaskDialog'
import { FullCalendar } from '@/components/FullCalendar'

export default function Tasks() {
  const { state, updateItem, deleteItem, addTask } = useLegalStore()
  const [open, setOpen] = useState(false)
  const [editingItem, setEditingItem] = useState<any>(null)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('Todos')

  const filtered = state.tasks.filter((t) => {
    const mSearch = t.title.toLowerCase().includes(search.toLowerCase())
    const mStatus = statusFilter === 'Todos' || t.status === statusFilter
    return mSearch && mStatus
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
          <div className="flex gap-4 w-full max-w-md">
            <Input
              placeholder="Buscar tarefa..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="flex-1"
            />
            <Select value={statusFilter} onValueChange={setStatusFilter}>
              <SelectTrigger className="w-[150px]">
                <SelectValue placeholder="Status" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="Todos">Todos</SelectItem>
                {state.settings.taskStatuses?.map((s) => (
                  <SelectItem key={s} value={s}>
                    {s}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
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
                    <div>
                      <p
                        className={`font-bold ${isDone ? 'line-through text-muted-foreground' : ''}`}
                      >
                        {t.title}{' '}
                        <Badge variant="outline" className="ml-2 text-[10px]">
                          {t.type}
                        </Badge>
                      </p>
                      <p className="text-xs text-muted-foreground mt-1">
                        Cliente: <span className="font-medium">{client?.name || 'N/A'}</span> •
                        Proc: {c?.number || 'N/A'}
                      </p>
                      <div className="flex gap-2 text-xs mt-2 items-center">
                        <Badge variant="secondary" className="text-[10px]">
                          {t.status}
                        </Badge>
                        <Badge className="text-[10px]">{t.priority}</Badge>
                        <span className="text-muted-foreground ml-2 font-semibold">
                          Vence: {new Date(t.dueDate).toLocaleDateString('pt-BR')}
                        </span>
                      </div>
                    </div>
                  </div>
                  <div className="flex gap-2">
                    <Button variant="ghost" size="icon" onClick={() => handleOpen(t)}>
                      <Edit className="h-4 w-4" />
                    </Button>
                    {state.currentUser.role === 'Admin' && (
                      <Button
                        variant="ghost"
                        size="icon"
                        className="text-red-500"
                        onClick={() => deleteItem('tasks', t.id)}
                      >
                        <Trash className="h-4 w-4" />
                      </Button>
                    )}
                  </div>
                </CardContent>
              </Card>
            )
          })}
        </TabsContent>
        <TabsContent value="calendar">
          <FullCalendar
            items={filtered.map((x) => ({ ...x, date: x.dueDate }))}
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
                  <div className="font-bold flex justify-between">
                    <span>{t.type}</span>{' '}
                    <span className="text-muted-foreground bg-muted px-1 rounded">
                      {resp?.name.substring(0, 2).toUpperCase()}
                    </span>
                  </div>
                  <div className="truncate mt-0.5 text-muted-foreground">
                    {c?.number || 'Sem processo'}
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
