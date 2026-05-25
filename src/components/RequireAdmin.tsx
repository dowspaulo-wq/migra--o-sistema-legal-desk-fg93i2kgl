import { Navigate } from 'react-router-dom'
import useLegalStore from '@/stores/useLegalStore'

export function RequireAdmin({ children }: { children: React.ReactNode }) {
  const { state } = useLegalStore()

  if (state.currentUser?.role !== 'Admin') {
    return <Navigate to="/" replace />
  }

  return <>{children}</>
}
