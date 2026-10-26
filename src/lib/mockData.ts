export interface User {
  id: string
  name: string
  email?: string
  role: 'Admin' | 'User'
  canViewFinance: boolean
  color: string
  avatar_url?: string
  is_active?: boolean
}
export interface Client {
  id: string
  name: string
  document: string
  type: 'PF' | 'PJ'
  email: string
  phone: string
  address: string
  birthday: string
  responsibleId: string
  status: 'Ativo' | 'Baixado'
  isSpecial: boolean
  observacoes: string
  captacao?: string
  classification?: string
  no_phone?: boolean
  no_email?: boolean
  phone_na?: boolean
  email_na?: boolean
  hide_birthday?: boolean
  cep?: string
  street?: string
  number?: string
  complement?: string
  neighborhood?: string
  city?: string
  state?: string
  asaas_id?: string | null
  created_at?: string
  created_by?: string | null
}
export interface CaseDocument {
  name: string
  url: string
  created_at: string
  category?: string
}

export interface Case {
  id: string
  clientId: string
  number: string
  position: string
  adverseParty: string
  type: string
  status: string
  court: string
  comarca: string
  state: string
  system: string
  value: number
  startDate: string
  responsibleId: string
  updatedAt: string
  isSpecial: boolean
  isProblematic?: boolean
  isRestricted?: boolean
  noFees?: boolean
  description: string
  internalNotes: string
  alerts: string
  parentId?: string | null
  classification?: string
  created_at?: string
  created_by?: string | null
  documents?: CaseDocument[]
}
export interface Task {
  id: string
  title: string
  description: string
  dueDate: string
  status: string
  priority: string
  responsibleId: string
  relatedProcessId: string | null
  type: string
  clientId: string | null
  internalNotes: string
  created_at?: string
  created_by?: string | null
  completed_by?: string | null
}
export interface Appointment {
  id: string
  title: string
  date: string
  type: string
  priority: string
  time: string
  description: string
  responsibleId: string
  clientId: string | null
  processId: string | null
  modality?: string
  status: string
}
export interface PaymentPlan {
  id: string
  clientId: string
  processId?: string | null
  title: string
  installmentAmount: number
  installmentsCount: number
  periodicity: 'mensal' | 'semanal' | 'anual' | string
  firstDueDate: string
  feePercentage: number
  clientPercentage: number
  feeInstallmentAmount: number
  clientInstallmentAmount: number
  totalAmount: number
  totalFeeAmount: number
  totalClientAmount: number
  bankAccount?: string
  paymentMethod?: string
  status: string
  notes?: string | null
  created_at?: string
  updated_at?: string
}

export interface Transaction {
  id: string
  description: string
  amount: number
  type: 'income' | 'expense'
  category: string
  status: 'Pendente' | 'Pago' | 'Atrasado'
  date: string
  clientId?: string
  processId?: string
  asaas_id?: string
  plan_id?: string | null
  pair_id?: string | null
  installment_number?: number | null
  installment_total?: number | null
  bankAccount?: string
  payment_method?: string
  percentage?: number
  sendToFinance?: boolean
  supplierId?: string
  supplier_group?: string | null
  recurring_id?: string
  pendente_vinculo?: boolean
  origem?: string
}
export interface Log {
  id: string
  action: string
  entity: string
  user: string
  date: string
  details: string
}
export interface Petition {
  id: string
  title: string
  content: string
  category: string
}
export interface CaseType {
  label: string
  color: string
}
export interface CaseStatusType {
  label: string
  color: string
}
export type OnboardingType = 'cliente' | 'processo'

export interface OnboardingStep {
  id: string
  title: string
  order: number
  responsibleId?: string | null
  type?: OnboardingType
}

export type AutomationTriggerEvent =
  | 'client_created'
  | 'case_created'
  | 'case_status_changed'
  | 'task_completed'
  | 'document_signed'

export type AutomationDueType = 'calendar_days' | 'business_days'

export interface AutomationRule {
  id: string
  title: string // Título da regra descritivo
  taskTitle: string // Título da tarefa que será gerada
  taskDescription?: string // Descrição opcional da tarefa
  triggerEvent: AutomationTriggerEvent // Evento gerador
  caseStatusTrigger?: string // Caso o evento seja 'case_status_changed', qual status dispara
  caseTypeTrigger?: string // Filtro opcional por tipo de processo (ex: Previdenciário)
  taskTypeTrigger?: string // Caso o evento seja 'task_completed', qual tipo de tarefa dispara
  dueDays: number // Prazo em dias (ex: 3, 5, 15)
  dueType?: AutomationDueType // 'calendar_days' (padrão) ou 'business_days'
  responsibleId?: string | null // Colaborador responsável (null = padrão / resp. do alvo)
  taskPriority?: 'Baixa' | 'Média' | 'Alta' | 'Urgente' // Padrão Média
  taskType?: string // Tipo da tarefa gerada (padrão 'Automação')
  active: boolean // Toggle ativo/inativo
  createdAt?: string
  updatedAt?: string
}

