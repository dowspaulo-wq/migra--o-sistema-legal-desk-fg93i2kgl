import { useState, useEffect } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import {
  Briefcase,
  Users,
  CheckSquare,
  DollarSign,
  AlertTriangle,
  Calendar,
  ChevronDown,
  ChevronUp,
  CheckCircle2,
  Clock,
  Gift,
} from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { Link, useNavigate } from 'react-router-dom'
import { ChartContainer, ChartTooltip, ChartTooltipContent } from '@/components/ui/chart'
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from 'recharts'
import { Badge } from '@/components/ui/badge'
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible'
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'
import { supabase } from '@/lib/supabase/client'

const COLORS = [
  'hsl(var(--chart-1))',
  'hsl(var(--chart-2))',
  'hsl(var(--chart-3))',
  'hsl(var(--chart-4))',
  'hsl(var(--chart-5))',
  'hsl(var(--chart-1)/0.7)',
  'hsl(var(--chart-2)/0.7)',
  'hsl(var(--chart-3)/0.7)',
]

const renderLabel = ({ name, value, percent }: any) => {
  return `${name}: ${value} (${(percent * 100).toFixed(0)}%)`
}

export default function Index() {
  const { state } = useLegalStore()
  const navigate = useNavigate()
  const [isTasksOpen, setIsTasksOpen] = useState(true)
  const [isAgendaOpen, setIsAgendaOpen] = useState(true)
  const [dbStatus, setDbStatus] = useState<'checking' | 'connected' | 'disconnected'>('checking')

  useEffect(() => {
    const checkConnection = async () => {
      try {
        const { error } = await supabase.from('settings').select('id').limit(1)
        setDbStatus(error ? 'disconnected' : 'connected')
      } catch (err) {
        setDbStatus('disconnected')
      }
    }
    checkConnection()
    const interval = setInterval(checkConnection, 15000)
    return () => clearInterval(interval)
  }, [])

  const pendingProtocol = state.tasks.filter((t) => t.status.toLowerCase() === 'aguarda protocolo')
  const myTasks = state.tasks.filter(
    (t) => t.responsibleId === state.currentUser.id && t.status.toLowerCase() !== 'concluída',
  )

  const processStatusData = Object.entries(
    state.cases.reduce(
      (acc, c) => {
        acc[c.status || ''] = (acc[c.status || ''] || 0) + 1
        return acc
      },
      {} as Record<string, number>,
    ),
  ).map(([name, value]) => ({ name: name || 'N/I', value }))

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

  const captacaoData = state.clients.reduce(
    (acc, c) => {
      const cap = c.captacao || 'Não Informado'
      acc[cap] = (acc[cap] || 0) + 1
      return acc
    },
    {} as Record<string, number>,
  )

  const captacaoChartData = Object.entries(captacaoData)
    .map(([name, value]) => ({ name, value }))
    .sort((a, b) => b.value - a.value)

  const totalIncome = state.transactions
    .filter((t) => t.type === 'income' && t.status === 'Pago')
    .reduce((sum, t) => sum + t.amount, 0)

  // Compute Today's string to avoid timezone parsing errors
  const getLocalDateStr = (d = new Date()) =>
    `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`

  const now = new Date()
  const todayStr = getLocalDateStr(now)

  const tomorrow = new Date(now)
  tomorrow.setDate(tomorrow.getDate() + 1)
  const tomorrowStr = getLocalDateStr(tomorrow)

  const todayAppts = state.appointments.filter((a) => a.date === todayStr)

  // Compute Task Management Dashboard stats
  const userTasksStats = state.users
    .map((user) => {
      const userTasks = state.tasks.filter((t) => t.responsibleId === user.id)
      const total = userTasks.length

      const incompleteTasks = userTasks.filter((t) => t.status.toLowerCase() !== 'concluída')

      const delayedDeadlines = incompleteTasks.filter((t) => {
        if (!t.dueDate) return false
        const isUpdate =
          t.type.toLowerCase() === 'atualização' || t.type.toLowerCase() === 'interna e adm'
        return t.dueDate < todayStr && !isUpdate
      }).length

      const delayedUpdates = incompleteTasks.filter((t) => {
        if (!t.dueDate) return false
        const isUpdate =
          t.type.toLowerCase() === 'atualização' || t.type.toLowerCase() === 'interna e adm'
        return t.dueDate < todayStr && isUpdate
      }).length

      const pending = userTasks.filter((t) => t.status.toLowerCase() === 'pendente').length
      const updating = userTasks.filter((t) => t.status.toLowerCase() === 'atualização').length
      const completed = userTasks.filter((t) => t.status.toLowerCase() === 'concluída').length

      const typesCount = userTasks.reduce(
        (acc, t) => {
          acc[t.type] = (acc[t.type] || 0) + 1
          return acc
        },
        {} as Record<string, number>,
      )

      const sortedTypes = Object.entries(typesCount).sort((a, b) => b[1] - a[1])

      return {
        user,
        total,
        delayedDeadlines,
        delayedUpdates,
        statusCounts: {
          Pendentes: pending,
          Atualização: updating,
          Concluídas: completed,
        },
        types: sortedTypes,
      }
    })
    .filter((u) => u.total > 0)
    .sort((a, b) => b.total - a.total)

  // Compute Agenda Management Dashboard stats
  const userAgendaStats = state.users
    .map((user) => {
      const userAppts = state.appointments.filter((a) => a.responsibleId === user.id)
      const todayCount = userAppts.filter((a) => a.date === todayStr).length
      const futureCount = userAppts.filter((a) => a.date > todayStr).length
      const pastCount = userAppts.filter((a) => a.date < todayStr).length

      const upcomingAppts = userAppts.filter((a) => a.date >= todayStr)
      const typesCount = upcomingAppts.reduce(
        (acc, a) => {
          acc[a.type] = (acc[a.type] || 0) + 1
          return acc
        },
        {} as Record<string, number>,
      )

      const sortedTypes = Object.entries(typesCount).sort((a, b) => b[1] - a[1])

      return {
        user,
        total: upcomingAppts.length,
        todayCount,
        futureCount,
        pastCount,
        types: sortedTypes,
      }
    })
    .filter((u) => u.total > 0 || u.pastCount > 0)
    .sort((a, b) => b.todayCount - a.todayCount || b.total - a.total)

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <div className="flex items-center gap-3">
            <h1 className="text-3xl font-bold tracking-tight text-slate-800 dark:text-slate-100">
              Painel SBJur
            </h1>
            <Tooltip>
              <TooltipTrigger asChild>
                <div
                  className={cn(
                    'h-4 w-4 rounded-full border-2 border-white shadow-sm mt-1 transition-colors duration-500',
                    dbStatus === 'checking'
                      ? 'bg-yellow-400 animate-pulse'
                      : dbStatus === 'connected'
                        ? 'bg-green-500'
                        : 'bg-red-500',
                  )}
                />
              </TooltipTrigger>
              <TooltipContent>
                <p>
                  {dbStatus === 'checking'
                    ? 'Verificando conexão...'
                    : dbStatus === 'connected'
                      ? 'Banco de dados conectado'
                      : 'Banco de dados desconectado'}
                </p>
              </TooltipContent>
            </Tooltip>
          </div>
          <p className="text-muted-foreground mt-1">Visão geral do escritório.</p>
        </div>
      </div>

      <Collapsible
        open={isAgendaOpen}
        onOpenChange={setIsAgendaOpen}
        className="bg-card rounded-xl border shadow-sm"
      >
        <div className="flex items-center justify-between px-6 py-4 border-b">
          <div className="flex items-center gap-2 text-primary font-semibold">
            <Calendar className="h-5 w-5" />
            <h2 className="text-lg">Agenda por Responsável</h2>
          </div>
          <CollapsibleTrigger asChild>
            <Button variant="ghost" size="sm" className="p-0 h-8 w-8">
              {isAgendaOpen ? (
                <ChevronUp className="h-5 w-5" />
              ) : (
                <ChevronDown className="h-5 w-5" />
              )}
            </Button>
          </CollapsibleTrigger>
        </div>
        <CollapsibleContent className="p-6">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {userAgendaStats.map((stat) => (
              <div
                key={stat.user.id}
                className={cn(
                  'border rounded-xl p-5 shadow-sm transition-colors',
                  stat.todayCount > 0
                    ? 'border-green-300 bg-green-50/30'
                    : 'border-slate-200 bg-card',
                )}
              >
                <div className="flex items-center gap-3 mb-4">
                  <Avatar>
                    <AvatarImage src={stat.user.avatar_url} />
                    <AvatarFallback className="bg-primary/10 text-primary font-bold">
                      {stat.user.name.substring(0, 2).toUpperCase()}
                    </AvatarFallback>
                  </Avatar>
                  <div>
                    <h3 className="font-semibold text-slate-800 dark:text-slate-100">
                      {stat.user.name}
                    </h3>
                    <p className="text-xs text-muted-foreground">
                      {stat.total} compromissos futuros/hoje
                    </p>
                  </div>
                </div>

                <div className="space-y-2 mb-4">
                  {stat.todayCount > 0 && (
                    <div
                      onClick={() =>
                        navigate(
                          `/agenda?resp=${stat.user.id}&dateFrom=${todayStr}&dateUntil=${todayStr}`,
                        )
                      }
                      className="flex items-center gap-2 bg-green-100/80 text-green-800 border border-green-200 rounded p-2 text-sm font-medium cursor-pointer hover:bg-green-200 transition-colors"
                    >
                      <Calendar className="h-4 w-4" />
                      {stat.todayCount} compromissos HOJE
                    </div>
                  )}
                </div>

                <div className="space-y-1.5 mb-4 border-b pb-4 text-sm">
                  <div
                    onClick={() =>
                      navigate(
                        `/agenda?resp=${stat.user.id}&dateFrom=${todayStr}&dateUntil=${todayStr}`,
                      )
                    }
                    className="flex justify-between items-center cursor-pointer hover:bg-slate-50 p-1 -mx-1 rounded transition-colors group"
                  >
                    <span className="text-muted-foreground group-hover:text-slate-800">Hoje:</span>
                    <span className="font-medium text-green-600 group-hover:underline">
                      {stat.todayCount}
                    </span>
                  </div>
                  <div
                    onClick={() => navigate(`/agenda?resp=${stat.user.id}&dateFrom=${tomorrowStr}`)}
                    className="flex justify-between items-center cursor-pointer hover:bg-slate-50 p-1 -mx-1 rounded transition-colors group"
                  >
                    <span className="text-muted-foreground group-hover:text-slate-800">
                      Próximos:
                    </span>
                    <span className="font-medium text-primary group-hover:underline">
                      {stat.futureCount}
                    </span>
                  </div>
                </div>

                <div>
                  <h4 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2">
                    Por Tipo (Futuros/Hoje)
                  </h4>
                  <div className="space-y-1">
                    {stat.types.map(([type, count]) => (
                      <div
                        key={type}
                        onClick={() =>
                          navigate(
                            `/agenda?resp=${stat.user.id}&dateFrom=${todayStr}&type=${encodeURIComponent(type)}`,
                          )
                        }
                        className="flex justify-between items-center text-sm cursor-pointer hover:bg-slate-50 p-1 -mx-1 rounded transition-colors group"
                      >
                        <span className="text-slate-700 dark:text-slate-300 capitalize-first flex items-center gap-1.5 group-hover:underline">
                          {type === 'Aniversário' && <Gift className="h-3 w-3 text-pink-500" />}
                          {type}
                        </span>
                        <span className="bg-slate-100 text-slate-700 dark:bg-slate-800 dark:text-slate-300 px-2 py-0.5 rounded text-xs font-medium">
                          {count}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            ))}
            {userAgendaStats.length === 0 && (
              <p className="text-sm text-muted-foreground col-span-full">
                Nenhum compromisso atribuído encontrado.
              </p>
            )}
          </div>
        </CollapsibleContent>
      </Collapsible>

      <Collapsible
        open={isTasksOpen}
        onOpenChange={setIsTasksOpen}
        className="bg-card rounded-xl border shadow-sm"
      >
        <div className="flex items-center justify-between px-6 py-4 border-b">
          <div className="flex items-center gap-2 text-primary font-semibold">
            <CheckCircle2 className="h-5 w-5" />
            <h2 className="text-lg">Tarefas por Responsável</h2>
          </div>
          <CollapsibleTrigger asChild>
            <Button variant="ghost" size="sm" className="p-0 h-8 w-8">
              {isTasksOpen ? (
                <ChevronUp className="h-5 w-5" />
              ) : (
                <ChevronDown className="h-5 w-5" />
              )}
            </Button>
          </CollapsibleTrigger>
        </div>
        <CollapsibleContent className="p-6">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {userTasksStats.map((stat) => (
              <div
                key={stat.user.id}
                className={cn(
                  'border rounded-xl p-5 shadow-sm transition-colors',
                  stat.delayedDeadlines > 0
                    ? 'border-red-300 bg-red-50/30'
                    : stat.delayedUpdates > 0
                      ? 'border-orange-300 bg-orange-50/30'
                      : 'border-slate-200 bg-card',
                )}
              >
                <div className="flex items-center gap-3 mb-4">
                  <Avatar>
                    <AvatarImage src={stat.user.avatar_url} />
                    <AvatarFallback className="bg-primary/10 text-primary font-bold">
                      {stat.user.name.substring(0, 2).toUpperCase()}
                    </AvatarFallback>
                  </Avatar>
                  <div>
                    <h3 className="font-semibold text-slate-800 dark:text-slate-100">
                      {stat.user.name}
                    </h3>
                    <p className="text-xs text-muted-foreground">{stat.total} tarefas</p>
                  </div>
                </div>

                <div className="space-y-2 mb-4">
                  {stat.delayedDeadlines > 0 && (
                    <div
                      onClick={() =>
                        navigate(
                          `/tarefas?resp=${stat.user.id}&statusNot=${encodeURIComponent('concluída')}&dateUntil=${todayStr}&typeNot=${encodeURIComponent('atualização,interna e adm')}`,
                        )
                      }
                      className="flex items-center gap-2 bg-red-100/80 text-red-700 border border-red-200 rounded p-2 text-sm font-medium cursor-pointer hover:bg-red-200 transition-colors"
                    >
                      <AlertTriangle className="h-4 w-4" />
                      {stat.delayedDeadlines} prazos atrasados!
                    </div>
                  )}
                  {stat.delayedUpdates > 0 && (
                    <div
                      onClick={() =>
                        navigate(
                          `/tarefas?resp=${stat.user.id}&statusNot=${encodeURIComponent('concluída')}&dateUntil=${todayStr}&typeIn=${encodeURIComponent('atualização,interna e adm')}`,
                        )
                      }
                      className="flex items-center gap-2 bg-orange-100/80 text-orange-800 border border-orange-200 rounded p-2 text-sm font-medium cursor-pointer hover:bg-orange-200 transition-colors"
                    >
                      <Clock className="h-4 w-4" />
                      {stat.delayedUpdates} atualizações atrasadas
                    </div>
                  )}
                </div>

                <div className="space-y-1.5 mb-4 border-b pb-4 text-sm">
                  <div
                    onClick={() => navigate(`/tarefas?resp=${stat.user.id}&status=pendente`)}
                    className="flex justify-between items-center cursor-pointer hover:bg-slate-50 p-1 -mx-1 rounded transition-colors group"
                  >
                    <span className="text-muted-foreground group-hover:text-slate-800">
                      Pendentes:
                    </span>
                    <span className="font-medium text-orange-600 group-hover:underline">
                      {stat.statusCounts.Pendentes}
                    </span>
                  </div>
                  <div
                    onClick={() =>
                      navigate(
                        `/tarefas?resp=${stat.user.id}&status=${encodeURIComponent('atualização')}`,
                      )
                    }
                    className="flex justify-between items-center cursor-pointer hover:bg-slate-50 p-1 -mx-1 rounded transition-colors group"
                  >
                    <span className="text-muted-foreground group-hover:text-slate-800">
                      Atualização:
                    </span>
                    <span className="font-medium text-primary group-hover:underline">
                      {stat.statusCounts.Atualização}
                    </span>
                  </div>
                  <div
                    onClick={() =>
                      navigate(
                        `/tarefas?resp=${stat.user.id}&status=${encodeURIComponent('concluída')}`,
                      )
                    }
                    className="flex justify-between items-center cursor-pointer hover:bg-slate-50 p-1 -mx-1 rounded transition-colors group"
                  >
                    <span className="text-muted-foreground group-hover:text-slate-800">
                      Concluídas:
                    </span>
                    <span className="font-medium text-secondary group-hover:underline">
                      {stat.statusCounts.Concluídas}
                    </span>
                  </div>
                </div>

                <div>
                  <h4 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2">
                    Por Tipo
                  </h4>
                  <div className="space-y-1">
                    {stat.types.map(([type, count]) => (
                      <div
                        key={type}
                        onClick={() =>
                          navigate(`/tarefas?resp=${stat.user.id}&type=${encodeURIComponent(type)}`)
                        }
                        className="flex justify-between items-center text-sm cursor-pointer hover:bg-slate-50 p-1 -mx-1 rounded transition-colors group"
                      >
                        <span className="text-primary dark:text-primary capitalize-first group-hover:underline">
                          {type}
                        </span>
                        <span className="bg-primary/10 text-primary dark:bg-primary/20 dark:text-primary-foreground px-2 py-0.5 rounded text-xs font-medium">
                          {count}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            ))}
            {userTasksStats.length === 0 && (
              <p className="text-sm text-muted-foreground col-span-full">
                Nenhuma tarefa atribuída encontrada.
              </p>
            )}
          </div>
        </CollapsibleContent>
      </Collapsible>

      {pendingProtocol.length > 0 && (
        <Alert
          variant="destructive"
          className="animate-fade-in border-destructive/50 bg-destructive/5"
        >
          <AlertTriangle className="h-4 w-4" />
          <AlertTitle>Atenção - Protocolos Pendentes</AlertTitle>
          <AlertDescription>
            Existem {pendingProtocol.length} tarefas aguardando protocolo urgente.{' '}
            <Link to="/tarefas?status=aguarda+protocolo" className="underline font-bold">
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
              to={`/tarefas?resp=${state.currentUser.id}&status=pendente`}
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
              <div className="text-2xl font-bold text-secondary">
                R$ {totalIncome.toLocaleString('pt-BR')}
              </div>
            </CardContent>
          </Card>
        )}
      </div>

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4 mb-6">
        <Card className="shadow-sm">
          <CardHeader>
            <CardTitle className="text-sm">Status dos Processos</CardTitle>
          </CardHeader>
          <CardContent className="h-56 flex justify-center">
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
                    label={renderLabel}
                  >
                    {processStatusData.map((e, i) => (
                      <Cell key={`c-${i}`} fill={COLORS[i % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip
                    formatter={(value, name, props) => [
                      `${value} (${((props as any).percent * 100).toFixed(1)}%)`,
                      name,
                    ]}
                  />
                </PieChart>
              </ResponsiveContainer>
            </ChartContainer>
          </CardContent>
        </Card>

        <Card className="shadow-sm">
          <CardHeader>
            <CardTitle className="text-sm">Clientes por Colaborador</CardTitle>
          </CardHeader>
          <CardContent className="h-56 flex justify-center">
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
                    label={renderLabel}
                  >
                    {clientsPerUser.map((e, i) => (
                      <Cell key={`c-${i}`} fill={COLORS[(i + 2) % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip
                    formatter={(value, name, props) => [
                      `${value} (${((props as any).percent * 100).toFixed(1)}%)`,
                      name,
                    ]}
                  />
                </PieChart>
              </ResponsiveContainer>
            </ChartContainer>
          </CardContent>
        </Card>

        <Card className="shadow-sm">
          <CardHeader>
            <CardTitle className="text-sm">Processos por Colaborador</CardTitle>
          </CardHeader>
          <CardContent className="h-56 flex justify-center">
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
                    label={renderLabel}
                  >
                    {casesPerUser.map((e, i) => (
                      <Cell key={`c-${i}`} fill={COLORS[(i + 4) % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip
                    formatter={(value, name, props) => [
                      `${value} (${((props as any).percent * 100).toFixed(1)}%)`,
                      name,
                    ]}
                  />
                </PieChart>
              </ResponsiveContainer>
            </ChartContainer>
          </CardContent>
        </Card>

        <Card className="shadow-sm">
          <CardHeader>
            <CardTitle className="text-sm">Clientes por Captação</CardTitle>
          </CardHeader>
          <CardContent className="h-56 flex justify-center">
            <ChartContainer config={{}} className="h-full w-full">
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie
                    data={captacaoChartData}
                    dataKey="value"
                    nameKey="name"
                    cx="50%"
                    cy="50%"
                    innerRadius={40}
                    outerRadius={60}
                    paddingAngle={5}
                    label={renderLabel}
                  >
                    {captacaoChartData.map((e, i) => (
                      <Cell key={`c-${i}`} fill={COLORS[(i + 3) % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip
                    formatter={(value, name, props) => [
                      `${value} (${((props as any).percent * 100).toFixed(1)}%)`,
                      name,
                    ]}
                  />
                </PieChart>
              </ResponsiveContainer>
            </ChartContainer>
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <Card className="shadow-sm lg:col-span-3">
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
                    {a.type === 'Aniversário' ? (
                      <Gift className="h-5 w-5 text-pink-500" />
                    ) : (
                      <Calendar className="h-5 w-5 text-primary" />
                    )}
                    <div>
                      <p className="text-sm font-medium leading-none">{a.title}</p>
                      <p className="text-xs text-muted-foreground">
                        {a.time} - {a.type}
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
