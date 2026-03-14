import { useState } from 'react'
import { Card, CardContent, CardHeader } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Search, Plus, Filter } from 'lucide-react'
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
import useLegalStore from '@/stores/useLegalStore'
import { Link } from 'react-router-dom'
import { toast } from '@/hooks/use-toast'

export default function Cases() {
  const { state, addCase } = useLegalStore()
  const [search, setSearch] = useState('')
  const [open, setOpen] = useState(false)
  const [sortBy, setSortBy] = useState('recent') // recent, urgent

  const [fd, setFd] = useState({
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
  })

  const filtered = state.cases
    .filter(
      (c) =>
        c.number.includes(search) || c.adverseParty.toLowerCase().includes(search.toLowerCase()),
    )
    .sort((a, b) => {
      if (sortBy === 'urgent')
        return new Date(a.updatedAt).getTime() - new Date(b.updatedAt).getTime() // oldest updated first
      return new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime()
    })

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (state.cases.some((c) => c.number === fd.number))
      return toast({ title: 'Erro', description: 'Número já cadastrado', variant: 'destructive' })
    addCase({ ...fd, startDate: new Date().toISOString().split('T')[0] })
    setOpen(false)
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Processos</h1>
          <p className="text-muted-foreground">
            Acompanhamento e gestão de casos judiciais e extrajudiciais.
          </p>
        </div>
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogTrigger asChild>
            <Button>
              <Plus className="mr-2 h-4 w-4" /> Novo Processo
            </Button>
          </DialogTrigger>
          <DialogContent className="max-w-2xl">
            <form onSubmit={handleSubmit} className="grid gap-4 py-4">
              <DialogHeader>
                <DialogTitle>Cadastrar Processo</DialogTitle>
              </DialogHeader>
              <div className="grid grid-cols-2 gap-4">
                <div className="col-span-2 space-y-2">
                  <Label>Número CNJ *</Label>
                  <Input
                    required
                    value={fd.number}
                    onChange={(e) => setFd({ ...fd, number: e.target.value })}
                    placeholder="0000000-00.0000.0.00.0000"
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
                  <Label>Posição do Cliente</Label>
                  <Input
                    value={fd.position}
                    onChange={(e) => setFd({ ...fd, position: e.target.value })}
                  />
                </div>
                <div className="space-y-2">
                  <Label>Parte Adversa</Label>
                  <Input
                    value={fd.adverseParty}
                    onChange={(e) => setFd({ ...fd, adverseParty: e.target.value })}
                  />
                </div>
                <div className="space-y-2">
                  <Label>Sistema (PJE, e-SAJ)</Label>
                  <Input
                    value={fd.system}
                    onChange={(e) => setFd({ ...fd, system: e.target.value })}
                  />
                </div>
                <div className="space-y-2">
                  <Label>Vara</Label>
                  <Input
                    value={fd.court}
                    onChange={(e) => setFd({ ...fd, court: e.target.value })}
                  />
                </div>
                <div className="space-y-2">
                  <Label>Comarca / UF</Label>
                  <div className="flex gap-2">
                    <Input
                      value={fd.comarca}
                      onChange={(e) => setFd({ ...fd, comarca: e.target.value })}
                      className="flex-1"
                    />
                    <Input
                      value={fd.state}
                      onChange={(e) => setFd({ ...fd, state: e.target.value })}
                      className="w-16"
                    />
                  </div>
                </div>
              </div>
              <DialogFooter>
                <Button type="submit">Salvar e Criar Tarefa Inicial</Button>
              </DialogFooter>
            </form>
          </DialogContent>
        </Dialog>
      </div>

      <div className="flex gap-4 items-center">
        <div className="relative flex-1 max-w-md">
          <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
          <Input
            type="search"
            placeholder="Buscar número ou parte adversa..."
            className="pl-9"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <Select value={sortBy} onValueChange={setSortBy}>
          <SelectTrigger className="w-[180px]">
            <Filter className="w-4 h-4 mr-2" /> <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="recent">Última Movimentação</SelectItem>
            <SelectItem value="urgent">Sem Movimentação (Urgente)</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <div className="grid gap-4">
        {filtered.map((c) => {
          const client = state.clients.find((cl) => cl.id === c.clientId)
          const daysSinceUpdate = Math.floor(
            (new Date().getTime() - new Date(c.updatedAt).getTime()) / (1000 * 3600 * 24),
          )
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
                    {daysSinceUpdate > 30 && (
                      <Badge variant="destructive" className="animate-pulse">
                        Sem mov. há {daysSinceUpdate} dias
                      </Badge>
                    )}
                  </div>
                  <p className="text-sm font-medium">
                    {client?.name} ({c.position}) x {c.adverseParty}
                  </p>
                  <p className="text-xs text-muted-foreground">
                    {c.system} • {c.court} • {c.comarca}/{c.state} • Tipo: {c.type}
                  </p>
                </div>
                <div className="text-right flex flex-col justify-between">
                  <p className="text-xs text-muted-foreground">
                    Atualizado em: {new Date(c.updatedAt).toLocaleDateString('pt-BR')}
                  </p>
                  <Button variant="outline" size="sm" asChild className="mt-2">
                    <Link to={`/processos/${c.id}`}>Abrir Processo</Link>
                  </Button>
                </div>
              </CardContent>
            </Card>
          )
        })}
      </div>
    </div>
  )
}
