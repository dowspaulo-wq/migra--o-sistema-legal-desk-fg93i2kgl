import { useParams, Link } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { ArrowLeft, Clock, Scale, Users, DollarSign, CheckSquare } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'

export default function CaseDetail() {
  const { id } = useParams<{ id: string }>()
  const { state } = useLegalStore()

  const c = state.cases.find((x) => x.id === id)
  const client = state.clients.find((cl) => cl.id === c?.clientId)
  const tasks = state.tasks.filter((t) => t.relatedProcessId === id)

  if (!c) return <div className="p-8 text-center">Processo não encontrado.</div>

  // Time in progress calc
  const start = new Date(c.startDate)
  const now = new Date()
  const diffTime = Math.abs(now.getTime() - start.getTime())
  const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24))
  const years = Math.floor(diffDays / 365)
  const months = Math.floor((diffDays % 365) / 30)

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-4">
        <Button variant="outline" size="icon" asChild>
          <Link to="/processos">
            <ArrowLeft className="h-4 w-4" />
          </Link>
        </Button>
        <div>
          <h1 className="text-2xl md:text-3xl font-bold tracking-tight text-primary">{c.number}</h1>
          <p className="text-muted-foreground flex items-center gap-2 mt-1">
            <Badge variant="outline">{c.status}</Badge> • Sistema: {c.system} • Tempo: {years}a{' '}
            {months}m
          </p>
        </div>
      </div>

      <Tabs defaultValue="info" className="w-full">
        <TabsList className="grid w-full grid-cols-4 max-w-2xl">
          <TabsTrigger value="info">Informações</TabsTrigger>
          <TabsTrigger value="tasks">Tarefas</TabsTrigger>
          <TabsTrigger value="subs">Sub-processos</TabsTrigger>
          {state.currentUser.canViewFinance && (
            <TabsTrigger value="finance">Honorários</TabsTrigger>
          )}
        </TabsList>

        <TabsContent value="info" className="mt-4 grid gap-6 md:grid-cols-2">
          <Card className="shadow-sm">
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <Users className="h-5 w-5" /> Partes
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div>
                <p className="text-sm text-muted-foreground">Cliente ({c.position})</p>
                <Link
                  to={`/clientes/${client?.id}`}
                  className="font-medium text-primary hover:underline"
                >
                  {client?.name}
                </Link>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Parte Adversa</p>
                <p className="font-medium">{c.adverseParty}</p>
              </div>
            </CardContent>
          </Card>
          <Card className="shadow-sm">
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <Scale className="h-5 w-5" /> Juízo
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div>
                <p className="text-sm text-muted-foreground">Vara</p>
                <p className="font-medium">{c.court}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Comarca / UF</p>
                <p className="font-medium">
                  {c.comarca} - {c.state}
                </p>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="tasks" className="mt-4">
          <Card className="shadow-sm">
            <CardHeader className="flex flex-row items-center justify-between">
              <CardTitle className="text-lg flex items-center gap-2">
                <CheckSquare className="h-5 w-5" /> Tarefas Vinculadas
              </CardTitle>
              <Button size="sm">Nova Tarefa</Button>
            </CardHeader>
            <CardContent>
              <div className="space-y-2">
                {tasks.map((t) => (
                  <div
                    key={t.id}
                    className="flex justify-between items-center border p-3 rounded hover:bg-slate-50"
                  >
                    <div>
                      <p className="font-semibold text-sm">{t.title}</p>
                      <p className="text-xs text-muted-foreground">Vencimento: {t.dueDate}</p>
                    </div>
                    <Badge variant="outline">{t.status}</Badge>
                  </div>
                ))}
                {tasks.length === 0 && (
                  <p className="text-sm text-muted-foreground">Nenhuma tarefa vinculada.</p>
                )}
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="subs" className="mt-4">
          <Card className="shadow-sm">
            <CardContent className="py-8 text-center text-muted-foreground">
              Funcionalidade de Sub-processos / Recursos em desenvolvimento.
            </CardContent>
          </Card>
        </TabsContent>

        {state.currentUser.canViewFinance && (
          <TabsContent value="finance" className="mt-4">
            <Card className="shadow-sm border-green-200">
              <CardHeader>
                <CardTitle className="text-lg flex items-center gap-2 text-green-700">
                  <DollarSign className="h-5 w-5" /> Financeiro do Processo
                </CardTitle>
              </CardHeader>
              <CardContent>
                <div className="text-xl font-bold mb-4">
                  Valor da Causa: R$ {c.value.toLocaleString('pt-BR')}
                </div>
                <p className="text-sm text-muted-foreground text-center py-4 border-t">
                  Visualização restrita apenas a usuários autorizados.
                </p>
              </CardContent>
            </Card>
          </TabsContent>
        )}
      </Tabs>
    </div>
  )
}
