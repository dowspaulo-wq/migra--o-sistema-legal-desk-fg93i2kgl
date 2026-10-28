import { useState, useEffect } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
import { Label } from '@/components/ui/label'
import { Input } from '@/components/ui/input'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import { toast } from '@/hooks/use-toast'
import { DatePicker } from '@/components/ui/date-picker'

import { Trash, CheckCircle2 } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'

export function AppointmentDialog({
  open,
  onOpenChange,
  data,
  onSave,
  onDelete,
  users,
  clients,
  cases,
  settings,
}: any) {
  const { state } = useLegalStore()
  const isAdmin = state.currentUser?.role === 'Admin'
  const sortedUsers = [...users].sort((a: any, b: any) => a.name.localeCompare(b.name))
  const sortedClients = [...clients].sort((a: any, b: any) => a.name.localeCompare(b.name))
  const DEFAULT_APPOINTMENT_TYPES = [
    'Reunião',
    'Aud.conciliação',
    'Diligência',
    'Feriado',
    'Outro',
    'AIJ',
  ]

  const getInitial = () => ({
    title: '',
    date: new Date().toISOString().split('T')[0],
    time: '10:00',
    type: '',
    priority: '',
    responsibleId: '',
    clientId: '',
    processId: '',
    description: '',
    modality: '',
    status: 'Pendente',
  })

  const [fd, setFd] = useState(() =>
    data
      ? { ...data, clientId: data.clientId || '', processId: data.processId || '' }
      : getInitial(),
  )

  const configuredTypes =
    state.settings?.appointmentTypes && state.settings.appointmentTypes.length > 0
      ? state.settings.appointmentTypes
      : settings?.appointmentTypes && settings.appointmentTypes.length > 0
        ? settings.appointmentTypes
        : DEFAULT_APPOINTMENT_TYPES

  const sortedTypes = (() => {
    const labels = new Set<string>()
    configuredTypes.forEach((t: any) => {
      const label = typeof t === 'string' ? t : t?.label
      if (label && typeof label === 'string' && label.trim()) {
        labels.add(label.trim())
      }
    })

    // Se o compromisso atual tiver um tipo gravado que não está mais na lista, mantém para não perder
    if (fd.type && fd.type.trim() && !labels.has(fd.type.trim())) {
      labels.add(fd.type.trim())
    }

    return Array.from(labels).sort((a, b) => a.localeCompare(b))
  })()

  const sortedCases = [...cases]
    .filter((c: any) => !fd.clientId || c.clientId === fd.clientId)
    .sort((a: any, b: any) => a.number.localeCompare(b.number))

  useEffect(() => {
    if (open) {
      setFd(
        data
          ? { ...data, clientId: data.clientId || '', processId: data.processId || '' }
          : getInitial(),
      )
    }
  }, [data, open])

  const isAudience = fd.type === 'Aud.conciliação' || fd.type === 'AIJ'

  const handleSubmit = (e?: React.FormEvent, forceStatus?: string) => {
    if (e) e.preventDefault()

    if (
      !fd.title?.trim() ||
      !fd.date ||
      !fd.time ||
      !fd.type ||
      !fd.priority ||
      !fd.responsibleId ||
      !fd.clientId
    ) {
      toast({
        title: 'Campos Obrigatórios',
        description:
          'Por favor, preencha Título, Data, Hora, Tipo, Prioridade, Responsável e Cliente.',
        variant: 'destructive',
      })
      return
    }

    if (!fd.processId) {
      toast({
        title: 'Campo Obrigatório',
        description: 'Por favor, selecione um Processo.',
        variant: 'destructive',
      })
      return
    }

    if (isAudience && !fd.modality) {
      toast({
        title: 'Campo Obrigatório',
        description: 'Por favor, informe a Modalidade para este tipo de evento.',
        variant: 'destructive',
      })
      return
    }

    const payload = {
      ...(data?.id ? { id: data.id } : {}),
      title: fd.title,
      date: fd.date,
      time: fd.time,
      type: fd.type,
      priority: fd.priority,
      responsibleId: fd.responsibleId,
      clientId: fd.clientId,
      processId: fd.processId,
      description: fd.description,
      modality: fd.modality || null,
      status: forceStatus || fd.status || 'Pendente',
      googleEventId: (data as any)?.googleEventId || undefined,
    }

    onSave(payload)
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl">
        <form onSubmit={handleSubmit} className="grid gap-4">
          <DialogHeader>
            <DialogTitle>{data ? 'Editar' : 'Agendar'} Compromisso</DialogTitle>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="col-span-2 space-y-2">
              <Label>Título *</Label>
              <Input
                required
                value={fd.title}
                onChange={(e) => setFd({ ...fd, title: e.target.value })}
              />
            </div>
            <div className="space-y-2">
              <Label>Data *</Label>
              <DatePicker value={fd.date} onChange={(v) => setFd({ ...fd, date: v })} />
            </div>
            <div className="space-y-2">
              <Label>Hora *</Label>
              <Input
                type="time"
                required
                value={fd.time}
                onChange={(e) => setFd({ ...fd, time: e.target.value })}
              />
            </div>
            <div className="space-y-2">
              <Label>Tipo *</Label>
              <Select value={fd.type} onValueChange={(v) => setFd({ ...fd, type: v })}>
                <SelectTrigger>
                  <SelectValue placeholder="Selecione o Tipo" />
                </SelectTrigger>
                <SelectContent>
                  {sortedTypes.map((label: string) => (
                    <SelectItem key={label} value={label}>
                      {label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>Modalidade {isAudience && '*'}</Label>
              <Select
                value={fd.modality || ''}
                onValueChange={(v) => setFd({ ...fd, modality: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Selecione a Modalidade" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Presencial">Presencial</SelectItem>
                  <SelectItem value="Virtual">Virtual</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>Prioridade *</Label>
              <Select value={fd.priority} onValueChange={(v) => setFd({ ...fd, priority: v })}>
                <SelectTrigger>
                  <SelectValue placeholder="Selecione a Prioridade" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Baixa">Baixa</SelectItem>
                  <SelectItem value="Média">Média</SelectItem>
                  <SelectItem value="Alta">Alta</SelectItem>
                  <SelectItem value="Urgente">Urgente</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>Responsável *</Label>
              <Select
                value={fd.responsibleId}
                onValueChange={(v) => setFd({ ...fd, responsibleId: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Selecione o Responsável" />
                </SelectTrigger>
                <SelectContent>
                  {sortedUsers.map((u: any) => (
                    <SelectItem key={u.id} value={u.id}>
                      {u.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>Cliente *</Label>
              <Select value={fd.clientId} onValueChange={(v) => setFd({ ...fd, clientId: v })}>
                <SelectTrigger>
                  <SelectValue placeholder="Selecione um Cliente..." />
                </SelectTrigger>
                <SelectContent>
                  {sortedClients.map((c: any) => (
                    <SelectItem key={c.id} value={c.id}>
                      {c.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Processo *</Label>
              <Select value={fd.processId} onValueChange={(v) => setFd({ ...fd, processId: v })}>
                <SelectTrigger>
                  <SelectValue placeholder="Selecione um Processo..." />
                </SelectTrigger>
                <SelectContent>
                  {sortedCases.map((c: any) => (
                    <SelectItem key={c.id} value={c.id}>
                      {c.number}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="col-span-2 space-y-2">
              <Label>Observações</Label>
              <Textarea
                value={fd.description}
                onChange={(e) => setFd({ ...fd, description: e.target.value })}
              />
            </div>
          </div>
          <DialogFooter className="sm:justify-between w-full mt-4">
            {data?.id && onDelete && data.itemType !== 'birthday' && isAdmin ? (
              <Button
                type="button"
                variant="destructive"
                onClick={() => {
                  onDelete(data)
                  onOpenChange(false)
                }}
              >
                <Trash className="h-4 w-4 mr-2" /> Excluir
              </Button>
            ) : (
              <div />
            )}
            <div className="flex gap-2">
              {data?.id && data.itemType !== 'birthday' && data.status !== 'Concluído' && (
                <Button
                  type="button"
                  variant="outline"
                  className="bg-green-50 hover:bg-green-100 text-green-600 border-green-200"
                  onClick={() => handleSubmit(undefined, 'Concluído')}
                >
                  <CheckCircle2 className="h-4 w-4 mr-2" /> Concluir
                </Button>
              )}
              <Button type="submit">Salvar na Agenda</Button>
            </div>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
