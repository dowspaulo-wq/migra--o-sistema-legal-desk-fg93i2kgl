import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { Toaster } from '@/components/ui/toaster'
import { Toaster as Sonner } from '@/components/ui/sonner'
import { TooltipProvider } from '@/components/ui/tooltip'
import Layout from './components/Layout'
import Index from './pages/Index'
import Clients from './pages/Clients'
import ClientDetail from './pages/ClientDetail'
import Cases from './pages/Cases'
import CaseDetail from './pages/CaseDetail'
import Agenda from './pages/Agenda'
import Tasks from './pages/Tasks'
import Finance from './pages/Finance'
import Petitions from './pages/Petitions'
import Logs from './pages/Logs'
import Settings from './pages/Settings'
import NotFound from './pages/NotFound'
import Login from './pages/Login'
import { LegalStoreProvider } from './stores/useLegalStore'
import { AuthProvider } from './hooks/use-auth'

const App = () => (
  <AuthProvider>
    <LegalStoreProvider>
      <BrowserRouter future={{ v7_startTransition: false, v7_relativeSplatPath: false }}>
        <TooltipProvider>
          <Toaster />
          <Sonner />
          <Routes>
            <Route path="/login" element={<Login />} />
            <Route element={<Layout />}>
              <Route path="/" element={<Index />} />
              <Route path="/clientes" element={<Clients />} />
              <Route path="/clientes/:id" element={<ClientDetail />} />
              <Route path="/processos" element={<Cases />} />
              <Route path="/processos/:id" element={<CaseDetail />} />
              <Route path="/agenda" element={<Agenda />} />
              <Route path="/tarefas" element={<Tasks />} />
              <Route path="/financeiro" element={<Finance />} />
              <Route path="/peticoes" element={<Petitions />} />
              <Route path="/logs" element={<Logs />} />
              <Route path="/configuracoes" element={<Settings />} />
            </Route>
            <Route path="*" element={<NotFound />} />
          </Routes>
        </TooltipProvider>
      </BrowserRouter>
    </LegalStoreProvider>
  </AuthProvider>
)

export default App
