import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Calendar } from '@/components/ui/calendar'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
  DialogFooter,
} from '@/components/ui/dialog'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Plus, Video, Gift } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'

export default function Agenda() {
  const { state, addAppointment } = useLegalStore()
  const [date, setDate] = useState<Date | undefined>(new Date())
  const [open, setOpen] = useState(false)
  const [fd, setFd] = useState({
    title: '',
    date: new Date().toISOString().split('T')[0],
    time: '10:00',
    type: 'Audiência',
    responsibleId: state.currentUser.id,
  })

  const selectedDateStr = date?.toDateString()
  const dayAppointments = state.appointments
    .filter((a) => new Date(a.date).toDateString() === selectedDateStr)
    .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime())
  const birthdays = state.clients.filter(
    (c) =>
      c.birthday &&
      new Date(c.birthday).getDate() === date?.getDate() &&
      new Date(c.birthday).getMonth() === date?.getMonth(),
  )

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    addAppointment({
      title: fd.title,
      date: new Date(`${fd.date}T${fd.time}:00`).toISOString(),
      type: fd.type,
      responsibleId: fd.responsibleId,
    })
    setOpen(false)
  }

  const getTypeStyle = (type: string) =>
    type === 'Audiência'
      ? 'border-red-500 bg-red-50'
      : type === 'Reunião'
        ? 'border-blue-500 bg-blue-50'
        : 'border-orange-500 bg-orange-50'

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Agenda Compartilhada</h1>
          <p className="text-muted-foreground">Audiências, prazos e reuniões.</p>
        </div>
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogTrigger asChild>
            <Button>
              <Plus className="mr-2 h-4 w-4" /> Novo Compromisso
            </Button>
          </DialogTrigger>
          <DialogContent>
            <form onSubmit={handleSubmit} className="space-y-4 py-4">
              <DialogHeader>
                <DialogTitle>Agendar Compromisso</DialogTitle>
              </DialogHeader>
              <div className="space-y-2">
                <Label>Título</Label>
                <Input
                  required
                  value={fd.title}
                  onChange={(e) => setFd({ ...fd, title: e.target.value })}
                />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Data</Label>
                  <Input
                    type="date"
                    required
                    value={fd.date}
                    onChange={(e) => setFd({ ...fd, date: e.target.value })}
                  />
                </div>
                <div className="space-y-2">
                  <Label>Hora</Label>
                  <Input
                    type="time"
                    required
                    value={fd.time}
                    onChange={(e) => setFd({ ...fd, time: e.target.value })}
                  />
                </div>
              </div>
              <div className="space-y-2">
                <Label>Tipo</Label>
                <Select value={fd.type} onValueChange={(v) => setFd({ ...fd, type: v })}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Audiência">Audiência</SelectItem>
                    <SelectItem value="Reunião">Reunião</SelectItem>
                    <SelectItem value="Prazo">Prazo</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <p className="text-xs text-muted-foreground bg-blue-50 p-2 rounded">
                Nota: Agendar "Audiência" criará automaticamente uma tarefa de preparação.
              </p>
              <DialogFooter>
                <Button type="submit">Salvar na Agenda</Button>
              </DialogFooter>
            </form>
          </DialogContent>
        </Dialog>
      </div>

      <div className="grid md:grid-cols-3 gap-6">
        <Card className="h-fit flex justify-center p-2 shadow-sm">
          <Calendar
            mode="single"
            selected={date}
            onSelect={setDate}
            className="w-full max-w-sm rounded-md"
          />
        </Card>
        <Card className="md:col-span-2 shadow-sm">
          <CardHeader>
            <CardTitle>Compromissos - {date?.toLocaleDateString('pt-BR')}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {birthdays.map((c) => (
              <div
                key={`b-${c.id}`}
                className="flex border-l-4 p-3 rounded-r-lg border-yellow-500 bg-yellow-50 mb-3"
              >
                <div className="w-16 flex justify-center items-center">
                  <Gift className="h-6 w-6 text-yellow-600" />
                </div>
                <div className="flex-1">
                  <p className="font-bold text-yellow-800">Aniversário do Cliente: {c.name}</p>
                  <p className="text-xs text-yellow-700 mt-1">
                    Ótima oportunidade para enviar uma mensagem!
                  </p>
                </div>
              </div>
            ))}
            {dayAppointments.length > 0
              ? dayAppointments.map((a) => {
                  const resp = state.users.find((u) => u.id === a.responsibleId)?.name
                  return (
                    <div
                      key={a.id}
                      className={`flex border-l-4 p-3 rounded-r-lg ${getTypeStyle(a.type)}`}
                    >
                      <div className="w-16 font-bold text-slate-700">
                        {new Date(a.date).toLocaleTimeString('pt-BR', {
                          hour: '2-digit',
                          minute: '2-digit',
                        })}
                      </div>
                      <div className="flex-1">
                        <p className="font-bold text-slate-800">{a.title}</p>
                        <p className="text-xs text-muted-foreground mt-1">
                          Tipo: {a.type} • Resp: {resp}
                        </p>
                      </div>
                      {a.type === 'Reunião' && (
                        <Button variant="ghost" size="icon" className="h-8 w-8 rounded-full">
                          <Video className="h-4 w-4 text-blue-500" />
                        </Button>
                      )}
                    </div>
                  )
                })
              : !birthdays.length && (
                  <div className="text-center py-8 text-muted-foreground">
                    Agenda livre neste dia.
                  </div>
                )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
