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

export function SupplierDialog({ open, onOpenChange, data, onSave, existingGroups = [] }: any) {
  const getInitial = () => ({
    name: '',
    document: '',
    email: '',
    phone: '',
    status: 'Ativo',
    group_name: '',
  })

  const [fd, setFd] = useState(data || getInitial())
  const [customGroup, setCustomGroup] = useState('')
  const [isCreatingCustomGroup, setIsCreatingCustomGroup] = useState(false)

  useEffect(() => {
    if (open) {
      const initial = data ? { ...getInitial(), ...data } : getInitial()
      setFd(initial)
      setCustomGroup('')
      setIsCreatingCustomGroup(false)
    }
  }, [data, open])

  const defaultSuggestions = [
    'Bolsa de Estágio',
    'Contabilidade',
    'Marketing',
    'Serviços Financeiros',
    'Tecnologia',
    'Telefonia',
    'Tributos',
  ]

  const allAvailableGroups = Array.from(
    new Set([
      ...defaultSuggestions,
      ...(existingGroups || []).filter(Boolean),
      ...(fd.group_name ? [fd.group_name] : []),
    ]),
  ).sort((a: string, b: string) => a.localeCompare(b, 'pt-BR', { sensitivity: 'base' }))

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

    const finalGroup = isCreatingCustomGroup ? customGroup.trim() : (fd.group_name || '').trim()

    onSave({
      ...fd,
      group_name: finalGroup || null,
    })
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
              <div className="flex items-center justify-between">
                <Label>Grupo do Fornecedor</Label>
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="h-6 px-1.5 text-xs text-blue-600 hover:text-blue-800"
                  onClick={() => {
                    setIsCreatingCustomGroup(!isCreatingCustomGroup)
                    if (!isCreatingCustomGroup) {
                      setCustomGroup('')
                    }
                  }}
                >
                  {isCreatingCustomGroup ? 'Escolher grupo existente' : '+ Criar novo grupo'}
                </Button>
              </div>

              {isCreatingCustomGroup ? (
                <Input
                  placeholder="Nome do novo grupo (ex: Cartórios, Motoboy)..."
                  value={customGroup}
                  onChange={(e) => setCustomGroup(e.target.value)}
                  autoFocus
                />
              ) : (
                <Select
                  value={fd.group_name || '__none__'}
                  onValueChange={(v) => setFd({ ...fd, group_name: v === '__none__' ? '' : v })}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Selecione um grupo (opcional)" />
                  </SelectTrigger>
                  <SelectContent className="max-h-56">
                    <SelectItem value="__none__">Nenhum grupo</SelectItem>
                    {allAvailableGroups.map((g) => (
                      <SelectItem key={g} value={g}>
                        {g}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              )}
              <p className="text-[11px] text-muted-foreground">
                Exemplos: Marketing, Telefonia, Bolsa de Estágio, Contabilidade.
              </p>
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
