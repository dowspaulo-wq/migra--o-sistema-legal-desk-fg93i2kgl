import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Badge } from '@/components/ui/badge'
import useLegalStore from '@/stores/useLegalStore'
import { LogIn, LogOut } from 'lucide-react'

export default function Acessos() {
  const { state } = useLegalStore()

  const authLogs = state.logs
    .filter((log) => log.action === 'LOGIN' || log.action === 'LOGOUT')
    .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())

  const getUserName = (logUser: string) => {
    const profile = state.users.find((u) => u.id === logUser || u.name === logUser)
    return profile?.name || logUser
  }

  const formatDate = (dateStr: string) => {
    const date = new Date(dateStr)
    return date.toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
    })
  }

  const formatTime = (dateStr: string) => {
    const date = new Date(dateStr)
    return date.toLocaleTimeString('pt-BR', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    })
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Acessos</h1>
        <p className="text-muted-foreground">Monitoramento de login e logout dos colaboradores.</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Registro de Acessos</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Colaborador</TableHead>
                <TableHead>Ação</TableHead>
                <TableHead>Data</TableHead>
                <TableHead>Horário</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {authLogs.map((log) => (
                <TableRow key={log.id}>
                  <TableCell className="font-medium">{getUserName(log.user)}</TableCell>
                  <TableCell>
                    <Badge variant={log.action === 'LOGIN' ? 'default' : 'secondary'}>
                      <span className="flex items-center gap-1.5">
                        {log.action === 'LOGIN' ? (
                          <LogIn className="h-3 w-3" />
                        ) : (
                          <LogOut className="h-3 w-3" />
                        )}
                        {log.action === 'LOGIN' ? 'Login' : 'Desconexão'}
                      </span>
                    </Badge>
                  </TableCell>
                  <TableCell>{formatDate(log.created_at)}</TableCell>
                  <TableCell className="font-mono text-sm">{formatTime(log.created_at)}</TableCell>
                </TableRow>
              ))}
              {authLogs.length === 0 && (
                <TableRow>
                  <TableCell colSpan={4} className="text-center py-8 text-muted-foreground">
                    Nenhum registro de acesso encontrado.
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
