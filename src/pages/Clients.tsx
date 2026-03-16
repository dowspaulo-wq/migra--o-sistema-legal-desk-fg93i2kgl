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
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { Label } from '@/components/ui/label'
import {
  Plus,
  ExternalLink,
  Star,
  MessageCircle,
  Edit,
  Trash2,
  LayoutGrid,
  List,
  Filter,
  ArrowUp,
  ArrowDown,
  ArrowUpDown,
} from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'
import { ClientDialog } from '@/components/ClientDialog'

export default function Clients() {
  const { state, addClient, updateItem, deleteItem } = useLegalStore()
  const [searchTerm, setSearchTerm] = useState('')
  const [statusFilter, setStatusFilter] = useState('Todos')
  const [typeFilter, setTypeFilter] = useState('Todos')
  const [respFilter, setRespFilter] = useState('Todos')
  const [captacaoFilter, setCaptacaoFilter] = useState('Todos')
  const [open, setOpen] = useState(false)
  const [editingClient, setEditingClient] = useState<any>(null)
  const [sortConfig, setSortConfig] = useState<{ key: string; direction: 'asc' | 'desc' } | null>(
    null,
  )

  const sortedUsers = [...state.users].sort((a, b) => a.name.localeCompare(b.name))
  const sortedCaptacao = [...(state.settings?.captacaoOptions || [])].sort((a, b) =>
    a.localeCompare(b),
  )

  const filtered = state.clients.filter((c) => {
    const matchSearch =
      c.name.toLowerCase().includes(searchTerm.toLowerCase()) || c.document.includes(searchTerm)
    const matchStatus = statusFilter === 'Todos' || c.status === statusFilter
    const matchType = typeFilter === 'Todos' || c.type === typeFilter
    const matchResp = respFilter === 'Todos' || c.responsibleId === respFilter
    const matchCaptacao = captacaoFilter === 'Todos' || c.captacao === captacaoFilter
    return matchSearch && matchStatus && matchType && matchResp && matchCaptacao
  })

  const sortedAndFiltered = [...filtered].sort((a: any, b: any) => {
    if (!sortConfig) return 0
    const { key, direction } = sortConfig
    let valA = a[key]
    let valB = b[key]

    if (key === 'responsibleId') {
      valA = state.users.find((u) => u.id === valA)?.name || ''
      valB = state.users.find((u) => u.id === valB)?.name || ''
    } else if (key === 'captacao') {
      valA = valA || ''
      valB = valB || ''
    } else if (typeof valA === 'string' && typeof valB === 'string') {
      valA = valA.toLowerCase()
      valB = valB.toLowerCase()
    }

    if (valA < valB) return direction === 'asc' ? -1 : 1
    if (valA > valB) return direction === 'asc' ? 1 : -1
    return 0
  })

  const handleSort = (key: string) => {
    setSortConfig((current) => {
      if (current?.key === key) {
        return { key, direction: current.direction === 'asc' ? 'desc' : 'asc' }
      }
      return { key, direction: 'asc' }
    })
  }

  const handleOpen = (client?: any) => {
    setEditingClient(client || null)
    setOpen(true)
  }

  const handleSave = (fd: any) => {
    if (editingClient) {
      updateItem('clients', editingClient.id, fd)
      toast({ title: 'Cliente atualizado' })
    } else {
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
        settings={state.settings}
      />

      <Card className="shadow-sm">
        <CardHeader className="py-4 flex flex-col md:flex-row gap-4">
          <div className="flex gap-2 w-full max-w-md">
            <Input
              type="search"
              placeholder="Buscar por nome ou CPF..."
              className="flex-1"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
            <Popover>
              <PopoverTrigger asChild>
                <Button variant="outline" className="flex items-center gap-2">
                  <Filter className="h-4 w-4" /> Filtros
                </Button>
              </PopoverTrigger>
              <PopoverContent className="w-80 space-y-4">
                <h4 className="font-medium text-sm border-b pb-2">Filtros Avançados</h4>
                <div className="space-y-2">
                  <Label className="text-xs">Status</Label>
                  <Select value={statusFilter} onValueChange={setStatusFilter}>
                    <SelectTrigger>
                      <SelectValue placeholder="Status" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Todos">Todos</SelectItem>
                      <SelectItem value="Ativo">Ativo</SelectItem>
                      <SelectItem value="Baixado">Baixado</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label className="text-xs">Tipo de Pessoa</Label>
                  <Select value={typeFilter} onValueChange={setTypeFilter}>
                    <SelectTrigger>
                      <SelectValue placeholder="Tipo" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Todos">Todos</SelectItem>
                      <SelectItem value="PF">Pessoa Física</SelectItem>
                      <SelectItem value="PJ">Pessoa Jurídica</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label className="text-xs">Responsável</Label>
                  <Select value={respFilter} onValueChange={setRespFilter}>
                    <SelectTrigger>
                      <SelectValue placeholder="Responsável" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Todos">Todos</SelectItem>
                      {sortedUsers.map((u) => (
                        <SelectItem key={u.id} value={u.id}>
                          {u.name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label className="text-xs">Captação</Label>
                  <Select value={captacaoFilter} onValueChange={setCaptacaoFilter}>
                    <SelectTrigger>
                      <SelectValue placeholder="Captação" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Todos">Todos</SelectItem>
                      {sortedCaptacao.map((c) => (
                        <SelectItem key={c} value={c}>
                          {c}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <Button
                  variant="ghost"
                  size="sm"
                  className="w-full mt-2"
                  onClick={() => {
                    setStatusFilter('Todos')
                    setTypeFilter('Todos')
                    setRespFilter('Todos')
                    setCaptacaoFilter('Todos')
                  }}
                >
                  Limpar Filtros
                </Button>
              </PopoverContent>
            </Popover>
          </div>
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
                    <TableHead
                      onClick={() => handleSort('name')}
                      className="cursor-pointer select-none hover:bg-slate-50 transition-colors"
                    >
                      <div className="flex items-center gap-2">
                        Nome
                        {sortConfig?.key === 'name' ? (
                          sortConfig.direction === 'asc' ? (
                            <ArrowUp className="h-3 w-3" />
                          ) : (
                            <ArrowDown className="h-3 w-3" />
                          )
                        ) : (
                          <ArrowUpDown className="h-3 w-3 opacity-20" />
                        )}
                      </div>
                    </TableHead>
                    <TableHead
                      onClick={() => handleSort('document')}
                      className="cursor-pointer select-none hover:bg-slate-50 transition-colors"
                    >
                      <div className="flex items-center gap-2">
                        CPF/CNPJ
                        {sortConfig?.key === 'document' ? (
                          sortConfig.direction === 'asc' ? (
                            <ArrowUp className="h-3 w-3" />
                          ) : (
                            <ArrowDown className="h-3 w-3" />
                          )
                        ) : (
                          <ArrowUpDown className="h-3 w-3 opacity-20" />
                        )}
                      </div>
                    </TableHead>
                    <TableHead
                      onClick={() => handleSort('phone')}
                      className="cursor-pointer select-none hover:bg-slate-50 transition-colors"
                    >
                      <div className="flex items-center gap-2">
                        Contato
                        {sortConfig?.key === 'phone' ? (
                          sortConfig.direction === 'asc' ? (
                            <ArrowUp className="h-3 w-3" />
                          ) : (
                            <ArrowDown className="h-3 w-3" />
                          )
                        ) : (
                          <ArrowUpDown className="h-3 w-3 opacity-20" />
                        )}
                      </div>
                    </TableHead>
                    <TableHead
                      onClick={() => handleSort('responsibleId')}
                      className="cursor-pointer select-none hover:bg-slate-50 transition-colors"
                    >
                      <div className="flex items-center gap-2">
                        Responsável
                        {sortConfig?.key === 'responsibleId' ? (
                          sortConfig.direction === 'asc' ? (
                            <ArrowUp className="h-3 w-3" />
                          ) : (
                            <ArrowDown className="h-3 w-3" />
                          )
                        ) : (
                          <ArrowUpDown className="h-3 w-3 opacity-20" />
                        )}
                      </div>
                    </TableHead>
                    <TableHead
                      onClick={() => handleSort('captacao')}
                      className="cursor-pointer select-none hover:bg-slate-50 transition-colors"
                    >
                      <div className="flex items-center gap-2">
                        Captação
                        {sortConfig?.key === 'captacao' ? (
                          sortConfig.direction === 'asc' ? (
                            <ArrowUp className="h-3 w-3" />
                          ) : (
                            <ArrowDown className="h-3 w-3" />
                          )
                        ) : (
                          <ArrowUpDown className="h-3 w-3 opacity-20" />
                        )}
                      </div>
                    </TableHead>
                    <TableHead
                      onClick={() => handleSort('status')}
                      className="cursor-pointer select-none hover:bg-slate-50 transition-colors"
                    >
                      <div className="flex items-center gap-2">
                        Status
                        {sortConfig?.key === 'status' ? (
                          sortConfig.direction === 'asc' ? (
                            <ArrowUp className="h-3 w-3" />
                          ) : (
                            <ArrowDown className="h-3 w-3" />
                          )
                        ) : (
                          <ArrowUpDown className="h-3 w-3 opacity-20" />
                        )}
                      </div>
                    </TableHead>
                    <TableHead className="text-right">Ações</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {sortedAndFiltered.map((c) => (
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
                      <TableCell>{c.captacao || '—'}</TableCell>
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
              {sortedAndFiltered.map((c) => {
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
                        <p>
                          Captação: <span className="font-medium">{c.captacao || '—'}</span>
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
