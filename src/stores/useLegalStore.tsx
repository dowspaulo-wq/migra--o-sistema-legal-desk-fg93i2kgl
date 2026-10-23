import React, {
  createContext,
  useContext,
  useState,
  useEffect,
  ReactNode,
  useCallback,
} from 'react'
import {
  LegalState as BaseLegalState,
  initialData,
  Client,
  Case,
  Task,
  Appointment,
  User,
  Transaction,
  PaymentPlan,
} from '../lib/mockData'

export interface Supplier {
  id: string
  name: string
  document?: string
  email?: string
  phone?: string
  status: string
  group_name?: string | null
  created_at?: string
}

export interface CaseSystem {
  id: string
  name: string
  image_url: string | null
  created_at?: string
}

export interface TransactionCase {
  id: string
  transaction_id: string
  case_id: string
  created_at: string
}

export interface LegalState extends BaseLegalState {
  suppliers: Supplier[]
  caseSystems: CaseSystem[]
  transactionCases: TransactionCase[]
  paymentPlans: PaymentPlan[]
}
import { toast } from '@/hooks/use-toast'
import { supabase } from '@/lib/supabase/client'
import { useAuth } from '@/hooks/use-auth'
import { normalizeStr, calculateInstallmentDate } from '@/lib/utils'
import { isNonFinancialFeeType, isSuccessFeeType } from '@/lib/fee-types'

interface LegalContextType {
  state: LegalState
  isInitialLoading: boolean
  isReloading: boolean
  reloadAllData: () => Promise<void>
  updateItem: (table: string, id: string, changes: any) => void
  deleteItem: (table: string, id: string) => void
  addLog: (action: string, entity: string, details: string) => void
  addClient: (client: Omit<Client, 'id'>) => Promise<Client | null>
  generateOnboardingTasks: (clientId: string, responsibleId?: string | null) => Promise<Task[]>
  addCase: (newCase: Omit<Case, 'id' | 'updatedAt'>) => void
  addTask: (task: Omit<Task, 'id'>) => void
  addAppointment: (app: Omit<Appointment, 'id'>) => void
  addTransaction: (t: Omit<Transaction, 'id'> | Omit<Transaction, 'id'>[]) => void
  addSupplier: (s: Omit<Supplier, 'id'>) => void
  addPetition: (p: Omit<any, 'id' | 'created_at'>) => void
  reloadTransactions: () => Promise<void>
  reloadAppointments: () => Promise<void>
  reloadPaymentPlans: () => Promise<void>
  addClientFee: (fee: {
    amount: number
    description: string
    date: string
    clientId: string
    caseIds: string[]
    bankAccount?: string
    status?: string
    installments?: number
    paymentMethod?: string
    feeType?: string
    percentage?: number
  }) => Promise<void>
  addPaymentPlan: (plan: {
    clientId: string
    processId?: string | null
    title: string
    installmentAmount: number
    installmentsCount: number
    periodicity?: string
    firstDueDate: string
    feePercentage: number
    bankAccount?: string
    paymentMethod?: string
    notes?: string
  }) => Promise<{ plan: PaymentPlan; transactions: Transaction[] } | null>
  markRepasseAsDone: (transactionId: string) => Promise<void>
  deletePaymentPlan: (id: string) => Promise<void>
  updateUser: (id: string, changes: Partial<User>) => void
  addUser: (user: any) => void
  renameType: (table: string, column: string, oldVal: string, newVal: string) => void
}

const LegalContext = createContext<LegalContextType | undefined>(undefined)

