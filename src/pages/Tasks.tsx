import { useState } from 'react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Calendar } from '@/components/ui/calendar'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { LayoutList, CalendarDays, Plus, Search } from 'lucide-react'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import useLegalStore from '@/stores/useLegalStore'

export default function Tasks() {
  const { state, setState, addTask } = useLegalStore()
  const [view, setView] = useState('list')
  const [filterResp, setFilterResp] = useState('all')
  const [date, setDate] = useState<Date | undefined>(new Date())

  const urlParams = new URLSearchParams(window.location.search)
  const respParam = urlParams.get('resp')
  if (respParam && filterResp === 'all') setFilterResp(respParam)

  const getPriorityColor = (p: string) => {
    switch (p) {
      case 'Urgente':
        return 'bg-red-500 text-white'
      case 'Alta':
        return 'bg-orange-400 text-white'
      case 'Média':
        return 'bg-blue-400 text-white'
      default:
        return 'bg-slate-300 text-slate-800'
    }
  }

  const getStatusColor = (s: string) => {
    if (s === 'Concluída') return 'border-green-500 text-green-700 bg-green-50'
    if (s === 'Aguarda protocolo') return 'border-red-500 text-red-700 bg-red-50 animate-pulse'
    return 'border-slate-300'
  }

  const filteredTasks = state.tasks.filter(
    (t) => filterResp === 'all' || t.responsibleId === filterResp,
  )

  const toggleTaskStatus = (id: string) => {
    setState((prev) => ({
      ...prev,
      tasks: prev.tasks.map((t) =>
        t.id === id ? { ...t, status: t.status === 'Concluída' ? 'Pendente' : 'Concluída' } : t,
      ),
    }))
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

      <div className="flex gap-4 items-center bg-slate-50 p-2 rounded-lg border">
        <Select value={filterResp} onValueChange={setFilterResp}>
          <SelectTrigger className="w-[200px] bg-white">
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
            const resp = state.users.find((u) => u.id === t.responsibleId)?.name
            return (
              <Card
                key={t.id}
                className={`shadow-sm border-l-4 ${t.status === 'Concluída' ? 'opacity-60 border-l-green-500' : 'border-l-primary'}`}
              >
                <CardContent className="p-4 flex items-center justify-between gap-4">
                  <div className="flex items-center gap-4">
                    <input
                      type="checkbox"
                      className="h-5 w-5 rounded border-slate-300 text-primary focus:ring-primary cursor-pointer"
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
                  <div className="text-xs text-right text-muted-foreground">Resp: {resp}</div>
                </CardContent>
              </Card>
            )
          })}
        </div>
      ) : (
        <Card className="p-4 flex justify-center">
          <Calendar
            mode="single"
            selected={date}
            onSelect={setDate}
            className="rounded-md border shadow"
          />
        </Card>
      )}
    </div>
  )
}
