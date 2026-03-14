export interface User {
  id: string
  name: string
  role: 'Admin' | 'User'
  canViewFinance: boolean
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
}
export interface Transaction {
  id: string
  description: string
  amount: number
  type: 'income' | 'expense'
  category: string
  status: 'Pendente' | 'Pago' | 'Atrasado'
  date: string
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
  settings: { showFinanceDashboard: boolean; themeColor: string; logoUrl: string }
}

export const initialData: LegalState = {
  currentUser: { id: 'u1', name: 'Advogado Sênior', role: 'Admin', canViewFinance: true },
  users: [
    { id: 'u1', name: 'Advogado Sênior', role: 'Admin', canViewFinance: true },
    { id: 'u2', name: 'Estagiário', role: 'User', canViewFinance: false },
  ],
  clients: [
    {
      id: 'c1',
      name: 'Empresa Alpha Ltda',
      document: '12.345.678/0001-90',
      type: 'PJ',
      email: 'contato@alpha.com',
      phone: '11987654321',
      address: 'Rua A, 100',
      birthday: '',
      responsibleId: 'u1',
      status: 'Ativo',
      isSpecial: true,
    },
    {
      id: 'c2',
      name: 'João Carlos',
      document: '123.456.789-00',
      type: 'PF',
      email: 'joao@email.com',
      phone: '21999998888',
      address: 'Rua B, 20',
      birthday: '1980-05-10',
      responsibleId: 'u2',
      status: 'Ativo',
      isSpecial: false,
    },
  ],
  cases: [
    {
      id: 'p1',
      clientId: 'c1',
      number: '0001234-56.2023.8.26.0100',
      position: 'Autor',
      adverseParty: 'Beta S/A',
      type: 'Cível',
      status: 'Em andamento',
      court: '1ª Vara',
      comarca: 'São Paulo',
      state: 'SP',
      system: 'PJE',
      value: 50000,
      startDate: '2023-01-10',
      responsibleId: 'u1',
      updatedAt: '2023-10-15',
    },
  ],
  tasks: [
    {
      id: 't1',
      title: 'Protocolar Petição',
      description: 'Urgente',
      dueDate: new Date().toISOString().split('T')[0],
      status: 'Aguarda protocolo',
      priority: 'Urgente',
      responsibleId: 'u1',
      relatedProcessId: 'p1',
    },
    {
      id: 't2',
      title: 'Revisar doc',
      description: 'Revisar',
      dueDate: '2024-12-01',
      status: 'Pendente',
      priority: 'Média',
      responsibleId: 'u2',
    },
  ],
  appointments: [
    {
      id: 'a1',
      title: 'Audiência Inicial',
      date: new Date().toISOString(),
      type: 'Audiência',
      responsibleId: 'u1',
    },
  ],
  transactions: [
    {
      id: 'tr1',
      description: 'Honorários Iniciais',
      amount: 5000,
      type: 'income',
      category: 'Honorários',
      status: 'Pago',
      date: '2023-10-01',
    },
  ],
  logs: [
    {
      id: 'l1',
      action: 'Login',
      entity: 'Auth',
      user: 'Advogado Sênior',
      date: new Date().toISOString(),
      details: 'Acesso ao sistema',
    },
  ],
  petitions: [
    {
      id: 'pe1',
      title: 'Petição Inicial Padrão',
      content: 'Excelentíssimo Senhor Juiz...',
      category: 'Cível',
    },
  ],
  settings: { showFinanceDashboard: true, themeColor: 'blue', logoUrl: '' },
}