export function LegalStoreProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth()
  const [state, setState] = useState<LegalState>({
    ...initialData,
    suppliers: [],
    caseSystems: [],
    transactionCases: [],
    paymentPlans: [],
  })

  const loadingInitialDataRef = React.useRef(false)
  const initialDataLoadedForUserRef = React.useRef<string | null>(null)
  const [isInitialLoading, setIsInitialLoading] = useState(true)
  const [isReloading, setIsReloading] = useState(false)

  // Função auxiliar de busca paginada e segura para qualquer tabela
  const fetchAllTableRows = async (t: string): Promise<{ data: any[]; error: any }> => {
    const allRows: any[] = []
    const pageSize = 1000
    let from = 0
    const maxPages = 50 // Proteção absoluta contra loops infinitos de paginação

    for (let page = 0; page < maxPages; page++) {
      try {
        const fetchPromise = supabase
          .from(t as any)
          .select('*')
          .range(from, from + pageSize - 1)

        const timeoutPromise = new Promise<{ data: any[] | null; error: any }>((resolve) =>
          setTimeout(
            () => resolve({ data: null, error: new Error(`Timeout na página ${page} de ${t}`) }),
            10000,
          ),
        )

        const { data, error } = await Promise.race([fetchPromise, timeoutPromise])

        if (error) {
          console.warn(`Erro ao buscar página ${page} da tabela ${t}:`, error)
          return { data: allRows, error }
        }

        if (data && Array.isArray(data) && data.length > 0) {
          allRows.push(...data)
          if (data.length < pageSize) {
            break
          }
          from += pageSize
        } else {
          break
        }
      } catch (pageErr) {
        console.warn(`Exceção ao buscar página ${page} da tabela ${t}:`, pageErr)
        return { data: allRows, error: pageErr }
      }
    }

    return { data: allRows, error: null }
  }

  const queryWithTimeout = async (t: string) => {
    try {
      const timeoutPromise = new Promise<{ data: any[]; error: any }>((resolve) =>
        setTimeout(() => resolve({ data: [], error: new Error(`Timeout loading ${t}`) }), 20000),
      )
      return await Promise.race([fetchAllTableRows(t), timeoutPromise])
    } catch (e) {
      console.warn(`Error or timeout fetching table ${t}:`, e)
      return { data: [], error: e }
    }
  }

  const safeSortDateDesc = (arr: any[], field: string) => {
    return (arr || []).sort(
      (a: any, b: any) => new Date(b?.[field] || 0).getTime() - new Date(a?.[field] || 0).getTime(),
    )
  }

  const buildCurrentUser = (authUser: any, userProfile: any) => {
    const userEmailLower = (authUser.email || '').toLowerCase()
    const isDouglas =
      userEmailLower === 'advdouglaspsantos@gmail.com' ||
      userEmailLower === 'dowspaulo@gmail.com' ||
      authUser.id === '6501af65-cd6c-43c3-958a-3091ce93ba78'

    return userProfile
      ? {
          ...initialData.currentUser,
          ...userProfile,
          id: authUser.id,
          email: userProfile.email || authUser.email || '',
          role:
            isDouglas || userProfile.role === 'Admin' || userEmailLower.includes('admin')
              ? 'Admin'
              : userProfile.role || 'User',
          canViewFinance: isDouglas || userProfile.canViewFinance || userProfile.role === 'Admin',
          is_active: userProfile.is_active ?? true,
        }
      : {
          ...initialData.currentUser,
          id: authUser.id,
          email: authUser.email || '',
          name: isDouglas
            ? 'Douglas'
            : authUser.user_metadata?.name || authUser.email?.split('@')[0] || 'User',
          role: isDouglas || userEmailLower.includes('admin') ? 'Admin' : 'User',
          canViewFinance: isDouglas || userEmailLower.includes('admin'),
          is_active: true,
        }
  }

  // Carregamento resiliente e progressivo de dados para o usuário autenticado
  const performLoad = useCallback(async (targetUser: any, isExplicitReload = false) => {
    if (!targetUser) return

    if (isExplicitReload) {
      setIsReloading(true)
    }

    try {
      // 1. Resolver o perfil do usuário
      let userProfile: any = null
      let profileFetchAttempts = 0
      const maxProfileAttempts = 3

      while (!userProfile && profileFetchAttempts < maxProfileAttempts) {
        profileFetchAttempts++
        try {
          const timeoutPromise = new Promise<{ data: any; error: any }>((resolve) =>
            setTimeout(
              () => resolve({ data: null, error: new Error('Timeout profile check') }),
              8000,
            ),
          )
          const res = await Promise.race([
            Promise.resolve(
              supabase.from('profiles').select('*').eq('id', targetUser.id).maybeSingle(),
            ),
            timeoutPromise,
          ])

          if (res.data) {
            userProfile = res.data
            break
          }
        } catch (err) {
          console.warn(`Attempt ${profileFetchAttempts} to fetch user profile failed:`, err)
        }

        if (!userProfile && profileFetchAttempts < maxProfileAttempts) {
          await new Promise((r) => setTimeout(r, 1000))
        }
      }

      // Se o usuário foi desativado explicitamente
      if (userProfile && (userProfile.is_active === false || userProfile.role === 'Inativo')) {
        try {
          await supabase.auth.signOut()
        } catch (signOutErr) {
          console.error('Error on sign out inactive user:', signOutErr)
        }
        window.location.href = '/login?inactive=1'
        return
      }

      const currentUser = buildCurrentUser(targetUser, userProfile)

      // Atualiza o currentUser
      setState((prev) => ({
        ...prev,
        currentUser,
      }))

      // GRUPO 1: Tabelas essenciais do sistema DPSjur
      // (profiles, clients, cases, transactions, tasks, appointments)
      const [profilesRes, clientsRes, casesRes, tasksRes, apptsRes, txnsRes] = await Promise.all([
        queryWithTimeout('profiles'),
        queryWithTimeout('clients'),
        queryWithTimeout('cases'),
        queryWithTimeout('tasks'),
        queryWithTimeout('appointments'),
        queryWithTimeout('transactions'),
      ])

      let profiles = profilesRes?.data || []
      if (currentUser.id && !profiles.some((p: any) => p.id === currentUser.id)) {
        profiles = [currentUser, ...profiles]
      }

      const loadedClients = safeSortDateDesc(clientsRes?.data || [], 'created_at')
      const loadedCases = (casesRes?.data || []).sort(
        (a: any, b: any) =>
          new Date(b?.updatedAt || b?.created_at || 0).getTime() -
          new Date(a?.updatedAt || a?.created_at || 0).getTime(),
      )
      const loadedTasks = safeSortDateDesc(tasksRes?.data || [], 'created_at')
      const loadedAppointments = (apptsRes?.data || []).sort(
        (a: any, b: any) => new Date(a?.date || 0).getTime() - new Date(b?.date || 0).getTime(),
      )
      const loadedTransactions = safeSortDateDesc(txnsRes?.data || [], 'date')

      // GRAVAÇÃO IMEDIATA DO GRUPO ESSENCIAL NO ESTADO (NUNCA descarta por isMounted)
      setState((prev) => ({
        ...prev,
        currentUser,
        users: profiles.length > 0 ? profiles : prev.users,
        clients:
          loadedClients.length > 0
            ? loadedClients
            : prev.clients.length > 0
              ? prev.clients
              : loadedClients,
        cases:
          loadedCases.length > 0 ? loadedCases : prev.cases.length > 0 ? prev.cases : loadedCases,
        tasks:
          loadedTasks.length > 0 ? loadedTasks : prev.tasks.length > 0 ? prev.tasks : loadedTasks,
        appointments:
          loadedAppointments.length > 0
            ? loadedAppointments
            : prev.appointments.length > 0
              ? prev.appointments
              : loadedAppointments,
        transactions:
          loadedTransactions.length > 0
            ? loadedTransactions
            : prev.transactions.length > 0
              ? prev.transactions
              : loadedTransactions,
      }))

      // Libera a tela de carregamento inicial assim que as essenciais terminam!
      setIsInitialLoading(false)
      if (loadedClients.length > 0 || loadedCases.length > 0) {
        initialDataLoadedForUserRef.current = targetUser.id
      }

      // GRUPO 2: Tabelas auxiliares / secundárias
      // (settings, transaction_cases, suppliers, case_systems, petitions, logs, whatsapp_messages, payment_plans)
      const [
        settingsRes,
        txCasesRes,
        suppliersRes,
        caseSystemsRes,
        petitionsRes,
        logsRes,
        whatsappRes,
        paymentPlansRes,
      ] = await Promise.all([
        queryWithTimeout('settings'),
        queryWithTimeout('transaction_cases'),
        queryWithTimeout('suppliers'),
        queryWithTimeout('case_systems'),
        queryWithTimeout('petitions'),
        queryWithTimeout('logs'),
        queryWithTimeout('whatsapp_messages'),
        queryWithTimeout('payment_plans'),
      ])

      const dbSettings = settingsRes?.data?.[0]
      const mergedSettings = {
        ...initialData.settings,
        ...(dbSettings || {}),
        id: dbSettings?.id || 'default',
      }

      if (mergedSettings.asaasApiKey || mergedSettings.asaasApiUrl) {
        import('@/services/asaas').then(({ setCachedAsaasConfig }) => {
          setCachedAsaasConfig({
            apiKey: mergedSettings.asaasApiKey,
            apiUrl: mergedSettings.asaasApiUrl,
          })
        })
      }

      if (mergedSettings.appointmentTypes?.some((t: any) => typeof t === 'string')) {
        const colors = [
          '#ef4444',
          '#f97316',
          '#f59e0b',
          '#84cc16',
          '#22c55e',
          '#10b981',
          '#06b6d4',
          '#0ea5e9',
          '#3b82f6',
          '#6366f1',
          '#8b5cf6',
          '#a855f7',
          '#d946ef',
          '#ec4899',
          '#f43f5e',
        ]
        mergedSettings.appointmentTypes = mergedSettings.appointmentTypes.map(
          (t: any, i: number) => {
            if (typeof t === 'object') return t
            return { label: t, color: colors[i % colors.length] }
          },
        )
        if (mergedSettings.id !== 'default') {
          supabase
            .from('settings')
            .update({ appointmentTypes: mergedSettings.appointmentTypes })
            .eq('id', mergedSettings.id)
            .then()
        }
      }

      const loadedTransactionCases = txCasesRes?.data || []
      const loadedSuppliers = safeSortDateDesc(suppliersRes?.data || [], 'created_at')
      const loadedCaseSystems = safeSortDateDesc(caseSystemsRes?.data || [], 'created_at')
      const loadedPetitions = petitionsRes?.data || []
      const loadedLogs = safeSortDateDesc(logsRes?.data || [], 'created_at')
      const loadedWhatsapp = safeSortDateDesc(whatsappRes?.data || [], 'created_at')
      const loadedPaymentPlans = safeSortDateDesc(paymentPlansRes?.data || [], 'created_at')

      // APLICAÇÃO PROGRESSIVA DO GRUPO AUXILIAR NO ESTADO
      setState((prev) => ({
        ...prev,
        settings: mergedSettings,
        transactionCases:
          loadedTransactionCases.length > 0
            ? loadedTransactionCases
            : prev.transactionCases.length > 0
              ? prev.transactionCases
              : loadedTransactionCases,
        suppliers:
          loadedSuppliers.length > 0
            ? loadedSuppliers
            : prev.suppliers.length > 0
              ? prev.suppliers
              : loadedSuppliers,
        caseSystems:
          loadedCaseSystems.length > 0
            ? loadedCaseSystems
            : prev.caseSystems.length > 0
              ? prev.caseSystems
              : loadedCaseSystems,
        petitions:
          loadedPetitions.length > 0
            ? loadedPetitions
            : prev.petitions.length > 0
              ? prev.petitions
              : loadedPetitions,
        logs: loadedLogs.length > 0 ? loadedLogs : prev.logs.length > 0 ? prev.logs : loadedLogs,
        whatsappMessages:
          loadedWhatsapp.length > 0
            ? loadedWhatsapp
            : prev.whatsappMessages.length > 0
              ? prev.whatsappMessages
              : loadedWhatsapp,
        paymentPlans:
          loadedPaymentPlans.length > 0
            ? loadedPaymentPlans
            : prev.paymentPlans.length > 0
              ? prev.paymentPlans
              : loadedPaymentPlans,
      }))
    } catch (err) {
      console.error('Failed to load initial data', err)
      // Garante fallback do currentUser sem zerar dados anteriores
      setState((prev) => ({
        ...prev,
        currentUser: prev.currentUser.id ? prev.currentUser : buildCurrentUser(targetUser, null),
      }))
    } finally {
      setIsInitialLoading(false)
      setIsReloading(false)
      loadingInitialDataRef.current = false
    }
  }, [])

  useEffect(() => {
    if (!user) {
      initialDataLoadedForUserRef.current = null
      setIsInitialLoading(false)
      return
    }

    // Se já carregamos os dados para este usuário com sucesso, não refaça o carregamento
    // completo inicial a cada reavaliação de efeito ou atualização de sessão
    if (initialDataLoadedForUserRef.current === user.id) {
      setIsInitialLoading(false)
      return
    }

    if (loadingInitialDataRef.current) {
      return
    }
    loadingInitialDataRef.current = true
    setIsInitialLoading(true)

    performLoad(user, false)
  }, [user, performLoad])

  const reloadAllData = useCallback(async () => {
    if (!user) return
    loadingInitialDataRef.current = true
    await performLoad(user, true)
  }, [user, performLoad])

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
          newState.appointments = prev.appointments.filter((a) => a.processId === id)
          newState.transactions = prev.transactions.filter((t) => t.processId === id)
        }
        if (table === 'transactions') {
          newState.transactionCases = (prev.transactionCases || []).filter(
            (tc) => tc.transaction_id !== id,
          )
        }
        return newState
      })
      if (table === 'transactions') {
        await supabase.from('transaction_cases').delete().eq('transaction_id', id)
      }
      await supabase
        .from(table as any)
        .delete()
        .eq('id', id)
      addLog('Excluir', table, `Registro ${id} removido`)
    },
    [addLog],
  )

  const updateItem = useCallback(
    async (table: string, id: string, changes: any) => {
      if (changes._delete) return deleteItem(table, id)

      let originalItem: any

      if (table === 'settings') {
        const previousSettings = state.settings
        setState((prev) => ({ ...prev, settings: { ...prev.settings, ...changes } }))
        if (changes.asaasApiKey !== undefined || changes.asaasApiUrl !== undefined) {
          import('@/services/asaas').then(({ setCachedAsaasConfig }) => {
            setCachedAsaasConfig({
              apiKey:
                changes.asaasApiKey !== undefined
                  ? changes.asaasApiKey
                  : previousSettings.asaasApiKey,
              apiUrl:
                changes.asaasApiUrl !== undefined
                  ? changes.asaasApiUrl
                  : previousSettings.asaasApiUrl,
            })
          })
        }

        try {
          if (id && id !== 'default') {
            const { error } = await supabase
              .from(table as any)
              .update(changes as any)
              .eq('id', id)
            if (error) throw error
          } else {
            const { data, error } = await supabase
              .from(table as any)
              .insert(changes as any)
              .select('id')
              .single()
            if (error) throw error
            if (data && 'id' in data)
              setState((prev) => ({
                ...prev,
                settings: { ...prev.settings, id: (data as any).id },
              }))
          }
        } catch (dbErr: any) {
          // Em caso de erro no banco (ex: coluna inexistente no VPS), faz rollback do estado local e do cache
          setState((prev) => ({ ...prev, settings: previousSettings }))
          if (changes.asaasApiKey !== undefined || changes.asaasApiUrl !== undefined) {
            import('@/services/asaas').then(({ setCachedAsaasConfig }) => {
              setCachedAsaasConfig({
                apiKey: previousSettings.asaasApiKey,
                apiUrl: previousSettings.asaasApiUrl,
              })
            })
          }
          throw dbErr
        }
      } else {
        let finalChanges = { ...changes }

        if (table === 'transactions' && finalChanges.supplierId && !finalChanges.supplier_group) {
          const sup = state.suppliers.find((s) => s.id === finalChanges.supplierId)
          if (sup?.group_name) {
            finalChanges.supplier_group = sup.group_name
          }
        }

        setState((prev) => {
          const arr = prev[table as keyof LegalState] as any[]
          originalItem = arr?.find((item) => item.id === id)

          if (table === 'cases' && changes.status) {
            const isConcluidoNew = normalizeStr(changes.status).includes('concluido')
            const isConcluidoOld = originalItem?.status
              ? normalizeStr(originalItem.status).includes('concluido')
              : false
            if (isConcluidoNew && !isConcluidoOld) {
              finalChanges.updatedAt = new Date().toISOString().split('T')[0]
            }
          }

          if (table === 'tasks' && finalChanges.status !== undefined) {
            const isFinishing =
              finalChanges.status &&
              (String(finalChanges.status).toLowerCase() === 'concluída' ||
                String(finalChanges.status).toLowerCase() === 'concluído')
            const wasDone =
              originalItem?.status &&
              (String(originalItem.status).toLowerCase() === 'concluída' ||
                String(originalItem.status).toLowerCase() === 'concluído')

            if (isFinishing && !wasDone && finalChanges.completed_by === undefined) {
              finalChanges.completed_by = state.currentUser?.id || user?.id || null
            } else if (!isFinishing && wasDone && finalChanges.completed_by === undefined) {
              finalChanges.completed_by = null
            }
          }

          return {
            ...prev,
            [table]: arr?.map((item) => (item.id === id ? { ...item, ...finalChanges } : item)),
          }
        })

        await supabase
          .from(table as any)
          .update(finalChanges as any)
          .eq('id', id)

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

  const generateOnboardingTasks = useCallback(
    async (clientId: string, responsibleId?: string | null): Promise<Task[]> => {
      const s = state.settings
      const steps =
        Array.isArray(s?.onboardingChecklist) && s.onboardingChecklist.length > 0
          ? [...s.onboardingChecklist].sort((a, b) => (a.order ?? 0) - (b.order ?? 0))
          : [
              { id: 'step-1', title: 'Cadastrar cliente', order: 1 },
              { id: 'step-2', title: 'Cadastrar processo(s)', order: 2 },
              { id: 'step-3', title: 'Coletar documentos', order: 3 },
              { id: 'step-4', title: 'Tratar documentos (qualidade/PDFs)', order: 4 },
              { id: 'step-5', title: 'Redigir procuração', order: 5 },
              { id: 'step-6', title: 'Redigir contrato', order: 6 },
              { id: 'step-7', title: 'Redigir declaração de hipossuficiência', order: 7 },
              { id: 'step-8', title: 'Monitorar assinaturas', order: 8 },
            ]

      const fallbackResponsible = responsibleId || state.currentUser?.id || user?.id || null
      const createdBy = state.currentUser?.id || user?.id || null
      const todayStr = new Date().toISOString().split('T')[0]

      const tasksToInsert = steps.map((step, idx) => ({
        title: step.title,
        clientId,
        relatedProcessId: null,
        status: idx === 0 ? 'Concluída' : 'pendente',
        priority: 'Média',
        type: 'Onboarding',
        description: `Etapa ${idx + 1} do Onboarding de Cliente Novo`,
        responsibleId: step.responsibleId || fallbackResponsible,
        created_by: createdBy,
        dueDate: todayStr,
      }))

      const { data, error } = await supabase
        .from('tasks')
        .insert(tasksToInsert as any)
        .select()

      if (error) {
        console.error('Erro ao gerar tarefas de onboarding:', error)
        toast({
          title: 'Aviso de Onboarding',
          description: 'Cliente criado, mas houve falha ao gerar as etapas de onboarding.',
          variant: 'destructive',
        })
        return []
      }

      if (data && data.length > 0) {
        setState((prev) => {
          const existingIds = new Set(prev.tasks.map((t) => t.id))
          const fresh = (data as Task[]).filter((t) => !existingIds.has(t.id))
          return {
            ...prev,
            tasks: [...fresh, ...prev.tasks],
          }
        })
      }

      return (data as Task[]) || []
    },
    [state.settings?.onboardingChecklist, state.currentUser?.id, user?.id],
  )

  const addClient = useCallback(
    async (client: Omit<Client, 'id'>) => {
      const { data, error } = await supabase
        .from('clients')
        .insert(client as any)
        .select()
        .single()
      if (error) {
        toast({ title: 'Erro', description: error.message, variant: 'destructive' })
        return null
      }

      // Dispara automaticamente as tarefas de onboarding com base no modelo configurado
      await generateOnboardingTasks(data.id, data.responsibleId)

      // Sincroniza todas as tarefas geradas (triggers do banco + checklist de onboarding)
      const { data: allClientTasks } = await supabase
        .from('tasks')
        .select('*')
        .eq('clientId', data.id)

      setState((prev) => {
        const existingTaskIds = new Set(prev.tasks.map((t) => t.id))
        const freshTasks = (allClientTasks || []).filter((t: any) => !existingTaskIds.has(t.id))
        return {
          ...prev,
          clients: [data as any, ...prev.clients],
          tasks: freshTasks.length > 0 ? [...freshTasks, ...prev.tasks] : prev.tasks,
        }
      })
      toast({
        title: 'Cliente adicionado',
        description: 'Checklist de Onboarding disparado com sucesso!',
      })
      return data as Client
    },
    [generateOnboardingTasks],
  )

  const addTask = useCallback(
    async (task: Omit<Task, 'id'>) => {
      const taskPayload = {
        ...task,
        created_by: (task as any).created_by || state.currentUser?.id || user?.id || null,
      }
      const { data, error } = await supabase
        .from('tasks')
        .insert(taskPayload as any)
        .select()
        .single()
      if (error) return toast({ title: 'Erro', description: error.message, variant: 'destructive' })
      if (data) {
        setState((prev) => ({ ...prev, tasks: [data, ...prev.tasks] }))
        toast({ title: 'Tarefa adicionada com sucesso!' })
      }
    },
    [state.currentUser?.id, user?.id],
  )

  const addCase = useCallback(async (newCasePayload: any) => {
    const { feeConfig, ...caseData } = newCasePayload
    if (feeConfig && feeConfig.hasFees) {
      caseData.feeType = feeConfig.feeType
      caseData.feeValue = parseFloat(feeConfig.feeValue || '0')
      caseData.feeInstallments = parseInt(feeConfig.feeInstallments || '1', 10)
    }
    const fullCase = { ...caseData, updatedAt: new Date().toISOString().split('T')[0] }
    const { data, error } = await supabase
      .from('cases')
      .insert(fullCase as any)
      .select()
      .single()
    if (error) return toast({ title: 'Erro', description: error.message, variant: 'destructive' })
    setState((prev) => ({ ...prev, cases: [data, ...prev.cases] }))
    toast({ title: fullCase.parentId ? 'Subprocesso adicionado' : 'Processo adicionado' })

    // Se estiver marcado para não gerar honorários, não gera lançamentos no financeiro
    if (fullCase.noFees) {
      return
    }

    if (feeConfig && feeConfig.hasFees) {
      const isNonFinancial = isNonFinancialFeeType(feeConfig.feeType || '')
      const isSuccessFee = isSuccessFeeType(feeConfig.feeType || '')
      if (isNonFinancial) {
        toast({ title: 'Honorário não financeiro registrado (sem lançamentos no financeiro).' })
        return
      }
      const val = parseFloat(feeConfig.feeValue || '0')
      const inst = parseInt(feeConfig.feeInstallments || '1', 10)
      if (val > 0 && inst > 0) {
        const recurringId = inst > 1 ? crypto.randomUUID() : null
        const transactions = []
        const dueDateStr = feeConfig.feeFirstDueDate || new Date().toISOString().split('T')[0]
        const installmentValue = val / inst

        for (let i = 0; i < inst; i++) {
          const dateStr = calculateInstallmentDate(dueDateStr, i)

          transactions.push({
            description: `Honorários (${feeConfig.feeType}) - Parcela ${i + 1}/${inst} - Processo ${data.number}`,
            amount: installmentValue,
            type: 'income',
            category: feeConfig.feeType || 'Honorários Contratuais',
            status: 'Previsto',
            date: dateStr,
            processId: data.id,
            clientId: data.clientId,
            percentage: feeConfig.feePercentage ? parseFloat(feeConfig.feePercentage) : undefined,
            sendToFinance: true,
            bankAccount: feeConfig.bankAccount,
            ...(recurringId ? { recurring_id: recurringId } : {}),
          })
        }

        const { data: tData, error: tErr } = await supabase
          .from('transactions')
          .insert(transactions as any)
          .select()
        if (tData && !tErr) {
          setState((prev) => ({
            ...prev,
            transactions: ([...tData, ...prev.transactions] as any[]).sort(
              (a, b) => new Date(b.date || 0).getTime() - new Date(a.date || 0).getTime(),
            ),
          }))
          toast({ title: `${inst} parcela(s) de honorários gerada(s).` })
        }
      }
    }
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

    const { data, error } = await supabase
      .from('appointments')
      .insert(toInsert as any)
      .select()
    if (error) return toast({ title: 'Erro', description: error.message, variant: 'destructive' })
    setState((prev) => ({
      ...prev,
      appointments: [...data, ...prev.appointments].sort(
        (a, b) => new Date(a.date).getTime() - new Date(b.date).getTime(),
      ),
    }))
    toast({ title: 'Agenda atualizada' })
  }, [])

  const addTransaction = useCallback(
    async (t: Omit<Transaction, 'id'> | Omit<Transaction, 'id'>[]) => {
      const rawItems = Array.isArray(t) ? t : [t]
      // Preencher supplier_group automaticamente caso venha com supplierId mas sem supplier_group
      const items = rawItems.map((item) => {
        if ((item as any).supplierId && !(item as any).supplier_group) {
          const sup = state.suppliers.find((s) => s.id === (item as any).supplierId)
          if (sup?.group_name) {
            return { ...item, supplier_group: sup.group_name }
          }
        }
        return item
      })
      const { data, error } = await supabase
        .from('transactions')
        .insert(items as any)
        .select()
      if (error) return toast({ title: 'Erro', description: error.message, variant: 'destructive' })
      if (data) {
        setState((prev) => ({
          ...prev,
          transactions: ([...data, ...prev.transactions] as any[]).sort(
            (a, b) => new Date(b.date || 0).getTime() - new Date(a.date || 0).getTime(),
          ),
        }))
        toast({
          title:
            items.length > 1
              ? `${items.length} Lançamentos adicionados com sucesso!`
              : 'Lançamento adicionado com sucesso!',
        })
      }
    },
    [],
  )

  const addSupplier = useCallback(async (s: Omit<Supplier, 'id'>) => {
    const { data, error } = await supabase
      .from('suppliers')
      .insert(s as any)
      .select()
      .single()
    if (error) return toast({ title: 'Erro', description: error.message, variant: 'destructive' })
    if (data) {
      setState((prev) => ({
        ...prev,
        suppliers: [...prev.suppliers, data],
      }))
      toast({ title: 'Fornecedor adicionado com sucesso!' })
    }
  }, [])

  const addPetition = useCallback(async (p: any) => {
    const { data, error } = await supabase.from('petitions').insert(p).select().single()
    if (error) return toast({ title: 'Erro', description: error.message, variant: 'destructive' })
    if (data) {
      setState((prev) => ({
        ...prev,
        petitions: [data, ...prev.petitions],
      }))
      toast({ title: 'Modelo adicionado com sucesso!' })
    }
  }, [])

  const addPaymentPlan = useCallback(
    async (planData: {
      clientId: string
      processId?: string | null
      title: string
      installmentAmount: number
      installmentsCount: number
      periodicity?: string
      firstDueDate: string
      feePercentage: number
      bankAccount?: string
      paymentMethod?: string
      notes?: string
    }) => {
      const inst = Math.max(1, planData.installmentsCount || 1)
      const installmentAmount = Math.max(0, planData.installmentAmount || 0)
      const feePct = Math.max(0, Math.min(100, planData.feePercentage || 0))
      const clientPct = 100 - feePct

      const feeInstallmentAmount = Math.round(installmentAmount * (feePct / 100) * 100) / 100
      const clientInstallmentAmount =
        Math.round((installmentAmount - feeInstallmentAmount) * 100) / 100

      const totalAmount = Math.round(installmentAmount * inst * 100) / 100
      const totalFeeAmount = Math.round(feeInstallmentAmount * inst * 100) / 100
      const totalClientAmount = Math.round(clientInstallmentAmount * inst * 100) / 100

      const planTitle = planData.title.trim() || `Parcelamento com Repasse (${inst}x)`
      const planPayload = {
        clientId: planData.clientId,
        processId: planData.processId || null,
        title: planTitle,
        installmentAmount,
        installmentsCount: inst,
        periodicity: planData.periodicity || 'mensal',
        firstDueDate: planData.firstDueDate,
        feePercentage: feePct,
        clientPercentage: clientPct,
        feeInstallmentAmount,
        clientInstallmentAmount,
        totalAmount,
        totalFeeAmount,
        totalClientAmount,
        bankAccount: planData.bankAccount || 'ASAAS',
        paymentMethod: planData.paymentMethod || 'PIX',
        status: 'Ativo',
        notes: planData.notes || null,
      }

      // 1. Inserir plano na tabela payment_plans
      const { data: createdPlan, error: planError } = await (supabase as any)
        .from('payment_plans')
        .insert(planPayload as any)
        .select()
        .single()

      if (planError || !createdPlan) {
        toast({
          title: 'Erro ao criar plano de parcelamento',
          description: planError?.message || 'Falha ao gravar registro.',
          variant: 'destructive',
        })
        return null
      }

      const safePlan = createdPlan as PaymentPlan

      // 2. Gerar pares de lançamentos com pair_id mútuo
      // Precisamos gerar UUIDs para vincular pair_id antes do insert
      const feeTransactions: any[] = []
      const repasseTransactions: any[] = []

      for (let i = 0; i < inst; i++) {
        const dueDate = calculateInstallmentDate(planData.firstDueDate, i)
        const feeId = crypto.randomUUID()
        const repasseId = crypto.randomUUID()

        // Lançamento de Honorários (Receita)
        feeTransactions.push({
          id: feeId,
          plan_id: safePlan.id,
          pair_id: repasseId,
          installment_number: i + 1,
          installment_total: inst,
          description: `Honorários (${feePct}%) - Parcela ${i + 1}/${inst} - ${safePlan.title}`,
          amount: feeInstallmentAmount,
          type: 'income',
          category: 'Honorários Contratuais',
          status: 'Previsto',
          date: dueDate,
          clientId: planData.clientId,
          processId: planData.processId || null,
          percentage: feePct,
          sendToFinance: true,
          bankAccount: planData.bankAccount || 'ASAAS',
          payment_method: planData.paymentMethod || 'PIX',
        })

        // Lançamento de Repasse ao Cliente (Despesa real que afeta o caixa)
        repasseTransactions.push({
          id: repasseId,
          plan_id: safePlan.id,
          pair_id: feeId,
          installment_number: i + 1,
          installment_total: inst,
          description: `Repasse ao Cliente (${clientPct}%) - Parcela ${i + 1}/${inst} - ${safePlan.title}`,
          amount: clientInstallmentAmount,
          type: 'expense',
          category: 'Repasse ao Cliente',
          status: 'Previsto',
          date: dueDate,
          clientId: planData.clientId,
          processId: planData.processId || null,
          percentage: clientPct,
          sendToFinance: true,
          bankAccount: planData.bankAccount || 'ASAAS',
          payment_method: planData.paymentMethod || 'PIX',
        })
      }

      const allNewTransactions = [...feeTransactions, ...repasseTransactions]

      const { data: insertedTxns, error: txnsError } = await supabase
        .from('transactions')
        .insert(allNewTransactions as any)
        .select()

      if (txnsError) {
        // Rollback do plano para consistência
        await (supabase as any).from('payment_plans').delete().eq('id', safePlan.id)
        toast({
          title: 'Erro ao gerar lançamentos do parcelamento',
          description: txnsError.message,
          variant: 'destructive',
        })
        return null
      }

      // 3. Se houver processo vinculado, criar transaction_cases
      if (planData.processId && insertedTxns) {
        const caseLinks = insertedTxns.map((tx: any) => ({
          transaction_id: tx.id,
          case_id: planData.processId,
        }))
        const { data: linkData } = await supabase
          .from('transaction_cases')
          .insert(caseLinks as any)
          .select()

        if (linkData) {
          setState((prev) => ({
            ...prev,
            transactionCases: [...(prev.transactionCases || []), ...linkData],
          }))
        }
      }

      // 4. Atualizar estado local
      setState((prev) => ({
        ...prev,
        paymentPlans: [createdPlan, ...(prev.paymentPlans || [])],
        transactions: (
          [...(insertedTxns || allNewTransactions), ...prev.transactions] as any[]
        ).sort((a, b) => new Date(b.date || 0).getTime() - new Date(a.date || 0).getTime()),
      }))

      toast({
        title: 'Parcelamento criado com sucesso!',
        description: `${inst} parcelas (${inst * 2} lançamentos vinculados) geradas com repasse ao cliente.`,
      })

      return { plan: createdPlan, transactions: insertedTxns || allNewTransactions }
    },
    [],
  )

  const markRepasseAsDone = useCallback(async (transactionId: string) => {
    const today = new Date().toISOString().split('T')[0]
    const { data, error } = await supabase
      .from('transactions')
      .update({
        status: 'Pago',
        date: today,
      } as any)
      .eq('id', transactionId)
      .select()
      .single()

    if (error) {
      toast({
        title: 'Erro ao marcar repasse como efetuado',
        description: error.message,
        variant: 'destructive',
      })
      return
    }

    setState((prev) => ({
      ...prev,
      transactions: prev.transactions.map((t) =>
        t.id === transactionId ? { ...t, status: 'Pago', date: today } : t,
      ),
    }))

    toast({
      title: 'Repasse registrado com sucesso!',
      description: 'O valor foi registrado como despesa paga no caixa do escritório.',
    })
  }, [])

  const deletePaymentPlan = useCallback(async (id: string) => {
    // Ao deletar o plano, o banco com ON DELETE CASCADE remove as transactions associadas
    const { error } = await (supabase as any).from('payment_plans').delete().eq('id', id)
    if (error) {
      toast({
        title: 'Erro ao excluir parcelamento',
        description: error.message,
        variant: 'destructive',
      })
      return
    }

    setState((prev) => ({
      ...prev,
      paymentPlans: (prev.paymentPlans || []).filter((p) => p.id !== id),
      transactions: prev.transactions.filter((t) => t.plan_id !== id),
    }))

    toast({ title: 'Parcelamento e lançamentos vinculados excluídos.' })
  }, [])

  const addClientFee = useCallback(
    async (fee: {
      amount: number
      description: string
      date: string
      clientId: string
      caseIds: string[]
      bankAccount?: string
      status?: string
      installments?: number
      paymentMethod?: string
      feeType?: string
      percentage?: number
    }) => {
      const isNonFinancial = isNonFinancialFeeType(fee.feeType || '')
      const isSuccessFee = isSuccessFeeType(fee.feeType || '')

      if (isNonFinancial) {
        if (fee.caseIds.length > 0) {
          await supabase
            .from('cases')
            .update({
              feeType: fee.feeType,
              feeValue: fee.amount,
            })
            .in('id', fee.caseIds)

          setState((prev) => ({
            ...prev,
            cases: prev.cases.map((c) =>
              fee.caseIds.includes(c.id)
                ? ({ ...c, feeType: fee.feeType!, feeValue: fee.amount } as any)
                : c,
            ),
          }))
        }
        toast({ title: 'Honorário não financeiro registrado.' })
        return
      }

      const inst = fee.installments || 1
      const payMethod = fee.paymentMethod || 'PIX'
      const installmentValue = fee.amount / inst
      const recurringId = inst > 1 ? crypto.randomUUID() : null

      const transactionsToInsert: any[] = []
      for (let i = 0; i < inst; i++) {
        let dateStr: string | null = null
        if (fee.date && fee.date.trim() !== '') {
          dateStr = calculateInstallmentDate(fee.date, i)
        }

        transactionsToInsert.push({
          description: inst > 1 ? `${fee.description} (${i + 1}/${inst})` : fee.description,
          amount: installmentValue,
          type: 'income',
          category: fee.feeType || 'Honorários Contratuais',
          status: fee.status === 'Realizado' ? 'Pago' : fee.status || 'Previsto',
          date: dateStr,
          clientId: fee.clientId,
          sendToFinance: true,
          bankAccount: fee.bankAccount || 'ASAAS',
          payment_method: payMethod,
          ...(fee.percentage != null ? { percentage: fee.percentage } : {}),
          ...(fee.caseIds.length === 1 ? { processId: fee.caseIds[0] } : {}),
          ...(recurringId ? { recurring_id: recurringId } : {}),
        })
      }

      const { data: txnData, error: txnError } = await supabase
        .from('transactions')
        .insert(transactionsToInsert)
        .select()

      if (txnError) {
        toast({ title: 'Erro', description: txnError.message, variant: 'destructive' })
        return
      }

      setState((prev) => ({
        ...prev,
        transactions: ([...txnData, ...prev.transactions] as any[]).sort(
          (a, b) => new Date(b.date || 0).getTime() - new Date(a.date || 0).getTime(),
        ),
      }))

      if (fee.caseIds.length > 0 && txnData) {
        const links = txnData.flatMap((txn: any) =>
          fee.caseIds.map((caseId) => ({
            transaction_id: txn.id,
            case_id: caseId,
          })),
        )

        const { data: linkData, error: linkError } = await supabase
          .from('transaction_cases')
          .insert(links)
          .select()

        if (linkData && !linkError) {
          setState((prev) => ({
            ...prev,
            transactionCases: [...(prev.transactionCases || []), ...linkData],
          }))
        }
      }

      toast({
        title:
          inst > 1 ? `${inst} parcelas de honorários criadas!` : 'Honorário criado com sucesso!',
      })
    },
    [],
  )

  const updateUser = useCallback(async (id: string, changes: Partial<User>) => {
    setState((prev) => ({
      ...prev,
      users: prev.users.map((u) => (u.id === id ? { ...u, ...changes } : u)),
      currentUser:
        prev.currentUser.id === id ? { ...prev.currentUser, ...changes } : prev.currentUser,
    }))
    await supabase
      .from('profiles')
      .update(changes as any)
      .eq('id', id)
  }, [])

  const addUser = useCallback((newUser: any) => {
    setState((prev) => ({ ...prev, users: [...prev.users, newUser] }))
  }, [])

  const renameType = useCallback(
    async (table: string, column: string, oldVal: string, newVal: string) => {
      setState((prev) => {
        const arr = prev[table as keyof LegalState] as any[]
        return {
          ...prev,
          [table]: arr.map((item) =>
            item[column] === oldVal ? { ...item, [column]: newVal } : item,
          ),
        }
      })
      await supabase
        .from(table as any)
        .update({ [column]: newVal })
        .eq(column, oldVal)
    },
    [],
  )

  return (
    <LegalContext.Provider
      value={{
        state,
        isInitialLoading,
        isReloading,
        reloadAllData,
        updateItem,
        deleteItem,
        addLog,
        addClient,
        generateOnboardingTasks,
        addCase,
        addTask,
        addAppointment,
        addTransaction,
        addSupplier,
        addPetition,
        addClientFee,
        updateUser,
        addUser,
        renameType,
        reloadTransactions: async () => {
          try {
            const allRows: any[] = []
            const pageSize = 1000
            let from = 0
            const maxPages = 50

            for (let page = 0; page < maxPages; page++) {
              const { data, error } = await supabase
                .from('transactions')
                .select('*')
                .range(from, from + pageSize - 1)

              if (error) {
                console.warn('Erro ao recarregar transactions:', error)
                break
              }

              if (data && Array.isArray(data) && data.length > 0) {
                allRows.push(...data)
                if (data.length < pageSize) {
                  break
                }
                from += pageSize
              } else {
                break
              }
            }

            if (allRows.length > 0) {
              setState((prev) => ({
                ...prev,
                transactions: (allRows as any[]).sort(
                  (a: any, b: any) =>
                    new Date(b.date || 0).getTime() - new Date(a.date || 0).getTime(),
                ),
              }))
            }
          } catch (err) {
            console.warn('Erro ao recarregar transactions:', err)
          }
        },
        reloadAppointments: async () => {
          try {
            const allRows: any[] = []
            const pageSize = 1000
            let from = 0
            const maxPages = 50

            for (let page = 0; page < maxPages; page++) {
              const { data, error } = await supabase
                .from('appointments')
                .select('*')
                .range(from, from + pageSize - 1)

              if (error) {
                console.warn('Erro ao recarregar appointments:', error)
                break
              }

              if (data && Array.isArray(data) && data.length > 0) {
                allRows.push(...data)
                if (data.length < pageSize) {
                  break
                }
                from += pageSize
              } else {
                break
              }
            }

            if (allRows.length > 0) {
              setState((prev) => ({
                ...prev,
                appointments: (allRows as any[]).sort(
                  (a: any, b: any) =>
                    new Date(a.date || 0).getTime() - new Date(b.date || 0).getTime(),
                ),
              }))
            }
          } catch (err) {
            console.warn('Erro ao recarregar appointments:', err)
          }
        },
        reloadPaymentPlans: async () => {
          try {
            const { data, error } = await (supabase as any)
              .from('payment_plans')
              .select('*')
              .order('created_at', { ascending: false })

            if (error) {
              console.warn('Erro ao recarregar payment_plans:', error)
              return
            }

            if (data) {
              setState((prev) => ({
                ...prev,
                paymentPlans: data as any[],
              }))
            }
          } catch (err) {
            console.warn('Erro ao recarregar payment_plans:', err)
          }
        },
        addPaymentPlan,
        markRepasseAsDone,
        deletePaymentPlan,
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
