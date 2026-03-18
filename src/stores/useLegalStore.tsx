import React, {
  createContext,
  useContext,
  useState,
  useEffect,
  ReactNode,
  useCallback,
} from 'react'
import { LegalState, initialData, Client, Case, Task, Appointment, User } from '../lib/mockData'
import { toast } from '@/hooks/use-toast'
import { supabase } from '@/lib/supabase/client'
import { useAuth } from '@/hooks/use-auth'

interface LegalContextType {
  state: LegalState
  updateItem: (table: string, id: string, changes: any) => void
  deleteItem: (table: string, id: string) => void
  addLog: (action: string, entity: string, details: string) => void
  addClient: (client: Omit<Client, 'id'>) => void
  addCase: (newCase: Omit<Case, 'id' | 'updatedAt'>) => void
  addTask: (task: Omit<Task, 'id'>) => void
  addAppointment: (app: Omit<Appointment, 'id'>) => void
  updateUser: (id: string, changes: Partial<User>) => void
  addUser: (user: any) => void
}

const LegalContext = createContext<LegalContextType | undefined>(undefined)

export function LegalStoreProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth()
  const [state, setState] = useState<LegalState>(initialData)

  useEffect(() => {
    if (!user) return
    const load = async () => {
      try {
        const tables = [
          'profiles',
          'clients',
          'cases',
          'tasks',
          'appointments',
          'transactions',
          'logs',
          'petitions',
          'settings',
          'whatsapp_messages',
        ]

        // Fetch all tables
        const results = await Promise.all(tables.map((t) => supabase.from(t).select('*')))

        const profiles = results[0].data || []
        const profile = profiles.find((p) => p.id === user.id)

        // Ensure we always have a valid currentUser object to prevent infinite loading state
        const currentUser = profile || {
          ...initialData.currentUser,
          id: user.id,
          email: user.email || '',
          name: user.user_metadata?.name || user.email?.split('@')[0] || 'User',
          role:
            user.email?.toLowerCase().includes('admin') || profile?.role === 'Admin'
              ? 'Admin'
              : 'User',
        }

        const dbSettings = results[8].data?.[0]
        const mergedSettings = {
          ...initialData.settings,
          ...(dbSettings || {}),
          id: dbSettings?.id || 'default',
        }

        setState({
          currentUser,
          users: profiles,
          clients: (results[1].data || []).sort(
            (a: any, b: any) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime(),
          ),
          cases: (results[2].data || []).sort(
            (a: any, b: any) =>
              new Date(b.updatedAt || b.created_at).getTime() -
              new Date(a.updatedAt || a.created_at).getTime(),
          ),
          tasks: (results[3].data || []).sort(
            (a: any, b: any) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime(),
          ),
          appointments: (results[4].data || []).sort(
            (a: any, b: any) => new Date(a.date).getTime() - new Date(b.date).getTime(),
          ),
          transactions: (results[5].data || []).sort(
            (a: any, b: any) => new Date(b.date).getTime() - new Date(a.date).getTime(),
          ),
          logs: (results[6].data || []).sort(
            (a: any, b: any) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime(),
          ),
          petitions: results[7].data || [],
          settings: mergedSettings,
          whatsappMessages: (results[9].data || []).sort(
            (a: any, b: any) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime(),
          ),
        })
      } catch (err) {
        console.error('Failed to load initial data', err)
        // Set a fallback state to unblock the UI
        setState((prev) => ({
          ...prev,
          currentUser: {
            ...initialData.currentUser,
            id: user.id,
            email: user.email || '',
            name: user.email?.split('@')[0] || 'User',
            role: 'Admin',
          },
        }))
      }
    }
    load()
  }, [user])

  const addLog = useCallback(
    async (action: string, entity: string, details: string) => {
      if (!state.currentUser.name) return
      const newLog = {
        action,
        entity,
        user: state.currentUser.name,
        date: new Date().toISOString(),
        details,
      }
      const { data } = await supabase.from('logs').insert(newLog).select().single()
      if (data) setState((prev) => ({ ...prev, logs: [data, ...prev.logs].slice(0, 100) }))
    },
    [state.currentUser.name],
  )

  const deleteItem = useCallback(
    async (table: string, id: string) => {
      setState((prev) => {
        const newState = {
          ...prev,
          [table]: (prev[table as keyof LegalState] as any[]).filter((item) => item.id !== id),
        }

        // Cascading deletion locally for immediate UI update
        if (table === 'clients') {
          newState.cases = prev.cases.filter((c) => c.clientId !== id)
          newState.tasks = prev.tasks.filter((t) => t.clientId !== id)
          newState.appointments = prev.appointments.filter((a) => a.clientId !== id)
          newState.transactions = prev.transactions.filter((t) => t.clientId !== id)
        }
        if (table === 'cases') {
          newState.tasks = prev.tasks.filter((t) => t.relatedProcessId !== id)
          newState.appointments = prev.appointments.filter((a) => a.processId !== id)
          newState.transactions = prev.transactions.filter((t) => t.processId !== id)
        }
        return newState
      })
      await supabase.from(table).delete().eq('id', id)
      addLog('Excluir', table, `Registro ${id} removido`)
    },
    [addLog],
  )

  const updateItem = useCallback(
    async (table: string, id: string, changes: any) => {
      if (changes._delete) return deleteItem(table, id)

      let originalItem: any

      if (table === 'settings') {
        setState((prev) => ({ ...prev, settings: { ...prev.settings, ...changes } }))
        if (id && id !== 'default') {
          await supabase.from(table).update(changes).eq('id', id)
        } else {
          const { data } = await supabase.from(table).insert(changes).select().single()
          if (data) setState((prev) => ({ ...prev, settings: { ...prev.settings, id: data.id } }))
        }
      } else {
        setState((prev) => {
          const arr = prev[table as keyof LegalState] as any[]
          originalItem = arr?.find((item) => item.id === id)
          return {
            ...prev,
            [table]: arr?.map((item) => (item.id === id ? { ...item, ...changes } : item)),
          }
        })
        await supabase.from(table).update(changes).eq('id', id)

        if (table === 'appointments' && originalItem) {
          const updatedItem = { ...originalItem, ...changes }
          const wasHoliday = originalItem.type?.toLowerCase() === 'feriado'
          const isHoliday = updatedItem.type?.toLowerCase() === 'feriado'
          const dateChanged = originalItem.date !== updatedItem.date

          if (isHoliday && (!wasHoliday || dateChanged)) {
            const [y, m, d] = updatedItem.date.split('-')
            const isLeapDay = m === '02' && d === '29'
            const futureHolidays = []
            for (let i = 1; i <= 5; i++) {
              let ny = parseInt(y) + i
              let nm = m
              let nd = d
              if (isLeapDay && !((ny % 4 === 0 && ny % 100 !== 0) || ny % 400 === 0)) {
                nm = '02'
                nd = '28'
              }
              futureHolidays.push({
                title: updatedItem.title,
                type: updatedItem.type,
                priority: 'Baixa',
                date: `${ny}-${nm}-${nd}`,
                time: updatedItem.time,
                description: updatedItem.description,
                responsibleId: updatedItem.responsibleId,
                clientId: updatedItem.clientId,
                processId: updatedItem.processId,
              })
            }
            supabase
              .from('appointments')
              .insert(futureHolidays)
              .select()
              .then(({ data, error }) => {
                if (data && !error) {
                  setState((prev) => ({
                    ...prev,
                    appointments: [...data, ...prev.appointments].sort(
                      (a, b) => new Date(a.date).getTime() - new Date(b.date).getTime(),
                    ),
                  }))
                }
              })
          }
        }
      }
    },
    [deleteItem],
  )

  const addClient = useCallback(async (client: Omit<Client, 'id'>) => {
    const { data, error } = await supabase.from('clients').insert(client).select().single()
    if (error) return toast({ title: 'Erro', description: error.message, variant: 'destructive' })
    setState((prev) => ({ ...prev, clients: [data, ...prev.clients] }))
    toast({ title: 'Cliente adicionado' })
  }, [])

  const addTask = useCallback(async (task: Omit<Task, 'id'>) => {
    const { data, error } = await supabase.from('tasks').insert(task).select().single()
    if (error) return toast({ title: 'Erro', description: error.message, variant: 'destructive' })
    if (data) {
      setState((prev) => ({ ...prev, tasks: [data, ...prev.tasks] }))
      toast({ title: 'Tarefa adicionada com sucesso!' })
    }
  }, [])

  const addCase = useCallback(async (newCase: Omit<Case, 'id' | 'updatedAt'>) => {
    const fullCase = { ...newCase, updatedAt: new Date().toISOString().split('T')[0] }
    const { data, error } = await supabase.from('cases').insert(fullCase).select().single()
    if (error) return toast({ title: 'Erro', description: error.message, variant: 'destructive' })
    setState((prev) => ({ ...prev, cases: [data, ...prev.cases] }))
    toast({ title: 'Processo adicionado' })
  }, [])

  const addAppointment = useCallback(async (app: Omit<Appointment, 'id'>) => {
    let toInsert = [app]

    if (app.type?.toLowerCase() === 'feriado') {
      app.priority = 'Baixa'
      const [y, m, d] = app.date.split('-')
      const isLeapDay = m === '02' && d === '29'

      for (let i = 1; i <= 5; i++) {
        let ny = parseInt(y) + i
        let nm = m
        let nd = d
        if (isLeapDay && !((ny % 4 === 0 && ny % 100 !== 0) || ny % 400 === 0)) {
          nm = '02'
          nd = '28'
        }
        toInsert.push({
          ...app,
          priority: 'Baixa',
          date: `${ny}-${nm}-${nd}`,
        })
      }
    }

    const { data, error } = await supabase.from('appointments').insert(toInsert).select()
    if (error) return toast({ title: 'Erro', description: error.message, variant: 'destructive' })
    setState((prev) => ({
      ...prev,
      appointments: [...data, ...prev.appointments].sort(
        (a, b) => new Date(a.date).getTime() - new Date(b.date).getTime(),
      ),
    }))
    toast({ title: 'Agenda atualizada' })
  }, [])

  const updateUser = useCallback(async (id: string, changes: Partial<User>) => {
    setState((prev) => ({
      ...prev,
      users: prev.users.map((u) => (u.id === id ? { ...u, ...changes } : u)),
      currentUser:
        prev.currentUser.id === id ? { ...prev.currentUser, ...changes } : prev.currentUser,
    }))
    await supabase.from('profiles').update(changes).eq('id', id)
  }, [])

  const addUser = useCallback((newUser: any) => {
    setState((prev) => ({ ...prev, users: [...prev.users, newUser] }))
  }, [])

  return (
    <LegalContext.Provider
      value={{
        state,
        updateItem,
        deleteItem,
        addLog,
        addClient,
        addCase,
        addTask,
        addAppointment,
        updateUser,
        addUser,
      }}
    >
      {children}
    </LegalContext.Provider>
  )
}

export default function useLegalStore() {
  const context = useContext(LegalContext)
  if (!context) throw new Error('useLegalStore must be used within LegalStoreProvider')
  return context
}
