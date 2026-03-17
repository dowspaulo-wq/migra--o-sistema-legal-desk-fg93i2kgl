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

export function AppointmentDialog({
  open,
  onOpenChange,
  data,
  onSave,
  users,
  clients,
  cases,
  settings,
}: any) {
  const sortedUsers = [...users].sort((a: any, b: any) => a.name.localeCompare(b.name))
  const sortedClients = [...clients].sort((a: any, b: any) => a.name.localeCompare(b.name))
  const sortedTypes = [...(settings.appointmentTypes || [])].sort((a: string, b: string) =>
    a.localeCompare(b),
  )

  const getInitial = () => ({
    title: '',
    date: new Date().toISOString().split('T')[0],
    time: '10:00',
    type: '',
    priority: '',
    responsibleId: '',
    clientId: 'none',
    processId: 'none',
    description: '',
    modality: '',
  })

  const [fd, setFd] = useState(() =>
    data
      ? { ...data, clientId: data.clientId || 'none', processId: data.processId || 'none' }
      : getInitial(),
  )

  const sortedCases = [...cases]
    .filter((c: any) => fd.clientId === 'none' || !fd.clientId || c.clientId === fd.clientId)
    .sort((a: any, b: any) => a.number.localeCompare(b.number))

  useEffect(() => {
    if (open) {
      setFd(
        data
          ? { ...data, clientId: data.clientId || 'none', processId: data.processId || 'none' }
          : getInitial(),
      )
    }
  }, [data, open])

  const isAudience = fd.type === 'Aud.conciliação' || fd.type === 'AIJ'

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()

    if (!fd.type || !fd.priority || !fd.responsibleId) {
      toast({
        title: 'Campos Obrigatórios',
        description: 'Por favor, preencha Tipo, Prioridade e Responsável.',
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

    onSave({
      ...fd,
      modality: fd.modality || null,
      clientId: fd.clientId === 'none' ? null : fd.clientId,
      processId: fd.processId === 'none' ? null : fd.processId,
    })
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
              <Input
                type="date"
                required
                value={fd.date}
                onChange={(e) => setFd({ ...fd, date: e.target.value })}
              />
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
                  {sortedTypes.map((t: string) => (
                    <SelectItem key={t} value={t}>
                      {t}
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
              <Label>Cliente</Label>
              <Select value={fd.clientId} onValueChange={(v) => setFd({ ...fd, clientId: v })}>
                <SelectTrigger>
                  <SelectValue placeholder="Selecione um Cliente..." />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">Nenhum / Não vinculado</SelectItem>
                  {sortedClients.map((c: any) => (
                    <SelectItem key={c.id} value={c.id}>
                      {c.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Processo</Label>
              <Select value={fd.processId} onValueChange={(v) => setFd({ ...fd, processId: v })}>
                <SelectTrigger>
                  <SelectValue placeholder="Selecione um Processo..." />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">Nenhum / Não vinculado</SelectItem>
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
          <DialogFooter>
            <Button type="submit">Salvar na Agenda</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
