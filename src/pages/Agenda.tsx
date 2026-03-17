import { useState } from 'react'
import { Card, CardContent } from '@/components/ui/card'
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
import { Plus, Gift, Video, Edit, LayoutGrid, List, Filter } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { FullCalendar } from '@/components/FullCalendar'
import { AppointmentDialog } from '@/components/AppointmentDialog'
import { Badge } from '@/components/ui/badge'

export default function Agenda() {
  const { state, addAppointment, updateItem } = useLegalStore()
  const [open, setOpen] = useState(false)
  const [editingItem, setEditingItem] = useState<any>(null)
  const [search, setSearch] = useState('')
  const [typeFilter, setTypeFilter] = useState('Todos')
  const [priorityFilter, setPriorityFilter] = useState('Todos')
  const [respFilter, setRespFilter] = useState('Todos')
  const [clientFilter, setClientFilter] = useState('Todos')
  const [processFilter, setProcessFilter] = useState('Todos')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')

  const sortedUsers = [...state.users].sort((a, b) => a.name.localeCompare(b.name))
  const sortedClients = [...state.clients].sort((a, b) => a.name.localeCompare(b.name))
  const sortedCases = [...state.cases].sort((a, b) => a.number.localeCompare(b.number))
  const sortedTypes = [...(state.settings.appointmentTypes || [])].sort((a, b) =>
    a.localeCompare(b),
  )

  const handleOpen = (item?: any) => {
    setEditingItem(item || null)
    setOpen(true)
  }

  const handleSave = (fd: any) => {
    if (editingItem) updateItem('appointments', editingItem.id, fd)
    else addAppointment(fd)
  }

  // Helper to safely parse YYYY-MM-DD avoiding timezone offsets
  const parseLocalDate = (dateStr: string) => {
    if (!dateStr) return new Date()
    const [y, m, d] = dateStr.split('T')[0].split('-')
    return new Date(Number(y), Number(m) - 1, Number(d))
  }

  const allItems = state.appointments.map((a) => ({
    ...a,
    itemType: a.type === 'Aniversário' ? ('birthday' as const) : ('appointment' as const),
    client: state.clients.find((c) => c.id === a.clientId),
  }))

  const filtered = allItems.filter((i) => {
    const mSearch = i.title.toLowerCase().includes(search.toLowerCase())
    const mType = typeFilter === 'Todos' || i.type === typeFilter
    const mPriority = priorityFilter === 'Todos' || (i as any).priority === priorityFilter
    const mResp = respFilter === 'Todos' || (i as any).responsibleId === respFilter
    const mClient = clientFilter === 'Todos' || (i as any).clientId === clientFilter
    const mProcess = processFilter === 'Todos' || (i as any).processId === processFilter

    let mDate = true
    const itemDate = i.date.split('T')[0]
    if (dateFrom && dateTo) {
      mDate = itemDate >= dateFrom && itemDate <= dateTo
    } else if (dateFrom) {
      mDate = itemDate >= dateFrom
    } else if (dateTo) {
      mDate = itemDate <= dateTo
    }

    return mSearch && mType && mPriority && mResp && mClient && mProcess && mDate
  })

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Agenda</h1>
          <p className="text-muted-foreground">Gerencie seus compromissos e eventos.</p>
        </div>
        <Button onClick={() => handleOpen()}>
          <Plus className="mr-2 h-4 w-4" /> Novo Compromisso
        </Button>
      </div>

      <AppointmentDialog
        open={open}
        onOpenChange={setOpen}
        data={editingItem}
        onSave={handleSave}
        users={state.users}
        clients={state.clients}
        cases={state.cases}
        settings={state.settings}
      />

      <Tabs defaultValue="calendar">
        <div className="flex justify-between items-center mb-4">
          <div className="flex gap-2 w-full max-w-md">
            <Input
              placeholder="Buscar evento..."
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
                  <Label className="text-xs">Tipo de Compromisso</Label>
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
                <div className="space-y-2">
                  <Label className="text-xs">Processo</Label>
                  <Select value={processFilter} onValueChange={setProcessFilter}>
                    <SelectTrigger>
                      <SelectValue placeholder="Processo" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Todos">Todos</SelectItem>
                      {sortedCases.map((c) => (
                        <SelectItem key={c.id} value={c.id}>
                          {c.number}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="grid grid-cols-2 gap-2">
                  <div className="space-y-2">
                    <Label className="text-xs">Data De</Label>
                    <Input
                      type="date"
                      value={dateFrom}
                      onChange={(e) => setDateFrom(e.target.value)}
                    />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-xs">Data Até</Label>
                    <Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
                  </div>
                </div>
                <Button
                  variant="ghost"
                  size="sm"
                  className="w-full mt-2"
                  onClick={() => {
                    setTypeFilter('Todos')
                    setPriorityFilter('Todos')
                    setRespFilter('Todos')
                    setClientFilter('Todos')
                    setProcessFilter('Todos')
                    setDateFrom('')
                    setDateTo('')
                  }}
                >
                  Limpar Filtros
                </Button>
              </PopoverContent>
            </Popover>
          </div>
          <TabsList>
            <TabsTrigger value="list">
              <List className="h-4 w-4 mr-2" /> Lista
            </TabsTrigger>
            <TabsTrigger value="calendar">
              <LayoutGrid className="h-4 w-4 mr-2" /> Calendário
            </TabsTrigger>
          </TabsList>
        </div>

        <TabsContent value="calendar">
          <FullCalendar
            items={filtered}
            onDayClick={() => {}}
            renderItem={(item) => {
              if (item.type === 'Aniversário')
                return (
                  <div
                    key={item.id}
                    onClick={(e) => {
                      e.stopPropagation()
                      handleOpen(item)
                    }}
                    className="text-[10px] p-1 bg-pink-100 text-pink-800 border border-pink-200 rounded flex items-center gap-1 mb-1 truncate cursor-pointer hover:bg-pink-200"
                    title={item.title}
                  >
                    <Gift className="h-3 w-3 shrink-0" />{' '}
                    {item.client?.name.split(' ')[0] || item.title.replace('Aniversário: ', '')}
                  </div>
                )
              const resp = state.users.find((u) => u.id === (item as any).responsibleId)
              const isFeriado = item.type === 'Feriado'
              return (
                <div
                  key={item.id}
                  onClick={(e) => {
                    e.stopPropagation()
                    handleOpen(item)
                  }}
                  className={`text-[10px] p-1 rounded cursor-pointer mb-1 truncate ${isFeriado ? 'bg-red-500 text-white font-bold' : ''}`}
                  style={
                    !isFeriado
                      ? {
                          backgroundColor: `${resp?.color}20`,
                          borderLeft: `3px solid ${resp?.color}`,
                          color: '#333',
                        }
                      : {}
                  }
                  title={item.title}
                >
                  <span className="font-semibold">{(item as any).time}</span> - {item.title}
                </div>
              )
            }}
          />
        </TabsContent>

        <TabsContent value="list" className="grid gap-3">
          {filtered.map((a: any) => {
            const resp = state.users.find((u) => u.id === a.responsibleId)
            const client = state.clients.find((c) => c.id === a.clientId)
            const localDate = parseLocalDate(a.date)

            return (
              <Card
                key={a.id}
                className="shadow-sm hover:border-primary/50 cursor-pointer"
                onClick={() => handleOpen(a)}
              >
                <CardContent className="p-4 flex justify-between items-center">
                  <div className="flex items-center gap-4">
                    <div className="text-center bg-muted p-2 rounded-lg min-w-[70px]">
                      <p className="text-xs font-bold uppercase">
                        {localDate.toLocaleDateString('pt-BR', { month: 'short' })}
                      </p>
                      <p className="text-xl font-black text-primary">{localDate.getDate()}</p>
                    </div>
                    <div>
                      <p className="font-bold text-lg flex items-center gap-2">
                        {a.title}{' '}
                        {a.type === 'Reunião' && <Video className="h-4 w-4 text-blue-500" />}{' '}
                        {a.type === 'Aniversário' && <Gift className="h-4 w-4 text-pink-500" />}{' '}
                        <Badge variant="outline">{a.type}</Badge>
                      </p>
                      <p className="text-sm text-muted-foreground mt-1">
                        Horário: {a.time} • Resp: {resp?.name}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        Cliente: {client?.name || 'Não vinculado'}
                      </p>
                    </div>
                  </div>
                  <Button variant="ghost" size="icon">
                    <Edit className="h-4 w-4" />
                  </Button>
                </CardContent>
              </Card>
            )
          })}
        </TabsContent>
      </Tabs>
    </div>
  )
}
