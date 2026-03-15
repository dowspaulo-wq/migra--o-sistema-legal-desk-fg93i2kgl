import { Outlet, Navigate } from 'react-router-dom'
import AppSidebar from './AppSidebar'
import Header from './Header'
import { SidebarProvider } from '@/components/ui/sidebar'
import { useAuth } from '@/hooks/use-auth'
import useLegalStore from '@/stores/useLegalStore'
import { Scale } from 'lucide-react'

export default function Layout() {
  const { user, loading } = useAuth()
  const { state } = useLegalStore()

  if (loading || (user && !state.currentUser.id)) {
    return (
      <div className="flex flex-col h-screen items-center justify-center bg-slate-50 gap-4">
        <Scale className="h-12 w-12 text-primary animate-pulse" />
        <p className="text-slate-500 font-medium">Carregando dados do sistema...</p>
      </div>
    )
  }

  if (!user) return <Navigate to="/login" replace />

  return (
    <SidebarProvider>
      <div className="flex min-h-screen w-full bg-background overflow-hidden">
        <AppSidebar />
        <div className="flex flex-col flex-1 w-full overflow-hidden">
          <Header />
          <main className="flex-1 overflow-y-auto p-4 md:p-6 lg:p-8 animate-fade-in-up">
            <Outlet />
          </main>
        </div>
      </div>
    </SidebarProvider>
  )
}
