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
  description: string
  internalNotes: string
  alerts: string
}
export interface Task {
  id: string
  title: string
  description: string
  dueDate: string
  status: string
  priority: string
  responsibleId: string
  relatedProcessId: string
  type: string
  clientId: string
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
  clientId: string
  processId: string
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
export interface Settings {
  id: string
  showFinanceDashboard: boolean
  themeColor: string
  logoUrl: string
  caseStatuses: string[]
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
    caseStatuses: ['Em andamento', 'Pendente', 'Concluído'],
    caseTypes: [
      { label: 'Cível', color: '#3b82f6' },
      { label: 'Trabalhista', color: '#ef4444' },
      { label: 'Família', color: '#8b5cf6' },
    ],
    appointmentTypes: ['Reunião', 'Feriado', 'Outro'],
    taskStatuses: ['pendente', 'em andamento', 'Concluída'],
    taskTypes: ['Cartórios', 'Petições', 'Recorrer', 'Redigir inicial', 'interna e adm'],
    captacaoOptions: ['Douglas', 'Eduardo', 'Luisito', 'MB', 'Zeno'],
  },
}
