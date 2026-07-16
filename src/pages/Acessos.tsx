import { useEffect, useState } from 'react'
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
import { supabase } from '@/lib/supabase/client'

export default function Acessos() {
  const { state } = useLegalStore()
  const [sessions, setSessions] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const fetchSessions = async () => {
      try {
        const { data, error } = await supabase
          .from('user_sessions')
          .select('*')
          .order('login_at', { ascending: false })

        if (data && !error) {
          setSessions(data)
        }
      } catch (error) {
        console.error('Error fetching sessions:', error)
      } finally {
        setLoading(false)
      }
    }
    fetchSessions()
  }, [])

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
    const date = new Date(dateStr)
    return date.toLocaleDateString('pt-BR')
  }

  const formatTime = (dateStr: string | null) => {
    if (!dateStr) return '--'
    const date = new Date(dateStr)
    if (isNaN(date.getTime())) return '--'
    return date.toLocaleTimeString('pt-BR', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    })
  }

  const getLogoutDisplay = (session: any) => {
    if (session.logout_at) {
      return formatTime(session.logout_at)
    }

    if (session.last_activity_at) {
      const lastActive = new Date(session.last_activity_at).getTime()
      const now = Date.now()
      const diffMinutes = (now - lastActive) / (1000 * 60)

      if (diffMinutes <= 10) {
        return 'Em andamento'
      }

      return formatTime(session.last_activity_at)
    }

    return '--'
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
              {loading ? (
                <TableRow>
                  <TableCell colSpan={4} className="text-center py-8 text-muted-foreground">
                    Carregando acessos...
                  </TableCell>
                </TableRow>
              ) : sessions.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={4} className="text-center py-8 text-muted-foreground">
                    Nenhum acesso registrado.
                  </TableCell>
                </TableRow>
              ) : (
                sessions.map((session) => (
                  <TableRow key={session.id}>
                    <TableCell className="font-medium py-4">
                      {getUserName(session.profile_id)}
                    </TableCell>
                    <TableCell className="py-4">
                      {formatDate(session.date || session.login_at)}
                    </TableCell>
                    <TableCell className="py-4">{formatTime(session.login_at)}</TableCell>
                    <TableCell className="py-4 text-muted-foreground">
                      {getLogoutDisplay(session)}
                    </TableCell>
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  )
}
