import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase as supabaseTyped } from '@/lib/supabase/client'
import { useAuth } from '@/hooks/use-auth'
import { sanitizeClientPhone, sanitizeDocument } from '@/lib/utils'
import { toast } from '@/hooks/use-toast'

// ============================================================
// MÓDULO DE LEADS — store próprio, separado do useLegalStore.
// REGRA FUNDAMENTAL: lead NUNCA vira cliente automaticamente.
// Conversão é SEMPRE manual, com confirmação explícita no diálogo.
// ============================================================

/** Client com tipagem flexível: as tabelas leads/lead_interactions são novas
 * e ainda não constam do Database gerado em lib/supabase/types.ts. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const supabase = supabaseTyped as any

export const LEAD_STAGES = [
  'Novo',
  'Aguardando contato',
  'Em atendimento',
  'Qualificado',
  'Proposta enviada',
  'Contratado',
  'Perdido',
  'Não qualificado',
] as const

export type LeadStage = (typeof LEAD_STAGES)[number]

export const LEAD_ORIGINS = [
  'Meta Ads — Facebook',
  'Meta Ads — Instagram',
  'Google Ads',
  'Site institucional',
  'WhatsApp',
  'Indicação',
  'Contato orgânico',
  'Outros',
] as const

export const LEAD_INTERACTION_TYPES = [
  'Ligação',
  'Mensagem',
  'Reunião',
  'Tentativa de contato',
  'Observação',
  'Proposta',
  'Mudança de etapa',
  'Retorno agendado',
] as const

export const LEAD_PRIORITIES = ['Baixa', 'Média', 'Alta', 'Urgente'] as const

export interface Lead {
  id: string
  name: string
  phone?: string | null
  email?: string | null
  city?: string | null
  state?: string | null
  entryDate?: string | null
  origin?: string | null
  campaign?: string | null
  adset?: string | null
  ad?: string | null
  formId?: string | null
  externalId?: string | null
  area?: string | null
  subject?: string | null
  summary?: string | null
  factDate?: string | null
  internalNotes?: string | null
  stage: string
  responsibleId?: string | null
  lastContactAt?: string | null
  nextContactAt?: string | null
  priority?: string | null
  lostReason?: string | null
  convertedClientId?: string | null
  convertedAt?: string | null
  created_by?: string | null
  created_at?: string
  updated_at?: string
}

export interface LeadInteraction {
  id: string
  leadId: string
  type: string
  description?: string | null
  fromStage?: string | null
  toStage?: string | null
  occurredAt: string
  userId?: string | null
  created_at?: string
}

const uuidOrNull = (v: unknown): string | null => {
  if (!v) return null
  const s = String(v).trim()
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s) ? s : null
}

const cleanText = (v: unknown): string | null => {
  const s = typeof v === 'string' ? v.trim() : ''
  return s ? s : null
}

export function useLeadsStore() {
  const { user } = useAuth()
  const [leads, setLeads] = useState<Lead[]>([])
  const [isLoading, setIsLoading] = useState(false)
  const loadingRef = useRef(false)
  // Ref de leitura para callbacks que precisam do estado atual sem dep de render
  const stateLeadsRef = useRef<Lead[]>([])
  stateLeadsRef.current = leads

  const fetchLeads = useCallback(async () => {
    if (loadingRef.current) return
    loadingRef.current = true
    setIsLoading(true)
    try {
      const { data, error } = await supabase
        .from('leads')
        .select('*')
        .order('created_at', { ascending: false })
      if (error) throw error
      setLeads((data as Lead[]) || [])
    } catch (err) {
      console.warn('Erro ao carregar leads:', err)
      toast({
        title: 'Erro ao carregar leads',
        description: 'Não foi possível buscar os leads. Verifique sua conexão.',
        variant: 'destructive',
      })
    } finally {
      loadingRef.current = false
      setIsLoading(false)
    }
  }, [])

  // Carrega uma única vez por sessão autenticada
  const userId = user?.id || null
  useEffect(() => {
    if (userId) fetchLeads()
  }, [userId, fetchLeads])

  const fetchInteractions = useCallback(async (leadId: string): Promise<LeadInteraction[]> => {
    try {
      const { data, error } = await supabase
        .from('lead_interactions')
        .select('*')
        .eq('leadId', leadId)
        .order('occurredAt', { ascending: false })
      if (error) throw error
      return (data as LeadInteraction[]) || []
    } catch (err) {
      console.warn('Erro ao carregar histórico do lead:', err)
      toast({
        title: 'Erro ao carregar histórico',
        description: 'Não foi possível carregar a timeline deste lead.',
        variant: 'destructive',
      })
      return []
    }
  }, [])

  const addInteraction = useCallback(
    async (
      leadId: string,
      type: string,
      description: string,
      opts?: { occurredAt?: string; fromStage?: string | null; toStage?: string | null },
    ): Promise<LeadInteraction | null> => {
      try {
        const payload: Record<string, unknown> = {
          leadId,
          type,
          description: cleanText(description),
          occurredAt: opts?.occurredAt || new Date().toISOString(),
          userId: uuidOrNull(user?.id),
        }
        if (opts?.fromStage !== undefined) payload.fromStage = cleanText(opts.fromStage)
        if (opts?.toStage !== undefined) payload.toStage = cleanText(opts.toStage)
        const { data, error } = await supabase
          .from('lead_interactions')
          .insert(payload)
          .select()
          .single()
        if (error) throw error
        return data as LeadInteraction
      } catch (err) {
        console.warn('Erro ao registrar interação:', err)
        toast({
          title: 'Erro ao registrar interação',
          description: 'O registro de histórico falhou.',
          variant: 'destructive',
        })
        return null
      }
    },
    [user?.id],
  )

  const addLead = useCallback(
    async (payload: Partial<Lead>): Promise<Lead | null> => {
      try {
        const insertPayload: Record<string, unknown> = {
          name: (payload.name || '').trim().toUpperCase(),
          phone: cleanText(payload.phone ? sanitizeClientPhone(payload.phone) : ''),
          email: cleanText(payload.email),
          city: cleanText(payload.city),
          state: cleanText(payload.state),
          entryDate: cleanText(payload.entryDate),
          origin: cleanText(payload.origin),
          campaign: cleanText(payload.campaign),
          adset: cleanText(payload.adset),
          ad: cleanText(payload.ad),
          formId: cleanText(payload.formId),
          externalId: cleanText(payload.externalId),
          area: cleanText(payload.area),
          subject: cleanText(payload.subject),
          summary: cleanText(payload.summary),
          factDate: cleanText(payload.factDate),
          internalNotes: cleanText(payload.internalNotes),
          stage: payload.stage || 'Novo',
          responsibleId: uuidOrNull(payload.responsibleId) || uuidOrNull(user?.id),
          nextContactAt: cleanText(payload.nextContactAt),
          priority: cleanText(payload.priority),
          lostReason: cleanText(payload.lostReason),
          created_by: uuidOrNull(user?.id),
        }
        const { data, error } = await supabase.from('leads').insert(insertPayload).select().single()
        if (error) throw error
        const lead = data as Lead
        setLeads((p) => [lead, ...p])
        // Histórico: criação do lead
        await addInteraction(lead.id, 'Observação', 'Lead cadastrado no sistema.')
        return lead
      } catch (err: any) {
        console.warn('Erro ao salvar lead:', err)
        const msg = String(err?.message || err?.details || '')
        const dup = msg.includes('uq_leads_phone_not_empty')
          ? 'Já existe um lead com este telefone.'
          : msg.includes('uq_leads_email_not_empty')
            ? 'Já existe um lead com este e-mail.'
            : 'Não foi possível salvar o lead. Verifique os dados e tente novamente.'
        toast({ title: 'Erro ao salvar lead', description: dup, variant: 'destructive' })
        return null
      }
    },
    [user?.id, addInteraction],
  )

  const updateLead = useCallback(
    async (
      id: string,
      changes: Partial<Lead>,
      opts?: { skipStageLog?: boolean },
    ): Promise<boolean> => {
      const prev = stateLeadsRef.current.find((l) => l.id === id)
      try {
        const textMap: Array<[keyof Lead, string]> = [
          ['name', 'name'],
          ['phone', 'phone'],
          ['email', 'email'],
          ['city', 'city'],
          ['state', 'state'],
          ['entryDate', 'entryDate'],
          ['origin', 'origin'],
          ['campaign', 'campaign'],
          ['adset', 'adset'],
          ['ad', 'ad'],
          ['formId', 'formId'],
          ['externalId', 'externalId'],
          ['area', 'area'],
          ['subject', 'subject'],
          ['summary', 'summary'],
          ['factDate', 'factDate'],
          ['internalNotes', 'internalNotes'],
          ['stage', 'stage'],
          ['nextContactAt', 'nextContactAt'],
          ['priority', 'priority'],
          ['lostReason', 'lostReason'],
        ]
        const finalChanges: Record<string, unknown> = {}
        for (const [key, col] of textMap) {
          if (key in changes) {
            let val: unknown = changes[key]
            if (key === 'name')
              val = String(val || '')
                .trim()
                .toUpperCase()
            if (key === 'phone') val = val ? sanitizeClientPhone(String(val)) : val
            finalChanges[col] = cleanText(val as string)
          }
        }
        if ('responsibleId' in changes) {
          finalChanges['responsibleId'] = uuidOrNull(changes.responsibleId)
        }
        if ('lastContactAt' in changes) {
          finalChanges['lastContactAt'] =
            changes.lastContactAt === null
              ? null
              : changes.lastContactAt || new Date().toISOString()
        }
        finalChanges['updated_at'] = new Date().toISOString()

        const { error } = await supabase.from('leads').update(finalChanges).eq('id', id)
        if (error) throw error

        setLeads((p) => p.map((l) => (l.id === id ? { ...l, ...(changes as any) } : l)))

        // Mudança de etapa gera registro automático no histórico (de/para)
        if (!opts?.skipStageLog && changes.stage && prev && prev.stage !== changes.stage) {
          await addInteraction(id, 'Mudança de etapa', '', {
            fromStage: prev.stage,
            toStage: String(changes.stage),
          })
        }
        return true
      } catch (err: any) {
        console.warn('Erro ao atualizar lead:', err)
        toast({
          title: 'Erro ao atualizar lead',
          description: String(err?.message || 'Tente novamente.'),
          variant: 'destructive',
        })
        return false
      }
    },
    [addInteraction],
  )

  const changeStage = useCallback(
    async (id: string, toStage: string): Promise<boolean> => {
      const lead = stateLeadsRef.current.find((l) => l.id === id)
      if (!lead) return false
      if (lead.stage === toStage) return true
      if (lead.convertedClientId) {
        toast({
          title: 'Lead já convertido',
          description: 'Este lead já foi convertido em cliente e seu funil está encerrado.',
          variant: 'destructive',
        })
        return false
      }
      if (toStage === 'Contratado') {
        toast({
          title: 'Conversão manual',
          description:
            'Use o botão "Converter em cliente" para marcar o lead como Contratado — a conversão é sempre manual e confirmada.',
          variant: 'destructive',
        })
        return false
      }
      return updateLead(id, { stage: toStage })
    },
    [updateLead],
  )

  const deleteLead = useCallback(async (id: string): Promise<boolean> => {
    try {
      const { error } = await supabase.from('leads').delete().eq('id', id)
      if (error) throw error
      setLeads((p) => p.filter((l) => l.id !== id))
      toast({ title: 'Lead excluído', description: 'O lead foi removido com seu histórico.' })
      return true
    } catch (err) {
      console.warn('Erro ao excluir lead:', err)
      toast({
        title: 'Erro ao excluir lead',
        description: 'Não foi possível excluir o lead.',
        variant: 'destructive',
      })
      return false
    }
  }, [])

  /** Aviso de provável duplicidade ao digitar telefone/e-mail — não bloqueia salvamento. */
  const checkLeadDuplicates = useCallback(
    async (phone?: string | null, email?: string | null, excludeLeadId?: string) => {
      const result = { phone: [] as Lead[], email: [] as Lead[] }
      try {
        const notMe = excludeLeadId || '00000000-0000-0000-0000-000000000000'
        const digits = (phone || '').replace(/\D/g, '')
        if (digits.length >= 8) {
          const { data } = await supabase.from('leads').select('*').neq('id', notMe)
          result.phone = ((data as Lead[]) || []).filter((l) =>
            (l.phone || '').replace(/\D/g, '').endsWith(digits.slice(-8)),
          )
        }
        if (email && email.includes('@')) {
          const { data } = await supabase
            .from('leads')
            .select('*')
            .ilike('email', email.trim())
            .neq('id', notMe)
          result.email = (data as Lead[]) || []
        }
      } catch (err) {
        console.warn('Erro ao checar duplicidade de lead:', err)
      }
      return result
    },
    [],
  )

  /**
   * CONVERSÃO MANUAL — só chamada a partir do ConvertLeadDialog, com confirmação explícita.
   * Transacional por design: o lead só é marcado como convertido (convertedClientId +
   * convertedAt + stage Contratado) se o cliente foi criado/vinculado com sucesso. Em erro,
   * o lead permanece como estava. A guarda .is(convertedClientId, null) impede conversão
   * duplicada em concorrência. O histórico do lead permanece intacto.
   */
  const convertLead = useCallback(
    async (
      lead: Lead,
      mode: 'create' | 'link',
      clientPayload: Record<string, unknown> | null,
      existingClientId: string | null,
    ): Promise<{ ok: boolean; clientId?: string }> => {
      if (lead.convertedClientId) {
        toast({
          title: 'Conversão duplicada',
          description: 'Este lead já foi convertido em cliente.',
          variant: 'destructive',
        })
        return { ok: false }
      }
      try {
        let clientId: string | null = null
        if (mode === 'link') {
          clientId = existingClientId
          if (!clientId) return { ok: false }
        } else {
          if (!clientPayload) return { ok: false }
          const { data, error } = await supabase
            .from('clients')
            .insert(clientPayload)
            .select('id')
            .single()
          if (error) throw error
          clientId = (data as any)?.id || null
        }
        if (!clientId) return { ok: false }

        const now = new Date().toISOString()
        const { data: upd, error: updErr } = await supabase
          .from('leads')
          .update({
            stage: 'Contratado',
            convertedClientId: clientId,
            convertedAt: now,
            updated_at: now,
          })
          .eq('id', lead.id)
          .is('convertedClientId', null)
          .select('id')
        if (updErr) throw updErr
        if (!upd || upd.length === 0) {
          toast({
            title: 'Conversão duplicada',
            description: 'Este lead já foi convertido por outro usuário.',
            variant: 'destructive',
          })
          return { ok: false }
        }

        await addInteraction(lead.id, 'Mudança de etapa', 'Lead convertido em cliente.', {
          fromStage: lead.stage,
          toStage: 'Contratado',
        })

        setLeads((p) =>
          p.map((l) =>
            l.id === lead.id
              ? { ...l, stage: 'Contratado', convertedClientId: clientId!, convertedAt: now }
              : l,
          ),
        )

        toast({
          title: 'Lead convertido',
          description: 'Cliente disponível no cadastro de clientes.',
        })
        return { ok: true, clientId: clientId || undefined }
      } catch (err: any) {
        console.warn('Erro na conversão do lead:', err)
        toast({
          title: 'Falha na conversão',
          description:
            String(err?.message || '') ||
            'O lead permanece como estava. Nenhum dado foi alterado. Tente novamente.',
          variant: 'destructive',
        })
        return { ok: false }
      }
    },
    [addInteraction],
  )

  /**
   * Atualiza a etapa de todos os leads com oldLabel para newLabel (usado ao renomear etapas nas configurações).
   */
  const batchRenameStage = useCallback(
    async (oldLabel: string, newLabel: string): Promise<boolean> => {
      if (!oldLabel || !newLabel || oldLabel === newLabel) return true
      try {
        const { error } = await supabase
          .from('leads')
          .update({ stage: newLabel, updated_at: new Date().toISOString() })
          .eq('stage', oldLabel)
        if (error) throw error

        setLeads((prev) => prev.map((l) => (l.stage === oldLabel ? { ...l, stage: newLabel } : l)))
        return true
      } catch (err: any) {
        console.warn('Erro ao atualizar etapa dos leads em lote:', err)
        toast({
          title: 'Aviso ao renomear etapa nos leads',
          description: String(
            err?.message || 'Falha ao propagar novo nome da etapa nos leads existentes.',
          ),
          variant: 'destructive',
        })
        return false
      }
    },
    [],
  )

  return {
    leads,
    isLoading,
    fetchLeads,
    fetchInteractions,
    addLead,
    updateLead,
    deleteLead,
    changeStage,
    batchRenameStage,
    addInteraction,
    convertLead,
    checkLeadDuplicates,
  }
}

/** Utilitário: pesquisa clientes existentes por documento / nome / telefone (duplicidade na conversão). */
export function findExistingClients(
  clients: Array<Record<string, any>>,
  document: string,
  name: string,
  phone: string,
): { byDocument: any[]; byName: any[]; byPhone: any[] } {
  const doc = sanitizeDocument(document)
  const nameNorm = name.trim().toUpperCase()
  const phoneDigits = (phone || '').replace(/\D/g, '').slice(-8)
  return {
    byDocument: doc ? clients.filter((c) => sanitizeDocument(c.document || '') === doc) : [],
    byName: nameNorm ? clients.filter((c) => (c.name || '').toUpperCase() === nameNorm) : [],
    byPhone: phoneDigits
      ? clients.filter((c) => (c.phone || '').replace(/\D/g, '').endsWith(phoneDigits))
      : [],
  }
}
