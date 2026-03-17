import { useState, useMemo } from 'react'
import { Link } from 'react-router-dom'
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
import {
  Plus,
  Gift,
  Video,
  Edit,
  LayoutGrid,
  List,
  Filter,
  MapPin,
  Calendar,
  RefreshCw,
} from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { FullCalendar } from '@/components/FullCalendar'
import { AppointmentDialog } from '@/components/AppointmentDialog'
import { Badge } from '@/components/ui/badge'
import { parseSafeLocalDate, getPriorityColorClass } from '@/lib/utils'
import { toast } from '@/hooks/use-toast'

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
  const [isSyncing, setIsSyncing] = useState(false)

  const sortedUsers = [...state.users].sort((a, b) => a.name.localeCompare(b.name))
  const sortedClients = [...state.clients].sort((a, b) => a.name.localeCompare(b.name))
  const sortedCases = [...state.cases].sort((a, b) => a.number.localeCompare(b.number))
  const sortedTypes = [...(state.settings.appointmentTypes || [])].sort((a, b) =>
    a.localeCompare(b),
  )

  const handleOpen = (item?: any) => {
    // If it's a virtual birthday, open the client profile instead of an appointment dialog
    if (item?.itemType === 'birthday') {
      window.location.href = `/clientes/${item.clientId}`
      return
    }
    setEditingItem(item || null)
    setOpen(true)
  }

  const handleSave = (fd: any) => {
    if (editingItem) updateItem('appointments', editingItem.id, fd)
    else addAppointment(fd)
  }

  const handleGoogleSync = () => {
    setIsSyncing(true)
    toast({
      title: 'Conectando ao Google...',
      description: 'Iniciando autorização com Google Agenda.',
    })

    // Simulating OAuth flow and sync delay
    setTimeout(() => {
      setIsSyncing(false)
      toast({
        title: 'Sincronização Concluída',
        description: 'Sua agenda foi vinculada e sincronizada com o Google Agenda com sucesso.',
      })
    }, 2000)
  }

  const allItems = useMemo(() => {
    const currentYear = new Date().getFullYear()
    const virtualBirthdays: any[] = []

    state.clients.forEach((client) => {
      if (client.birthday) {
        const parts = client.birthday.split('T')[0].split('-')
        if (parts.length === 3) {
          const m = parts[1]
          const d = parts[2]
          const isLeapDay = m === '02' && d === '29'

          for (let y = currentYear - 2; y <= currentYear + 5; y++) {
            let ny = y
            let nm = m
            let nd = d
            if (isLeapDay && !((ny % 4 === 0 && ny % 100 !== 0) || ny % 400 === 0)) {
              nd = '28'
            }
            virtualBirthdays.push({
              id: `bday-${client.id}-${ny}`,
              title: `Aniversário: ${client.name}`,
              date: `${ny}-${nm}-${nd}`,
              time: '08:00',
              type: 'Aniversário',
              priority: 'Baixa',
              responsibleId: client.responsibleId,
              clientId: client.id,
              processId: null,
              itemType: 'birthday',
              client: client,
            })
          }
        }
      }
    })

    return [
      ...state.appointments.map((a) => ({
        ...a,
        itemType: 'appointment',
        client: state.clients.find((c) => c.id === a.clientId),
      })),
      ...virtualBirthdays,
    ].sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime())
  }, [state.appointments, state.clients])

  const filtered = allItems.filter((i) => {
    const mSearch = i.title.toLowerCase().includes(search.toLowerCase())
    const mType =
      typeFilter === 'Todos' || (typeFilter === 'Vazio' ? !i.type : i.type === typeFilter)
    const mPriority =
      priorityFilter === 'Todos' ||
      (priorityFilter === 'Vazio' ? !(i as any).priority : (i as any).priority === priorityFilter)
    const mResp =
      respFilter === 'Todos' ||
      (respFilter === 'Vazio' ? !(i as any).responsibleId : (i as any).responsibleId === respFilter)
    const mClient =
      clientFilter === 'Todos' ||
      (clientFilter === 'Vazio' ? !(i as any).clientId : (i as any).clientId === clientFilter)
    const mProcess =
      processFilter === 'Todos' ||
      (processFilter === 'Vazio' ? !(i as any).processId : (i as any).processId === processFilter)

    if (respFilter !== 'Todos' && respFilter !== 'Vazio' && i.type === 'Aniversário') return false

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
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Agenda</h1>
          <p className="text-muted-foreground">Gerencie seus compromissos e eventos.</p>
        </div>
        <div className="flex gap-2 w-full sm:w-auto">
          <Button
            variant="outline"
            onClick={handleGoogleSync}
            disabled={isSyncing}
            className="flex-1 sm:flex-none"
          >
            {isSyncing ? (
              <RefreshCw className="mr-2 h-4 w-4 animate-spin" />
            ) : (
              <Calendar className="mr-2 h-4 w-4" />
            )}
            Sincronizar Google Agenda
          </Button>
          <Button onClick={() => handleOpen()} className="flex-1 sm:flex-none">
            <Plus className="mr-2 h-4 w-4" /> Novo Compromisso
          </Button>
        </div>
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
        <div className="flex flex-col md:flex-row justify-between items-start md:items-center mb-4 gap-4">
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
                      <SelectItem value="Vazio">Não Informado (Vazio)</SelectItem>
                      <SelectItem value="Aniversário">Aniversário</SelectItem>
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
                      <SelectItem value="Vazio">Não Informado (Vazio)</SelectItem>
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
                <div className="space-y-2">
                  <Label className="text-xs">Processo</Label>
                  <Select value={processFilter} onValueChange={setProcessFilter}>
                    <SelectTrigger>
                      <SelectValue placeholder="Processo" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Todos">Todos</SelectItem>
                      <SelectItem value="Vazio">Sem Processo (Vazio)</SelectItem>
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
          <TabsList className="w-full md:w-auto">
            <TabsTrigger value="list" className="flex-1 md:flex-none">
              <List className="h-4 w-4 mr-2" /> Lista
            </TabsTrigger>
            <TabsTrigger value="calendar" className="flex-1 md:flex-none">
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
              const isAudience = item.type === 'Aud.conciliação' || item.type === 'AIJ'
              const bgColor = isFeriado ? '#ef4444' : resp?.color || '#cbd5e1'

              return (
                <div
                  key={item.id}
                  onClick={(e) => {
                    e.stopPropagation()
                    handleOpen(item)
                  }}
                  className={`text-[10px] p-1.5 flex flex-col rounded cursor-pointer mb-1 truncate ${isFeriado ? 'text-white font-bold' : ''}`}
                  style={{
                    backgroundColor: isFeriado ? bgColor : `${bgColor}20`,
                    borderLeft: `3px solid ${bgColor}`,
                    color: isFeriado ? '#fff' : '#333',
                  }}
                  title={item.title}
                >
                  <div className="flex justify-between items-start gap-1 w-full">
                    <span className="font-semibold shrink-0 flex items-center gap-1">
                      {(item as any).time}
                      {isAudience && (item as any).modality === 'Presencial' && (
                        <MapPin className="h-2.5 w-2.5 text-green-600" title="Presencial" />
                      )}
                      {isAudience && (item as any).modality === 'Virtual' && (
                        <Video className="h-2.5 w-2.5 text-purple-600" title="Virtual" />
                      )}
                    </span>
                    {!isFeriado && resp && (
                      <span
                        className="text-[8px] px-1 py-0.5 rounded truncate max-w-[60px]"
                        style={{ backgroundColor: bgColor, color: '#fff' }}
                        title={resp.name}
                      >
                        {resp.name.split(' ')[0]}
                      </span>
                    )}
                  </div>
                  <span className="truncate mt-0.5">{item.title}</span>
                </div>
              )
            }}
          />
        </TabsContent>

        <TabsContent value="list" className="grid gap-3">
          {filtered.map((a: any) => {
            const resp = state.users.find((u) => u.id === a.responsibleId)
            const client = state.clients.find((c) => c.id === a.clientId)
            const process = state.cases.find((c) => c.id === a.processId)
            const localDate = parseSafeLocalDate(a.date)
            const isAudience = a.type === 'Aud.conciliação' || a.type === 'AIJ'

            return (
              <Card
                key={a.id}
                className="shadow-sm hover:border-primary/50 cursor-pointer"
                onClick={() => handleOpen(a)}
              >
                <CardContent className="p-4 flex justify-between items-center">
                  <div className="flex items-center gap-4 w-full">
                    <div className="text-center bg-muted p-2 rounded-lg min-w-[70px]">
                      <p className="text-xs font-bold uppercase">
                        {localDate.toLocaleDateString('pt-BR', { month: 'short' })}
                      </p>
                      <p className="text-xl font-black text-primary">{localDate.getDate()}</p>
                    </div>
                    <div className="flex-1 w-full">
                      <div className="font-bold text-lg flex items-center gap-2 flex-wrap">
                        {a.title}
                        {a.type === 'Reunião' && <Video className="h-4 w-4 text-blue-500" />}
                        {a.type === 'Aniversário' && <Gift className="h-4 w-4 text-pink-500" />}
                        {isAudience && a.modality === 'Presencial' && (
                          <MapPin className="h-4 w-4 text-green-600" title="Presencial" />
                        )}
                        {isAudience && a.modality === 'Virtual' && (
                          <Video className="h-4 w-4 text-purple-600" title="Virtual" />
                        )}
                        <Badge variant="outline">{a.type}</Badge>
                        {a.modality && (
                          <Badge variant="secondary" className="bg-muted text-muted-foreground">
                            {a.modality}
                          </Badge>
                        )}
                      </div>
                      <p className="text-sm text-muted-foreground mt-1 flex items-center gap-2 flex-wrap">
                        <span>Horário: {a.time}</span>
                        {a.type !== 'Aniversário' && (
                          <Badge
                            variant="outline"
                            className={`text-[10px] ${getPriorityColorClass(a.priority)}`}
                          >
                            {a.priority || 'Sem prioridade'}
                          </Badge>
                        )}
                        {resp && (
                          <span
                            className="text-xs px-2 py-0.5 rounded-full font-medium ml-auto"
                            style={{
                              backgroundColor: `${resp.color}20`,
                              color: resp.color,
                              border: `1px solid ${resp.color}40`,
                            }}
                          >
                            Resp: {resp.name}
                          </span>
                        )}
                      </p>
                      <p className="text-xs text-muted-foreground mt-1">
                        Cliente: {client?.name || 'Não vinculado'}
                        {process && (
                          <span>
                            {' '}
                            • Proc:{' '}
                            <Link
                              to={`/processos/${process.id}`}
                              onClick={(e) => e.stopPropagation()}
                              className="hover:underline text-primary"
                            >
                              {process.number}
                            </Link>
                          </span>
                        )}
                      </p>
                    </div>
                  </div>
                  {a.type !== 'Aniversário' && (
                    <Button variant="ghost" size="icon" className="ml-2">
                      <Edit className="h-4 w-4" />
                    </Button>
                  )}
                </CardContent>
              </Card>
            )
          })}
        </TabsContent>
      </Tabs>
    </div>
  )
}
