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
import { Search, Plus, ExternalLink, Star, MessageCircle } from 'lucide-react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
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
import { Textarea } from '@/components/ui/textarea'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'

export default function Clients() {
  const { state, addClient, setState } = useLegalStore()
  const [searchTerm, setSearchTerm] = useState('')
  const [open, setOpen] = useState(false)
  const [bulkOpen, setBulkOpen] = useState(false)
  const [bulkText, setBulkText] = useState('')

  const [fd, setFd] = useState({
    name: '',
    document: '',
    type: 'PF',
    email: '',
    phone: '',
    address: '',
    birthday: '',
    responsibleId: state.currentUser.id,
  })

  const filtered = state.clients.filter(
    (c) =>
      c.name.toLowerCase().includes(searchTerm.toLowerCase()) || c.document.includes(searchTerm),
  )

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (state.clients.some((c) => c.document === fd.document)) {
      return toast({ title: 'Erro', description: 'CPF/CNPJ já cadastrado', variant: 'destructive' })
    }
    addClient({ ...fd, type: fd.type as 'PF' | 'PJ', status: 'Ativo', isSpecial: false })
    setOpen(false)
    setFd({
      name: '',
      document: '',
      type: 'PF',
      email: '',
      phone: '',
      address: '',
      birthday: '',
      responsibleId: state.currentUser.id,
    })
  }

  const handleBulk = () => {
    const lines = bulkText.split('\n')
    let added = 0
    lines.forEach((line) => {
      const parts = line.split(';')
      if (parts.length >= 2 && !state.clients.some((c) => c.document === parts[1].trim())) {
        addClient({
          name: parts[0].trim(),
          document: parts[1].trim(),
          type: 'PF',
          email: '',
          phone: '',
          address: '',
          birthday: '',
          responsibleId: state.currentUser.id,
          status: 'Ativo',
          isSpecial: false,
        })
        added++
      }
    })
    toast({ title: 'Importação concluída', description: `${added} clientes importados.` })
    setBulkOpen(false)
    setBulkText('')
  }

  const toggleSpecial = (id: string) => {
    setState((prev) => ({
      ...prev,
      clients: prev.clients.map((c) => (c.id === id ? { ...c, isSpecial: !c.isSpecial } : c)),
    }))
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight text-slate-800 dark:text-slate-100">
            Clientes (CRM)
          </h1>
          <p className="text-muted-foreground">Gestão completa da carteira.</p>
        </div>
        <div className="flex gap-2">
          <Dialog open={bulkOpen} onOpenChange={setBulkOpen}>
            <DialogTrigger asChild>
              <Button variant="outline">Importação em Massa</Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Importar Clientes</DialogTitle>
              </DialogHeader>
              <p className="text-sm text-muted-foreground">
                Cole os dados separados por ponto-e-vírgula (Nome; CPF/CNPJ)
              </p>
              <Textarea
                rows={10}
                value={bulkText}
                onChange={(e) => setBulkText(e.target.value)}
                placeholder="João Silva; 12345678900"
              />
              <Button onClick={handleBulk}>Processar</Button>
            </DialogContent>
          </Dialog>

          <Dialog open={open} onOpenChange={setOpen}>
            <DialogTrigger asChild>
              <Button>
                <Plus className="mr-2 h-4 w-4" /> Novo Cliente
              </Button>
            </DialogTrigger>
            <DialogContent className="sm:max-w-[500px]">
              <form onSubmit={handleSubmit} className="grid gap-4 py-4">
                <DialogHeader>
                  <DialogTitle>Cadastrar Cliente</DialogTitle>
                </DialogHeader>
                <div className="grid grid-cols-2 gap-4">
                  <div className="col-span-2 space-y-2">
                    <Label>Nome Completo / Razão Social *</Label>
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
                        <SelectItem value="PF">Física (PF)</SelectItem>
                        <SelectItem value="PJ">Jurídica (PJ)</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="space-y-2">
                    <Label>CPF / CNPJ *</Label>
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
                    <Label>Telefone (WhatsApp)</Label>
                    <Input
                      value={fd.phone}
                      onChange={(e) => setFd({ ...fd, phone: e.target.value })}
                      placeholder="5511999999999"
                    />
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
        </div>
      </div>

      <Card className="shadow-sm">
        <CardHeader className="py-4">
          <div className="relative w-full max-w-sm">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
            <Input
              type="search"
              placeholder="Buscar por nome ou CPF/CNPJ..."
              className="pl-9"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
          </div>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-12"></TableHead>
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
                  <TableCell>
                    <button onClick={() => toggleSpecial(client.id)} className="focus:outline-none">
                      <Star
                        className={`h-5 w-5 ${client.isSpecial ? 'fill-yellow-400 text-yellow-400' : 'text-slate-300'}`}
                      />
                    </button>
                  </TableCell>
                  <TableCell className="font-medium">
                    {client.name}{' '}
                    <Badge variant="outline" className="ml-2 text-[10px]">
                      {client.type}
                    </Badge>
                  </TableCell>
                  <TableCell>{client.document}</TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <span className="text-sm">{client.phone}</span>
                      {client.phone && (
                        <a
                          href={`https://wa.me/${client.phone.replace(/\D/g, '')}`}
                          target="_blank"
                          rel="noreferrer"
                          className="text-green-500 hover:text-green-600"
                        >
                          <MessageCircle className="h-4 w-4" />
                        </a>
                      )}
                    </div>
                  </TableCell>
                  <TableCell>
                    <Badge variant={client.status === 'Ativo' ? 'default' : 'secondary'}>
                      {client.status}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-right">
                    <Button variant="ghost" size="sm" asChild>
                      <Link to={`/clientes/${client.id}`}>
                        <ExternalLink className="h-4 w-4 mr-2" /> Detalhes
                      </Link>
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
              {filtered.length === 0 && (
                <TableRow>
                  <TableCell colSpan={6} className="text-center py-8">
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
