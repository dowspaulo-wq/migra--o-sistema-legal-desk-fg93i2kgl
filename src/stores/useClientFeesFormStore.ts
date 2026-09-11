import { create } from 'zustand'

export interface ClientFeeDraft {
  description: string
  amount: string
  date: string
  installments: string
  paymentMethod: string
  bankAccount: string
  status: string
  feeType: string
  percentage: string
  selectedCases: string[]
}

export interface ClientFeeEditDraft {
  feeId: string
  clientId: string
  data: any
}

interface ClientFeesFormStore {
  // Rascunho para Novo Honorário
  // isOpen indica se o modal está aberto ou deve ser reaberto se o usuário estiver na página do cliente
  isCreateOpen: boolean
  activeClientId: string | null
  draft: ClientFeeDraft | null

  // Ações para Novo Honorário
  openCreateFee: (clientId: string, defaultValues?: Partial<ClientFeeDraft>) => void
  closeCreateFee: () => void
  setDraft: (updater: Partial<ClientFeeDraft> | ((prev: ClientFeeDraft) => ClientFeeDraft)) => void
  clearDraft: () => void

  // Rascunho para Editar Honorário
  isEditOpen: boolean
  editDraft: ClientFeeEditDraft | null

  // Ações para Editar Honorário
  openEditFee: (clientId: string, fee: any) => void
  closeEditFee: () => void
  updateEditFeeData: (updater: any | ((prev: any) => any)) => void
  clearEditDraft: () => void
}

const DEFAULT_CREATE_DRAFT: ClientFeeDraft = {
  description: '',
  amount: '',
  date: new Date().toISOString().split('T')[0],
  installments: '1',
  paymentMethod: 'PIX',
  bankAccount: 'ASAAS',
  status: 'Previsto',
  feeType: 'Honorários Contratuais',
  percentage: '',
  selectedCases: [],
}

export const useClientFeesFormStore = create<ClientFeesFormStore>((set) => ({
  isCreateOpen: false,
  activeClientId: null,
  draft: null,

  openCreateFee: (clientId: string, defaultValues?: Partial<ClientFeeDraft>) => {
    set((state) => {
      // Se já houver um rascunho para este mesmo cliente, mantemos os dados e só abrimos o modal
      if (state.activeClientId === clientId && state.draft) {
        return { isCreateOpen: true }
      }
      // Se mudou de cliente ou não há rascunho, inicia novo rascunho
      return {
        isCreateOpen: true,
        activeClientId: clientId,
        draft: {
          ...DEFAULT_CREATE_DRAFT,
          ...defaultValues,
        },
      }
    })
  },

  closeCreateFee: () => {
    set({ isCreateOpen: false })
  },

  setDraft: (updater) => {
    set((state) => {
      const baseDraft = state.draft || { ...DEFAULT_CREATE_DRAFT }
      const newDraft =
        typeof updater === 'function' ? updater(baseDraft) : { ...baseDraft, ...updater }
      return { draft: newDraft }
    })
  },

  clearDraft: () => {
    set({
      isCreateOpen: false,
      activeClientId: null,
      draft: null,
    })
  },

  // Editar honorário
  isEditOpen: false,
  editDraft: null,

  openEditFee: (clientId: string, fee: any) => {
    set((state) => {
      if (
        state.editDraft &&
        state.editDraft.feeId === fee.id &&
        state.editDraft.clientId === clientId
      ) {
        return { isEditOpen: true }
      }
      return {
        isEditOpen: true,
        editDraft: {
          feeId: fee.id,
          clientId,
          data: fee,
        },
      }
    })
  },

  closeEditFee: () => {
    set({ isEditOpen: false })
  },

  updateEditFeeData: (updater) => {
    set((state) => {
      if (!state.editDraft) return state
      const nextData =
        typeof updater === 'function'
          ? updater(state.editDraft.data)
          : { ...state.editDraft.data, ...updater }
      return {
        editDraft: {
          ...state.editDraft,
          data: nextData,
        },
      }
    })
  },

  clearEditDraft: () => {
    set({
      isEditOpen: false,
      editDraft: null,
    })
  },
}))
