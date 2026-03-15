import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Card, CardContent, CardHeader } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Badge } from '@/components/ui/badge'
import { Search, Plus, ExternalLink, Star, MessageCircle, Edit, Trash2 } from 'lucide-react'
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

export default function Clients() {
  const { state, addClient, updateItem, deleteItem } = useLegalStore()
  const [searchTerm, setSearchTerm] = useState('')
  const [open, setOpen] = useState(false)
  const [editingId, setEditingId] = useState<string | null>(null)

  const initialFd = {
    name: '',
    document: '',
    type: 'PF',
    email: '',
    phone: '',
    address: '',
    birthday: '',
    responsibleId: state.currentUser.id,
    status: 'Ativo',
  }
  const [fd, setFd] = useState(initialFd)

  const filtered = state.clients.filter(
    (c) =>
      c.name.toLowerCase().includes(searchTerm.toLowerCase()) || c.document.includes(searchTerm),
  )

  const handleOpen = (client?: any) => {
    if (client) {
      setFd(client)
      setEditingId(client.id)
    } else {
      setFd(initialFd)
      setEditingId(null)
    }
    setOpen(true)
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (editingId) {
      updateItem('clients', editingId, fd)
      toast({ title: 'Cliente atualizado' })
    } else {
      if (state.clients.some((c) => c.document === fd.document))
        return toast({
          title: 'Erro',
          description: 'Documento já cadastrado',
          variant: 'destructive',
        })
      addClient({
        ...fd,
        type: fd.type as 'PF' | 'PJ',
        status: fd.status as 'Ativo' | 'Baixado',
        isSpecial: false,
      })
    }
    setOpen(false)
  }

  const handleDelete = (id: string) => {
    if (window.confirm('Tem certeza? Isso excluirá processos e tarefas vinculadas.'))
      deleteItem('clients', id)
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Clientes (CRM)</h1>
          <p className="text-muted-foreground">Gestão completa da carteira.</p>
        </div>
        <Button onClick={() => handleOpen()}>
          <Plus className="mr-2 h-4 w-4" /> Novo Cliente
        </Button>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-[500px]">
          <form onSubmit={handleSubmit} className="grid gap-4 py-4">
            <DialogHeader>
              <DialogTitle>{editingId ? 'Editar' : 'Cadastrar'} Cliente</DialogTitle>
            </DialogHeader>
            <div className="grid grid-cols-2 gap-4">
              <div className="col-span-2 space-y-2">
                <Label>Nome Completo *</Label>
                <Input
                  required
                  value={fd.name}
                  onChange={(e) => setFd({ ...fd, name: e.target.value })}
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
                <Label>Documento *</Label>
                <Input
                  required
                  value={fd.document}
                  onChange={(e) => setFd({ ...fd, document: e.target.value })}
                />
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
              <div className="col-span-2 space-y-2">
                <Label>Endereço</Label>
                <Input
                  value={fd.address}
                  onChange={(e) => setFd({ ...fd, address: e.target.value })}
                />
              </div>
            </div>
            <DialogFooter>
              <Button type="submit">Salvar</Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      <Card className="shadow-sm">
        <CardHeader className="py-4">
          <Input
            type="search"
            placeholder="Buscar por nome ou documento..."
            className="max-w-sm"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
          />
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Nome</TableHead>
                <TableHead>Documento</TableHead>
                <TableHead>Contato</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="text-right">Ações</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {filtered.map((client) => (
                <TableRow key={client.id}>
                  <TableCell className="font-medium">
                    <div className="flex items-center gap-2">
                      <Star
                        className={`h-4 w-4 cursor-pointer ${client.isSpecial ? 'fill-yellow-400 text-yellow-400' : 'text-slate-300'}`}
                        onClick={() =>
                          updateItem('clients', client.id, { isSpecial: !client.isSpecial })
                        }
                      />
                      {client.name}{' '}
                      <Badge variant="outline" className="text-[10px]">
                        {client.type}
                      </Badge>
                    </div>
                  </TableCell>
                  <TableCell>{client.document}</TableCell>
                  <TableCell className="text-sm">{client.phone}</TableCell>
                  <TableCell>
                    <Badge variant={client.status === 'Ativo' ? 'default' : 'secondary'}>
                      {client.status}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-right">
                    <div className="flex justify-end gap-2">
                      <Button variant="ghost" size="icon" asChild>
                        <Link to={`/clientes/${client.id}`}>
                          <ExternalLink className="h-4 w-4" />
                        </Link>
                      </Button>
                      <Button variant="ghost" size="icon" onClick={() => handleOpen(client)}>
                        <Edit className="h-4 w-4" />
                      </Button>
                      {state.currentUser.role === 'Admin' && (
                        <Button
                          variant="ghost"
                          size="icon"
                          className="text-red-500"
                          onClick={() => handleDelete(client.id)}
                        >
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      )}
                    </div>
                  </TableCell>
                </TableRow>
              ))}
              {filtered.length === 0 && (
                <TableRow>
                  <TableCell colSpan={5} className="text-center py-8">
                    Nenhum cliente encontrado.
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  )
}
