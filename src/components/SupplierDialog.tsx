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

export function SupplierDialog({ open, onOpenChange, data, onSave }: any) {
  const getInitial = () => ({
    name: '',
    document: '',
    email: '',
    phone: '',
    status: 'Ativo',
  })

  const [fd, setFd] = useState(data || getInitial())

  useEffect(() => {
    if (open) {
      setFd(data || getInitial())
    }
  }, [data, open])

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()

    if (!fd.name) {
      toast({
        title: 'Campos Obrigatórios',
        description: 'Por favor, informe o nome do fornecedor.',
        variant: 'destructive',
      })
      return
    }

    onSave(fd)
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <form onSubmit={handleSubmit} className="grid gap-4">
          <DialogHeader>
            <DialogTitle>{data ? 'Editar' : 'Novo'} Fornecedor</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-2">
              <Label>Nome *</Label>
              <Input
                required
                placeholder="Razão Social ou Nome"
                value={fd.name}
                onChange={(e) => setFd({ ...fd, name: e.target.value })}
              />
            </div>

            <div className="space-y-2">
              <Label>Documento (CNPJ/CPF)</Label>
              <Input
                placeholder="00.000.000/0000-00"
                value={fd.document || ''}
                onChange={(e) => setFd({ ...fd, document: e.target.value })}
              />
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>E-mail</Label>
                <Input
                  type="email"
                  placeholder="contato@empresa.com"
                  value={fd.email || ''}
                  onChange={(e) => setFd({ ...fd, email: e.target.value })}
                />
              </div>
              <div className="space-y-2">
                <Label>Telefone</Label>
                <Input
                  placeholder="(00) 00000-0000"
                  value={fd.phone || ''}
                  onChange={(e) => setFd({ ...fd, phone: e.target.value })}
                />
              </div>
            </div>

            <div className="space-y-2">
              <Label>Status</Label>
              <Select value={fd.status} onValueChange={(v) => setFd({ ...fd, status: v })}>
                <SelectTrigger>
                  <SelectValue placeholder="Status" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Ativo">Ativo</SelectItem>
                  <SelectItem value="Inativo">Inativo</SelectItem>
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
