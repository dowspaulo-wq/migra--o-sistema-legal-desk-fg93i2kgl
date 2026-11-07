import { useEffect, useState } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
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
import { Button } from '@/components/ui/button'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { UserWarning } from './LeadDuplicateAlert'
import { LEAD_ORIGINS, LEAD_PRIORITIES, LEAD_STAGES, type Lead } from '@/stores/useLeadsStore'
import { toast } from '@/hooks/use-toast'
import { formatPhone } from '@/lib/utils'
import { BRAZILIAN_STATES } from '@/lib/cep'

const todayISO = () => {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

function getEmptyForm(responsibleId: string) {
  return {
    name: '',
    phone: '',
    email: '',
    city: '',
    state: '',
    entryDate: todayISO(),
    origin: '',
    campaign: '',
    adset: '',
    ad: '',
    formId: '',
    externalId: '',
    area: '',
    subject: '',
    summary: '',
    factDate: '',
    internalNotes: '',
    stage: 'Novo',
    responsibleId: responsibleId || '',
    nextContactAt: '',
    priority: 'Média',
    lostReason: '',
  }
}

interface LeadDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  lead?: Lead | null
  users: Array<{ id: string; name: string }>
  leadAreas: string[]
  leadSubjects: string[]
  onSave: (payload: Partial<Lead>) => Promise<boolean>
  onCheckDuplicates: (
    phone?: string | null,
    email?: string | null,
    excludeLeadId?: string,
  ) => Promise<{ phone: Lead[]; email: Lead[] }>
}

