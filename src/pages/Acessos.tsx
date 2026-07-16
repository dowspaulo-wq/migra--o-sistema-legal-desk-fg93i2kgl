import { useMemo } from 'react'
import { Card, CardContent } from '@/components/ui/card'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import useLegalStore from '@/stores/useLegalStore'

export default function Acessos() {
  const { state } = useLegalStore()

  // Parse sessions from logs
  const sessions = useMemo(() => {
    // Filter auth logs
    const authLogs = state.logs
      .filter((log) => log.entity === 'auth' && (log.action === 'LOGIN' || log.action === 'LOGOUT'))
      .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime()) // sort ascending by date

    const userSessions: Record<string, any[]> = {}
    const completedSessions: any[] = []

    authLogs.forEach((log) => {
      if (!userSessions[log.user]) {
        userSessions[log.user] = []
      }

      if (log.action === 'LOGIN') {
        userSessions[log.user].push({
          id: log.id,
          userId: log.user,
          loginDate: log.date,
          logoutDate: null,
        })
      } else if (log.action === 'LOGOUT') {
        const userActiveSessions = userSessions[log.user].filter((s) => !s.logoutDate)
        if (userActiveSessions.length > 0) {
          // pair with the last login
          const lastSession = userActiveSessions[userActiveSessions.length - 1]
          lastSession.logoutDate = log.date
        } else {
          // logout without login - might happen if login was before data retention
          userSessions[log.user].push({
            id: log.id,
            userId: log.user,
            loginDate: null,
            logoutDate: log.date,
          })
        }
      }
    })

    // Flatten all sessions
    Object.values(userSessions).forEach((sessions) => {
      completedSessions.push(...sessions)
    })

    // Sort descending by login date (or logout date if no login)
    return completedSessions.sort((a, b) => {
      const dateA = new Date(a.loginDate || a.logoutDate).getTime()
      const dateB = new Date(b.loginDate || b.logoutDate).getTime()
      return dateB - dateA
    })
  }, [state.logs])

  if (!['Admin', 'ADM', 'admin'].includes(state.currentUser?.role || '')) {
    return (
      <div className="p-8 text-center text-destructive font-bold">
        Acesso negado. Apenas administradores.
      </div>
    )
  }

  const getUserName = (idOrName: string) => {
    const user = state.users.find((u) => u.id === idOrName)
    return user ? user.name : idOrName
  }

  const formatDate = (dateStr: string | null) => {
    if (!dateStr) return '--'
    return new Date(dateStr).toLocaleDateString('pt-BR')
  }

  const formatTime = (dateStr: string | null) => {
    if (!dateStr) return '--'
    return new Date(dateStr).toLocaleTimeString('pt-BR', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    })
  }

  return (
    <div className="space-y-6 pb-12">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Registro de Acessos</h1>
      </div>

      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Colaborador</TableHead>
                <TableHead>Data</TableHead>
                <TableHead>Horário Login</TableHead>
                <TableHead>Horário Logout</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {sessions.map((session) => (
                <TableRow key={session.id}>
                  <TableCell className="font-medium py-4">{getUserName(session.userId)}</TableCell>
                  <TableCell className="py-4">
                    {formatDate(session.loginDate || session.logoutDate)}
                  </TableCell>
                  <TableCell className="py-4">{formatTime(session.loginDate)}</TableCell>
                  <TableCell className="py-4 text-muted-foreground">
                    {session.logoutDate ? formatTime(session.logoutDate) : 'Em andamento'}
                  </TableCell>
                </TableRow>
              ))}
              {sessions.length === 0 && (
                <TableRow>
                  <TableCell colSpan={4} className="text-center py-8 text-muted-foreground">
                    Nenhum acesso registrado.
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
