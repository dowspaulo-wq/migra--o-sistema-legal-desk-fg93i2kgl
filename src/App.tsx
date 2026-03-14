import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { Toaster } from '@/components/ui/toaster'
import { Toaster as Sonner } from '@/components/ui/sonner'
import { TooltipProvider } from '@/components/ui/tooltip'
import Layout from './components/Layout'
import Index from './pages/Index'
import Clients from './pages/Clients'
import ClientDetail from './pages/ClientDetail'
import Cases from './pages/Cases'
import Agenda from './pages/Agenda'
import Tasks from './pages/Tasks'
import Settings from './pages/Settings'
import NotFound from './pages/NotFound'
import { LegalStoreProvider } from './stores/useLegalStore'

const App = () => (
  <LegalStoreProvider>
    <BrowserRouter future={{ v7_startTransition: false, v7_relativeSplatPath: false }}>
      <TooltipProvider>
        <Toaster />
        <Sonner />
        <Routes>
          <Route element={<Layout />}>
            <Route path="/" element={<Index />} />
            <Route path="/clientes" element={<Clients />} />
            <Route path="/clientes/:id" element={<ClientDetail />} />
            <Route path="/processos" element={<Cases />} />
            <Route path="/agenda" element={<Agenda />} />
            <Route path="/tarefas" element={<Tasks />} />
            <Route path="/configuracoes" element={<Settings />} />
          </Route>
          <Route path="*" element={<NotFound />} />
        </Routes>
      </TooltipProvider>
    </BrowserRouter>
  </LegalStoreProvider>
)

export default App
