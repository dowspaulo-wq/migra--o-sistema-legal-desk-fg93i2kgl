import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Search, Plus, Edit, Trash2 } from 'lucide-react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
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
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'

export default function Cases() {
  const { state, addCase, updateItem, deleteItem } = useLegalStore()
  const [search, setSearch] = useState('')
  const [open, setOpen] = useState(false)
  const [editingId, setEditingId] = useState<string | null>(null)

  const initialFd = {
    clientId: '',
    number: '',
    position: 'Autor',
    adverseParty: '',
    type: 'Cível',
    status: 'Em andamento',
    court: '',
    comarca: '',
    state: 'SP',
    system: 'PJE',
    value: 0,
    responsibleId: state.currentUser.id,
  }
  const [fd, setFd] = useState(initialFd)

  const filtered = state.cases.filter(
    (c) => c.number.includes(search) || c.adverseParty.toLowerCase().includes(search.toLowerCase()),
  )

  const handleOpen = (c?: any) => {
    if (c) {
      setFd(c)
      setEditingId(c.id)
    } else {
      setFd(initialFd)
      setEditingId(null)
    }
    setOpen(true)
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (editingId) {
      updateItem('cases', editingId, fd)
      toast({ title: 'Processo atualizado' })
    } else {
      if (state.cases.some((c) => c.number === fd.number))
        return toast({ title: 'Erro', description: 'Número já cadastrado', variant: 'destructive' })
      addCase({ ...fd, startDate: new Date().toISOString().split('T')[0] })
    }
    setOpen(false)
  }

  const handleDelete = (id: string) => {
    if (
      window.confirm(
        'Excluir este processo apagará também as tarefas vinculadas. Deseja continuar?',
      )
    )
      deleteItem('cases', id)
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Processos</h1>
          <p className="text-muted-foreground">Gestão de casos judiciais e extrajudiciais.</p>
        </div>
        <Button onClick={() => handleOpen()}>
          <Plus className="mr-2 h-4 w-4" /> Novo Processo
        </Button>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-2xl">
          <form onSubmit={handleSubmit} className="grid gap-4 py-4">
            <DialogHeader>
              <DialogTitle>{editingId ? 'Editar' : 'Cadastrar'} Processo</DialogTitle>
            </DialogHeader>
            <div className="grid grid-cols-2 gap-4">
              <div className="col-span-2 space-y-2">
                <Label>Número CNJ *</Label>
                <Input
                  required
                  value={fd.number}
                  onChange={(e) => setFd({ ...fd, number: e.target.value })}
                />
              </div>
              <div className="space-y-2">
                <Label>Cliente *</Label>
                <Select
                  value={fd.clientId}
                  onValueChange={(v) => setFd({ ...fd, clientId: v })}
                  required
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Selecione..." />
                  </SelectTrigger>
                  <SelectContent>
                    {state.clients.map((c) => (
                      <SelectItem key={c.id} value={c.id}>
                        {c.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label>Parte Adversa</Label>
                <Input
                  value={fd.adverseParty}
                  onChange={(e) => setFd({ ...fd, adverseParty: e.target.value })}
                />
              </div>
              <div className="space-y-2">
                <Label>Sistema / Vara</Label>
                <div className="flex gap-2">
                  <Input
                    value={fd.system}
                    className="w-24"
                    onChange={(e) => setFd({ ...fd, system: e.target.value })}
                  />
                  <Input
                    className="flex-1"
                    value={fd.court}
                    onChange={(e) => setFd({ ...fd, court: e.target.value })}
                  />
                </div>
              </div>
              <div className="space-y-2">
                <Label>Comarca / UF</Label>
                <div className="flex gap-2">
                  <Input
                    value={fd.comarca}
                    className="flex-1"
                    onChange={(e) => setFd({ ...fd, comarca: e.target.value })}
                  />
                  <Input
                    value={fd.state}
                    className="w-16"
                    onChange={(e) => setFd({ ...fd, state: e.target.value })}
                  />
                </div>
              </div>
            </div>
            <DialogFooter>
              <Button type="submit">Salvar</Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      <Input
        type="search"
        placeholder="Buscar número..."
        className="max-w-md"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
      />

      <div className="grid gap-4">
        {filtered.map((c) => {
          const client = state.clients.find((cl) => cl.id === c.clientId)
          return (
            <Card key={c.id} className="shadow-sm hover:border-primary/50 transition-all">
              <CardContent className="p-4 flex flex-col md:flex-row justify-between gap-4">
                <div className="space-y-1">
                  <div className="flex items-center gap-2">
                    <Link
                      to={`/processos/${c.id}`}
                      className="text-lg font-bold text-primary hover:underline"
                    >
                      {c.number}
                    </Link>
                    <Badge variant={c.status === 'Em andamento' ? 'default' : 'secondary'}>
                      {c.status}
                    </Badge>
                  </div>
                  <p className="text-sm font-medium">
                    {client?.name} x {c.adverseParty}
                  </p>
                </div>
                <div className="flex items-center gap-2">
                  <Button variant="outline" size="sm" onClick={() => handleOpen(c)}>
                    <Edit className="h-4 w-4" />
                  </Button>
                  {state.currentUser.role === 'Admin' && (
                    <Button
                      variant="outline"
                      size="sm"
                      className="text-red-500 border-red-200 hover:bg-red-50"
                      onClick={() => handleDelete(c.id)}
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  )}
                </div>
              </CardContent>
            </Card>
          )
        })}
      </div>
    </div>
  )
}
