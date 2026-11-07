import { useEffect, useState } from 'react'
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from '@/components/ui/sheet'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Separator } from '@/components/ui/separator'
import {
  LEAD_INTERACTION_TYPES,
  LEAD_STAGES,
  type Lead,
  type LeadInteraction,
} from '@/stores/useLeadsStore'
import { formatSafeDateTime, formatSafeLocalDate, getWhatsAppPhone } from '@/lib/utils'
import { toast } from '@/hooks/use-toast'
import {
  Phone,
  MessageSquare,
  CalendarClock,
  CheckCircle2,
  ArrowRight,
  Trash2,
  UserCheck,
} from 'lucide-react'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog'
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip'

interface LeadDetailSheetProps {
  lead?: Lead | null
  open: boolean
  onOpenChange: (open: boolean) => void
  users: Array<{ id: string; name: string }>
  leadStages?: string[]
  leadInteractionTypes?: string[]
  canDelete?: boolean
  fetchInteractions: (leadId: string) => Promise<LeadInteraction[]>
  addInteraction: (
    leadId: string,
    type: string,
    description: string,
    opts?: { occurredAt?: string; fromStage?: string | null; toStage?: string | null },
  ) => Promise<LeadInteraction | null>
  onChangeStage: (id: string, toStage: string) => Promise<boolean>
  onScheduleFollowUp: (id: string, date: string) => Promise<boolean>
  onConvert: (lead: Lead) => void
  onEdit: (lead: Lead) => void
  onDelete?: (lead: Lead) => Promise<boolean>
}
function typeIcon(type: string) {
  switch (type) {
    case 'Ligação':
      return <Phone className="h-3.5 w-3.5" />
    case 'Mensagem':
      return <MessageSquare className="h-3.5 w-3.5" />
    case 'Retorno agendado':
      return <CalendarClock className="h-3.5 w-3.5" />
    case 'Mudança de etapa':
      return <ArrowRight className="h-3.5 w-3.5" />
    default:
      return <CheckCircle2 className="h-3.5 w-3.5" />
  }
}