export function LeadDialog({
  open,
  onOpenChange,
  lead,
  users,
  leadAreas,
  leadSubjects,
  onSave,
  onCheckDuplicates,
}: LeadDialogProps) {
  const isEdit = !!lead
  const [fd, setFd] = useState(() => getEmptyForm(''))
  const [saving, setSaving] = useState(false)
  const [dupWarning, setDupWarning] = useState<string | null>(null)

  useEffect(() => {
    if (open) {
      setDupWarning(null)
      if (lead) {
        setFd({
          ...getEmptyForm(''),
          ...lead,
          phone: lead.phone ? formatPhone(lead.phone) : '',
        } as typeof fd)
      } else {
        setFd(getEmptyForm(''))
      }
    }
  }, [open, lead])

  // Aviso de provável duplicidade ao digitar telefone/e-mail (não bloqueia salvamento)
  useEffect(() => {
    if (!open) return
    const digits = (fd.phone || '').replace(/\D/g, '')
    const email = (fd.email || '').trim()
    if (digits.length < 10 && !email.includes('@')) {
      setDupWarning(null)
      return
    }
    const t = setTimeout(async () => {
      const res = await onCheckDuplicates(
        digits.length >= 8 ? fd.phone : null,
        email || null,
        lead?.id,
      )
      const names = [...res.phone.map((l) => l.name), ...res.email.map((l) => l.name)]
      const unique = Array.from(new Set(names))
      setDupWarning(unique.length > 0 ? unique.join(', ') : null)
    }, 500)
    return () => clearTimeout(t)
  }, [fd.phone, fd.email, open, lead?.id, onCheckDuplicates])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!fd.name?.trim()) {
      toast({
        title: 'Campo obrigatório',
        description: 'Informe o nome do lead.',
        variant: 'destructive',
      })
      return
    }
    if (!fd.phone?.trim() && !fd.email?.trim()) {
      toast({
        title: 'Contato obrigatório',
        description: 'Informe pelo menos um meio de contato: telefone ou e-mail.',
        variant: 'destructive',
      })
      return
    }
    setSaving(true)
    const ok = await onSave(fd)
    setSaving(false)
    if (ok) onOpenChange(false)
  }

  const ucase = (v: string) => v.toUpperCase()

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[720px] max-h-[90vh] overflow-y-auto">
        <form onSubmit={handleSubmit} className="grid gap-4">
          <DialogHeader>
            <DialogTitle>{isEdit ? 'Editar Lead' : 'Cadastrar Lead'}</DialogTitle>
          </DialogHeader>

          {dupWarning && <UserWarning names={dupWarning} />}

          {/* Identificação */}
          <div className="grid grid-cols-2 gap-4">
            <div className="col-span-2 space-y-2">
              <Label>Nome *</Label>
              <Input
                required
                value={fd.name}
                onChange={(e) => setFd({ ...fd, name: ucase(e.target.value) })}
                placeholder="Nome do lead"
              />
            </div>
            <div className="space-y-2">
              <Label>WhatsApp / Telefone</Label>
              <Input
                value={fd.phone}
                onChange={(e) => setFd({ ...fd, phone: formatPhone(e.target.value) })}
                placeholder="(31) 98765-4321"
                inputMode="tel"
              />
            </div>
            <div className="space-y-2">
              <Label>E-mail</Label>
              <Input
                type="email"
                value={fd.email || ''}
                onChange={(e) => setFd({ ...fd, email: e.target.value })}
                placeholder="lead@email.com"
              />
            </div>
            <div className="space-y-2">
              <Label>Cidade</Label>
              <Input
                value={fd.city || ''}
                onChange={(e) => setFd({ ...fd, city: e.target.value })}
              />
            </div>
            <div className="space-y-2">
              <Label>UF</Label>
              <Select
                value={fd.state || undefined}
                onValueChange={(v) => setFd({ ...fd, state: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Selecione" />
                </SelectTrigger>
                <SelectContent>
                  {BRAZILIAN_STATES.map((uf) => (
                    <SelectItem key={uf} value={uf}>
                      {uf}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Data de entrada</Label>
              <Input
                type="date"
                value={fd.entryDate || ''}
                onChange={(e) => setFd({ ...fd, entryDate: e.target.value })}
              />
            </div>
            <div className="space-y-2">
              <Label>Origem</Label>
              <Select
                value={fd.origin || undefined}
                onValueChange={(v) => setFd({ ...fd, origin: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Selecione a origem" />
                </SelectTrigger>
                <SelectContent>
                  {LEAD_ORIGINS.map((o) => (
                    <SelectItem key={o} value={o}>
                      {o}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          {/* Campanha (opcional) */}
          <details className="rounded-lg border p-3">
            <summary className="text-sm font-medium cursor-pointer text-muted-foreground">
              Dados de campanha (opcional)
            </summary>
            <div className="grid grid-cols-2 gap-3 mt-3">
              <div className="space-y-1">
                <Label className="text-xs">Campanha</Label>
                <Input
                  value={fd.campaign || ''}
                  onChange={(e) => setFd({ ...fd, campaign: e.target.value })}
                />
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Conjunto (Adset)</Label>
                <Input
                  value={fd.adset || ''}
                  onChange={(e) => setFd({ ...fd, adset: e.target.value })}
                />
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Anúncio (Ad)</Label>
                <Input value={fd.ad || ''} onChange={(e) => setFd({ ...fd, ad: e.target.value })} />
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Form ID</Label>
                <Input
                  value={fd.formId || ''}
                  onChange={(e) => setFd({ ...fd, formId: e.target.value })}
                />
              </div>
              <div className="space-y-1">
                <Label className="text-xs">ID Externo</Label>
                <Input
                  value={fd.externalId || ''}
                  onChange={(e) => setFd({ ...fd, externalId: e.target.value })}
                />
              </div>
            </div>
          </details>

          {/* Interesse jurídico */}
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>Área jurídica</Label>
              <Select
                value={fd.area || undefined}
                onValueChange={(v) => setFd({ ...fd, area: v, subject: '' })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Selecione a área" />
                </SelectTrigger>
                <SelectContent>
                  {leadAreas.map((a) => (
                    <SelectItem key={a} value={a}>
                      {a}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Assunto</Label>
              <Select
                value={fd.subject || undefined}
                onValueChange={(v) => setFd({ ...fd, subject: v })}
                disabled={!fd.area}
              >
                <SelectTrigger>
                  <SelectValue
                    placeholder={fd.area ? 'Selecione o assunto' : 'Selecione a área primeiro'}
                  />
                </SelectTrigger>
                <SelectContent>
                  {leadSubjects.map((s) => (
                    <SelectItem key={s} value={s}>
                      {s}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="col-span-2 space-y-2">
              <Label>Resumo do caso</Label>
              <Textarea
                rows={2}
                value={fd.summary || ''}
                onChange={(e) => setFd({ ...fd, summary: e.target.value })}
              />
            </div>
            <div className="space-y-2">
              <Label>Data aproximada do fato</Label>
              <Input
                type="date"
                value={fd.factDate || ''}
                onChange={(e) => setFd({ ...fd, factDate: e.target.value })}
              />
            </div>
            <div className="col-span-2 space-y-2">
              <Label>Observações internas</Label>
              <Textarea
                rows={2}
                value={fd.internalNotes || ''}
                onChange={(e) => setFd({ ...fd, internalNotes: e.target.value })}
              />
            </div>
          </div>

          {/* Acompanhamento */}
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>Etapa</Label>
              <Select
                value={fd.stage}
                onValueChange={(v) => setFd({ ...fd, stage: v })}
                disabled={isEdit && !!lead?.convertedClientId}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {LEAD_STAGES.map((s) => (
                    <SelectItem key={s} value={s}>
                      {s}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {isEdit && !lead?.convertedClientId && (
                <p className="text-xs text-muted-foreground">
                  A mudança de etapa feita aqui fica registrada no histórico do lead.
                </p>
              )}
            </div>
            <div className="space-y-2">
              <Label>Responsável</Label>
              <Select
                value={fd.responsibleId || undefined}
                onValueChange={(v) => setFd({ ...fd, responsibleId: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Selecione" />
                </SelectTrigger>
                <SelectContent>
                  {users.map((u) => (
                    <SelectItem key={u.id} value={u.id}>
                      {u.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Próximo contato agendado</Label>
              <Input
                type="date"
                value={fd.nextContactAt || ''}
                onChange={(e) => setFd({ ...fd, nextContactAt: e.target.value })}
              />
            </div>
            <div className="space-y-2">
              <Label>Prioridade</Label>
              <Select
                value={fd.priority || undefined}
                onValueChange={(v) => setFd({ ...fd, priority: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Selecione" />
                </SelectTrigger>
                <SelectContent>
                  {LEAD_PRIORITIES.map((p) => (
                    <SelectItem key={p} value={p}>
                      {p}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            {(fd.stage === 'Perdido' || fd.stage === 'Não qualificado') && (
              <div className="col-span-2 space-y-2">
                <Label>Motivo da perda/descarte</Label>
                <Textarea
                  rows={2}
                  value={fd.lostReason || ''}
                  onChange={(e) => setFd({ ...fd, lostReason: e.target.value })}
                  placeholder="Ex.: preço, sem retorno, fora da área de atuação..."
                />
              </div>
            )}
          </div>

          <Alert className="bg-slate-50 border-slate-200">
            <AlertDescription className="text-xs text-slate-600">
              O lead NÃO é um cliente: ele não gera processo, contrato nem honorários. Somente após
              confirmação manual na etapa "Qualificado" ou "Proposta enviada" ele pode ser
              convertido em cliente.
            </AlertDescription>
          </Alert>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              Cancelar
            </Button>
            <Button type="submit" disabled={saving}>
              {saving ? 'Salvando...' : isEdit ? 'Salvar alterações' : 'Cadastrar lead'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
