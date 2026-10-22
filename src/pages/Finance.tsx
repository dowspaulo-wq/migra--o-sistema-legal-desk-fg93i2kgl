import { useState, useMemo } from 'react'
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
import { Button } from '@/components/ui/button'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Plus,
  ArrowUpRight,
  ArrowDownRight,
  Download,
  Trash,
  Filter,
  Edit,
  Send,
} from 'lucide-react'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import { Bar, BarChart, CartesianGrid, XAxis, YAxis, ResponsiveContainer } from 'recharts'
import { ChartContainer, ChartTooltip, ChartTooltipContent } from '@/components/ui/chart'
import useLegalStore from '@/stores/useLegalStore'
import { Navigate } from 'react-router-dom'
import { downloadCSV } from '@/lib/export'
import { TransactionDialog } from '@/components/TransactionDialog'
import { formatSafeLocalDate, formatSafeDateTime, calculateInstallmentDate } from '@/lib/utils'
import { SupplierDialog } from '@/components/SupplierDialog'
import { syncChargeWithAsaas, cancelChargeWithAsaas, syncHistoryWithAsaas } from '@/services/asaas'
import { LinkTransactionToCaseDialog } from '@/components/LinkTransactionToCaseDialog'
import { supabase } from '@/lib/supabase/client'
import { toast } from '@/hooks/use-toast'
import { Link2 } from 'lucide-react'
import { RecurringTransactionEditDialog } from '@/components/RecurringTransactionEditDialog'
import { ConciliationTab } from '@/components/ConciliationTab'
import { AsaasExtractImportDialog } from '@/components/AsaasExtractImportDialog'
import { BankPdfImportDialog } from '@/components/BankPdfImportDialog'
import { PaymentPlanDialog } from '@/components/PaymentPlanDialog'
import { Calculator, CheckCircle2 } from 'lucide-react'

