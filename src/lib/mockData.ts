export interface User {
  id: string
  name: string
  role: 'Admin' | 'User'
  canViewFinance: boolean
  color: string
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
}
export interface Task {
  id: string
  title: string
  description: string
  dueDate: string
  status: string
  priority: string
  responsibleId: string
  relatedProcessId?: string
}
export interface Appointment {
  id: string
  title: string
  date: string
  type: string
  responsibleId: string
  clientId?: string
  processId?: string
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
export interface Settings {
  id: string
  showFinanceDashboard: boolean
  themeColor: string
  logoUrl: string
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
  currentUser: { id: '', name: '', role: 'User', canViewFinance: false, color: '#000' },
  users: [],
  clients: [],
  cases: [],
  tasks: [],
  appointments: [],
  transactions: [],
  logs: [],
  petitions: [],
  whatsappMessages: [],
  settings: { id: '', showFinanceDashboard: true, themeColor: 'blue', logoUrl: '' },
}
