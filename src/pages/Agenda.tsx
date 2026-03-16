import { useState } from 'react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Plus, Gift, Video, Edit, LayoutGrid, List } from 'lucide-react'
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

  const handleOpen = (item?: any) => {
    setEditingItem(item || null)
    setOpen(true)
  }

  const handleSave = (fd: any) => {
    if (editingItem) updateItem('appointments', editingItem.id, fd)
    else addAppointment(fd)
  }

  const allItems = [
    ...state.appointments.map((a) => ({ ...a, itemType: 'appointment' as const })),
    ...state.clients
      .filter((c) => c.birthday)
      .map((c) => {
        // Create a virtual birthday event for current year and next year
        const d = new Date(c.birthday!)
        const currD = new Date()
        d.setFullYear(currD.getFullYear())
        return {
          id: `bday-${c.id}`,
          date: d.toISOString(),
          title: `Aniversário: ${c.name}`,
          type: 'Aniversário',
          itemType: 'birthday' as const,
          client: c,
        }
      }),
  ]

  const filtered = allItems.filter((i) => i.title.toLowerCase().includes(search.toLowerCase()))

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
          <Input
            placeholder="Buscar evento..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="max-w-xs"
          />
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
              if (item.itemType === 'birthday')
                return (
                  <div
                    key={item.id}
                    className="text-[10px] p-1 bg-pink-100 text-pink-800 border border-pink-200 rounded flex items-center gap-1 mb-1 truncate"
                    title={item.title}
                  >
                    <Gift className="h-3 w-3 shrink-0" /> {item.client?.name.split(' ')[0]}
                  </div>
                )
              const resp = state.users.find((u) => u.id === item.responsibleId)
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
                  <span className="font-semibold">{item.time}</span> - {item.title}
                </div>
              )
            }}
          />
        </TabsContent>

        <TabsContent value="list" className="grid gap-3">
          {filtered
            .filter((i) => i.itemType !== 'birthday')
            .map((a) => {
              const resp = state.users.find((u) => u.id === a.responsibleId)
              const client = state.clients.find((c) => c.id === a.clientId)
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
                          {new Date(a.date).toLocaleDateString('pt-BR', { month: 'short' })}
                        </p>
                        <p className="text-xl font-black text-primary">
                          {new Date(a.date).getDate()}
                        </p>
                      </div>
                      <div>
                        <p className="font-bold text-lg flex items-center gap-2">
                          {a.title}{' '}
                          {a.type === 'Reunião' && <Video className="h-4 w-4 text-blue-500" />}{' '}
                          <Badge variant="outline">{a.type}</Badge>
                        </p>
                        <p className="text-sm text-muted-foreground mt-1">
                          Horário: {a.time} • Resp: {resp?.name}
                        </p>
                        <p className="text-xs text-muted-foreground">
                          Cliente: {client?.name || 'N/A'}
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