export default function Finance() {
  const {
    state,
    updateItem,
    deleteItem,
    addTransaction,
    addSupplier,
    reloadTransactions,
    markRepasseAsDone,
    deletePaymentPlan,
  } = useLegalStore() as any

  const now = new Date()
  const firstDay = new Date(now.getFullYear(), now.getMonth(), 1)
  const lastDay = new Date(now.getFullYear(), now.getMonth() + 1, 0)
  const pad = (n: number) => n.toString().padStart(2, '0')
  const formatYYYYMMDD = (d: Date) =>
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`

  const [activeTab, setActiveTab] = useState('geral')
  const [filterStatus, setFilterStatus] = useState('Todos')
  const [filterBank, setFilterBank] = useState('Todos')
  const [filterCategory, setFilterCategory] = useState('Todas')
  const [filterSupplier, setFilterSupplier] = useState('Todos')
  const [filterSupplierGroup, setFilterSupplierGroup] = useState('Todos')
  const [filterClient, setFilterClient] = useState('Todos')
  const [filterCase, setFilterCase] = useState('Todos')
  const [filterStartDate, setFilterStartDate] = useState(formatYYYYMMDD(firstDay))
  const [filterEndDate, setFilterEndDate] = useState(formatYYYYMMDD(lastDay))
  const [searchQuery, setSearchQuery] = useState('')

  const monthShortcuts = useMemo(() => {
    const months = [
      'jan',
      'fev',
      'mar',
      'abr',
      'mai',
      'jun',
      'jul',
      'ago',
      'set',
      'out',
      'nov',
      'dez',
    ]
    const now = new Date()
    const offsets = [-6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6]
    return offsets.map((offset) => {
      const target = new Date(now.getFullYear(), now.getMonth() + offset, 1)
      return {
        label: `${months[target.getMonth()]}/${target.getFullYear().toString().slice(2)}`,
        offset,
      }
    })
  }, [])

  const setMonthRange = (offset: number) => {
    const now = new Date()
    const target = new Date(now.getFullYear(), now.getMonth() + offset, 1)
    const first = new Date(target.getFullYear(), target.getMonth(), 1)
    const last = new Date(target.getFullYear(), target.getMonth() + 1, 0)
    setFilterStartDate(formatYYYYMMDD(first))
    setFilterEndDate(formatYYYYMMDD(last))
  }

  const setYearRange = (year: number) => {
    setFilterStartDate(`${year}-01-01`)
    setFilterEndDate(`${year}-12-31`)
  }

  const setLast12MonthsRange = () => {
    const now = new Date()
    const past = new Date(now.getFullYear() - 1, now.getMonth(), now.getDate())
    setFilterStartDate(formatYYYYMMDD(past))
    setFilterEndDate(formatYYYYMMDD(now))
  }

  const setNext12MonthsRange = () => {
    const now = new Date()
    const future = new Date(now.getFullYear() + 1, now.getMonth(), now.getDate())
    setFilterStartDate(formatYYYYMMDD(now))
    setFilterEndDate(formatYYYYMMDD(future))
  }

  const [editingTransaction, setEditingTransaction] = useState<any>(null)
  const [creatingTransaction, setCreatingTransaction] = useState(false)
  const [creatingExpenseTransaction, setCreatingExpenseTransaction] = useState(false)
  const [creatingPaymentPlan, setCreatingPaymentPlan] = useState(false)
  const [convertingSuccessCase, setConvertingSuccessCase] = useState<any>(null)

  const [editingSupplier, setEditingSupplier] = useState<any>(null)
  const [creatingSupplier, setCreatingSupplier] = useState(false)
  const [syncingAsaasId, setSyncingAsaasId] = useState<string | null>(null)
  const [syncingHistory, setSyncingHistory] = useState(false)
  const [linkingTx, setLinkingTx] = useState<any>(null)
  const [asaasExtractDialogOpen, setAsaasExtractDialogOpen] = useState(false)
  const [pdfImportDialogOpen, setPdfImportDialogOpen] = useState(false)
  const [txToDelete, setTxToDelete] = useState<any>(null)
  const [deletingTx, setDeletingTx] = useState(false)
  const [txDeleteError, setTxDeleteError] = useState<string | null>(null)
  const [recurringEditData, setRecurringEditData] = useState<{
    id: string
    changes: any
    recurring_id: string
    currentDate: string
  } | null>(null)

  const baseTransactions = useMemo(() => {
    // Only show transactions sent to finance
    return state.transactions.filter((t) => t.sendToFinance !== false)
  }, [state.transactions])

  // Honorários de êxito registrados no processo ("Não gera lançamento financeiro")
  // visíveis no Financeiro na seção "Êxito a apurar"
  const unbilledSuccessFees = useMemo(() => {
    const processIdsWithTx = new Set<string>()
    for (const t of state.transactions || []) {
      if (t.processId) processIdsWithTx.add(t.processId)
    }
    for (const tc of state.transactionCases || []) {
      if (tc.case_id) processIdsWithTx.add(tc.case_id)
    }

    return (state.cases || [])
      .filter((c: any) => {
        const feeType = (c.feeType || '').toLowerCase()
        const isSuccess =
          feeType.includes('êxito') ||
          feeType.includes('exito') ||
          feeType.includes('quota') ||
          feeType.includes('littis')
        if (!isSuccess) return false
        // Exclui se já tiver transação financeira
        return !processIdsWithTx.has(c.id)
      })
      .map((c: any) => {
        const clientObj = state.clients?.find((cl: any) => cl.id === c.clientId)
        const feeValue = typeof c.feeValue === 'number' ? c.feeValue : parseFloat(c.feeValue) || 0
        const percentage = c.feePercentage ? parseFloat(c.feePercentage) : undefined
        return {
          caseId: c.id,
          caseNumber: c.number,
          clientName: clientObj?.name || 'Cliente não identificado',
          clientId: c.clientId,
          feeType: 'Honorários de Êxito',
          feeValue,
          feePercentage: percentage,
          dueDate: `${new Date().getFullYear()}-12-31`,
          status: 'Previsto',
        }
      })
  }, [state.cases, state.transactions, state.transactionCases, state.clients])

  const filtered = useMemo(() => {
    let list = baseTransactions

    if (activeTab === 'honorarios') {
      list = list.filter((t) => {
        if (t.type === 'expense') return false
        const cat = (t.category || '').toLowerCase()
        return (
          cat.includes('honor') ||
          cat.includes('êxito') ||
          cat.includes('exito') ||
          cat.includes('acordo') ||
          cat.includes('alvará') ||
          cat.includes('alvara') ||
          cat === 'outros'
        )
      })
    } else if (activeTab === 'despesas-cliente') {
      list = list.filter((t) => {
        if (t.type !== 'expense') return false
        // Despesas do escritório (origem === 'OFFICE') nunca entram na aba Despesas do Cliente
        if (t.origem === 'OFFICE') return false
        // Se a despesa estiver explicitamente vinculada a um fornecedor (ex: Estagiário, Contabilidade, Telefonia),
        // trata-se de despesa do escritório / fornecedores, NÃO despesa do cliente!
        if (t.supplierId) return false

        const cat = (t.category || '').toLowerCase()
        // Regra: despesas vinculadas a cliente ou que representem custas/diligências/repasse
        const isClientRelatedCategory =
          cat.includes('custa') ||
          cat.includes('dilig') ||
          cat.includes('depósito') ||
          cat.includes('deposito') ||
          cat.includes('repasse') ||
          cat === 'despesa do cliente'

        // Se tem clientId explicitamente vinculado ou é categoria típica de cliente sem fornecedor
        return Boolean(t.clientId) || isClientRelatedCategory
      })
    } else if (activeTab === 'fornecedores') {
      list = list.filter((t) => {
        if (t.type !== 'expense') return false
        // Aba Fornecedores inclui todas as despesas do escritório / fornecedor:
        // vinculadas a fornecedor OU marcadas como despesa do escritório (origem === 'OFFICE')
        return Boolean(t.supplierId) || t.origem === 'OFFICE'
      })
    } else if (activeTab === 'parcelamentos') {
      list = list.filter((t) => Boolean(t.plan_id))
    }

    return list.filter((t) => {
      const matchStatus =
        filterStatus === 'Todos'
          ? true
          : filterStatus === 'Pago'
            ? t.status === 'Pago' || t.status === 'Realizado'
            : t.status === filterStatus
      const matchBank = filterBank === 'Todos' || t.bankAccount === filterBank
      // Se estamos na aba de Honorários e o filtro de categoria for de despesa, não deve afetar os honorários
      const matchCategory = filterCategory === 'Todas' || t.category === filterCategory
      const matchSupplier = filterSupplier === 'Todos' || t.supplierId === filterSupplier
      const matchSupplierGroup = (() => {
        if (filterSupplierGroup === 'Todos') return true
        if (!t.supplierId) return false
        const s = (state.suppliers || []).find((sup: any) => sup.id === t.supplierId)
        return s?.group_name === filterSupplierGroup
      })()

      let matchClient = true
      let matchCase = true
      if (activeTab === 'honorarios' || activeTab === 'despesas-cliente') {
        if (filterClient !== 'Todos') {
          // Verifica clientId direto ou clientId do processo vinculado (via processId ou transactionCases)
          let matchesThisClient = t.clientId === filterClient
          if (!matchesThisClient) {
            const linkedCaseIds = (state.transactionCases || [])
              .filter((tc: any) => tc.transaction_id === t.id)
              .map((tc: any) => tc.case_id)
            const allCaseIds = [
              ...new Set([...linkedCaseIds, ...(t.processId ? [t.processId] : [])]),
            ]
            matchesThisClient = allCaseIds.some((cid) => {
              const c = state.cases.find((cs: any) => cs.id === cid)
              return c?.clientId === filterClient
            })
          }
          matchClient = matchesThisClient
        }

        if (filterCase !== 'Todos') {
          const linkedCaseIds = (state.transactionCases || [])
            .filter((tc: any) => tc.transaction_id === t.id)
            .map((tc: any) => tc.case_id)
          const allCaseIds = [...new Set([...linkedCaseIds, ...(t.processId ? [t.processId] : [])])]
          matchCase = allCaseIds.includes(filterCase)
        }
      }

      let matchSearch = true
      if (searchQuery.trim()) {
        const q = searchQuery.toLowerCase().trim()
        const descMatch = (t.description || '').toLowerCase().includes(q)
        const catMatch = (t.category || '').toLowerCase().includes(q)

        // Busca por nome do cliente associado à transação
        let clientMatch = false
        if (t.clientId) {
          const cObj = state.clients.find((cl: any) => cl.id === t.clientId)
          if (cObj && cObj.name?.toLowerCase().includes(q)) {
            clientMatch = true
          }
        }

        // Busca por processo vinculado ou nome do cliente do processo
        let caseMatch = false
        const linkedCaseIds = (state.transactionCases || [])
          .filter((tc: any) => tc.transaction_id === t.id)
          .map((tc: any) => tc.case_id)
        const allCaseIds = [...new Set([...linkedCaseIds, ...(t.processId ? [t.processId] : [])])]
        for (const cid of allCaseIds) {
          const cObj = state.cases.find((cs: any) => cs.id === cid)
          if (cObj) {
            if ((cObj.number || '').toLowerCase().includes(q)) caseMatch = true
            const cClient = state.clients.find((cl: any) => cl.id === cObj.clientId)
            if (cClient && cClient.name?.toLowerCase().includes(q)) caseMatch = true
          }
        }

        matchSearch = descMatch || catMatch || clientMatch || caseMatch
      }

      let matchStart = true
      let matchEnd = true
      if (filterStartDate) matchStart = t.date >= filterStartDate
      if (filterEndDate) matchEnd = t.date <= filterEndDate

      return (
        matchStatus &&
        matchBank &&
        matchCategory &&
        matchSupplier &&
        matchSupplierGroup &&
        matchClient &&
        matchCase &&
        matchSearch &&
        matchStart &&
        matchEnd
      )
    })
  }, [
    baseTransactions,
    activeTab,
    filterStatus,
    filterBank,
    filterCategory,
    filterSupplier,
    filterClient,
    filterCase,
    searchQuery,
    filterStartDate,
    filterEndDate,
    state.cases,
    state.clients,
    state.transactionCases,
  ])

  const chartData = useMemo(() => {
    const dataByDate: Record<string, { date: string; income: number; expense: number }> = {}

    filtered.forEach((t) => {
      if (!dataByDate[t.date]) {
        dataByDate[t.date] = { date: t.date, income: 0, expense: 0 }
      }
      if (t.type === 'income') {
        dataByDate[t.date].income += t.amount
      } else if (t.type === 'expense') {
        // Todas as despesas (inclusive Repasse ao Cliente) afetam a saída real do caixa
        dataByDate[t.date].expense += t.amount
      }
    })

    return Object.values(dataByDate).sort((a, b) => a.date.localeCompare(b.date))
  }, [filtered])

  const sortedSuppliers = useMemo(() => {
    return [...(state.suppliers || [])].sort((a: any, b: any) =>
      (a.name || '').localeCompare(b.name || '', 'pt-BR', { sensitivity: 'base' }),
    )
  }, [state.suppliers])

  const sortedClients = useMemo(() => {
    return [...(state.clients || [])].sort((a: any, b: any) =>
      (a.name || '').localeCompare(b.name || '', 'pt-BR', { sensitivity: 'base' }),
    )
  }, [state.clients])

  const sortedCases = useMemo(() => {
    return [...(state.cases || [])]
      .map((cs: any) => {
        const clientObj = state.clients.find((cl: any) => cl.id === cs.clientId)
        const clientName = clientObj?.name || ''
        const displayLabel = clientName ? `${cs.number} — ${clientName}` : cs.number
        return {
          ...cs,
          clientName,
          displayLabel,
        }
      })
      .sort((a: any, b: any) =>
        (a.displayLabel || '').localeCompare(b.displayLabel || '', 'pt-BR', {
          sensitivity: 'base',
        }),
      )
  }, [state.cases, state.clients])

  const categories = useMemo(() => {
    let source = baseTransactions
    if (activeTab === 'honorarios') {
      // Dropdown de categoria na aba Honorários deve listar apenas categorias de RECEITA / Honorários
      source = baseTransactions.filter((t) => t.type === 'income')
    } else if (activeTab === 'despesas-cliente') {
      source = baseTransactions.filter(
        (t) => t.type === 'expense' && !t.supplierId && t.origem !== 'OFFICE',
      )
    } else if (activeTab === 'fornecedores') {
      source = baseTransactions.filter(
        (t) => t.type === 'expense' && (Boolean(t.supplierId) || t.origem === 'OFFICE'),
      )
    }
    const cats = new Set(source.map((t) => t.category).filter(Boolean))
    return Array.from(cats).sort((a: any, b: any) =>
      String(a).localeCompare(String(b), 'pt-BR', { sensitivity: 'base' }),
    )
  }, [baseTransactions, activeTab])

  const supplierGroups = useMemo(() => {
    const groups = new Set<string>()
    ;(state.suppliers || []).forEach((s: any) => {
      if (s.group_name && s.group_name.trim()) groups.add(s.group_name.trim())
    })
    return Array.from(groups).sort((a, b) => a.localeCompare(b, 'pt-BR', { sensitivity: 'base' }))
  }, [state.suppliers])

  const bankOptions = useMemo(() => {
    const banks = new Set<string>(
      state.settings?.bankAccounts || ['ASAAS', 'SICOOB', 'CAIXA', 'PESSOAL'],
    )
    baseTransactions.forEach((t) => t.bankAccount && banks.add(t.bankAccount))
    return Array.from(banks).sort((a, b) => a.localeCompare(b, 'pt-BR', { sensitivity: 'base' }))
  }, [baseTransactions, state.settings?.bankAccounts])

  const handleAsaasChargeSync = async (transactionId: string) => {
    setSyncingAsaasId(transactionId)
    const { data, error } = await syncChargeWithAsaas(transactionId)
    setSyncingAsaasId(null)
    if (error) {
      toast({
        title: 'Erro na cobrança Asaas',
        description: error.message || 'Falha ao enviar para ASAAS.',
        variant: 'destructive',
      })
    } else {
      if (data?.asaas_id) {
        updateItem('transactions', transactionId, { asaas_id: data.asaas_id })
      }
      toast({
        title: 'Sucesso',
        description: data?.asaas_id
          ? `Cobrança enviada para ASAAS com sucesso! (ID: ${data.asaas_id})`
          : data?.message || 'Cobrança enviada para ASAAS.',
      })
    }
  }

  const handleSyncHistory = async () => {
    setSyncingHistory(true)
    const { data, error } = await syncHistoryWithAsaas()
    setSyncingHistory(false)
    if (error) {
      toast({
        title: 'Erro',
        description: error.message || 'Falha ao sincronizar histórico do ASAAS.',
        variant: 'destructive',
      })
    } else {
      const nowIso = new Date().toISOString()
      // Atualizar settings com o timestamp da última sincronização do Asaas
      await supabase
        .from('settings')
        .update({ lastAsaasSyncAt: nowIso })
        .eq('id', state.settings.id || 'default')
      updateItem('settings', state.settings.id || 'default', { lastAsaasSyncAt: nowIso })

      if (reloadTransactions) await reloadTransactions()

      toast({
        title: 'Sucesso',
        description: data?.message || 'Histórico sincronizado com ASAAS.',
      })
    }
  }

  const handleSicoobImportCompleted = async (timestamp: string) => {
    await supabase
      .from('settings')
      .update({ lastSicoobImportAt: timestamp })
      .eq('id', state.settings.id || 'default')
    updateItem('settings', state.settings.id || 'default', { lastSicoobImportAt: timestamp })
  }

  const handleLinkToCase = async (transactionId: string, caseId: string) => {
    const { error: tcError } = await supabase
      .from('transaction_cases')
      .upsert(
        { transaction_id: transactionId, case_id: caseId },
        { onConflict: 'transaction_id,case_id' },
      )

    if (tcError) {
      toast({
        title: 'Erro',
        description: 'Falha ao vincular processo.',
        variant: 'destructive',
      })
      return
    }

    await updateItem('transactions', transactionId, { processId: caseId })

    toast({ title: 'Sucesso', description: 'Processo vinculado com sucesso.' })
    setLinkingTx(null)
  }

  const handleTxDelete = async (forceLocal = false) => {
    if (!txToDelete) return
    setDeletingTx(true)
    setTxDeleteError(null)

    if (!forceLocal && txToDelete.asaas_id) {
      const { error: asaasError } = await cancelChargeWithAsaas(txToDelete.id)
      if (asaasError) {
        setDeletingTx(false)
        setTxDeleteError(asaasError.message || 'Falha ao cancelar cobrança no ASAAS.')
        return
      }
    }

    await deleteItem('transactions', txToDelete.id)
    setDeletingTx(false)
    setTxToDelete(null)
    setTxDeleteError(null)
    toast({ title: 'Lançamento excluído com sucesso.' })
  }

  if (!state.currentUser.canViewFinance) return <Navigate to="/" replace />

  // DECISÃO 1 DO DOUGLAS: O repasse ao cliente DEVE afetar o saldo do caixa no Financeiro — é despesa real.
  // A receita conta SOMENTE o honorário.
  const income = filtered.filter((t) => t.type === 'income').reduce((a, b) => a + b.amount, 0)
  const expense = filtered.filter((t) => t.type === 'expense').reduce((a, b) => a + b.amount, 0)
  const clientRepassTotal = filtered
    .filter((t) => t.type === 'expense' && (t.category?.toLowerCase() || '').includes('repasse'))
    .reduce((a, b) => a + b.amount, 0)
  const balance = income - expense

  return (
    <div className="space-y-6">
      <TransactionDialog
        open={!!editingTransaction}
        onOpenChange={(v: boolean) => !v && setEditingTransaction(null)}
        data={editingTransaction}
        onSave={(d: any) => {
          if (editingTransaction?.recurring_id) {
            setRecurringEditData({
              id: editingTransaction.id,
              changes: d,
              recurring_id: editingTransaction.recurring_id,
              currentDate: editingTransaction.date,
            })
          } else {
            updateItem('transactions', editingTransaction.id, d)
            if (
              d.amount !== undefined &&
              editingTransaction?.category?.toLowerCase().includes('honor')
            ) {
              const linkedCaseIds = (state.transactionCases || [])
                .filter((tc: any) => tc.transaction_id === editingTransaction.id)
                .map((tc: any) => tc.case_id)
              const allCaseIds = [
                ...new Set([
                  ...linkedCaseIds,
                  ...(editingTransaction.processId ? [editingTransaction.processId] : []),
                ]),
              ]
              allCaseIds.forEach((cid: string) => updateItem('cases', cid, { feeValue: d.amount }))
            }
          }
        }}
      />
      <TransactionDialog
        open={creatingTransaction}
        onOpenChange={setCreatingTransaction}
        onSave={(d: any, isRecurring?: boolean, installments?: number) => {
          if (isRecurring && installments && installments > 1) {
            const recurringId = crypto.randomUUID()
            const baseDateStr = d.date

            const toInsert = []
            for (let i = 0; i < installments; i++) {
              const dateStr = calculateInstallmentDate(baseDateStr, i)
              toInsert.push({
                ...d,
                date: dateStr,
                description: `${d.description} (${i + 1}/${installments})`,
                recurring_id: recurringId,
              })
            }
            addTransaction(toInsert)
          } else {
            addTransaction(d)
          }
        }}
      />
      <TransactionDialog
        open={creatingExpenseTransaction}
        onOpenChange={setCreatingExpenseTransaction}
        data={{
          type: 'expense',
          category: 'Custas Iniciais',
          description: '',
          amount: '',
          status: 'Previsto',
          date: formatYYYYMMDD(new Date()),
        }}
        onSave={(d: any, isRecurring?: boolean, installments?: number) => {
          if (isRecurring && installments && installments > 1) {
            const recurringId = crypto.randomUUID()
            const baseDateStr = d.date

            const toInsert = []
            for (let i = 0; i < installments; i++) {
              const dateStr = calculateInstallmentDate(baseDateStr, i)
              toInsert.push({
                ...d,
                type: 'expense',
                date: dateStr,
                description: `${d.description} (${i + 1}/${installments})`,
                recurring_id: recurringId,
              })
            }
            addTransaction(toInsert)
          } else {
            addTransaction({ ...d, type: 'expense' })
          }
        }}
      />
      <TransactionDialog
        open={!!convertingSuccessCase}
        onOpenChange={(v: boolean) => !v && setConvertingSuccessCase(null)}
        data={
          convertingSuccessCase
            ? {
                type: 'income',
                category: 'Honorários de Êxito',
                description: `Honorários de Êxito - Processo ${convertingSuccessCase.caseNumber}`,
                amount: convertingSuccessCase.feeValue > 0 ? convertingSuccessCase.feeValue : '',
                percentage: convertingSuccessCase.feePercentage || '',
                date: new Date().toISOString().split('T')[0],
                status: 'Pago',
                clientId: convertingSuccessCase.clientId,
                processId: convertingSuccessCase.caseId,
                sendToFinance: true,
              }
            : null
        }
        onSave={async (d: any) => {
          if (!convertingSuccessCase) return
          const targetCaseId = convertingSuccessCase.caseId

          // 1. Gera lançamento financeiro (receita, Honorários de Êxito)
          const newTxPayload = {
            ...d,
            type: 'income',
            category: 'Honorários de Êxito',
            clientId: convertingSuccessCase.clientId,
            processId: targetCaseId,
            sendToFinance: true,
            status: d.status || 'Pago',
          }
          await addTransaction(newTxPayload)

          // 2. Atualiza o processo limpando o estado de "não gera lançamento"
          await updateItem('cases', targetCaseId, {
            feeType: 'Honorários de Êxito',
            feeValue: d.amount || 0,
            feePercentage: d.percentage || null,
          })

          toast({
            title: 'Lançamento gerado com sucesso!',
            description: 'Honorário de êxito agora possui lançamento financeiro ativo.',
          })
          setConvertingSuccessCase(null)
        }}
      />
      <SupplierDialog
        open={!!editingSupplier}
        onOpenChange={(v: boolean) => !v && setEditingSupplier(null)}
        data={editingSupplier}
        existingGroups={supplierGroups}
        onSave={(d: any) => updateItem('suppliers', editingSupplier.id, d)}
      />
      <SupplierDialog
        open={creatingSupplier}
        onOpenChange={setCreatingSupplier}
        existingGroups={supplierGroups}
        onSave={(d: any) => addSupplier(d)}
      />

      <LinkTransactionToCaseDialog
        open={!!linkingTx}
        onOpenChange={(v: boolean) => !v && setLinkingTx(null)}
        transaction={linkingTx}
        cases={state.cases}
        onLink={handleLinkToCase}
      />

      <RecurringTransactionEditDialog
        open={!!recurringEditData}
        onOpenChange={(v: boolean) => !v && setRecurringEditData(null)}
        onChoose={async (choice: 'single' | 'future') => {
          if (!recurringEditData) return
          const { id, changes, recurring_id, currentDate } = recurringEditData

          if (choice === 'single') {
            await updateItem('transactions', id, changes)
          } else {
            await updateItem('transactions', id, changes)

            const today = new Date().toISOString().split('T')[0]
            const { data: futureTxns } = await supabase
              .from('transactions')
              .select('id, date, status')
              .eq('recurring_id', recurring_id)
              .gt('date', currentDate)

            const toUpdate = (futureTxns || []).filter(
              (t: any) =>
                t.date >= today && !['Pago', 'pago', 'Realizado', 'realizado'].includes(t.status),
            )

            const { date: _d, description: _desc, recurring_id: _r, ...sharedChanges } = changes

            for (const t of toUpdate) {
              await updateItem('transactions', t.id, sharedChanges)
            }
          }

          setRecurringEditData(null)
          setEditingTransaction(null)
          toast({
            title: 'Sucesso',
            description:
              choice === 'single'
                ? 'Lançamento atualizado.'
                : 'Lançamento e próximos vinculados atualizados.',
          })
        }}
      />

      <AlertDialog
        open={!!txToDelete}
        onOpenChange={(v) => {
          if (!v) {
            setTxToDelete(null)
            setTxDeleteError(null)
          }
        }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Excluir Lançamento?</AlertDialogTitle>
            <AlertDialogDescription>
              {txDeleteError
                ? `Erro ao cancelar no ASAAS: ${txDeleteError}. Deseja excluir apenas localmente?`
                : 'Esta ação é irreversível. O registro será removido e, se houver cobrança no ASAAS, será cancelada.'}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={deletingTx}>Cancelar</AlertDialogCancel>
            {txDeleteError ? (
              <>
                <AlertDialogAction
                  onClick={() => handleTxDelete(true)}
                  disabled={deletingTx}
                  className="bg-amber-600 hover:bg-amber-700"
                >
                  Excluir apenas local
                </AlertDialogAction>
                <AlertDialogAction onClick={() => handleTxDelete(false)} disabled={deletingTx}>
                  Tentar novamente
                </AlertDialogAction>
              </>
            ) : (
              <AlertDialogAction
                onClick={() => handleTxDelete(false)}
                disabled={deletingTx}
                className="bg-red-600 hover:bg-red-700"
              >
                {deletingTx ? 'Excluindo...' : 'Excluir'}
              </AlertDialogAction>
            )}
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <div className="flex flex-col md:flex-row md:justify-between md:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Financeiro</h1>
          <p className="text-muted-foreground">Controle de honorários e despesas.</p>
        </div>
        <div className="flex flex-wrap gap-3 items-start">
          {/* Botão Sincronizar com Asaas + Timestamp */}
          <div className="flex flex-col items-center">
            <Button
              variant="outline"
              onClick={handleSyncHistory}
              disabled={syncingHistory}
              className="border-blue-200 text-blue-700 hover:bg-blue-50"
            >
              <Send className={`mr-2 h-4 w-4 ${syncingHistory ? 'animate-pulse' : ''}`} />
              {syncingHistory ? 'Sincronizando...' : 'Sincronizar com Asaas'}
            </Button>
            <span className="text-[11px] text-muted-foreground mt-1">
              {state.settings?.lastAsaasSyncAt
                ? `Última sincronização: ${formatSafeDateTime(state.settings.lastAsaasSyncAt)}`
                : 'Última sincronização: Nunca'}
            </span>
          </div>

          {/* Botão Importar Extrato SICOOB / Cartões + Timestamp */}
          <div className="flex flex-col items-center">
            <Button
              variant="outline"
              onClick={() => setPdfImportDialogOpen(true)}
              className="border-emerald-200 text-emerald-700 hover:bg-emerald-50"
            >
              <Download className="mr-2 h-4 w-4 text-emerald-600" />
              Importar Extrato SICOOB / Cartões (PDF)
            </Button>
            <span className="text-[11px] text-muted-foreground mt-1">
              {state.settings?.lastSicoobImportAt
                ? `Última importação: ${formatSafeDateTime(state.settings.lastSicoobImportAt)}`
                : 'Última importação: Nunca'}
            </span>
          </div>

          <Button
            variant="outline"
            onClick={() => {
              const exportData = filtered.map((t) => {
                const linkedIds = (state.transactionCases || [])
                  .filter((tc: any) => tc.transaction_id === t.id)
                  .map((tc: any) => tc.case_id)
                const linkedCases = state.cases.filter((c) => linkedIds.includes(c.id))
                const allDisplayCases =
                  linkedCases.length > 0
                    ? linkedCases
                    : t.processId
                      ? state.cases.filter((c) => c.id === t.processId)
                      : []
                const processInfo = allDisplayCases
                  .map((c) => {
                    const clientObj = state.clients.find(
                      (cl: any) => cl.id === (c.clientId || t.clientId),
                    )
                    return clientObj?.name ? `${c.number} — ${clientObj.name}` : c.number
                  })
                  .join('; ')

                return {
                  Data: t.date,
                  Descrição: t.description,
                  Categoria: t.category,
                  'Processo / Cliente': processInfo || '-',
                  Banco: t.bankAccount || '-',
                  Status: t.status,
                  Tipo: t.type === 'income' ? 'Entrada' : 'Saída',
                  Valor: t.amount,
                }
              })

              // Se houver honorários de êxito a apurar, inclui no relatório de exportação
              if (activeTab === 'honorarios' && unbilledSuccessFees.length > 0) {
                unbilledSuccessFees.forEach((fee) => {
                  exportData.push({
                    Data: fee.dueDate,
                    Descrição: `Honorários de Êxito (A apurar) - Processo ${fee.caseNumber}`,
                    Categoria: 'Honorários de Êxito',
                    'Processo / Cliente': `${fee.caseNumber} — ${fee.clientName}`,
                    Banco: '-',
                    Status: 'Previsto',
                    Tipo: 'Entrada',
                    Valor: fee.feeValue > 0 ? (fee.feeValue as any) : 'A apurar',
                  })
                })
              }

              downloadCSV(exportData, 'financeiro.csv')
            }}
          >
            <Download className="mr-2 h-4 w-4" /> Exportar
          </Button>
          <Button
            variant="outline"
            onClick={() => setCreatingPaymentPlan(true)}
            className="border-blue-300 text-blue-800 hover:bg-blue-50 dark:border-blue-700 dark:text-blue-300 dark:hover:bg-blue-950/40"
          >
            <Calculator className="mr-2 h-4 w-4 text-blue-600" /> Novo Parcelamento
          </Button>
          <Button
            variant="outline"
            onClick={() => setCreatingExpenseTransaction(true)}
            className="border-amber-300 text-amber-800 hover:bg-amber-50"
          >
            <Plus className="mr-2 h-4 w-4 text-amber-600" /> Despesa do Cliente
          </Button>
          <Button onClick={() => setCreatingTransaction(true)}>
            <Plus className="mr-2 h-4 w-4" /> Novo Lançamento
          </Button>
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-4">
        <Card className="bg-green-50 border-green-200">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-green-800">Entradas</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-green-700 flex items-center">
              <ArrowUpRight className="mr-2" /> R${' '}
              {income.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
            </div>
          </CardContent>
        </Card>
        <Card className="bg-red-50 border-red-200">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-red-800">Saídas</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-red-700 flex items-center">
              <ArrowDownRight className="mr-2" /> R${' '}
              {expense.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
            </div>
          </CardContent>
        </Card>
        <Card className="bg-slate-800 text-white">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-slate-300">Saldo Visível</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              R$ {balance.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
            </div>
          </CardContent>
        </Card>
        <Card className="bg-blue-50 border-blue-200">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-blue-800">Repasses a clientes</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-blue-700">
              R$ {clientRepassTotal.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
            </div>
            <p className="text-[11px] text-blue-600 mt-1">Despesa real inclusa nas saídas</p>
          </CardContent>
        </Card>
      </div>

      <Tabs value={activeTab} onValueChange={setActiveTab} className="w-full">
        <TabsList className="grid w-full max-w-5xl grid-cols-6">
          <TabsTrigger value="geral">Visão Geral</TabsTrigger>
          <TabsTrigger value="honorarios">Honorários</TabsTrigger>
          <TabsTrigger value="parcelamentos">
            Parcelamentos ({state.paymentPlans?.length || 0})
          </TabsTrigger>
          <TabsTrigger value="despesas-cliente">Despesas do Cliente</TabsTrigger>
          <TabsTrigger value="fornecedores">Fornecedores</TabsTrigger>
          <TabsTrigger value="conciliacao" className="relative">
            Conciliação
            {(() => {
              const pendingCount = (state.transactions || []).filter((t: any) =>
                Boolean(t.pendente_vinculo),
              ).length
              if (pendingCount > 0) {
                return (
                  <Badge
                    variant="destructive"
                    className="ml-1.5 h-4 px-1.5 text-[10px] leading-none rounded-full"
                  >
                    {pendingCount}
                  </Badge>
                )
              }
              return null
            })()}
          </TabsTrigger>
        </TabsList>

        {activeTab !== 'conciliacao' && (
          <Card className="mt-4">
            <CardHeader className="pb-4">
              <div className="flex flex-col gap-4">
                <div className="flex flex-col gap-3">
                  <div className="flex items-center gap-2 text-lg font-semibold">
                    <Filter className="h-5 w-5 text-muted-foreground" />
                    Filtros
                  </div>
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="text-sm text-muted-foreground">Atalhos por Mês:</span>
                    {monthShortcuts.map((m) => (
                      <Button
                        key={m.offset}
                        variant="outline"
                        size="sm"
                        className="h-7 text-xs"
                        onClick={() => setMonthRange(m.offset)}
                      >
                        {m.label}
                      </Button>
                    ))}
                  </div>

                  <div className="flex flex-wrap items-center gap-2">
                    <span className="text-sm text-muted-foreground">Atalhos por Ano:</span>
                    <Button
                      variant="outline"
                      size="sm"
                      className="h-7 text-xs font-medium bg-slate-50 hover:bg-slate-100"
                      onClick={() => setYearRange(2026)}
                    >
                      2026
                    </Button>
                    <Button
                      variant="outline"
                      size="sm"
                      className="h-7 text-xs font-medium bg-slate-50 hover:bg-slate-100"
                      onClick={() => setYearRange(2027)}
                    >
                      2027
                    </Button>
                    <Button
                      variant="outline"
                      size="sm"
                      className="h-7 text-xs font-medium bg-slate-50 hover:bg-slate-100"
                      onClick={() => setYearRange(2028)}
                    >
                      2028
                    </Button>
                    <Button
                      variant="outline"
                      size="sm"
                      className="h-7 text-xs text-blue-700 border-blue-200 bg-blue-50/50 hover:bg-blue-100"
                      onClick={setLast12MonthsRange}
                    >
                      Últimos 12 meses
                    </Button>
                    <Button
                      variant="outline"
                      size="sm"
                      className="h-7 text-xs text-blue-700 border-blue-200 bg-blue-50/50 hover:bg-blue-100"
                      onClick={setNext12MonthsRange}
                    >
                      Próximos 12 meses
                    </Button>
                  </div>
                </div>

                {/* Campo de busca textual por descrição, nº do processo ou cliente */}
                <div className="max-w-md">
                  <Input
                    placeholder="Buscar por descrição, processo ou cliente..."
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    className="bg-white text-sm"
                  />
                </div>

                <div
                  className={`grid grid-cols-1 md:grid-cols-3 ${
                    activeTab === 'honorarios' ? 'lg:grid-cols-8' : 'lg:grid-cols-6'
                  } gap-4`}
                >
                  <div className="space-y-1.5">
                    <Label>Status</Label>
                    <Select value={filterStatus} onValueChange={setFilterStatus}>
                      <SelectTrigger className="bg-white">
                        <SelectValue placeholder="Status" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="Todos">Todos</SelectItem>
                        <SelectItem value="Atrasado">Atrasado</SelectItem>
                        <SelectItem value="Cancelado">Cancelado</SelectItem>
                        <SelectItem value="Pago">Pago</SelectItem>
                        <SelectItem value="Pendente">Pendente</SelectItem>
                        <SelectItem value="Previsto">Previsto</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="space-y-1.5">
                    <Label>Banco / Conta</Label>
                    <Select value={filterBank} onValueChange={setFilterBank}>
                      <SelectTrigger className="bg-white">
                        <SelectValue placeholder="Banco" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="Todos">Todos</SelectItem>
                        {bankOptions.map((b) => (
                          <SelectItem key={b} value={b}>
                            {b}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="space-y-1.5">
                    <Label>Categoria</Label>
                    <Select value={filterCategory} onValueChange={setFilterCategory}>
                      <SelectTrigger className="bg-white">
                        <SelectValue placeholder="Categoria" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="Todas">Todas</SelectItem>
                        {categories.map((c: any) => (
                          <SelectItem key={String(c)} value={String(c)}>
                            {String(c)}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  {activeTab !== 'honorarios' && (
                    <>
                      <div className="space-y-1.5">
                        <Label>Fornecedor</Label>
                        <Select value={filterSupplier} onValueChange={setFilterSupplier}>
                          <SelectTrigger className="bg-white">
                            <SelectValue placeholder="Fornecedor" />
                          </SelectTrigger>
                          <SelectContent className="max-h-72">
                            <SelectItem value="Todos">Todos</SelectItem>
                            {sortedSuppliers.map((s: any) => (
                              <SelectItem key={s.id} value={s.id}>
                                {s.name}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                      <div className="space-y-1.5">
                        <Label>Grupo Fornecedor</Label>
                        <Select value={filterSupplierGroup} onValueChange={setFilterSupplierGroup}>
                          <SelectTrigger className="bg-white">
                            <SelectValue placeholder="Grupo" />
                          </SelectTrigger>
                          <SelectContent className="max-h-72">
                            <SelectItem value="Todos">Todos</SelectItem>
                            {supplierGroups.map((g) => (
                              <SelectItem key={g} value={g}>
                                {g}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                    </>
                  )}
                  {activeTab === 'honorarios' && (
                    <>
                      <div className="space-y-1.5">
                        <Label>Cliente</Label>
                        <Select value={filterClient} onValueChange={setFilterClient}>
                          <SelectTrigger className="bg-white">
                            <SelectValue placeholder="Cliente" />
                          </SelectTrigger>
                          <SelectContent className="max-h-72">
                            <SelectItem value="Todos">Todos</SelectItem>
                            {sortedClients.map((c: any) => (
                              <SelectItem key={c.id} value={c.id}>
                                {c.name}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                      <div className="space-y-1.5">
                        <Label>Processo / Cliente</Label>
                        <Select value={filterCase} onValueChange={setFilterCase}>
                          <SelectTrigger className="bg-white">
                            <SelectValue placeholder="Processo — Cliente" />
                          </SelectTrigger>
                          <SelectContent className="max-h-72">
                            <SelectItem value="Todos">Todos</SelectItem>
                            {sortedCases.map((cs: any) => (
                              <SelectItem key={cs.id} value={cs.id}>
                                {cs.displayLabel}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                    </>
                  )}
                  <div className="space-y-1.5">
                    <Label>Data Inicial</Label>
                    <Input
                      type="date"
                      value={filterStartDate}
                      onChange={(e) => setFilterStartDate(e.target.value)}
                    />
                  </div>
                  <div className="space-y-1.5">
                    <Label>Data Final</Label>
                    <Input
                      type="date"
                      value={filterEndDate}
                      onChange={(e) => setFilterEndDate(e.target.value)}
                    />
                  </div>
                </div>
              </div>
            </CardHeader>
            <CardContent>
              {chartData.length > 0 && (
                <div className="mb-8">
                  <h3 className="text-lg font-medium mb-4">Evolução Financeira no Período</h3>
                  <ChartContainer
                    config={{
                      income: { label: 'Entradas', color: '#22c55e' },
                      expense: { label: 'Saídas', color: '#ef4444' },
                    }}
                    className="h-[250px] w-full"
                  >
                    <BarChart data={chartData} margin={{ top: 10, right: 10, left: 10, bottom: 0 }}>
                      <CartesianGrid strokeDasharray="3 3" vertical={false} />
                      <XAxis
                        dataKey="date"
                        tickFormatter={(value) => {
                          const parts = value.split('-')
                          return `${parts[2]}/${parts[1]}`
                        }}
                        tickLine={false}
                        axisLine={false}
                      />
                      <YAxis
                        tickFormatter={(value) => `R$ ${value}`}
                        tickLine={false}
                        axisLine={false}
                        width={80}
                      />
                      <ChartTooltip content={(props: any) => <ChartTooltipContent {...props} />} />
                      <Bar
                        dataKey="income"
                        fill="var(--color-income)"
                        radius={[4, 4, 0, 0]}
                        maxBarSize={40}
                      />
                      <Bar
                        dataKey="expense"
                        fill="var(--color-expense)"
                        radius={[4, 4, 0, 0]}
                        maxBarSize={40}
                      />
                    </BarChart>
                  </ChartContainer>
                </div>
              )}
              <div className="rounded-md border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Data</TableHead>
                      <TableHead>Descrição</TableHead>
                      <TableHead>Categoria</TableHead>
                      <TableHead>Conta</TableHead>
                      <TableHead>Processos</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead className="text-right">Valor</TableHead>
                      <TableHead className="w-[80px]"></TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {filtered.map((t) => (
                      <TableRow
                        key={t.id}
                        className="cursor-pointer hover:bg-slate-50 group"
                        onClick={() => setEditingTransaction(t)}
                      >
                        <TableCell>{formatSafeLocalDate(t.date)}</TableCell>
                        <TableCell className="font-medium">
                          <div>{t.description}</div>
                          {t.category === 'Honorários Avulsos' && (
                            <div className="text-xs text-muted-foreground font-normal">
                              Serviço: {t.description || '—'}
                            </div>
                          )}
                        </TableCell>
                        <TableCell>
                          <div className="flex items-center gap-1.5 flex-wrap">
                            <span>{t.category}</span>
                            {t.category === 'Honorários Avulsos' && (
                              <Badge
                                variant="secondary"
                                className="text-[10px] bg-blue-50 text-blue-700 border-blue-200"
                              >
                                Avulso
                              </Badge>
                            )}
                          </div>
                        </TableCell>
                        <TableCell>{t.bankAccount || '-'}</TableCell>
                        <TableCell>
                          {(() => {
                            const linkedIds = (state.transactionCases || [])
                              .filter((tc: any) => tc.transaction_id === t.id)
                              .map((tc: any) => tc.case_id)
                            const linkedCases = state.cases.filter((c) => linkedIds.includes(c.id))
                            const allDisplayCases =
                              linkedCases.length > 0
                                ? linkedCases
                                : t.processId
                                  ? state.cases.filter((c) => c.id === t.processId)
                                  : []

                            if (allDisplayCases.length > 0) {
                              return (
                                <div className="flex flex-col gap-1">
                                  {allDisplayCases.map((c) => {
                                    const clientObj = state.clients.find(
                                      (cl: any) => cl.id === (c.clientId || t.clientId),
                                    )
                                    const clientName = clientObj?.name || ''
                                    const label = clientName
                                      ? `${c.number} — ${clientName}`
                                      : c.number
                                    return (
                                      <Badge
                                        key={c.id}
                                        variant="secondary"
                                        className="text-[11px] font-normal justify-start max-w-xs truncate"
                                        title={label}
                                      >
                                        {label}
                                      </Badge>
                                    )
                                  })}
                                </div>
                              )
                            }

                            if (t.clientId) {
                              const clientObj = state.clients.find(
                                (cl: any) => cl.id === t.clientId,
                              )
                              if (clientObj?.name) {
                                return (
                                  <Badge
                                    variant="outline"
                                    className="text-xs font-normal bg-blue-50/60 text-blue-900 border-blue-200 max-w-xs truncate"
                                    title={`Cliente: ${clientObj.name}`}
                                  >
                                    Cliente: {clientObj.name}
                                  </Badge>
                                )
                              }
                            }

                            return '-'
                          })()}
                        </TableCell>
                        <TableCell>
                          <Badge
                            variant="outline"
                            className={
                              t.status === 'Pago' || t.status === 'Paga' || t.status === 'Realizado'
                                ? 'border-emerald-300 text-emerald-700 bg-emerald-50 font-semibold'
                                : t.status === 'Atrasado' || t.status === 'Vencida'
                                  ? 'border-red-200 text-red-700 bg-red-50'
                                  : t.status === 'Cancelada' || t.status === 'Estornada'
                                    ? 'border-slate-200 text-slate-600 bg-slate-50'
                                    : 'border-orange-200 text-orange-700 bg-orange-50'
                            }
                          >
                            {t.status}
                          </Badge>
                        </TableCell>
                        <TableCell
                          className={`text-right font-bold ${t.type === 'income' ? 'text-green-600' : 'text-red-600'}`}
                        >
                          {t.type === 'income' ? '+' : '-'} R${' '}
                          {t.amount.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
                        </TableCell>
                        <TableCell>
                          <div className="flex items-center justify-end gap-1">
                            {/* Botão próprio "Repasse efetuado" para lançamentos de Repasse ao Cliente */}
                            {t.type === 'expense' &&
                              (t.category?.toLowerCase() || '').includes('repasse') &&
                              t.status !== 'Pago' && (
                                <Button
                                  variant="outline"
                                  size="sm"
                                  className="h-7 text-xs bg-emerald-50 text-emerald-700 border-emerald-300 hover:bg-emerald-100 dark:bg-emerald-950/40 dark:text-emerald-300"
                                  onClick={(e) => {
                                    e.stopPropagation()
                                    markRepasseAsDone(t.id)
                                  }}
                                  title="Marcar repasse como Pago (dinheiro repassado ao cliente)"
                                >
                                  <CheckCircle2 className="h-3.5 w-3.5 mr-1" />
                                  Repasse efetuado
                                </Button>
                              )}
                            {/* Botão rápido Marcar Pago para honorários ou outras receitas previstas */}
                            {t.type === 'income' && t.status !== 'Pago' && (
                              <Button
                                variant="outline"
                                size="sm"
                                className="h-7 text-xs border-green-300 text-green-700 hover:bg-green-50"
                                onClick={(e) => {
                                  e.stopPropagation()
                                  updateItem('transactions', t.id, {
                                    status: 'Pago',
                                    date: new Date().toISOString().split('T')[0],
                                  })
                                  toast({ title: 'Honorário marcado como Pago!' })
                                }}
                                title="Marcar honorário como Pago"
                              >
                                Marcar Pago
                              </Button>
                            )}
                            <Button
                              variant="ghost"
                              size="icon"
                              className="h-8 w-8 text-slate-500 hover:text-slate-700 hover:bg-slate-100 opacity-0 group-hover:opacity-100 transition-opacity"
                              onClick={(e) => {
                                e.stopPropagation()
                                setEditingTransaction(t)
                              }}
                              title="Editar Lançamento"
                            >
                              <Edit className="h-4 w-4" />
                            </Button>
                            <Button
                              variant="ghost"
                              size="icon"
                              className="h-8 w-8 text-purple-500 hover:text-purple-700 hover:bg-purple-50 opacity-0 group-hover:opacity-100 transition-opacity"
                              onClick={(e) => {
                                e.stopPropagation()
                                setLinkingTx(t)
                              }}
                              title="Vincular a Processo"
                            >
                              <Link2 className="h-4 w-4" />
                            </Button>
                            <Button
                              variant="ghost"
                              size="icon"
                              className={`h-8 w-8 ${t.asaas_id ? 'text-blue-600 font-medium' : 'text-blue-500'} hover:text-blue-700 hover:bg-blue-50 opacity-0 group-hover:opacity-100 transition-opacity`}
                              onClick={(e) => {
                                e.stopPropagation()
                                handleAsaasChargeSync(t.id)
                              }}
                              disabled={syncingAsaasId === t.id}
                              title={
                                t.asaas_id ? 'Sincronizar/Atualizar com ASAAS' : 'Enviar para ASAAS'
                              }
                            >
                              <Send
                                className={`h-4 w-4 ${syncingAsaasId === t.id ? 'animate-pulse' : ''}`}
                              />
                            </Button>
                            <Button
                              variant="ghost"
                              size="icon"
                              className="h-8 w-8 text-red-500 hover:text-red-700 hover:bg-red-50 opacity-0 group-hover:opacity-100 transition-opacity"
                              onClick={(e) => {
                                e.stopPropagation()
                                setTxToDelete(t)
                                setTxDeleteError(null)
                              }}
                              title="Excluir"
                            >
                              <Trash className="h-4 w-4" />
                            </Button>
                          </div>
                        </TableCell>
                      </TableRow>
                    ))}
                    {filtered.length === 0 && (
                      <TableRow>
                        <TableCell colSpan={8} className="text-center py-8 text-muted-foreground">
                          Nenhum lançamento encontrado.
                        </TableCell>
                      </TableRow>
                    )}
                  </TableBody>
                </Table>
              </div>

              {/* Seção: Êxito a apurar (Honorários marcados apenas no processo sem lançamento financeiro) */}
              {/* Regra do Douglas: filtros de categorias de despesa NÃO ocultam os honorários de êxito a apurar */}
              {(activeTab === 'geral' || activeTab === 'honorarios') &&
                (() => {
                  const filteredUnbilledFees = unbilledSuccessFees.filter((fee) => {
                    if (filterClient !== 'Todos' && fee.clientId !== filterClient) return false
                    if (filterCase !== 'Todos' && fee.caseId !== filterCase) return false
                    if (searchQuery.trim()) {
                      const q = searchQuery.toLowerCase().trim()
                      const matchNumber = (fee.caseNumber || '').toLowerCase().includes(q)
                      const matchClientName = (fee.clientName || '').toLowerCase().includes(q)
                      if (!matchNumber && !matchClientName) return false
                    }
                    // Se o usuário filtrou por uma categoria específica e NÃO é "Todas":
                    // Honorários de Êxito só são filtrados se a categoria selecionada for explicitamente compatível com êxito/honorários.
                    // Se for categoria de despesa (ex: Impostos e Tributos, Aluguel, etc), NÃO filtra/oculta os êxitos.
                    if (filterCategory !== 'Todas') {
                      const catLower = filterCategory.toLowerCase()
                      const isFeeCategoryFilter =
                        catLower.includes('honor') ||
                        catLower.includes('êxito') ||
                        catLower.includes('exito') ||
                        catLower.includes('acordo') ||
                        catLower.includes('alvará') ||
                        catLower.includes('alvara')
                      if (isFeeCategoryFilter) {
                        return (
                          catLower.includes('êxito') ||
                          catLower.includes('exito') ||
                          filterCategory === 'Honorários de Êxito'
                        )
                      }
                      // Se o filtro selecionado foi uma categoria de despesa, os honorários permanecem visíveis
                    }
                    return true
                  })

                  if (filteredUnbilledFees.length === 0) return null

                  return (
                    <div className="mt-8 border-t pt-6">
                      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 mb-3">
                        <div>
                          <h3 className="text-base font-semibold text-slate-800 flex items-center gap-2">
                            <span>🎯</span> Honorários de Êxito a Apurar (
                            {filteredUnbilledFees.length})
                          </h3>
                          <p className="text-xs text-muted-foreground">
                            Honorários registrados diretamente no processo (&quot;Não gera
                            lançamento financeiro&quot;). Ao ganhar a ação, clique em &quot;Marcar
                            como Pago&quot; para apurar o valor e gerar o lançamento financeiro
                            automático.
                          </p>
                        </div>
                      </div>

                      <div className="rounded-md border bg-slate-50/50">
                        <Table>
                          <TableHeader>
                            <TableRow>
                              <TableHead>Processo — Cliente</TableHead>
                              <TableHead>Tipo</TableHead>
                              <TableHead>Percentual / Valor</TableHead>
                              <TableHead>Vencimento Padrão</TableHead>
                              <TableHead>Status</TableHead>
                              <TableHead className="w-[180px] text-right">Ação</TableHead>
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {filteredUnbilledFees.map((fee) => (
                              <TableRow
                                key={`unbilled-fee-${fee.caseId}`}
                                className="hover:bg-white"
                              >
                                <TableCell className="font-medium text-sm">
                                  <div>
                                    <span className="font-semibold text-primary">
                                      {fee.caseNumber}
                                    </span>
                                    <span className="text-muted-foreground">
                                      {' '}
                                      — {fee.clientName}
                                    </span>
                                  </div>
                                </TableCell>
                                <TableCell>
                                  <Badge
                                    variant="outline"
                                    className="bg-blue-50 text-blue-700 border-blue-200 text-xs"
                                  >
                                    {fee.feeType}
                                  </Badge>
                                </TableCell>
                                <TableCell className="font-semibold text-slate-700">
                                  {fee.feeValue > 0
                                    ? `R$ ${fee.feeValue.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}`
                                    : fee.feePercentage
                                      ? `${fee.feePercentage}% (A apurar)`
                                      : 'A apurar'}
                                </TableCell>
                                <TableCell className="text-sm text-muted-foreground">
                                  {formatSafeLocalDate(fee.dueDate)} (31/12)
                                </TableCell>
                                <TableCell>
                                  <Badge
                                    variant="outline"
                                    className="border-orange-200 text-orange-700 bg-orange-50 text-xs"
                                  >
                                    {fee.status}
                                  </Badge>
                                </TableCell>
                                <TableCell className="text-right">
                                  <Button
                                    size="sm"
                                    variant="outline"
                                    className="h-8 text-xs border-green-300 text-green-700 hover:bg-green-50"
                                    onClick={() => setConvertingSuccessCase(fee)}
                                  >
                                    Marcar como Pago →
                                  </Button>
                                </TableCell>
                              </TableRow>
                            ))}
                          </TableBody>
                        </Table>
                      </div>
                    </div>
                  )
                })()}
            </CardContent>
          </Card>
        )}

        {activeTab === 'conciliacao' && (
          <div className="mt-4">
            <ConciliationTab
              transactions={state.transactions || []}
              clients={state.clients || []}
              cases={state.cases || []}
              suppliers={state.suppliers || []}
              onUpdateTransaction={(id: string, changes: any) =>
                updateItem('transactions', id, changes)
              }
              onOpenAsaasImport={() => setAsaasExtractDialogOpen(true)}
              onOpenPdfImport={() => setPdfImportDialogOpen(true)}
            />
          </div>
        )}

        {/* SUB-ABA PARCELAMENTOS: Agrupamento detalhado por plano de parcelamento com repasse */}
        {activeTab === 'parcelamentos' && (
          <div className="mt-4 space-y-6">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
              <div>
                <h2 className="text-xl font-bold flex items-center gap-2">
                  <Calculator className="w-5 h-5 text-blue-600" />
                  Planos de Parcelamento com Repasse ao Cliente
                </h2>
                <p className="text-sm text-muted-foreground">
                  Visão consolidada por plano: cobrança integral (Asaas), receita de honorários
                  apurada e repasses efetuados.
                </p>
              </div>
              <Button
                onClick={() => setCreatingPaymentPlan(true)}
                className="bg-blue-600 hover:bg-blue-700 text-white"
              >
                <Plus className="mr-2 h-4 w-4" /> Novo Parcelamento
              </Button>
            </div>

            {!state.paymentPlans || state.paymentPlans.length === 0 ? (
              <Card className="p-8 text-center border-dashed">
                <Calculator className="w-12 h-12 text-muted-foreground/40 mx-auto mb-3" />
                <h3 className="text-base font-semibold">Nenhum parcelamento cadastrado ainda</h3>
                <p className="text-sm text-muted-foreground max-w-md mx-auto mt-1 mb-4">
                  Crie parcelamentos longos (ex: 18x de R$ 500) com divisão automática entre seus
                  honorários (30%) e o repasse ao cliente (70%).
                </p>
                <Button onClick={() => setCreatingPaymentPlan(true)}>
                  <Plus className="mr-2 h-4 w-4" /> Criar Primeiro Parcelamento
                </Button>
              </Card>
            ) : (
              state.paymentPlans.map((plan: any) => {
                const clientObj = state.clients.find((c: any) => c.id === plan.clientId)
                const caseObj = state.cases.find((cs: any) => cs.id === plan.processId)

                // Transações deste plano
                const planTxns = state.transactions.filter((t: any) => t.plan_id === plan.id)
                const feeTxns = planTxns.filter((t: any) => t.type === 'income')
                const repasseTxns = planTxns.filter((t: any) => t.type === 'expense')

                // Agregados
                const feeReceived = feeTxns
                  .filter((t: any) => t.status === 'Pago' || t.status === 'Realizado')
                  .reduce((acc: number, t: any) => acc + (t.amount || 0), 0)
                const feePending = feeTxns
                  .filter((t: any) => t.status !== 'Pago' && t.status !== 'Realizado')
                  .reduce((acc: number, t: any) => acc + (t.amount || 0), 0)

                const repasseDone = repasseTxns
                  .filter((t: any) => t.status === 'Pago' || t.status === 'Realizado')
                  .reduce((acc: number, t: any) => acc + (t.amount || 0), 0)
                const repassePending = repasseTxns
                  .filter((t: any) => t.status !== 'Pago' && t.status !== 'Realizado')
                  .reduce((acc: number, t: any) => acc + (t.amount || 0), 0)

                return (
                  <Card key={plan.id} className="overflow-hidden border-blue-200/60 shadow-sm">
                    {/* Header do Plano */}
                    <CardHeader className="bg-slate-50/70 dark:bg-slate-900/40 border-b pb-4">
                      <div className="flex flex-col md:flex-row md:items-center justify-between gap-3">
                        <div className="space-y-1">
                          <div className="flex items-center gap-2 flex-wrap">
                            <span className="font-bold text-lg text-slate-800 dark:text-slate-100">
                              {plan.title}
                            </span>
                            <Badge
                              variant="outline"
                              className="bg-blue-50 text-blue-700 border-blue-300 dark:bg-blue-900/50 dark:text-blue-200"
                            >
                              {plan.installmentsCount} parcelas {plan.periodicity || 'mensais'}
                            </Badge>
                            <Badge
                              variant="secondary"
                              className="bg-emerald-50 text-emerald-700 border-emerald-300"
                            >
                              Honorário: {plan.feePercentage}%
                            </Badge>
                            <Badge
                              variant="secondary"
                              className="bg-amber-50 text-amber-700 border-amber-300"
                            >
                              Repasse: {plan.clientPercentage}%
                            </Badge>
                          </div>
                          <div className="text-xs text-muted-foreground flex flex-wrap items-center gap-3">
                            <span>
                              Cliente:{' '}
                              <strong className="text-foreground">
                                {clientObj?.name || 'Não identificado'}
                              </strong>
                            </span>
                            {caseObj && (
                              <span>
                                Processo:{' '}
                                <strong className="text-foreground">{caseObj.number}</strong>
                              </span>
                            )}
                            <span>1ª Parcela: {formatSafeLocalDate(plan.firstDueDate)}</span>
                            <span>Conta: {plan.bankAccount || 'ASAAS'}</span>
                          </div>
                        </div>

                        <div className="flex items-center gap-2">
                          <Button
                            variant="destructive"
                            size="sm"
                            onClick={() => {
                              if (
                                confirm(
                                  `Deseja excluir o parcelamento "${plan.title}" e todos os seus ${planTxns.length} lançamentos vinculados?`,
                                )
                              ) {
                                deletePaymentPlan(plan.id)
                              }
                            }}
                          >
                            <Trash className="h-4 w-4 mr-1.5" /> Excluir Plano
                          </Button>
                        </div>
                      </div>

                      {/* Resumo de Indicadores por Plano */}
                      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 pt-3">
                        <div className="bg-white dark:bg-slate-950 p-2.5 rounded-lg border">
                          <div className="text-[11px] text-muted-foreground uppercase font-medium">
                            Contrato Total
                          </div>
                          <div className="text-base font-bold text-foreground">
                            R${' '}
                            {Number(plan.totalAmount || 0).toLocaleString('pt-BR', {
                              minimumFractionDigits: 2,
                            })}
                          </div>
                          <div className="text-[10px] text-muted-foreground">
                            {plan.installmentsCount}x de R${' '}
                            {Number(plan.installmentAmount || 0).toLocaleString('pt-BR', {
                              minimumFractionDigits: 2,
                            })}{' '}
                            (Cobrança cheia Asaas)
                          </div>
                        </div>

                        <div className="bg-white dark:bg-slate-950 p-2.5 rounded-lg border border-emerald-200 dark:border-emerald-800">
                          <div className="text-[11px] text-emerald-700 dark:text-emerald-400 uppercase font-medium">
                            Honorários Recebidos
                          </div>
                          <div className="text-base font-bold text-emerald-600 dark:text-emerald-400">
                            R$ {feeReceived.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
                          </div>
                          <div className="text-[10px] text-muted-foreground">
                            Pendente: R${' '}
                            {feePending.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}{' '}
                            (Total R${' '}
                            {Number(plan.totalFeeAmount || 0).toLocaleString('pt-BR', {
                              minimumFractionDigits: 2,
                            })}
                            )
                          </div>
                        </div>

                        <div className="bg-white dark:bg-slate-950 p-2.5 rounded-lg border border-amber-200 dark:border-amber-800">
                          <div className="text-[11px] text-amber-700 dark:text-amber-400 uppercase font-medium">
                            Repasses Efetuados
                          </div>
                          <div className="text-base font-bold text-amber-600 dark:text-amber-400">
                            R$ {repasseDone.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
                          </div>
                          <div className="text-[10px] text-muted-foreground">
                            Pendente: R${' '}
                            {repassePending.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}{' '}
                            (Total R${' '}
                            {Number(plan.totalClientAmount || 0).toLocaleString('pt-BR', {
                              minimumFractionDigits: 2,
                            })}
                            )
                          </div>
                        </div>

                        <div className="bg-white dark:bg-slate-950 p-2.5 rounded-lg border">
                          <div className="text-[11px] text-muted-foreground uppercase font-medium">
                            Status do Caixa
                          </div>
                          <div className="text-base font-bold text-slate-700 dark:text-slate-300">
                            R${' '}
                            {(feeReceived - repasseDone).toLocaleString('pt-BR', {
                              minimumFractionDigits: 2,
                            })}
                          </div>
                          <div className="text-[10px] text-muted-foreground">
                            Honorário recebido (-) Repasse pago
                          </div>
                        </div>
                      </div>
                    </CardHeader>

                    {/* Tabela de Pares de Lançamento por Parcela */}
                    <CardContent className="p-0">
                      <Table>
                        <TableHeader>
                          <TableRow className="bg-muted/40">
                            <TableHead className="w-[80px]">Parcela</TableHead>
                            <TableHead>Vencimento</TableHead>
                            <TableHead>Cobrança Integral</TableHead>
                            <TableHead>Honorário ({plan.feePercentage}%)</TableHead>
                            <TableHead>Status Honorário</TableHead>
                            <TableHead>Repasse ({plan.clientPercentage}%)</TableHead>
                            <TableHead>Status Repasse</TableHead>
                            <TableHead className="w-[180px] text-right">Ação</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {Array.from({ length: plan.installmentsCount }).map((_, idx) => {
                            const instNum = idx + 1
                            const feeTx = feeTxns.find((t: any) => t.installment_number === instNum)
                            const repasseTx = repasseTxns.find(
                              (t: any) => t.installment_number === instNum,
                            )
                            const dueDate = feeTx?.date || repasseTx?.date || '-'

                            const isFeePaid =
                              feeTx?.status === 'Pago' || feeTx?.status === 'Realizado'
                            const isRepassePaid =
                              repasseTx?.status === 'Pago' || repasseTx?.status === 'Realizado'

                            return (
                              <TableRow key={`plan-${plan.id}-inst-${instNum}`}>
                                <TableCell className="font-semibold">
                                  {instNum}/{plan.installmentsCount}
                                </TableCell>
                                <TableCell>{formatSafeLocalDate(dueDate)}</TableCell>
                                <TableCell className="font-medium text-slate-800 dark:text-slate-200">
                                  R${' '}
                                  {Number(plan.installmentAmount || 0).toLocaleString('pt-BR', {
                                    minimumFractionDigits: 2,
                                  })}
                                </TableCell>

                                {/* Honorário */}
                                <TableCell className="font-semibold text-emerald-600 dark:text-emerald-400">
                                  R${' '}
                                  {Number(
                                    feeTx?.amount || plan.feeInstallmentAmount || 0,
                                  ).toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
                                </TableCell>
                                <TableCell>
                                  <Badge
                                    variant="outline"
                                    className={
                                      isFeePaid
                                        ? 'border-emerald-200 text-emerald-700 bg-emerald-50'
                                        : 'border-orange-200 text-orange-700 bg-orange-50'
                                    }
                                  >
                                    {feeTx?.status || 'Previsto'}
                                  </Badge>
                                </TableCell>

                                {/* Repasse */}
                                <TableCell className="font-semibold text-amber-600 dark:text-amber-400">
                                  R${' '}
                                  {Number(
                                    repasseTx?.amount || plan.clientInstallmentAmount || 0,
                                  ).toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
                                </TableCell>
                                <TableCell>
                                  <Badge
                                    variant="outline"
                                    className={
                                      isRepassePaid
                                        ? 'border-emerald-200 text-emerald-700 bg-emerald-50'
                                        : 'border-amber-200 text-amber-700 bg-amber-50'
                                    }
                                  >
                                    {repasseTx?.status || 'Previsto'}
                                  </Badge>
                                </TableCell>

                                {/* Ações */}
                                <TableCell className="text-right">
                                  <div className="flex items-center justify-end gap-1.5">
                                    {!isFeePaid && feeTx && (
                                      <Button
                                        size="sm"
                                        variant="outline"
                                        className="h-7 text-xs border-green-300 text-green-700 hover:bg-green-50"
                                        onClick={() => {
                                          updateItem('transactions', feeTx.id, {
                                            status: 'Pago',
                                            date: new Date().toISOString().split('T')[0],
                                          })
                                          toast({
                                            title: `Honorário da parcela ${instNum} recebido!`,
                                          })
                                        }}
                                        title="Marcar honorário como Pago"
                                      >
                                        Pago
                                      </Button>
                                    )}

                                    {!isRepassePaid && repasseTx && (
                                      <Button
                                        size="sm"
                                        variant="outline"
                                        className="h-7 text-xs bg-amber-50 text-amber-800 border-amber-300 hover:bg-amber-100 dark:bg-amber-950/40 dark:text-amber-300"
                                        onClick={() => markRepasseAsDone(repasseTx.id)}
                                        title="Registrar que o repasse foi passado ao cliente"
                                      >
                                        Repasse efetuado
                                      </Button>
                                    )}

                                    {isFeePaid && isRepassePaid && (
                                      <span className="text-xs text-emerald-600 font-medium flex items-center justify-end gap-1">
                                        <CheckCircle2 className="w-3.5 h-3.5" /> Concluído
                                      </span>
                                    )}
                                  </div>
                                </TableCell>
                              </TableRow>
                            )
                          })}
                        </TableBody>
                      </Table>
                    </CardContent>
                  </Card>
                )
              })
            )}
          </div>
        )}

        {/* Dialogs de importação de extrato */}
        <BankPdfImportDialog
          open={pdfImportDialogOpen}
          onOpenChange={setPdfImportDialogOpen}
          bankAccounts={bankOptions}
          onImportCompleted={handleSicoobImportCompleted}
          onSuccess={async () => {
            if (reloadTransactions) await reloadTransactions()
          }}
        />

        {activeTab === 'fornecedores' && (
          <Card className="mt-4">
            <CardHeader className="pb-4 flex flex-row items-center justify-between">
              <div className="flex items-center gap-2 text-lg font-semibold">
                Fornecedores Cadastrados
              </div>
              <Button size="sm" onClick={() => setCreatingSupplier(true)}>
                <Plus className="mr-2 h-4 w-4" /> Novo Fornecedor
              </Button>
            </CardHeader>
            <CardContent>
              <div className="rounded-md border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Nome</TableHead>
                      <TableHead>Grupo</TableHead>
                      <TableHead>Documento</TableHead>
                      <TableHead>Email</TableHead>
                      <TableHead>Telefone</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead className="w-[100px]"></TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {sortedSuppliers.map((s: any) => (
                      <TableRow key={s.id}>
                        <TableCell className="font-medium">{s.name}</TableCell>
                        <TableCell>
                          {s.group_name ? (
                            <Badge
                              variant="secondary"
                              className="bg-blue-50 text-blue-700 border border-blue-200 font-normal text-xs"
                            >
                              {s.group_name}
                            </Badge>
                          ) : (
                            <span className="text-muted-foreground text-xs">—</span>
                          )}
                        </TableCell>
                        <TableCell>{s.document || '-'}</TableCell>
                        <TableCell>{s.email || '-'}</TableCell>
                        <TableCell>{s.phone || '-'}</TableCell>
                        <TableCell>
                          <Badge
                            variant="outline"
                            className={
                              s.status === 'Ativo'
                                ? 'bg-green-50 text-green-700 border-green-200'
                                : 'bg-slate-50 text-slate-700 border-slate-200'
                            }
                          >
                            {s.status}
                          </Badge>
                        </TableCell>
                        <TableCell>
                          <div className="flex items-center justify-end gap-2">
                            <Button
                              variant="ghost"
                              size="icon"
                              className="h-8 w-8 text-slate-500 hover:text-slate-700"
                              onClick={() => setEditingSupplier(s)}
                            >
                              <Edit className="h-4 w-4" />
                            </Button>
                            <Button
                              variant="ghost"
                              size="icon"
                              className="h-8 w-8 text-red-500 hover:text-red-700 hover:bg-red-50"
                              onClick={() => {
                                if (confirm('Deseja excluir este fornecedor?')) {
                                  deleteItem('suppliers', s.id)
                                }
                              }}
                            >
                              <Trash className="h-4 w-4" />
                            </Button>
                          </div>
                        </TableCell>
                      </TableRow>
                    ))}
                    {(!state.suppliers || state.suppliers.length === 0) && (
                      <TableRow>
                        <TableCell colSpan={7} className="text-center py-8 text-muted-foreground">
                          Nenhum fornecedor encontrado.
                        </TableCell>
                      </TableRow>
                    )}
                  </TableBody>
                </Table>
              </div>
            </CardContent>
          </Card>
        )}
      </Tabs>

      {/* Modal de criação de parcelamento com repasse */}
      <PaymentPlanDialog open={creatingPaymentPlan} onOpenChange={setCreatingPaymentPlan} />
    </div>
  )
}
