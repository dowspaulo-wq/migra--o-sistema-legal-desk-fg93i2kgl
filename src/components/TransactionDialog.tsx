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
import { toast } from '@/hooks/use-toast'

const CATEGORIES = [
  'Custas Iniciais',
  'Custas Finais',
  'Depósito Recursal',
  'Honorários Periciais',
  'Honorários Sucumbenciais',
  'Honorários Contratuais',
  'Alvará / Condenação',
  'Diligência',
  'Acordo',
  'Outros',
]

export function TransactionDialog({
  open,
  onOpenChange,
  data,
  onSave,
  lockedProcessId,
  lockedClientId,
}: any) {
  const getInitial = () => ({
    description: '',
    amount: '',
    type: 'expense',
    category: '',
    status: 'Pendente',
    date: new Date().toISOString().split('T')[0],
    clientId: lockedClientId || '',
    processId: lockedProcessId || '',
  })

  const [fd, setFd] = useState(() =>
    data ? { ...data, amount: data.amount.toString() } : getInitial(),
  )

  useEffect(() => {
    if (open) {
      setFd(data ? { ...data, amount: data.amount.toString() } : getInitial())
    }
  }, [data, open, lockedProcessId, lockedClientId])

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()

    if (!fd.description || !fd.amount || !fd.type || !fd.category || !fd.status || !fd.date) {
      toast({
        title: 'Campos Obrigatórios',
        description: 'Por favor, preencha todos os campos obrigatórios.',
        variant: 'destructive',
      })
      return
    }

    const payload = {
      ...fd,
      amount: parseFloat(fd.amount.replace(',', '.')),
    }

    onSave(payload)
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <form onSubmit={handleSubmit} className="grid gap-4">
          <DialogHeader>
            <DialogTitle>{data ? 'Editar' : 'Novo'} Lançamento</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Tipo *</Label>
                <Select value={fd.type} onValueChange={(v) => setFd({ ...fd, type: v })}>
                  <SelectTrigger>
                    <SelectValue placeholder="Tipo" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="expense">Despesa / Custa</SelectItem>
                    <SelectItem value="income">Receita / Alvará</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label>Valor (R$) *</Label>
                <Input
                  type="number"
                  step="0.01"
                  required
                  value={fd.amount}
                  onChange={(e) => setFd({ ...fd, amount: e.target.value })}
                />
              </div>
            </div>

            <div className="space-y-2">
              <Label>Descrição *</Label>
              <Input
                required
                placeholder="Ex: Guia de custas iniciais"
                value={fd.description}
                onChange={(e) => setFd({ ...fd, description: e.target.value })}
              />
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Categoria *</Label>
                <Select value={fd.category} onValueChange={(v) => setFd({ ...fd, category: v })}>
                  <SelectTrigger>
                    <SelectValue placeholder="Categoria" />
                  </SelectTrigger>
                  <SelectContent>
                    {CATEGORIES.map((c) => (
                      <SelectItem key={c} value={c}>
                        {c}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
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
            </div>

            <div className="space-y-2">
              <Label>Status *</Label>
              <Select value={fd.status} onValueChange={(v) => setFd({ ...fd, status: v })}>
                <SelectTrigger>
                  <SelectValue placeholder="Status" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Pendente">Pendente</SelectItem>
                  <SelectItem value="Pago">Pago / Recebido</SelectItem>
                  <SelectItem value="Atrasado">Atrasado</SelectItem>
                </SelectContent>
              </Select>
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
