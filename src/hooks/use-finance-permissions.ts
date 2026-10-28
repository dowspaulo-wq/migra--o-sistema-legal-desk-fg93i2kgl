import useLegalStore from '@/stores/useLegalStore'

export interface FinancePermissions {
  isAdmin: boolean
  isColaborador: boolean
  canManageAsaas: boolean
  canEditFinance: boolean
  canDeleteFinance: boolean
  canCreateFinance: boolean
  canManagePaymentPlans: boolean
}

export function useFinancePermissions(): FinancePermissions {
  const { state } = useLegalStore()
  const currentUser = state.currentUser
  const role = (currentUser?.role || '').toLowerCase()
  const email = (currentUser?.email || '').toLowerCase()
  const id = currentUser?.id

  const isDouglas =
    email === 'advdouglaspsantos@gmail.com' ||
    email === 'dowspaulo@gmail.com' ||
    id === '6501af65-cd6c-43c3-958a-3091ce93ba78'

  const isAdmin = isDouglas || role === 'admin' || role === 'adm'
  const isColaborador = !isAdmin

  return {
    isAdmin,
    isColaborador,
    canManageAsaas: isAdmin,
    canEditFinance: isAdmin,
    canDeleteFinance: isAdmin,
    canCreateFinance: true,
    canManagePaymentPlans: isAdmin,
  }
}