export function LeadDetailSheet({
  lead,
  open,
  onOpenChange,
  users,
  leadStages,
  leadInteractionTypes,
  canDelete = true,
  fetchInteractions,
  addInteraction,
  onChangeStage,
  onScheduleFollowUp,
  onConvert,
  onEdit,
  onDelete,
}: LeadDetailSheetProps) {
  const [interactions, setInteractions] = useState<LeadInteraction[]>([])
  const [loading, setLoading] = useState(false)
  const [newType, setNewType] = useState<string>('Ligação')
  const [newDesc, setNewDesc] = useState('')
  const [newDate, setNewDate] = useState('')
  const [saving, setSaving] = useState(false)
  const [deleting, setDeleting] = useState(false)

  const isEligibleStage = lead?.stage === 'Qualificado' || lead?.stage === 'Proposta enviada'
  const isAlreadyConverted = !!lead?.convertedClientId
  const canConvert = !!lead && !isAlreadyConverted && isEligibleStage

  useEffect(() => {
    if (!open || !lead) return
    let active = true
    setLoading(true)
    fetchInteractions(lead.id).then((list) => {
      if (!active) return
      setInteractions(list)
      setLoading(false)
    })
    return () => {
      active = false
    }
  }, [open, lead?.id, fetchInteractions])

  const handleAdd = async () => {
    if (!lead) return
    if (newType === 'Retorno agendado' && !newDate) {
      toast({
        title: 'Data obrigatória',
        description: 'Informe a data do retorno agendado.',
        variant: 'destructive',
      })
      return
    }
    setSaving(true)
    const occurredAt = newDate ? new Date(`${newDate}T12:00:00`).toISOString() : undefined
    const created = await addInteraction(lead.id, newType, newDesc, { occurredAt })
    setSaving(false)
    if (created) {
      // Retorno agendado também atualiza o "próximo contato" do lead
      if (newType === 'Retorno agendado' && newDate) {
        await onScheduleFollowUp(lead.id, newDate)
      }
      setNewDesc('')
      setNewDate('')
      const list = await fetchInteractions(lead.id)
      setInteractions(list)
    }
  }

  if (!lead) return null

  const responsible = users.find((u) => u.id === lead.responsibleId)

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="w-full sm:max-w-xl overflow-y-auto p-6">
        <SheetHeader className="p-0">
          <SheetTitle>{lead.name}</SheetTitle>
          <SheetDescription>
            {lead.origin || 'Sem origem'} · Entrada {formatSafeLocalDate(lead.entryDate)}
          </SheetDescription>
        </SheetHeader>

        <div className="mt-4 space-y-4">
          {/* Dados de contato */}
          <div className="rounded-lg border p-3 text-sm space-y-1">
            <div>
              <span className="text-muted-foreground">Telefone:</span> {lead.phone || '—'}
            </div>
            <div>
              <span className="text-muted-foreground">E-mail:</span> {lead.email || '—'}
            </div>
            <div>
              <span className="text-muted-foreground">Cidade/UF:</span>{' '}
              {[lead.city, lead.state].filter(Boolean).join(' / ') || '—'}
            </div>
            <div>
              <span className="text-muted-foreground">Área/Assunto:</span>{' '}
              {[lead.area, lead.subject].filter(Boolean).join(' — ') || '—'}
            </div>
            {lead.summary && (
              <div>
                <span className="text-muted-foreground">Resumo:</span> {lead.summary}
              </div>
            )}
            <div className="flex flex-wrap gap-2 pt-1">
              <Badge variant="secondary">{lead.stage}</Badge>
              {lead.priority && <Badge variant="outline">{lead.priority}</Badge>}
              {responsible && <Badge variant="outline">Resp.: {responsible.name}</Badge>}
              {lead.convertedClientId && <Badge className="bg-emerald-600">Convertido</Badge>}
            </div>
          </div>

          <div className="flex flex-wrap gap-2 items-center">
            <Button size="sm" variant="outline" onClick={() => onEdit(lead)}>
              Editar lead
            </Button>

            {/* Botão Converter em cliente: sempre presente na área de ações da ficha */}
            <TooltipProvider>
              {canConvert ? (
                <Button
                  size="sm"
                  className="bg-emerald-600 hover:bg-emerald-700 text-white font-medium"
                  onClick={() => onConvert(lead)}
                >
                  <UserCheck className="h-4 w-4 mr-1.5" />
                  Converter em cliente
                </Button>
              ) : isAlreadyConverted ? (
                <Tooltip>
                  <TooltipTrigger asChild>
                    <span tabIndex={0}>
                      <Button
                        size="sm"
                        disabled
                        variant="secondary"
                        className="opacity-60 cursor-not-allowed"
                      >
                        <UserCheck className="h-4 w-4 mr-1.5" />
                        Cliente já contratado
                      </Button>
                    </span>
                  </TooltipTrigger>
                  <TooltipContent>
                    <p>Este lead já foi convertido em cliente ativo.</p>
                  </TooltipContent>
                </Tooltip>
              ) : (
                <Tooltip>
                  <TooltipTrigger asChild>
                    <span tabIndex={0}>
                      <Button
                        size="sm"
                        className="bg-emerald-600 hover:bg-emerald-700 text-white font-medium"
                        onClick={() => onConvert(lead)}
                      >
                        <UserCheck className="h-4 w-4 mr-1.5" />
                        Converter em cliente
                      </Button>
                    </span>
                  </TooltipTrigger>
                  <TooltipContent>
                    <p>
                      Etapa atual: {lead.stage}. Clique para abrir o fluxo de conversão e efetivar a
                      contratação do cliente.
                    </p>
                  </TooltipContent>
                </Tooltip>
              )}
            </TooltipProvider>

            {lead.phone && getWhatsAppPhone(lead.phone) && (
              <Button
                size="sm"
                variant="outline"
                onClick={() =>
                  window.open(`https://wa.me/${getWhatsAppPhone(lead.phone)}`, '_blank', 'noopener')
                }
              >
                Abrir WhatsApp
              </Button>
            )}

            {/* Opção de Excluir o lead com diálogo de confirmação explícita */}
            {canDelete && onDelete && (
              <AlertDialog>
                <AlertDialogTrigger asChild>
                  <Button
                    size="sm"
                    variant="ghost"
                    className="text-red-600 hover:bg-red-50 hover:text-red-700 ml-auto"
                    disabled={deleting}
                  >
                    <Trash2 className="h-4 w-4 mr-1.5" />
                    Excluir lead
                  </Button>
                </AlertDialogTrigger>
                <AlertDialogContent>
                  <AlertDialogHeader>
                    <AlertDialogTitle>Excluir Lead?</AlertDialogTitle>
                    <AlertDialogDescription>
                      Esta ação é irreversível. O lead <strong>"{lead.name}"</strong> e todo o seu
                      histórico de interações serão removidos definitivamente do sistema.
                    </AlertDialogDescription>
                  </AlertDialogHeader>
                  <AlertDialogFooter>
                    <AlertDialogCancel>Cancelar</AlertDialogCancel>
                    <AlertDialogAction
                      className="bg-red-600 hover:bg-red-700 text-white"
                      onClick={async () => {
                        setDeleting(true)
                        const ok = await onDelete(lead)
                        setDeleting(false)
                        if (ok) {
                          onOpenChange(false)
                        }
                      }}
                    >
                      Excluir definitivamente
                    </AlertDialogAction>
                  </AlertDialogFooter>
                </AlertDialogContent>
              </AlertDialog>
            )}
          </div>

          {/* Mudança de etapa */}
          <div className="grid grid-cols-[1fr_auto] gap-2 items-end">
            <div className="space-y-1">
              <Label className="text-xs">Mover para etapa</Label>
              <Select
                value={lead.stage}
                onValueChange={async (v) => {
                  if (v === lead.stage) return
                  // Se o usuário selecionou 'Contratado', dispara automaticamente o fluxo de conversão
                  if (v === 'Contratado') {
                    onConvert(lead)
                    return
                  }
                  const ok = await onChangeStage(lead.id, v)
                  if (ok) {
                    const list = await fetchInteractions(lead.id)
                    setInteractions(list)
                  }
                }}
                disabled={!!lead.convertedClientId}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {(() => {
                    const baseStages =
                      leadStages && leadStages.length > 0 ? leadStages : LEAD_STAGES
                    const allStages =
                      lead.stage && !baseStages.includes(lead.stage as any)
                        ? [lead.stage, ...baseStages]
                        : baseStages
                    return allStages.map((s) => (
                      <SelectItem key={s} value={s}>
                        {s === 'Contratado' ? 'Contratado (via conversão)' : s}
                      </SelectItem>
                    ))
                  })()}
                </SelectContent>
              </Select>
            </div>
          </div>

          <Separator />

          {/* Nova interação */}
          <div className="space-y-2">
            <div className="text-sm font-medium">Registrar interação</div>
            <div className="grid grid-cols-2 gap-2">
              <div className="space-y-1">
                <Label className="text-xs">Tipo</Label>
                <Select value={newType} onValueChange={setNewType}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {(() => {
                      const baseTypes = (
                        leadInteractionTypes && leadInteractionTypes.length > 0
                          ? leadInteractionTypes
                          : LEAD_INTERACTION_TYPES
                      ).filter((t) => t !== 'Mudança de etapa')
                      const allTypes =
                        newType && !baseTypes.includes(newType)
                          ? [newType, ...baseTypes]
                          : baseTypes
                      return allTypes.map((t) => (
                        <SelectItem key={t} value={t}>
                          {t}
                        </SelectItem>
                      ))
                    })()}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1">
                <Label className="text-xs">
                  Data {newType === 'Retorno agendado' ? 'do retorno' : '(opcional)'}
                </Label>
                <Input type="date" value={newDate} onChange={(e) => setNewDate(e.target.value)} />
              </div>
            </div>
            <Textarea
              rows={2}
              placeholder="Descrição da interação..."
              value={newDesc}
              onChange={(e) => setNewDesc(e.target.value)}
            />
            <Button size="sm" onClick={handleAdd} disabled={saving}>
              {saving ? 'Salvando...' : 'Registrar'}
            </Button>
          </div>

          <Separator />

          {/* Timeline */}
          <div className="space-y-2">
            <div className="text-sm font-medium">Histórico</div>
            {loading ? (
              <div className="text-sm text-muted-foreground">Carregando...</div>
            ) : interactions.length === 0 ? (
              <div className="text-sm text-muted-foreground">Nenhuma interação registrada.</div>
            ) : (
              <ol className="space-y-3">
                {interactions.map((it) => (
                  <li key={it.id} className="border-l-2 pl-3 py-0.5 border-slate-200">
                    <div className="flex items-center gap-2 text-xs text-muted-foreground">
                      {typeIcon(it.type)}
                      <span className="font-medium text-foreground">{it.type}</span>
                      <span>·</span>
                      <span>{formatSafeDateTime(it.occurredAt)}</span>
                      {it.userId && (
                        <>
                          <span>·</span>
                          <span>{users.find((u) => u.id === it.userId)?.name || 'Usuário'}</span>
                        </>
                      )}
                    </div>
                    {(it.fromStage || it.toStage) && (
                      <div className="text-xs mt-0.5">
                        {it.fromStage || '—'} <ArrowRight className="inline h-3 w-3" />{' '}
                        {it.toStage || '—'}
                      </div>
                    )}
                    {it.description && <div className="text-sm mt-0.5">{it.description}</div>}
                  </li>
                ))}
              </ol>
            )}
          </div>
        </div>
      </SheetContent>
    </Sheet>
  )
}
