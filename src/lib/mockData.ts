export interface User {
  id: string
  name: string
  role: 'Admin' | 'User'
  canViewFinance: boolean
  color: string
  avatar_url?: string
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
  description: string
  internalNotes: string
  alerts: string
  parentId?: string | null
  classification?: string
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
}

export const initialData: LegalState = {
  currentUser: { id: '', name: '', role: 'User', canViewFinance: false, color: '#3b82f6' },
  users: [],
  clients: [],
  cases: [],
  tasks: [],
  appointments: [],
  transactions: [],
  logs: [],
  petitions: [],
  whatsappMessages: [],
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
  },
}
