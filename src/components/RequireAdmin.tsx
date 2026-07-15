import { Navigate } from 'react-router-dom'
import useLegalStore from '@/stores/useLegalStore'

const ADMIN_ROLES = ['Admin', 'ADM', 'admin']

export function RequireAdmin({ children }: { children: React.ReactNode }) {
  const { state } = useLegalStore()

  if (!ADMIN_ROLES.includes(state.currentUser?.role || '')) {
    return <Navigate to="/" replace />
  }

  return <>{children}</>
}
