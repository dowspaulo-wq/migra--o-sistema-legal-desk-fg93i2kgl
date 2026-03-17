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
import { Toggle } from '@/components/ui/toggle'
import { Textarea } from '@/components/ui/textarea'
import { Star } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'

export function ClientDialog({ open, onOpenChange, client, onSave, users, settings }: any) {
  const { state } = useLegalStore()
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
    responsibleId: sortedUsers[0]?.id || '',
    captacao: '',
  }
  const [fd, setFd] = useState(initial)

  useEffect(() => {
    setFd(client || initial)
  }, [client, open])

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()

    if (!fd.birthday || !fd.email || !fd.phone || !fd.responsibleId || !fd.captacao) {
      toast({
        title: 'Campos Obrigatórios',
        description:
          'Nascimento, E-mail, WhatsApp, Responsável e Captação são de preenchimento obrigatório.',
        variant: 'destructive',
      })
      return
    }

    const isDupName = state.clients.some(
      (c) => c.name.toLowerCase() === fd.name.toLowerCase() && c.id !== client?.id,
    )
    const isDupDoc = state.clients.some((c) => c.document === fd.document && c.id !== client?.id)

    if (isDupName || isDupDoc) {
      toast({
        title: 'Erro',
        description: 'Erro: Já existe um cliente cadastrado com este Nome ou CPF/CNPJ.',
        variant: 'destructive',
      })
      return
    }

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
            <div className="col-span-2 flex justify-between items-end gap-4 pb-1">
              <div className="flex-1 space-y-2">
                <Label>Nome Completo *</Label>
                <Input
                  required
                  value={fd.name}
                  onChange={(e) => setFd({ ...fd, name: e.target.value })}
                />
              </div>
              <div className="flex gap-2">
                <Toggle
                  pressed={fd.isSpecial}
                  onPressedChange={(v) => setFd({ ...fd, isSpecial: v })}
                  variant="outline"
                  className={fd.isSpecial ? 'bg-yellow-50 border-yellow-200' : ''}
                  title="Cliente Especial"
                >
                  <Star
                    className={`h-4 w-4 ${fd.isSpecial ? 'fill-yellow-400 text-yellow-400' : 'text-slate-400'}`}
                  />
                </Toggle>
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
              <Label>Nascimento *</Label>
              <Input
                type="date"
                required
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
              <Label>E-mail *</Label>
              <Input
                type="email"
                required
                value={fd.email}
                onChange={(e) => setFd({ ...fd, email: e.target.value })}
              />
            </div>
            <div className="space-y-2">
              <Label>WhatsApp *</Label>
              <Input
                required
                value={fd.phone}
                onChange={(e) => setFd({ ...fd, phone: e.target.value })}
              />
            </div>
            <div className="space-y-2">
              <Label>Responsável *</Label>
              <Select
                value={fd.responsibleId}
                onValueChange={(v) => setFd({ ...fd, responsibleId: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Selecione..." />
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
              <Label>Captação *</Label>
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
