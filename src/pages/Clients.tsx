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
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Plus,
  ExternalLink,
  Star,
  MessageCircle,
  Edit,
  Trash2,
  LayoutGrid,
  List,
} from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'
import { ClientDialog } from '@/components/ClientDialog'

export default function Clients() {
  const { state, addClient, updateItem, deleteItem } = useLegalStore()
  const [searchTerm, setSearchTerm] = useState('')
  const [statusFilter, setStatusFilter] = useState('Todos')
  const [open, setOpen] = useState(false)
  const [editingClient, setEditingClient] = useState<any>(null)

  const filtered = state.clients.filter((c) => {
    const matchSearch =
      c.name.toLowerCase().includes(searchTerm.toLowerCase()) || c.document.includes(searchTerm)
    const matchStatus = statusFilter === 'Todos' || c.status === statusFilter
    return matchSearch && matchStatus
  })

  const handleOpen = (client?: any) => {
    setEditingClient(client || null)
    setOpen(true)
  }

  const handleSave = (fd: any) => {
    if (editingClient) {
      updateItem('clients', editingClient.id, fd)
      toast({ title: 'Cliente atualizado' })
    } else {
      if (state.clients.some((c) => c.document === fd.document))
        return toast({ title: 'Erro', description: 'CPF já cadastrado', variant: 'destructive' })
      addClient(fd)
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Clientes</h1>
          <p className="text-muted-foreground">Gestão completa da carteira.</p>
        </div>
        <Button onClick={() => handleOpen()}>
          <Plus className="mr-2 h-4 w-4" /> Novo Cliente
        </Button>
      </div>

      <ClientDialog
        open={open}
        onOpenChange={setOpen}
        client={editingClient}
        onSave={handleSave}
        users={state.users}
      />

      <Card className="shadow-sm">
        <CardHeader className="py-4 flex flex-col md:flex-row gap-4">
          <Input
            type="search"
            placeholder="Buscar por nome ou CPF..."
            className="max-w-sm"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
          />
          <Select value={statusFilter} onValueChange={setStatusFilter}>
            <SelectTrigger className="max-w-[150px]">
              <SelectValue placeholder="Status" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="Todos">Todos</SelectItem>
              <SelectItem value="Ativo">Ativo</SelectItem>
              <SelectItem value="Baixado">Baixado</SelectItem>
            </SelectContent>
          </Select>
        </CardHeader>
        <CardContent>
          <Tabs defaultValue="list">
            <div className="flex justify-end mb-4">
              <TabsList>
                <TabsTrigger value="list">
                  <List className="h-4 w-4 mr-2" /> Lista
                </TabsTrigger>
                <TabsTrigger value="grid">
                  <LayoutGrid className="h-4 w-4 mr-2" /> Grade
                </TabsTrigger>
              </TabsList>
            </div>
            <TabsContent value="list">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Nome</TableHead>
                    <TableHead>CPF/CNPJ</TableHead>
                    <TableHead>Contato</TableHead>
                    <TableHead>Responsável</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead className="text-right">Ações</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filtered.map((c) => (
                    <TableRow key={c.id}>
                      <TableCell className="font-medium">
                        <div className="flex items-center gap-2">
                          <Star
                            className={`h-4 w-4 cursor-pointer ${c.isSpecial ? 'fill-yellow-400 text-yellow-400' : 'text-slate-300'}`}
                            onClick={() => updateItem('clients', c.id, { isSpecial: !c.isSpecial })}
                          />{' '}
                          {c.name}{' '}
                          <Badge variant="outline" className="text-[10px]">
                            {c.type}
                          </Badge>
                        </div>
                      </TableCell>
                      <TableCell>{c.document}</TableCell>
                      <TableCell className="text-sm flex items-center gap-2">
                        {c.phone}{' '}
                        {c.phone && (
                          <a
                            href={`https://wa.me/${c.phone.replace(/\D/g, '')}`}
                            target="_blank"
                            rel="noreferrer"
                            className="text-green-500 hover:scale-110 transition-transform"
                          >
                            <MessageCircle className="h-4 w-4" />
                          </a>
                        )}
                      </TableCell>
                      <TableCell>
                        {state.users.find((u) => u.id === c.responsibleId)?.name}
                      </TableCell>
                      <TableCell>
                        <Badge variant={c.status === 'Ativo' ? 'default' : 'secondary'}>
                          {c.status}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-right">
                        <div className="flex justify-end gap-2">
                          <Button variant="ghost" size="icon" asChild>
                            <Link to={`/clientes/${c.id}`}>
                              <ExternalLink className="h-4 w-4" />
                            </Link>
                          </Button>
                          <Button variant="ghost" size="icon" onClick={() => handleOpen(c)}>
                            <Edit className="h-4 w-4" />
                          </Button>
                          {state.currentUser.role === 'Admin' && (
                            <Button
                              variant="ghost"
                              size="icon"
                              className="text-red-500"
                              onClick={() => {
                                if (confirm('Tem certeza?')) deleteItem('clients', c.id)
                              }}
                            >
                              <Trash2 className="h-4 w-4" />
                            </Button>
                          )}
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TabsContent>
            <TabsContent
              value="grid"
              className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4"
            >
              {filtered.map((c) => {
                const caseCount = state.cases.filter((x) => x.clientId === c.id).length
                return (
                  <Card key={c.id} className="relative overflow-hidden group">
                    <div
                      className={`absolute top-0 left-0 w-1 h-full ${c.status === 'Ativo' ? 'bg-green-500' : 'bg-slate-300'}`}
                    />
                    <CardContent className="p-4 pl-5">
                      <div className="flex justify-between items-start">
                        <div>
                          <h3 className="font-bold flex items-center gap-1">
                            {c.name}{' '}
                            {c.isSpecial && (
                              <Star className="h-3 w-3 fill-yellow-400 text-yellow-400" />
                            )}
                          </h3>
                          <p className="text-xs text-muted-foreground">
                            {c.type} • {c.document}
                          </p>
                        </div>
                        <Badge variant={c.status === 'Ativo' ? 'default' : 'secondary'}>
                          {c.status}
                        </Badge>
                      </div>
                      <div className="mt-4 space-y-1 text-sm">
                        <p>
                          Resp:{' '}
                          <span className="font-medium">
                            {state.users.find((u) => u.id === c.responsibleId)?.name}
                          </span>
                        </p>
                        <p className="flex items-center gap-2">
                          Tel: {c.phone}{' '}
                          {c.phone && (
                            <a
                              href={`https://wa.me/${c.phone.replace(/\D/g, '')}`}
                              target="_blank"
                              rel="noreferrer"
                              className="text-green-500"
                            >
                              <MessageCircle className="h-4 w-4" />
                            </a>
                          )}
                        </p>
                        <p>
                          Processos: <span className="font-bold">{caseCount}</span>
                        </p>
                      </div>
                      <div className="mt-4 flex gap-2">
                        <Button size="sm" variant="outline" className="flex-1" asChild>
                          <Link to={`/clientes/${c.id}`}>Ver Detalhes</Link>
                        </Button>
                        <Button size="sm" variant="outline" onClick={() => handleOpen(c)}>
                          <Edit className="h-4 w-4" />
                        </Button>
                      </div>
                    </CardContent>
                  </Card>
                )
              })}
            </TabsContent>
          </Tabs>
        </CardContent>
      </Card>
    </div>
  )
}
