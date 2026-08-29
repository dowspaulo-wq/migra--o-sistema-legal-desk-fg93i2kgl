import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
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
import FinancialDashboard from './pages/FinancialDashboard'
import Petitions from './pages/Petitions'
import DocumentTemplates from './pages/DocumentTemplates'
import Logs from './pages/Logs'
import Acessos from './pages/Acessos'
import Backups from './pages/Backups'
import SettingsPage from './pages/Settings'
import { SystemManagement } from './components/SystemManagement'
import NotFound from './pages/NotFound'
import Login from './pages/Login'
import GoogleCallback from './pages/GoogleCallback'
import UpdatePassword from './pages/UpdatePassword'
import { LegalStoreProvider } from './stores/useLegalStore'
import { AuthProvider } from './hooks/use-auth'
import { RequireAdmin } from './components/RequireAdmin'
import { SystemIconOverlay } from './components/SystemIconOverlay'

const SettingsWrapper = () => (
  <div className="flex flex-col h-full overflow-y-auto">
    <SettingsPage />
    <div className="px-4 md:px-8 pb-12 w-full max-w-7xl mx-auto mt-6">
      <SystemManagement />
    </div>
  </div>
)

const App = () => (
  <AuthProvider>
    <LegalStoreProvider>
      <BrowserRouter future={{ v7_startTransition: false, v7_relativeSplatPath: false }}>
        <TooltipProvider>
          <SystemIconOverlay />
          <Toaster />
          <Sonner />
          <Routes>
            <Route path="/login" element={<Login />} />
            <Route path="/google-callback" element={<GoogleCallback />} />
            <Route path="/update-password" element={<UpdatePassword />} />
            <Route element={<Layout />}>
              <Route path="/" element={<Index />} />
              <Route path="/clientes" element={<Clients />} />
              <Route path="/clientes/:id" element={<ClientDetail />} />
              <Route path="/processos" element={<Cases />} />
              <Route path="/processos/:id" element={<CaseDetail />} />
              <Route
                path="/agenda"
                element={
                  <RequireAdmin>
                    <Agenda />
                  </RequireAdmin>
                }
              />
              <Route path="/tarefas" element={<Tasks />} />
              <Route path="/financeiro" element={<Finance />} />
              <Route path="/dashboard-financeiro" element={<FinancialDashboard />} />
              <Route path="/peticoes" element={<Petitions />} />
              <Route path="/modelos" element={<DocumentTemplates />} />
              <Route
                path="/logs"
                element={
                  <RequireAdmin>
                    <Logs />
                  </RequireAdmin>
                }
              />
              <Route
                path="/acessos"
                element={
                  <RequireAdmin>
                    <Acessos />
                  </RequireAdmin>
                }
              />
              <Route
                path="/backups"
                element={
                  <RequireAdmin>
                    <Backups />
                  </RequireAdmin>
                }
              />
              <Route path="/configuracoes" element={<SettingsWrapper />} />

              {/* Aliases to satisfy English path assumptions and potential external links */}
              <Route path="/cases" element={<Navigate to="/processos" replace />} />
              <Route path="/cases/:id" element={<CaseDetail />} />
              <Route path="/settings" element={<Navigate to="/configuracoes" replace />} />
            </Route>
            <Route path="*" element={<NotFound />} />
          </Routes>
        </TooltipProvider>
      </BrowserRouter>
    </LegalStoreProvider>
  </AuthProvider>
)

export default App
