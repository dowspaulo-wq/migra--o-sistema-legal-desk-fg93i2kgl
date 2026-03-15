import { useState, useEffect } from 'react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Calendar } from '@/components/ui/calendar'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { LayoutList, CalendarDays, Plus, Trash } from 'lucide-react'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'

export default function Tasks() {
  const { state, updateItem, deleteItem } = useLegalStore()
  const urlParams = new URLSearchParams(window.location.search)

  const [view, setView] = useState('list')
  const [filterResp, setFilterResp] = useState(urlParams.get('resp') || 'all')
  const [filterStatus, setFilterStatus] = useState(urlParams.get('status') || 'all')
  const [date, setDate] = useState<Date | undefined>(new Date())

  const getPriorityColor = (p: string) =>
    p === 'Urgente'
      ? 'bg-red-500 text-white'
      : p === 'Alta'
        ? 'bg-orange-400 text-white'
        : 'bg-blue-400 text-white'
  const getStatusColor = (s: string) =>
    s === 'Concluída'
      ? 'border-green-500 text-green-700 bg-green-50'
      : s === 'Aguarda protocolo'
        ? 'border-red-500 text-red-700 bg-red-50 animate-pulse'
        : 'border-slate-300'

  const filteredTasks = state.tasks.filter(
    (t) =>
      (filterResp === 'all' || t.responsibleId === filterResp) &&
      (filterStatus === 'all' || t.status === filterStatus),
  )

  const toggleTaskStatus = (id: string) => {
    const t = state.tasks.find((x) => x.id === id)
    if (t) updateItem('tasks', id, { status: t.status === 'Concluída' ? 'Pendente' : 'Concluída' })
  }

  const handleDeleteTask = (id: string) => {
    if (state.currentUser.role !== 'Admin')
      return toast({
        title: 'Acesso Negado',
        description: 'Apenas admins podem excluir.',
        variant: 'destructive',
      })
    deleteItem('tasks', id)
  }

  return (
    <div className="space-y-6 h-full flex flex-col">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Tarefas</h1>
          <p className="text-muted-foreground">Controle de prazos e atividades.</p>
        </div>
        <Button>
          <Plus className="mr-2 h-4 w-4" /> Nova Tarefa
        </Button>
      </div>

      <div className="flex flex-wrap gap-4 items-center bg-slate-50 p-2 rounded-lg border">
        <Select value={filterResp} onValueChange={setFilterResp}>
          <SelectTrigger className="w-[180px] bg-white">
            <SelectValue placeholder="Responsável" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Todos Responsáveis</SelectItem>
            {state.users.map((u) => (
              <SelectItem key={u.id} value={u.id}>
                {u.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Select value={filterStatus} onValueChange={setFilterStatus}>
          <SelectTrigger className="w-[180px] bg-white">
            <SelectValue placeholder="Status" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Todos Status</SelectItem>
            <SelectItem value="Pendente">Pendente</SelectItem>
            <SelectItem value="Aguarda protocolo">Aguarda protocolo</SelectItem>
            <SelectItem value="Concluída">Concluída</SelectItem>
          </SelectContent>
        </Select>
        <Tabs value={view} onValueChange={setView} className="ml-auto">
          <TabsList>
            <TabsTrigger value="list">
              <LayoutList className="h-4 w-4 mr-2" /> Lista
            </TabsTrigger>
            <TabsTrigger value="calendar">
              <CalendarDays className="h-4 w-4 mr-2" /> Calendário
            </TabsTrigger>
          </TabsList>
        </Tabs>
      </div>

      {view === 'list' ? (
        <div className="grid gap-3">
          {filteredTasks.map((t) => {
            const resp = state.users.find((u) => u.id === t.responsibleId)
            return (
              <Card
                key={t.id}
                className={`shadow-sm border-l-4 ${t.status === 'Concluída' ? 'opacity-60 border-l-green-500' : 'border-l-primary'}`}
              >
                <CardContent className="p-4 flex items-center justify-between gap-4">
                  <div className="flex items-center gap-4">
                    <input
                      type="checkbox"
                      className="h-5 w-5 rounded border-slate-300 text-primary cursor-pointer"
                      checked={t.status === 'Concluída'}
                      onChange={() => toggleTaskStatus(t.id)}
                    />
                    <div>
                      <p
                        className={`font-semibold ${t.status === 'Concluída' ? 'line-through' : ''}`}
                      >
                        {t.title}
                      </p>
                      <div className="flex gap-2 text-xs mt-1 items-center">
                        <Badge className={`${getPriorityColor(t.priority)} text-[10px]`}>
                          {t.priority}
                        </Badge>
                        <Badge
                          variant="outline"
                          className={`${getStatusColor(t.status)} text-[10px]`}
                        >
                          {t.status}
                        </Badge>
                        <span className="text-muted-foreground ml-2">
                          Vence:{' '}
                          <strong
                            className={
                              new Date(t.dueDate) < new Date() && t.status !== 'Concluída'
                                ? 'text-red-500'
                                : ''
                            }
                          >
                            {new Date(t.dueDate).toLocaleDateString('pt-BR')}
                          </strong>
                        </span>
                      </div>
                    </div>
                  </div>
                  <div className="flex items-center gap-4">
                    <div className="text-xs text-right text-muted-foreground">
                      Resp: {resp?.name}
                    </div>
                    {state.currentUser.role === 'Admin' && (
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8 text-destructive hover:bg-destructive/10"
                        onClick={() => handleDeleteTask(t.id)}
                      >
                        <Trash className="h-4 w-4" />
                      </Button>
                    )}
                  </div>
                </CardContent>
              </Card>
            )
          })}
          {filteredTasks.length === 0 && (
            <p className="text-center py-8 text-muted-foreground">
              Nenhuma tarefa encontrada para os filtros aplicados.
            </p>
          )}
        </div>
      ) : (
        <div className="flex flex-col md:flex-row gap-6">
          <Card className="p-4 flex-shrink-0 h-fit flex justify-center">
            <Calendar
              mode="single"
              selected={date}
              onSelect={setDate}
              className="rounded-md border shadow"
            />
          </Card>
          <Card className="flex-1 p-4 space-y-3 bg-slate-50">
            <h3 className="font-bold border-b pb-2 text-slate-700">
              Tarefas do Dia - {date?.toLocaleDateString('pt-BR')}
            </h3>
            {filteredTasks
              .filter((t) => t.dueDate === date?.toISOString().split('T')[0])
              .map((t) => {
                const resp = state.users.find((u) => u.id === t.responsibleId)
                return (
                  <div
                    key={t.id}
                    className="p-3 border rounded-md bg-white shadow-sm flex justify-between items-center"
                    style={{ borderLeftColor: resp?.color || '#ccc', borderLeftWidth: 4 }}
                  >
                    <div>
                      <p className="font-semibold text-sm">{t.title}</p>
                      <p className="text-xs text-muted-foreground">
                        Resp: {resp?.name} • Status: {t.status}
                      </p>
                    </div>
                  </div>
                )
              })}
            {filteredTasks.filter((t) => t.dueDate === date?.toISOString().split('T')[0]).length ===
              0 && (
              <p className="text-sm text-muted-foreground">Nenhuma tarefa no dia selecionado.</p>
            )}
          </Card>
        </div>
      )}
    </div>
  )
}
