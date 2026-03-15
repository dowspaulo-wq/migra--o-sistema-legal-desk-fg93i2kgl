import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Briefcase, Users, CheckSquare, DollarSign, AlertTriangle, Calendar } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { Link } from 'react-router-dom'
import { ChartContainer, ChartTooltip, ChartTooltipContent } from '@/components/ui/chart'
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from 'recharts'
import { Badge } from '@/components/ui/badge'

const COLORS = [
  'hsl(var(--chart-1))',
  'hsl(var(--chart-2))',
  'hsl(var(--chart-3))',
  'hsl(var(--chart-4))',
  'hsl(var(--chart-5))',
]

export default function Index() {
  const { state } = useLegalStore()

  const pendingProtocol = state.tasks.filter((t) => t.status === 'Aguarda protocolo')
  const myTasks = state.tasks.filter(
    (t) => t.responsibleId === state.currentUser.id && t.status !== 'Concluída',
  )

  const processStatusData = Object.entries(
    state.cases.reduce(
      (acc, c) => {
        acc[c.status] = (acc[c.status] || 0) + 1
        return acc
      },
      {} as Record<string, number>,
    ),
  ).map(([name, value]) => ({ name, value }))

  const clientsPerUser = state.users
    .map((u) => ({
      name: u.name,
      value: state.clients.filter((c) => c.responsibleId === u.id).length,
    }))
    .filter((x) => x.value > 0)

  const casesPerUser = state.users
    .map((u) => ({
      name: u.name,
      value: state.cases.filter((c) => c.responsibleId === u.id).length,
    }))
    .filter((x) => x.value > 0)

  const totalIncome = state.transactions
    .filter((t) => t.type === 'income' && t.status === 'Pago')
    .reduce((sum, t) => sum + t.amount, 0)
  const todayAppts = state.appointments.filter(
    (a) => new Date(a.date).toDateString() === new Date().toDateString(),
  )

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-3xl font-bold tracking-tight text-slate-800 dark:text-slate-100">
            Painel SBJur
          </h1>
          <p className="text-muted-foreground mt-1">Visão geral do escritório.</p>
        </div>
      </div>

      {pendingProtocol.length > 0 && (
        <Alert
          variant="destructive"
          className="animate-fade-in border-destructive/50 bg-destructive/5"
        >
          <AlertTriangle className="h-4 w-4" />
          <AlertTitle>Atenção - Protocolos Pendentes</AlertTitle>
          <AlertDescription>
            Existem {pendingProtocol.length} tarefas aguardando protocolo urgente.{' '}
            <Link to="/tarefas?status=Aguarda+protocolo" className="underline font-bold">
              Ver tarefas
            </Link>
          </AlertDescription>
        </Alert>
      )}

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <Card className="shadow-sm">
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Processos Ativos</CardTitle>
            <Briefcase className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{state.cases.length}</div>
          </CardContent>
        </Card>
        <Card className="shadow-sm">
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Clientes Cadastrados</CardTitle>
            <Users className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{state.clients.length}</div>
          </CardContent>
        </Card>
        <Card className="shadow-sm">
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Minhas Tarefas Pendentes</CardTitle>
            <CheckSquare className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{myTasks.length}</div>
            <Link
              to={`/tarefas?resp=${state.currentUser.id}&status=Pendente`}
              className="text-xs text-primary hover:underline"
            >
              Ver lista filtrada
            </Link>
          </CardContent>
        </Card>
        {state.currentUser.canViewFinance && state.settings.showFinanceDashboard && (
          <Card className="shadow-sm">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Receita Global (Paga)</CardTitle>
              <DollarSign className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold text-green-600">
                R$ {totalIncome.toLocaleString('pt-BR')}
              </div>
            </CardContent>
          </Card>
        )}
      </div>

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
        <Card className="shadow-sm">
          <CardHeader>
            <CardTitle className="text-sm">Status dos Processos</CardTitle>
          </CardHeader>
          <CardContent className="h-48 flex justify-center">
            <ChartContainer config={{}} className="h-full w-full">
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie
                    data={processStatusData}
                    dataKey="value"
                    nameKey="name"
                    cx="50%"
                    cy="50%"
                    innerRadius={40}
                    outerRadius={60}
                    paddingAngle={5}
                  >
                    {processStatusData.map((e, i) => (
                      <Cell key={`c-${i}`} fill={COLORS[i % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip />
                </PieChart>
              </ResponsiveContainer>
            </ChartContainer>
          </CardContent>
        </Card>

        <Card className="shadow-sm">
          <CardHeader>
            <CardTitle className="text-sm">Clientes por Colaborador</CardTitle>
          </CardHeader>
          <CardContent className="h-48 flex justify-center">
            <ChartContainer config={{}} className="h-full w-full">
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie
                    data={clientsPerUser}
                    dataKey="value"
                    nameKey="name"
                    cx="50%"
                    cy="50%"
                    innerRadius={40}
                    outerRadius={60}
                    paddingAngle={5}
                  >
                    {clientsPerUser.map((e, i) => (
                      <Cell key={`c-${i}`} fill={COLORS[(i + 2) % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip />
                </PieChart>
              </ResponsiveContainer>
            </ChartContainer>
          </CardContent>
        </Card>

        <Card className="shadow-sm">
          <CardHeader>
            <CardTitle className="text-sm">Processos por Colaborador</CardTitle>
          </CardHeader>
          <CardContent className="h-48 flex justify-center">
            <ChartContainer config={{}} className="h-full w-full">
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie
                    data={casesPerUser}
                    dataKey="value"
                    nameKey="name"
                    cx="50%"
                    cy="50%"
                    innerRadius={40}
                    outerRadius={60}
                    paddingAngle={5}
                  >
                    {casesPerUser.map((e, i) => (
                      <Cell key={`c-${i}`} fill={COLORS[(i + 4) % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip />
                </PieChart>
              </ResponsiveContainer>
            </ChartContainer>
          </CardContent>
        </Card>

        <Card className="shadow-sm lg:col-span-2">
          <CardHeader>
            <CardTitle className="text-sm">Processos Recentes</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {state.cases.slice(0, 5).map((c) => (
                <div
                  key={c.id}
                  className="flex justify-between items-start border-b pb-2 last:border-0"
                >
                  <div>
                    <Link
                      to={`/processos/${c.id}`}
                      className="text-sm font-medium hover:underline text-primary"
                    >
                      {c.number}
                    </Link>
                    <p className="text-xs text-muted-foreground">
                      {c.type} • Resp: {state.users.find((u) => u.id === c.responsibleId)?.name}
                    </p>
                  </div>
                  <Badge variant="outline" className="text-[10px]">
                    {c.status}
                  </Badge>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>

        <Card className="shadow-sm lg:col-span-1">
          <CardHeader>
            <CardTitle className="text-sm">Compromissos Hoje</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {todayAppts.length > 0 ? (
                todayAppts.map((a) => (
                  <div key={a.id} className="flex gap-3 items-center border-b pb-2 last:border-0">
                    <Calendar className="h-5 w-5 text-primary" />
                    <div>
                      <p className="text-sm font-medium leading-none">{a.title}</p>
                      <p className="text-xs text-muted-foreground">
                        {new Date(a.date).toLocaleTimeString('pt-BR', {
                          hour: '2-digit',
                          minute: '2-digit',
                        })}{' '}
                        - {a.type}
                      </p>
                    </div>
                  </div>
                ))
              ) : (
                <p className="text-sm text-muted-foreground text-center py-4">Agenda livre.</p>
              )}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
