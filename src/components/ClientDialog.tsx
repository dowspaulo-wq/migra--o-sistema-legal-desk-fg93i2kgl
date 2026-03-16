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

export function ClientDialog({ open, onOpenChange, client, onSave, users, settings }: any) {
  const sortedUsers = [...users].sort((a: any, b: any) => a.name.localeCompare(b.name))
  const sortedCaptacao = [...(settings?.captacaoOptions || [])].sort((a: string, b: string) =>
    a.localeCompare(b),
  )

  const initial = client || {
    name: '',
    document: '',
    type: 'PF',
    email: '',
    phone: '',
    address: '',
    birthday: '',
    status: 'Ativo',
    isSpecial: false,
    observacoes: '',
    responsibleId: sortedUsers[0]?.id,
    captacao: '',
  }
  const [fd, setFd] = useState(initial)

  useEffect(() => {
    setFd(client || initial)
  }, [client, open])

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    onSave(fd)
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[500px]">
        <form onSubmit={handleSubmit} className="grid gap-4">
          <DialogHeader>
            <DialogTitle>{client ? 'Editar' : 'Cadastrar'} Cliente</DialogTitle>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="col-span-2 flex justify-between items-center">
              <div className="space-y-2 flex-1 mr-4">
                <Label>Nome Completo *</Label>
                <Input
                  required
                  value={fd.name}
                  onChange={(e) => setFd({ ...fd, name: e.target.value })}
                />
              </div>
              <div className="flex flex-col items-center gap-2 mt-4">
                <Label>Especial</Label>
                <Switch
                  checked={fd.isSpecial}
                  onCheckedChange={(v) => setFd({ ...fd, isSpecial: v })}
                />
              </div>
            </div>
            <div className="space-y-2">
              <Label>CPF/CNPJ *</Label>
              <Input
                required
                value={fd.document}
                onChange={(e) => setFd({ ...fd, document: e.target.value })}
              />
            </div>
            <div className="space-y-2">
              <Label>Tipo</Label>
              <Select value={fd.type} onValueChange={(v) => setFd({ ...fd, type: v })}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="PF">PF</SelectItem>
                  <SelectItem value="PJ">PJ</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Nascimento</Label>
              <Input
                type="date"
                value={fd.birthday}
                onChange={(e) => setFd({ ...fd, birthday: e.target.value })}
              />
            </div>
            <div className="space-y-2">
              <Label>Status</Label>
              <Select value={fd.status} onValueChange={(v) => setFd({ ...fd, status: v })}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Ativo">Ativo</SelectItem>
                  <SelectItem value="Baixado">Baixado</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>E-mail</Label>
              <Input
                type="email"
                value={fd.email}
                onChange={(e) => setFd({ ...fd, email: e.target.value })}
              />
            </div>
            <div className="space-y-2">
              <Label>WhatsApp</Label>
              <Input value={fd.phone} onChange={(e) => setFd({ ...fd, phone: e.target.value })} />
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
              <Label>Captação</Label>
              <Select value={fd.captacao} onValueChange={(v) => setFd({ ...fd, captacao: v })}>
                <SelectTrigger>
                  <SelectValue placeholder="Selecione..." />
                </SelectTrigger>
                <SelectContent>
                  {sortedCaptacao.map((c: string) => (
                    <SelectItem key={c} value={c}>
                      {c}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="col-span-2 space-y-2">
              <Label>Observações</Label>
              <Textarea
                value={fd.observacoes}
                onChange={(e) => setFd({ ...fd, observacoes: e.target.value })}
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
