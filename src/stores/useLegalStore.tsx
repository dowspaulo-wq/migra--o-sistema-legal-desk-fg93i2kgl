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
      const results = await Promise.all(tables.map((t) => supabase.from(t).select('*')))
      const currentUser = results[0].data?.find((p) => p.id === user.id) || initialData.currentUser

      setState({
        currentUser,
        users: results[0].data || [],
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
        settings: { ...initialData.settings, ...(results[8].data?.[0] || {}) },
        whatsappMessages: (results[9].data || []).sort(
          (a: any, b: any) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime(),
        ),
      })
    }
    load()
  }, [user])

  const addLog = useCallback(
    async (action: string, entity: string, details: string) => {
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

  const updateItem = useCallback(async (table: string, id: string, changes: any) => {
    if (changes._delete) return deleteItem(table, id)
    if (table === 'settings') {
      setState((prev) => ({ ...prev, settings: { ...prev.settings, ...changes } }))
    } else {
      setState((prev) => ({
        ...prev,
        [table]: (prev[table as keyof LegalState] as any[]).map((item) =>
          item.id === id ? { ...item, ...changes } : item,
        ),
      }))
    }
    await supabase.from(table).update(changes).eq('id', id)
  }, [])

  const deleteItem = useCallback(
    async (table: string, id: string) => {
      setState((prev) => ({
        ...prev,
        [table]: (prev[table as keyof LegalState] as any[]).filter((item) => item.id !== id),
      }))
      await supabase.from(table).delete().eq('id', id)
      addLog('Excluir', table, `Registro ${id} removido`)
    },
    [addLog],
  )

  const addClient = useCallback(async (client: Omit<Client, 'id'>) => {
    const { data, error } = await supabase.from('clients').insert(client).select().single()
    if (error) return toast({ title: 'Erro', description: error.message, variant: 'destructive' })
    setState((prev) => ({ ...prev, clients: [data, ...prev.clients] }))
    toast({ title: 'Cliente adicionado' })
  }, [])

  const addTask = useCallback(async (task: Omit<Task, 'id'>) => {
    const { data } = await supabase.from('tasks').insert(task).select().single()
    if (data) setState((prev) => ({ ...prev, tasks: [data, ...prev.tasks] }))
  }, [])

  const addCase = useCallback(async (newCase: Omit<Case, 'id' | 'updatedAt'>) => {
    const fullCase = { ...newCase, updatedAt: new Date().toISOString().split('T')[0] }
    const { data, error } = await supabase.from('cases').insert(fullCase).select().single()
    if (error) return toast({ title: 'Erro', description: error.message, variant: 'destructive' })
    setState((prev) => ({ ...prev, cases: [data, ...prev.cases] }))
    toast({ title: 'Processo adicionado' })
  }, [])

  const addAppointment = useCallback(async (app: Omit<Appointment, 'id'>) => {
    const { data, error } = await supabase.from('appointments').insert(app).select().single()
    if (error) return toast({ title: 'Erro', description: error.message, variant: 'destructive' })
    setState((prev) => ({ ...prev, appointments: [data, ...prev.appointments] }))
    toast({ title: 'Agenda atualizada' })
  }, [])

  const updateUser = useCallback(async (id: string, changes: Partial<User>) => {
    setState((prev) => ({
      ...prev,
      users: prev.users.map((u) => (u.id === id ? { ...u, ...changes } : u)),
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
