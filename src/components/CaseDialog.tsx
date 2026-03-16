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
import { Switch } from '@/components/ui/switch'
import { Textarea } from '@/components/ui/textarea'

export function CaseDialog({ open, onOpenChange, data, onSave, users, clients, settings }: any) {
  const sortedUsers = [...users].sort((a: any, b: any) => a.name.localeCompare(b.name))
  const sortedClients = [...clients].sort((a: any, b: any) => a.name.localeCompare(b.name))
  const sortedTypes = [...(settings.caseTypes || [])].sort((a: string, b: string) =>
    a.localeCompare(b),
  )
  const sortedStatuses = [...(settings.caseStatuses || [])].sort((a: string, b: string) =>
    a.localeCompare(b),
  )

  const initial = data || {
    number: '',
    clientId: '',
    position: 'Autor',
    adverseParty: '',
    type: sortedTypes[0] || 'Cível',
    status: sortedStatuses[0] || 'Em andamento',
    court: '',
    comarca: '',
    state: 'SP',
    value: 0,
    startDate: new Date().toISOString().split('T')[0],
    responsibleId: sortedUsers[0]?.id,
    isSpecial: false,
    description: '',
    internalNotes: '',
    alerts: '',
  }
  const [fd, setFd] = useState(initial)

  useEffect(() => {
    setFd(data || initial)
  }, [data, open])

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    onSave(fd)
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
        <form onSubmit={handleSubmit} className="grid gap-4">
          <DialogHeader>
            <DialogTitle>{data ? 'Editar' : 'Cadastrar'} Processo</DialogTitle>
          </DialogHeader>
          <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
            <div className="col-span-2 flex gap-4">
              <div className="flex-1 space-y-2">
                <Label>Nº do Processo (CNJ) *</Label>
                <Input
                  required
                  value={fd.number}
                  onChange={(e) => setFd({ ...fd, number: e.target.value })}
                />
              </div>
              <div className="flex flex-col items-center gap-2 mt-2">
                <Label>Especial</Label>
                <Switch
                  checked={fd.isSpecial}
                  onCheckedChange={(v) => setFd({ ...fd, isSpecial: v })}
                />
              </div>
            </div>
            <div className="space-y-2">
              <Label>Cliente *</Label>
              <Select
                value={fd.clientId}
                onValueChange={(v) => setFd({ ...fd, clientId: v })}
                required
              >
                <SelectTrigger>
                  <SelectValue placeholder="Selecione" />
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
              <Label>Tipo</Label>
              <Select value={fd.type} onValueChange={(v) => setFd({ ...fd, type: v })}>
                <SelectTrigger>
                  <SelectValue />
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
              <Label>Status</Label>
              <Select value={fd.status} onValueChange={(v) => setFd({ ...fd, status: v })}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {sortedStatuses.map((t: string) => (
                    <SelectItem key={t} value={t}>
                      {t}
                    </SelectItem>
                  ))}
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
              <Label>Posição do Cliente</Label>
              <Input
                value={fd.position}
                onChange={(e) => setFd({ ...fd, position: e.target.value })}
              />
            </div>
            <div className="space-y-2">
              <Label>Parte Adversa</Label>
              <Input
                value={fd.adverseParty}
                onChange={(e) => setFd({ ...fd, adverseParty: e.target.value })}
              />
            </div>
            <div className="space-y-2">
              <Label>Vara / Juízo</Label>
              <Input
                required
                value={fd.court}
                onChange={(e) => setFd({ ...fd, court: e.target.value })}
              />
            </div>
            <div className="space-y-2">
              <Label>Comarca / UF</Label>
              <div className="flex gap-2">
                <Input
                  value={fd.comarca}
                  onChange={(e) => setFd({ ...fd, comarca: e.target.value })}
                />
                <Input
                  className="w-16"
                  value={fd.state}
                  onChange={(e) => setFd({ ...fd, state: e.target.value })}
                />
              </div>
            </div>
            <div className="space-y-2">
              <Label>Valor da Causa</Label>
              <Input
                type="number"
                required
                value={fd.value}
                onChange={(e) => setFd({ ...fd, value: Number(e.target.value) })}
              />
            </div>
            <div className="space-y-2">
              <Label>Data Início</Label>
              <Input
                type="date"
                required
                value={fd.startDate}
                onChange={(e) => setFd({ ...fd, startDate: e.target.value })}
              />
            </div>
            <div className="col-span-full space-y-2">
              <Label>Alertas (Suporta Emojis)</Label>
              <Input
                value={fd.alerts}
                onChange={(e) => setFd({ ...fd, alerts: e.target.value })}
                placeholder="Ex: 🚨 Prazo fatal em 2 dias!"
              />
            </div>
            <div className="col-span-full md:col-span-2 space-y-2">
              <Label>Descrição</Label>
              <Textarea
                value={fd.description}
                onChange={(e) => setFd({ ...fd, description: e.target.value })}
              />
            </div>
            <div className="col-span-full md:col-span-1 space-y-2">
              <Label>Notas Internas</Label>
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
