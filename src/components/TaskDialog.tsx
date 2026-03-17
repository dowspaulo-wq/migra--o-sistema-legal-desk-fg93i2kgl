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

export function TaskDialog({
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
  const sortedStatuses = [...(settings.taskStatuses || [])].sort((a: string, b: string) =>
    a.localeCompare(b),
  )
  const sortedTypes = [...(settings.taskTypes || [])].sort((a: string, b: string) =>
    a.localeCompare(b),
  )

  const getInitial = () => ({
    title: '',
    description: '',
    internalNotes: '',
    dueDate: new Date().toISOString().split('T')[0],
    status: sortedStatuses[0] || 'pendente',
    priority: 'Média',
    responsibleId: sortedUsers[0]?.id,
    type: sortedTypes[0] || 'interna e adm',
    clientId: 'none',
    relatedProcessId: 'none',
  })

  const [fd, setFd] = useState(() =>
    data
      ? {
          ...data,
          clientId: data.clientId || 'none',
          relatedProcessId: data.relatedProcessId || 'none',
        }
      : getInitial(),
  )

  const sortedCases = [...cases]
    .filter((c: any) => fd.clientId === 'none' || !fd.clientId || c.clientId === fd.clientId)
    .sort((a: any, b: any) => a.number.localeCompare(b.number))

  useEffect(() => {
    if (open) {
      setFd(
        data
          ? {
              ...data,
              clientId: data.clientId || 'none',
              relatedProcessId: data.relatedProcessId || 'none',
            }
          : getInitial(),
      )
    }
  }, [data, open])

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    onSave({
      ...fd,
      clientId: fd.clientId === 'none' ? null : fd.clientId,
      relatedProcessId: fd.relatedProcessId === 'none' ? null : fd.relatedProcessId,
    })
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <form onSubmit={handleSubmit} className="grid gap-4">
          <DialogHeader>
            <DialogTitle>{data ? 'Editar' : 'Nova'} Tarefa</DialogTitle>
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
              <Label>Tipo da Tarefa</Label>
              <Select value={fd.type} onValueChange={(v) => setFd({ ...fd, type: v })}>
                <SelectTrigger>
                  <SelectValue placeholder="Selecione..." />
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
              <Label>Vencimento</Label>
              <Input
                type="date"
                value={fd.dueDate}
                onChange={(e) => setFd({ ...fd, dueDate: e.target.value })}
              />
            </div>
            <div className="space-y-2">
              <Label>Status</Label>
              <Select value={fd.status} onValueChange={(v) => setFd({ ...fd, status: v })}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {sortedStatuses.map((s: string) => (
                    <SelectItem key={s} value={s}>
                      {s}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Prioridade</Label>
              <Select value={fd.priority} onValueChange={(v) => setFd({ ...fd, priority: v })}>
                <SelectTrigger>
                  <SelectValue />
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
              <Label>Responsável</Label>
              <Select
                value={fd.responsibleId}
                onValueChange={(v) => setFd({ ...fd, responsibleId: v })}
              >
                <SelectTrigger>
                  <SelectValue />
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
                  <SelectValue placeholder="Selecione..." />
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
              <Select
                value={fd.relatedProcessId}
                onValueChange={(v) => setFd({ ...fd, relatedProcessId: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Selecione..." />
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
              <Label>Descrição</Label>
              <Textarea
                value={fd.description}
                onChange={(e) => setFd({ ...fd, description: e.target.value })}
              />
            </div>
            <div className="col-span-2 space-y-2">
              <Label>Observação Interna</Label>
              <Textarea
                value={fd.internalNotes}
                onChange={(e) => setFd({ ...fd, internalNotes: e.target.value })}
              />
            </div>
          </div>
          <DialogFooter>
            <Button type="submit">Salvar</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