export const DEFAULT_CLIENT_ONBOARDING_STEPS: OnboardingStep[] = [
  { id: 'step-client-1', title: 'Cadastrar cliente', order: 1, type: 'cliente' },
  { id: 'step-client-2', title: 'Cadastrar processo(s)', order: 2, type: 'cliente' },
  { id: 'step-client-3', title: 'Coletar documentos', order: 3, type: 'cliente' },
]

export const DEFAULT_CASE_ONBOARDING_STEPS: OnboardingStep[] = [
  { id: 'step-case-1', title: 'Redigir procuração', order: 1, type: 'processo' },
  {
    id: 'step-case-2',
    title: 'Redigir declaração de hipossuficiência',
    order: 2,
    type: 'processo',
  },
  { id: 'step-case-3', title: 'Redigir contrato', order: 3, type: 'processo' },
  { id: 'step-case-4', title: 'Lançar honorários', order: 4, type: 'processo' },
  { id: 'step-case-5', title: 'Tratar documentos (qualidade/PDFs)', order: 5, type: 'processo' },
  { id: 'step-case-6', title: 'Monitorar assinaturas', order: 6, type: 'processo' },
]

// Compatibilidade retroativa
export const DEFAULT_ONBOARDING_STEPS: OnboardingStep[] = DEFAULT_CLIENT_ONBOARDING_STEPS

export interface Settings {
  id: string
  showFinanceDashboard: boolean
  themeColor: string
  logoUrl: string
  caseStatuses: (string | CaseStatusType)[]
  caseTypes: (string | CaseType)[]
  appointmentTypes: string[]
  taskStatuses: string[]
  taskTypes: string[]
  captacaoOptions: string[]
  transactionCategories?: string[]
  bankAccounts?: any[]
  expenseTypes?: string[]
  clientPositions?: string[]
  subprocessTypes?: string[]
  asaasApiKey?: string | null
  asaasApiUrl?: string | null
  googleCalendarTokens?: any | null
  googleClientId?: string | null
  googleClientSecret?: string | null
  googleServiceAccount?: string | null
  lastAsaasSyncAt?: string | null
  lastSicoobImportAt?: string | null
  onboardingChecklist?: OnboardingStep[]
  caseOnboardingChecklist?: OnboardingStep[]
  automationRules?: AutomationRule[]
}
export interface WhatsAppMessage {
  id: string
  phone: string
  contact_name: string
  message: string
  direction: 'inbound' | 'outbound'
  created_at: string
}

export interface LegalState {
  currentUser: User
  users: User[]
  clients: Client[]
  cases: Case[]
  tasks: Task[]
  appointments: Appointment[]
  transactions: Transaction[]
  logs: Log[]
  petitions: Petition[]
  settings: Settings
  whatsappMessages: WhatsAppMessage[]
  paymentPlans?: PaymentPlan[]
}

export const initialData: LegalState = {
  currentUser: {
    id: '',
    name: '',
    role: 'User',
    canViewFinance: false,
    color: '#3b82f6',
    is_active: true,
  },
  users: [],
  clients: [],
  cases: [],
  tasks: [],
  appointments: [],
  transactions: [],
  logs: [],
  petitions: [],
  whatsappMessages: [],
  paymentPlans: [],
  settings: {
    id: '',
    showFinanceDashboard: true,
    themeColor: 'blue',
    logoUrl: '',
    caseStatuses: [
      { label: 'Em andamento', color: '#22c55e' },
      { label: 'Pendente', color: '#f97316' },
      { label: 'Suspenso', color: '#eab308' },
      { label: 'Aguardando documentos', color: '#ef4444' },
      { label: 'Concluído', color: '#f1f5f9' },
    ],
    caseTypes: [
      { label: 'Previdenciário', color: '#eab308' },
      { label: 'Tutelas e/ou Curatelas', color: '#92400e' },
      { label: 'Alimentos', color: '#ec4899' },
      { label: 'Possessórios e usucapião', color: '#ef4444' },
      { label: 'Incidentes', color: '#f97316' },
      { label: 'Busca e apreensão', color: '#14b8a6' },
      { label: 'Anulatória', color: '#14b8a6' },
      { label: 'Execução ou embargos', color: '#8b5cf6' },
      { label: 'Reclamatória trabalhista', color: '#eab308' },
      { label: 'Outros', color: '#64748b' },
      { label: 'Divórcio e União Estável', color: '#ec4899' },
      { label: 'Indenizatória', color: '#22c55e' },
      { label: 'Inventário', color: '#3b82f6' },
    ],
    appointmentTypes: ['Reunião', 'Aud.conciliação', 'Diligência', 'Feriado', 'Outro', 'AIJ'],
    taskStatuses: ['pendente', 'em andamento', 'Concluída'],
    taskTypes: ['Cartórios', 'Petições', 'Recorrer', 'Redigir inicial', 'interna e adm'],
    captacaoOptions: ['Douglas', 'Eduardo', 'Luisito', 'MB', 'Zeno'],
    asaasApiKey: null,
    asaasApiUrl: 'https://api.asaas.com/v3',
    googleServiceAccount: null,
    lastAsaasSyncAt: null,
    lastSicoobImportAt: null,
    onboardingChecklist: DEFAULT_CLIENT_ONBOARDING_STEPS,
    caseOnboardingChecklist: DEFAULT_CASE_ONBOARDING_STEPS,
    automationRules: [],
  },
}
