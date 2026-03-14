import React, {
  createContext,
  useContext,
  useState,
  useEffect,
  ReactNode,
  useCallback,
} from 'react'
import {
  LegalState,
  initialData,
  Client,
  Case,
  Task,
  Log,
  Transaction,
  Appointment,
  Petition,
} from '../lib/mockData'
import { toast } from '@/hooks/use-toast'

interface LegalContextType {
  state: LegalState
  setState: React.Dispatch<React.SetStateAction<LegalState>>
  addLog: (action: string, entity: string, details: string) => void
  addClient: (client: Omit<Client, 'id'>) => void
  addCase: (newCase: Omit<Case, 'id' | 'updatedAt'>) => void
  addTask: (task: Omit<Task, 'id'>) => void
  addAppointment: (app: Omit<Appointment, 'id'>) => void
}

const LegalContext = createContext<LegalContextType | undefined>(undefined)

export function LegalStoreProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<LegalState>(() => {
    try {
      const saved = localStorage.getItem('sbjurData')
      return saved ? { ...initialData, ...JSON.parse(saved) } : initialData
    } catch (e) {
      return initialData
    }
  })

  useEffect(() => {
    localStorage.setItem('sbjurData', JSON.stringify(state))
  }, [state])

  const addLog = useCallback(
    (action: string, entity: string, details: string) => {
      const newLog: Log = {
        id: Math.random().toString(36).substring(7),
        action,
        entity,
        user: state.currentUser.name,
        date: new Date().toISOString(),
        details,
      }
      setState((prev) => ({ ...prev, logs: [newLog, ...prev.logs].slice(0, 100) }))
    },
    [state.currentUser.name],
  )

  const addClient = useCallback(
    (client: Omit<Client, 'id'>) => {
      const newClient = { ...client, id: Math.random().toString(36).substring(7) }
      setState((prev) => ({ ...prev, clients: [newClient, ...prev.clients] }))
      addLog('Criar', 'Cliente', `Cliente ${client.name} adicionado`)
      toast({ title: 'Cliente adicionado' })
    },
    [addLog],
  )

  const addTask = useCallback(
    (task: Omit<Task, 'id'>) => {
      const newTask = { ...task, id: Math.random().toString(36).substring(7) }
      setState((prev) => ({ ...prev, tasks: [newTask, ...prev.tasks] }))
      addLog('Criar', 'Tarefa', `Tarefa ${task.title} adicionada`)
    },
    [addLog],
  )

  const addCase = useCallback(
    (newCase: Omit<Case, 'id' | 'updatedAt'>) => {
      const fullCase: Case = {
        ...newCase,
        id: Math.random().toString(36).substring(7),
        updatedAt: new Date().toISOString().split('T')[0],
      }
      setState((prev) => ({ ...prev, cases: [fullCase, ...prev.cases] }))
      addLog('Criar', 'Processo', `Processo ${fullCase.number} adicionado`)
      // Auto-create task
      addTask({
        title: 'Movimentação Processual - Novo Registro',
        description: 'Verificar andamento inicial',
        dueDate: new Date().toISOString().split('T')[0],
        status: 'Pendente',
        priority: 'Alta',
        responsibleId: fullCase.responsibleId,
        relatedProcessId: fullCase.id,
      })
      toast({ title: 'Processo adicionado' })
    },
    [addLog, addTask],
  )

  const addAppointment = useCallback(
    (app: Omit<Appointment, 'id'>) => {
      const newApp = { ...app, id: Math.random().toString(36).substring(7) }
      setState((prev) => ({ ...prev, appointments: [newApp, ...prev.appointments] }))
      addLog('Criar', 'Agenda', `Compromisso ${app.title} adicionado`)
      if (app.type === 'Audiência') {
        addTask({
          title: `Prep para Audiência: ${app.title}`,
          description: 'Preparação automática',
          dueDate: app.date.split('T')[0],
          status: 'Pendente',
          priority: 'Urgente',
          responsibleId: app.responsibleId,
        })
      }
      toast({ title: 'Agenda atualizada' })
    },
    [addLog, addTask],
  )

  return (
    <LegalContext.Provider
      value={{ state, setState, addLog, addClient, addCase, addTask, addAppointment }}
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
