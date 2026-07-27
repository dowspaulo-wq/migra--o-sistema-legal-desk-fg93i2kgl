import { useEffect, useState, useMemo } from 'react'
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

  const formatDate = (dateStr: string | null, loginAtStr?: string | null) => {
    if (loginAtStr) {
      const loginDate = new Date(loginAtStr)
      if (!isNaN(loginDate.getTime())) {
        return loginDate.toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo' })
      }
    }

    if (!dateStr) return '--'

    const parts = dateStr.split('-')
    if (parts.length === 3) {
      const [year, month, day] = parts
      return `${day.padStart(2, '0')}/${month.padStart(2, '0')}/${year}`
    }

    const date = new Date(dateStr)
    if (isNaN(date.getTime())) return '--'
    return date.toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo' })
  }

  const formatTime = (dateStr: string | null) => {
    if (!dateStr) return '--'
    const date = new Date(dateStr)
    if (isNaN(date.getTime())) return '--'
    return date.toLocaleTimeString('pt-BR', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      timeZone: 'America/Sao_Paulo',
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

  const uniqueSessions = useMemo(() => {
    if (!sessions || sessions.length === 0) return []

    const result: any[] = []

    for (const session of sessions) {
      const loginTime = new Date(session.login_at).getTime()
      if (isNaN(loginTime)) {
        result.push(session)
        continue
      }

      const duplicateIndex = result.findIndex((item) => {
        if (item.profile_id !== session.profile_id) return false
        const itemLoginTime = new Date(item.login_at).getTime()
        return Math.abs(loginTime - itemLoginTime) <= 10000
      })

      if (duplicateIndex === -1) {
        result.push(session)
      } else {
        const existing = result[duplicateIndex]
        const existingIsActive = !existing.logout_at
        const currentIsActive = !session.logout_at

        if (currentIsActive && !existingIsActive) {
          result[duplicateIndex] = session
        } else if (!existingIsActive && !currentIsActive) {
          const existingAct = new Date(existing.last_activity_at || 0).getTime()
          const currentAct = new Date(session.last_activity_at || 0).getTime()
          if (currentAct > existingAct) {
            result[duplicateIndex] = session
          }
        }
      }
    }

    return result
  }, [sessions])

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
              ) : uniqueSessions.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={4} className="text-center py-8 text-muted-foreground">
                    Nenhum acesso registrado.
                  </TableCell>
                </TableRow>
              ) : (
                uniqueSessions.map((session) => (
                  <TableRow key={session.id}>
                    <TableCell className="font-medium py-4">
                      {getUserName(session.profile_id)}
                    </TableCell>
                    <TableCell className="py-4">
                      {formatDate(session.date, session.login_at)}
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
