import React, {
  createContext,
  useContext,
  useState,
  useEffect,
  ReactNode,
  useCallback,
} from 'react'
import { LegalState, initialData, Client, Case, Task } from '../lib/mockData'
import { toast } from '@/hooks/use-toast'

interface LegalContextType {
  state: LegalState
  addClient: (client: Omit<Client, 'id'>) => void
  updateTask: (id: string, completed: boolean) => void
  importData: (clients: Partial<Client>[]) => void
  addCase: (newCase: Omit<Case, 'id' | 'updatedAt'>) => void
}

const LegalContext = createContext<LegalContextType | undefined>(undefined)

export function LegalStoreProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<LegalState>(() => {
    try {
      const saved = localStorage.getItem('legalDeskData')
      return saved ? JSON.parse(saved) : initialData
    } catch (e) {
      return initialData
    }
  })

  useEffect(() => {
    localStorage.setItem('legalDeskData', JSON.stringify(state))
  }, [state])

  const addClient = useCallback((client: Omit<Client, 'id'>) => {
    const newClient = { ...client, id: Math.random().toString(36).substring(7) }
    setState((prev) => ({
      ...prev,
      clients: [newClient, ...prev.clients],
      activities: [
        {
          id: Math.random().toString(),
          text: `Novo cliente cadastrado: ${client.name}`,
          date: 'Agora',
          type: 'client',
        },
        ...prev.activities,
      ].slice(0, 10),
    }))
    toast({ title: 'Cliente adicionado', description: 'O cliente foi cadastrado com sucesso.' })
  }, [])

  const updateTask = useCallback((id: string, completed: boolean) => {
    setState((prev) => ({
      ...prev,
      tasks: prev.tasks.map((t) => (t.id === id ? { ...t, completed } : t)),
    }))
  }, [])

  const addCase = useCallback((newCase: Omit<Case, 'id' | 'updatedAt'>) => {
    const fullCase: Case = {
      ...newCase,
      id: Math.random().toString(36).substring(7),
      updatedAt: new Date().toISOString().split('T')[0],
    }
    setState((prev) => ({
      ...prev,
      cases: [fullCase, ...prev.cases],
    }))
    toast({ title: 'Processo adicionado', description: 'O processo foi registrado com sucesso.' })
  }, [])

  const importData = useCallback((importedClients: Partial<Client>[]) => {
    const newClients = importedClients.map((c) => ({
      id: Math.random().toString(36).substring(7),
      name: c.name || 'Desconhecido',
      document: c.document || 'N/A',
      email: c.email || '',
      phone: c.phone || '',
      status: c.status || 'Ativo',
    })) as Client[]

    setState((prev) => ({
      ...prev,
      clients: [...newClients, ...prev.clients],
    }))
    toast({
      title: 'Importação concluída',
      description: `${newClients.length} clientes importados.`,
    })
  }, [])

  return (
    <LegalContext.Provider value={{ state, addClient, updateTask, importData, addCase }}>
      {children}
    </LegalContext.Provider>
  )
}

export default function useLegalStore() {
  const context = useContext(LegalContext)
  if (!context) throw new Error('useLegalStore must be used within LegalStoreProvider')
  return context
}
