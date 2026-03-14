export interface Client {
  id: string
  name: string
  document: string
  email: string
  phone: string
  status: 'Ativo' | 'Inativo'
}

export interface Case {
  id: string
  clientId: string
  number: string
  title: string
  status: 'Análise' | 'Petição Inicial' | 'Em Andamento' | 'Sentença'
  updatedAt: string
}

export interface Task {
  id: string
  title: string
  dueDate: string
  completed: boolean
}

export interface Activity {
  id: string
  text: string
  date: string
  type: 'process' | 'client' | 'task'
}

export interface RevenueData {
  month: string
  value: number
}

export interface LegalState {
  clients: Client[]
  cases: Case[]
  tasks: Task[]
  activities: Activity[]
  revenue: RevenueData[]
}

export const initialData: LegalState = {
  clients: [
    {
      id: '1',
      name: 'Empresa Alpha Ltda',
      document: '12.345.678/0001-90',
      email: 'contato@alpha.com',
      phone: '(11) 98765-4321',
      status: 'Ativo',
    },
    {
      id: '2',
      name: 'João Carlos Santos',
      document: '123.456.789-00',
      email: 'joao.carlos@email.com',
      phone: '(21) 99999-8888',
      status: 'Ativo',
    },
    {
      id: '3',
      name: 'Maria Fernandes',
      document: '987.654.321-11',
      email: 'maria.f@email.com',
      phone: '(31) 97777-6666',
      status: 'Inativo',
    },
  ],
  cases: [
    {
      id: '101',
      clientId: '1',
      number: '0001234-56.2023.8.26.0100',
      title: 'Ação de Cobrança',
      status: 'Em Andamento',
      updatedAt: '2023-10-15',
    },
    {
      id: '102',
      clientId: '2',
      number: '0009876-54.2023.8.26.0200',
      title: 'Revisão Contratual',
      status: 'Análise',
      updatedAt: '2023-10-20',
    },
    {
      id: '103',
      clientId: '1',
      number: '0005555-33.2022.8.26.0100',
      title: 'Defesa Trabalhista',
      status: 'Sentença',
      updatedAt: '2023-09-10',
    },
    {
      id: '104',
      clientId: '3',
      number: '0004444-22.2023.8.26.0300',
      title: 'Indenização por Danos Morais',
      status: 'Petição Inicial',
      updatedAt: '2023-10-25',
    },
  ],
  tasks: [
    {
      id: 't1',
      title: 'Revisar petição inicial do João Carlos',
      dueDate: 'Hoje',
      completed: false,
    },
    { id: 't2', title: 'Reunião com a Empresa Alpha', dueDate: 'Amanhã', completed: false },
    { id: 't3', title: 'Analisar documentos da Maria', dueDate: 'Quinta-feira', completed: true },
    { id: 't4', title: 'Protocolar defesa trabalhista', dueDate: 'Hoje', completed: false },
  ],
  activities: [
    { id: 'a1', text: 'Publicação no processo 0001234-56', date: 'Há 2 horas', type: 'process' },
    {
      id: 'a2',
      text: 'Novo cliente cadastrado: João Carlos Santos',
      date: 'Há 5 horas',
      type: 'client',
    },
    { id: 'a3', text: 'Tarefa concluída: Analisar documentos', date: 'Ontem', type: 'task' },
    {
      id: 'a4',
      text: 'Audiência agendada para processo 0005555-33',
      date: 'Ontem',
      type: 'process',
    },
  ],
  revenue: [
    { month: 'Jan', value: 12000 },
    { month: 'Fev', value: 15000 },
    { month: 'Mar', value: 14000 },
    { month: 'Abr', value: 18000 },
    { month: 'Mai', value: 22000 },
    { month: 'Jun', value: 25000 },
  ],
}
