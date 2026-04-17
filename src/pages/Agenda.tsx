import { useState, useMemo, useEffect } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { Card, CardContent } from '@/components/ui/card'
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
  Gift,
  Video,
  Edit,
  Trash,
  LayoutGrid,
  List,
  Filter,
  MapPin,
  Calendar,
  RefreshCw,
  ChevronUp,
  ChevronDown,
  Search,
  X,
  CheckCircle2,
  Circle,
} from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { FullCalendar } from '@/components/FullCalendar'
import { AppointmentDialog } from '@/components/AppointmentDialog'
import { Badge } from '@/components/ui/badge'
import { parseSafeLocalDate, getPriorityColorClass, normalizeStr } from '@/lib/utils'
import { DatePicker } from '@/components/ui/date-picker'
import { MultiSelect } from '@/components/ui/multi-select'
import { toast } from '@/hooks/use-toast'
import { downloadCSV } from '@/lib/export'
import { Download } from 'lucide-react'
import { supabase } from '@/lib/supabase/client'

const initialFilters = {
  titulo: '',
  tipo: [] as string[],
  modalidade: 'Todos',
  prioridade: 'Todos',
  dataEventoDe: '',
  dataEventoAte: '',
  responsavelId: 'Todos',
  clienteId: 'Todos',
  processoId: 'Todos',
}

