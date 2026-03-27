import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Card, CardContent } from '@/components/ui/card'
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
import { Label } from '@/components/ui/label'
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog'
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
  ChevronDown,
  ChevronUp,
  Search,
  X,
} from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'
import { ClientDialog } from '@/components/ClientDialog'
import { normalizeStr } from '@/lib/utils'

const initialFilters = {
  nome: '',
  documento: '',
  tipo: 'Todos',
  status: 'Todos',
  email: '',
  telefone: '',
  responsavelId: 'Todos',
  especial: 'Todos',
  classificacao: 'Todos',
}

export default function Clients() {
  const { state, addClient, updateItem, deleteItem } = useLegalStore()
  const [filters, setFilters] = useState(initialFilters)
  const [appliedFilters, setAppliedFilters] = useState(initialFilters)
  const [quickSearch, setQuickSearch] = useState('')
  const [searchOpen, setSearchOpen] = useState(true)
  const [open, setOpen] = useState(false)
  const [editingClient, setEditingClient] = useState<any>(null)
  const [sortConfig, setSortConfig] = useState<{ key: string; direction: 'asc' | 'desc' } | null>(
    null,
  )

  const sortedUsers = [...state.users].sort((a, b) => a.name.localeCompare(b.name))

  const filtered = state.clients.filter((c) => {
    if (quickSearch) {
      const q = normalizeStr(quickSearch)
      if (!normalizeStr(c.name).includes(q) && !normalizeStr(c.document).includes(q)) return false
    }
    const f = appliedFilters
    if (f.nome && !normalizeStr(c.name).includes(normalizeStr(f.nome))) return false
    if (f.documento && !normalizeStr(c.document).includes(normalizeStr(f.documento))) return false
    if (f.tipo !== 'Todos' && c.type !== f.tipo) return false
    if (f.status !== 'Todos' && c.status !== f.status) return false
    if (f.email && !normalizeStr(c.email).includes(normalizeStr(f.email))) return false
    if (f.telefone && !normalizeStr(c.phone).includes(normalizeStr(f.telefone))) return false
    if (f.responsavelId !== 'Todos' && c.responsibleId !== f.responsavelId) return false
    if (f.classificacao !== 'Todos' && (c.classification || 'SB') !== f.classificacao) return false
    if (f.especial !== 'Todos') {
      const isEspecial = f.especial === 'Sim'
      if (!!c.isSpecial !== isEspecial) return false
    }
    return true
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
    } else if (key === 'casesCount') {
      valA = state.cases.filter((x) => x.clientId === a.id).length
      valB = state.cases.filter((x) => x.clientId === b.id).length
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
        <div className="flex flex-col sm:flex-row w-full sm:w-auto items-center gap-2">
          <div className="relative flex-1 w-full sm:w-64">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Pesquisar nome ou doc..."
              className="pl-8"
              value={quickSearch}
              onChange={(e) => setQuickSearch(e.target.value)}
            />
          </div>
          <Button onClick={() => handleOpen()} className="w-full sm:w-auto shrink-0">
            <Plus className="mr-2 h-4 w-4" /> Novo Cliente
          </Button>
        </div>
      </div>

      <ClientDialog
        open={open}
        onOpenChange={setOpen}
        client={editingClient}
        onSave={handleSave}
        users={state.users}
        settings={state.settings}
      />

      <Collapsible
        open={searchOpen}
        onOpenChange={setSearchOpen}
        className="bg-card border rounded-lg shadow-sm"
      >
        <CollapsibleTrigger asChild>
          <div className="flex items-center justify-between p-4 cursor-pointer hover:bg-muted/50 transition-colors rounded-t-lg">
            <div className="flex items-center gap-2 font-bold text-primary">
              <Filter className="h-5 w-5" />
              Pesquisa Avançada
            </div>
            {searchOpen ? <ChevronUp className="h-5 w-5" /> : <ChevronDown className="h-5 w-5" />}
          </div>
        </CollapsibleTrigger>
        <CollapsibleContent className="px-4 pb-4">
          <div className="border-t pt-4 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">Nome do Cliente</Label>
              <Input
                placeholder="Buscar por nome..."
                value={filters.nome}
                onChange={(e) => setFilters({ ...filters, nome: e.target.value })}
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">
                Documento (CPF/CNPJ)
              </Label>
              <Input
                placeholder="Buscar por documento..."
                value={filters.documento}
                onChange={(e) => setFilters({ ...filters, documento: e.target.value })}
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">Tipo</Label>
              <Select
                value={filters.tipo}
                onValueChange={(v) => setFilters({ ...filters, tipo: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Todos" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Todos">Todos</SelectItem>
                  <SelectItem value="PF">Pessoa Física</SelectItem>
                  <SelectItem value="PJ">Pessoa Jurídica</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">Status</Label>
              <Select
                value={filters.status}
                onValueChange={(v) => setFilters({ ...filters, status: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Todos os status" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Todos">Todos os status</SelectItem>
                  <SelectItem value="Ativo">Ativo</SelectItem>
                  <SelectItem value="Baixado">Inativo (Baixado)</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">Classificação</Label>
              <Select
                value={filters.classificacao}
                onValueChange={(v) => setFilters({ ...filters, classificacao: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Todos" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Todos">Todos</SelectItem>
                  <SelectItem value="SB">SB</SelectItem>
                  <SelectItem value="DPS">DPS</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">E-mail</Label>
              <Input
                placeholder="Buscar por e-mail..."
                value={filters.email}
                onChange={(e) => setFilters({ ...filters, email: e.target.value })}
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">Telefone</Label>
              <Input
                placeholder="Buscar por telefone..."
                value={filters.telefone}
                onChange={(e) => setFilters({ ...filters, telefone: e.target.value })}
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">
                Colaborador Responsável
              </Label>
              <Select
                value={filters.responsavelId}
                onValueChange={(v) => setFilters({ ...filters, responsavelId: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Todos" />
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
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">
                Cliente Especial
              </Label>
              <Select
                value={filters.especial}
                onValueChange={(v) => setFilters({ ...filters, especial: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Todos" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Todos">Todos</SelectItem>
                  <SelectItem value="Sim">Sim</SelectItem>
                  <SelectItem value="Não">Não</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="flex justify-end gap-2 pt-4 mt-4 border-t">
            <Button
              variant="outline"
              onClick={() => {
                setFilters(initialFilters)
                setAppliedFilters(initialFilters)
                setQuickSearch('')
              }}
            >
              <X className="mr-2 h-4 w-4" /> Limpar Filtros
            </Button>
            <Button
              onClick={() => setAppliedFilters(filters)}
              className="bg-primary text-primary-foreground"
            >
              <Search className="mr-2 h-4 w-4" /> Pesquisar
            </Button>
          </div>
        </CollapsibleContent>
      </Collapsible>

      <Card className="shadow-sm">
        <CardContent className="p-4">
          <Tabs defaultValue="list">
            <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center mb-4 gap-2">
              <p className="text-sm font-medium text-muted-foreground">
                {sortedAndFiltered.length} cliente(s) encontrado(s)
              </p>
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
                    <TableHead
                      onClick={() => handleSort('casesCount')}
                      className="cursor-pointer select-none hover:bg-slate-50 transition-colors text-center"
                    >
                      <div className="flex items-center justify-center gap-2">
                        Processos
                        {sortConfig?.key === 'casesCount' ? (
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
                  {sortedAndFiltered.map((c) => {
                    const resp = state.users.find((u) => u.id === c.responsibleId)
                    const caseCount = state.cases.filter((x) => x.clientId === c.id).length
                    return (
                      <TableRow key={c.id}>
                        <TableCell className="font-medium">
                          <div className="flex items-center gap-2">
                            <Star
                              className={`h-4 w-4 cursor-pointer ${c.isSpecial ? 'fill-yellow-400 text-yellow-400' : 'text-slate-300'}`}
                              onClick={() =>
                                updateItem('clients', c.id, { isSpecial: !c.isSpecial })
                              }
                            />{' '}
                            {c.name}{' '}
                            <Badge variant="outline" className="text-[10px]">
                              {c.type}
                            </Badge>
                            <Badge variant="secondary" className="text-[10px]">
                              {c.classification || 'SB'}
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
                          {resp ? (
                            <span
                              className="text-xs px-2 py-0.5 rounded-full font-medium inline-block"
                              style={{
                                backgroundColor: `${resp.color}20`,
                                color: resp.color,
                                border: `1px solid ${resp.color}40`,
                              }}
                            >
                              {resp.name}
                            </span>
                          ) : (
                            '—'
                          )}
                        </TableCell>
                        <TableCell>{c.captacao || '—'}</TableCell>
                        <TableCell>
                          <Badge variant={c.status === 'Ativo' ? 'default' : 'secondary'}>
                            {c.status}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-center font-bold text-muted-foreground">
                          {caseCount}
                        </TableCell>
                        <TableCell className="text-right">
                          <div className="flex justify-end gap-2">
                            <Button variant="ghost" size="icon" asChild title="Abrir">
                              <Link to={`/clientes/${c.id}`}>
                                <ExternalLink className="h-4 w-4" />
                              </Link>
                            </Button>
                            <Button
                              variant="ghost"
                              size="icon"
                              onClick={() => handleOpen(c)}
                              title="Editar"
                            >
                              <Edit className="h-4 w-4" />
                            </Button>
                            <AlertDialog>
                              <AlertDialogTrigger asChild>
                                <Button
                                  variant="ghost"
                                  size="icon"
                                  className="text-red-500 hover:bg-red-50"
                                  title="Excluir"
                                >
                                  <Trash2 className="h-4 w-4" />
                                </Button>
                              </AlertDialogTrigger>
                              <AlertDialogContent>
                                <AlertDialogHeader>
                                  <AlertDialogTitle>Excluir Cliente?</AlertDialogTitle>
                                  <AlertDialogDescription>
                                    Esta ação é irreversível. Isso removerá o cliente e todo o seu
                                    histórico (processos, tarefas e agendamentos).
                                  </AlertDialogDescription>
                                </AlertDialogHeader>
                                <AlertDialogFooter>
                                  <AlertDialogCancel>Cancelar</AlertDialogCancel>
                                  <AlertDialogAction
                                    className="bg-red-600 hover:bg-red-700"
                                    onClick={() => deleteItem('clients', c.id)}
                                  >
                                    Excluir
                                  </AlertDialogAction>
                                </AlertDialogFooter>
                              </AlertDialogContent>
                            </AlertDialog>
                          </div>
                        </TableCell>
                      </TableRow>
                    )
                  })}
                </TableBody>
              </Table>
            </TabsContent>
            <TabsContent
              value="grid"
              className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4"
            >
              {sortedAndFiltered.map((c) => {
                const caseCount = state.cases.filter((x) => x.clientId === c.id).length
                const resp = state.users.find((u) => u.id === c.responsibleId)
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
                            {c.classification || 'SB'} • {c.type} • {c.document}
                          </p>
                        </div>
                        <Badge variant={c.status === 'Ativo' ? 'default' : 'secondary'}>
                          {c.status}
                        </Badge>
                      </div>
                      <div className="mt-4 space-y-1 text-sm">
                        <p className="flex items-center gap-1">
                          Resp:{' '}
                          {resp ? (
                            <span
                              className="text-[10px] px-2 py-0.5 rounded-full font-medium inline-block"
                              style={{
                                backgroundColor: `${resp.color}20`,
                                color: resp.color,
                                border: `1px solid ${resp.color}40`,
                              }}
                            >
                              {resp.name}
                            </span>
                          ) : (
                            <span className="font-medium">—</span>
                          )}
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
                        <AlertDialog>
                          <AlertDialogTrigger asChild>
                            <Button
                              size="sm"
                              variant="outline"
                              className="text-red-500 hover:bg-red-50 hover:text-red-600"
                              title="Excluir"
                            >
                              <Trash2 className="h-4 w-4 mr-1" /> Excluir
                            </Button>
                          </AlertDialogTrigger>
                          <AlertDialogContent>
                            <AlertDialogHeader>
                              <AlertDialogTitle>Excluir Cliente?</AlertDialogTitle>
                              <AlertDialogDescription>
                                Esta ação é irreversível. Isso removerá o cliente e todo o seu
                                histórico (processos, tarefas e agendamentos).
                              </AlertDialogDescription>
                            </AlertDialogHeader>
                            <AlertDialogFooter>
                              <AlertDialogCancel>Cancelar</AlertDialogCancel>
                              <AlertDialogAction
                                className="bg-red-600 hover:bg-red-700"
                                onClick={() => deleteItem('clients', c.id)}
                              >
                                Excluir
                              </AlertDialogAction>
                            </AlertDialogFooter>
                          </AlertDialogContent>
                        </AlertDialog>
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