export default function Agenda() {
  const { state, addAppointment, updateItem, deleteItem } = useLegalStore()
  const [searchParams, setSearchParams] = useSearchParams()
  const [filters, setFilters] = useState(initialFilters)
  const [appliedFilters, setAppliedFilters] = useState(initialFilters)
  const [quickSearch, setQuickSearch] = useState('')
  const [searchOpen, setSearchOpen] = useState(false)
  const [open, setOpen] = useState(false)
  const [editingItem, setEditingItem] = useState<any>(null)
  const [isSyncing, setIsSyncing] = useState(false)
  const [calendarDate, setCalendarDate] = useState(new Date())

  useEffect(() => {
    if (searchParams.size > 0) {
      const newFilters = { ...initialFilters }
      if (searchParams.has('resp')) newFilters.responsavelId = searchParams.get('resp')!
      if (searchParams.has('dateFrom')) newFilters.dataEventoDe = searchParams.get('dateFrom')!
      if (searchParams.has('dateUntil')) newFilters.dataEventoAte = searchParams.get('dateUntil')!
      if (searchParams.has('type')) newFilters.tipo = searchParams.get('type')!.split(',')

      setFilters(newFilters)
      setAppliedFilters(newFilters)
      setSearchOpen(true)

      setSearchParams({}, { replace: true })
    }
  }, [searchParams, setSearchParams])

  const sortedUsers = [...state.users].sort((a, b) => a.name.localeCompare(b.name))
  const sortedClients = [...state.clients].sort((a, b) => a.name.localeCompare(b.name))
  const sortedCases = [...state.cases].sort((a, b) => a.number.localeCompare(b.number))

  const allTypes = useMemo(() => {
    const types = new Set(['Aniversário', ...(state.settings.appointmentTypes || [])])
    return Array.from(types).sort((a, b) => a.localeCompare(b))
  }, [state.settings.appointmentTypes])

  const handleOpen = (item?: any) => {
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

    setTimeout(() => {
      if ((state.settings as any).googleCalendarTokens) {
        supabase.functions
          .invoke('google-calendar', {
            body: { action: 'sync' },
          })
          .catch((err) => console.error('Erro no auto-sync:', err))
      }
    }, 1500)
  }

  const handleDelete = (item: any) => {
    deleteItem('appointments', item.id)
    if (item.googleEventId && (state.settings as any).googleCalendarTokens) {
      supabase.functions
        .invoke('google-calendar', {
          body: { action: 'deleteEvent', eventId: item.googleEventId },
        })
        .catch((err) => console.error('Erro ao excluir no Google:', err))
    }
  }

  const handleGoogleSync = async () => {
    setIsSyncing(true)
    try {
      if ((state.settings as any).googleCalendarTokens) {
        const { data, error } = await supabase.functions.invoke('google-calendar', {
          body: { action: 'sync' },
        })
        if (error) throw error
        if (data?.error) {
          if (
            data.error.includes('Sessão expirada') ||
            data.error.includes('Conta do Google não conectada')
          ) {
            const redirectUri = `${window.location.origin}/google-callback`
            const { data: authData, error: authError } = await supabase.functions.invoke(
              'google-calendar',
              {
                body: { action: 'getAuthUrl', redirectUri },
              },
            )
            if (authError) throw authError
            if (authData?.error) throw new Error(authData.error)
            if (authData?.url) {
              window.location.href = authData.url
              return
            }
          }
          throw new Error(data.error)
        }

        toast({
          title: 'Sincronização Concluída',
          description: data.message || 'Sua agenda foi sincronizada com o Google Calendar.',
        })

        setTimeout(() => {
          window.location.reload()
        }, 2000)

        setIsSyncing(false)
        return
      }

      const redirectUri = `${window.location.origin}/google-callback`
      const { data, error } = await supabase.functions.invoke('google-calendar', {
        body: { action: 'getAuthUrl', redirectUri },
      })

      if (error) throw error
      if (data?.error) throw new Error(data.error)

      if (data?.url) {
        window.location.href = data.url
      }
    } catch (err: any) {
      toast({
        title: 'Erro de Integração',
        description: err.message || 'Falha ao conectar com Google.',
        variant: 'destructive',
      })
      setIsSyncing(false)
    }
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
              title: `Aniversário`,
              date: `${ny}-${nm}-${nd}`,
              time: '08:00',
              type: 'Aniversário',
              priority: 'Baixa',
              responsibleId: client.responsibleId,
              clientId: client.id,
              processId: null,
              itemType: 'birthday',
              client: client,
              status: 'Pendente',
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
    if (quickSearch && !normalizeStr(i.title).includes(normalizeStr(quickSearch))) return false
    const f = appliedFilters
    if (f.titulo && !normalizeStr(i.title).includes(normalizeStr(f.titulo))) return false
    const itemType = i.type || 'Vazio'
    if (f.tipo.length > 0 && !f.tipo.includes(itemType)) return false
    if (f.modalidade !== 'Todos' && (i as any).modality !== f.modalidade) return false
    if (f.prioridade !== 'Todos' && (i as any).priority !== f.prioridade) return false

    const itemDate = i.date.split('T')[0]
    if (f.dataEventoDe && itemDate < f.dataEventoDe) return false
    if (f.dataEventoAte && itemDate > f.dataEventoAte) return false

    if (f.responsavelId !== 'Todos' && (i as any).responsibleId !== f.responsavelId) return false
    if (f.clienteId !== 'Todos' && (i as any).clientId !== f.clienteId) return false
    if (f.processoId !== 'Todos' && (i as any).processId !== f.processoId) return false

    return true
  })

  const listItems = filtered

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Agenda</h1>
          <p className="text-muted-foreground">Gerencie seus compromissos e eventos.</p>
        </div>
        <div className="flex flex-col sm:flex-row gap-2 w-full sm:w-auto">
          <div className="relative flex-1 sm:w-56">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Pesquisar título..."
              className="pl-8"
              value={quickSearch}
              onChange={(e) => setQuickSearch(e.target.value)}
            />
          </div>
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
            Sincronizar
          </Button>
          <Button
            variant="outline"
            onClick={() => {
              const exportData = filtered.map((a) => {
                const resp = state.users.find((u) => u.id === (a as any).responsibleId)
                const client = state.clients.find((c) => c.id === (a as any).clientId)
                const process = state.cases.find((c) => c.id === (a as any).processId)
                return {
                  Título: a.title,
                  Data: a.date,
                  Hora: (a as any).time || '',
                  Tipo: a.type || '',
                  Modalidade: (a as any).modality || '',
                  Prioridade: (a as any).priority || '',
                  Status: a.status || '',
                  Cliente: client?.name || '',
                  Processo: process?.number || '',
                  Responsável: resp?.name || '',
                  Descrição: (a as any).description || '',
                }
              })
              downloadCSV(exportData, 'agenda.csv')
            }}
            className="flex-1 sm:flex-none shrink-0"
          >
            <Download className="mr-2 h-4 w-4" /> Exportar
          </Button>
          <Button onClick={() => handleOpen()} className="flex-1 sm:flex-none shrink-0">
            <Plus className="mr-2 h-4 w-4" /> Novo Compromisso
          </Button>
        </div>
      </div>

      <AppointmentDialog
        open={open}
        onOpenChange={setOpen}
        data={editingItem}
        onSave={handleSave}
        onDelete={handleDelete}
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
                Título do Compromisso
              </Label>
              <Input
                placeholder="Buscar por título..."
                value={filters.titulo}
                onChange={(e) => setFilters({ ...filters, titulo: e.target.value })}
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">
                Tipo de Compromisso
              </Label>
              <MultiSelect
                options={allTypes}
                values={filters.tipo}
                onChange={(v) => setFilters({ ...filters, tipo: v })}
                placeholder="Todos os tipos"
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">Modalidade</Label>
              <Select
                value={filters.modalidade}
                onValueChange={(v) => setFilters({ ...filters, modalidade: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Todas" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Todos">Todas</SelectItem>
                  <SelectItem value="Presencial">Presencial</SelectItem>
                  <SelectItem value="Virtual">Virtual</SelectItem>
                </SelectContent>
              </Select>
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
              <Label className="text-xs font-semibold text-muted-foreground">
                Data do Evento (De)
              </Label>
              <DatePicker
                value={filters.dataEventoDe}
                onChange={(v) => setFilters({ ...filters, dataEventoDe: v })}
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">
                Data do Evento (Até)
              </Label>
              <DatePicker
                value={filters.dataEventoAte}
                onChange={(v) => setFilters({ ...filters, dataEventoAte: v })}
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
              <Label className="text-xs font-semibold text-muted-foreground">Processo</Label>
              <Select
                value={filters.processoId}
                onValueChange={(v) => setFilters({ ...filters, processoId: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Todos os processos" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Todos">Todos os processos</SelectItem>
                  {sortedCases.map((c) => (
                    <SelectItem key={c.id} value={c.id}>
                      {c.number}
                    </SelectItem>
                  ))}
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

      <Tabs defaultValue="calendar">
        <div className="flex flex-col md:flex-row justify-between items-start md:items-center mb-4 gap-4">
          <p className="text-sm font-medium text-muted-foreground">
            {filtered.length} compromisso(s) encontrado(s)
          </p>
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
            currentDate={calendarDate}
            onDateChange={setCalendarDate}
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
                    title={`${item.title} - ${item.client?.name}`}
                  >
                    <Gift className="h-3 w-3 shrink-0" /> {item.client?.name.split(' ')[0]}
                  </div>
                )
              const resp = state.users.find((u) => u.id === (item as any).responsibleId)
              const isFeriado = item.type === 'Feriado'
              const bgColor = isFeriado ? '#ef4444' : resp?.color || '#cbd5e1'
              const isDone = item.status === 'Concluído'

              const clientName = item.client?.name || 'Sem cliente'
              const respName = resp?.name.split(' ')[0] || ''
              const titleFull = `${item.title} - ${clientName} - ${respName}`

              return (
                <div
                  key={item.id}
                  onClick={(e) => {
                    e.stopPropagation()
                    handleOpen(item)
                  }}
                  className={`text-[10px] p-1.5 flex flex-col rounded cursor-pointer mb-1 truncate ${isFeriado ? 'text-white font-bold' : ''} ${isDone ? 'opacity-60' : ''}`}
                  style={{
                    backgroundColor: isFeriado ? bgColor : `${bgColor}20`,
                    borderLeft: `3px solid ${bgColor}`,
                    color: isFeriado ? '#fff' : '#333',
                  }}
                  title={titleFull}
                >
                  <div className="flex justify-between items-start gap-1 w-full">
                    <span
                      className={`font-semibold shrink-0 flex items-center gap-1 ${isDone ? 'line-through' : ''}`}
                    >
                      {(item as any).time}
                      {(item as any).modality === 'Presencial' && (
                        <MapPin className="h-2.5 w-2.5 text-green-600" title="Presencial" />
                      )}
                      {(item as any).modality === 'Virtual' && (
                        <Video className="h-2.5 w-2.5 text-purple-600" title="Virtual" />
                      )}
                    </span>
                  </div>
                  <span
                    className={`truncate mt-0.5 ${isDone ? 'line-through text-muted-foreground' : ''}`}
                  >
                    {titleFull}
                  </span>
                </div>
              )
            }}
          />
        </TabsContent>

        <TabsContent value="list" className="grid gap-3">
          {listItems.length === 0 ? (
            <div className="text-center p-8 text-muted-foreground bg-muted/20 rounded-lg border border-dashed mt-4">
              Nenhum compromisso encontrado com os filtros atuais.
            </div>
          ) : (
            listItems.map((a: any) => {
              const resp = state.users.find((u) => u.id === a.responsibleId)
              const client = state.clients.find((c) => c.id === a.clientId)
              const process = state.cases.find((c) => c.id === a.processId)
              const localDate = parseSafeLocalDate(a.date)
              const isDone = a.status === 'Concluído'
              const isBirthday = a.type === 'Aniversário'

              return (
                <Card
                  key={a.id}
                  className={`shadow-sm hover:border-primary/50 cursor-pointer ${isDone ? 'opacity-60 border-l-4 border-l-green-500' : 'border-l-4 border-l-primary'}`}
                  onClick={() => handleOpen(a)}
                >
                  <CardContent className="p-4 flex justify-between items-center gap-4">
                    <div className="flex items-start gap-4 w-full">
                      {!isBirthday && (
                        <button
                          onClick={(e) => {
                            e.stopPropagation()
                            updateItem('appointments', a.id, {
                              status: isDone ? 'Pendente' : 'Concluído',
                            })
                          }}
                          className="mt-1 text-muted-foreground hover:text-primary transition-colors"
                        >
                          {isDone ? (
                            <CheckCircle2 className="h-5 w-5 text-green-500" />
                          ) : (
                            <Circle className="h-5 w-5" />
                          )}
                        </button>
                      )}

                      <div className="text-center bg-muted p-2 rounded-lg min-w-[70px]">
                        <p className="text-xs font-bold uppercase">
                          {localDate.toLocaleDateString('pt-BR', { month: 'short' })}
                        </p>
                        <p className="text-xl font-black text-primary">{localDate.getDate()}</p>
                      </div>

                      <div className="flex-1 w-full">
                        <div
                          className={`font-bold text-lg flex items-center gap-2 flex-wrap ${isDone ? 'line-through text-muted-foreground' : ''}`}
                        >
                          {a.title}
                          {isBirthday && <Gift className="h-4 w-4 text-pink-500" />}
                          {a.modality === 'Presencial' && (
                            <MapPin className="h-4 w-4 text-green-600" title="Presencial" />
                          )}
                          {a.modality === 'Virtual' && (
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
                          {!isBirthday && (
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
                          Cliente:{' '}
                          <span className="font-medium">{client?.name || 'Não vinculado'}</span>
                          {process && (
                            <span>
                              {' '}
                              • Proc:{' '}
                              <Link
                                to={`/processos/${process.id}`}
                                onClick={(e) => e.stopPropagation()}
                                className="hover:underline text-primary font-medium ml-1"
                              >
                                {process.number}
                              </Link>
                            </span>
                          )}
                        </p>
                      </div>
                    </div>

                    {!isBirthday && (
                      <div className="flex gap-2">
                        <Button
                          variant="ghost"
                          size="icon"
                          onClick={(e) => {
                            e.stopPropagation()
                            handleOpen(a)
                          }}
                        >
                          <Edit className="h-4 w-4" />
                        </Button>
                        <AlertDialog>
                          <AlertDialogTrigger asChild>
                            <Button
                              variant="ghost"
                              size="icon"
                              className="text-red-500"
                              onClick={(e) => e.stopPropagation()}
                            >
                              <Trash className="h-4 w-4" />
                            </Button>
                          </AlertDialogTrigger>
                          <AlertDialogContent onClick={(e) => e.stopPropagation()}>
                            <AlertDialogHeader>
                              <AlertDialogTitle>Excluir Compromisso?</AlertDialogTitle>
                              <AlertDialogDescription>
                                Esta ação removerá o compromisso permanentemente do sistema.
                              </AlertDialogDescription>
                            </AlertDialogHeader>
                            <AlertDialogFooter>
                              <AlertDialogCancel>Cancelar</AlertDialogCancel>
                              <AlertDialogAction
                                className="bg-red-600 hover:bg-red-700"
                                onClick={() => handleDelete(a)}
                              >
                                Excluir
                              </AlertDialogAction>
                            </AlertDialogFooter>
                          </AlertDialogContent>
                        </AlertDialog>
                      </div>
                    )}
                  </CardContent>
                </Card>
              )
            })
          )}
        </TabsContent>
      </Tabs>
    </div>
  )
}
