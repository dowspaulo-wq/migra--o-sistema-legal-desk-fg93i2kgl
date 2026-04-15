import { useState, useEffect } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
import { Label } from '@/components/ui/label'
import { Input } from '@/components/ui/input'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Button } from '@/components/ui/button'
import { Toggle } from '@/components/ui/toggle'
import { Textarea } from '@/components/ui/textarea'
import { Checkbox } from '@/components/ui/checkbox'
import { Star } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'

const PREDEFINED_ALERTS = [
  '💣 Liminar contrária',
  '☘️ Liminar em nosso favor',
  '💩 Ônus da prova contrário',
  '🕵️ Ônus da prova em nosso favor',
  '🎤 Sustentação oral',
  '❌ JG indeferida ou não solicitada',
  '✅ JG deferida',
  '⚠️ Revelia',
  '⏰ Perda de prazo',
  '💸 Cobrar astreites',
  '🛑 Litigância de má-fé',
]

const SUBPROCESS_TYPES = ['Recurso', 'Precatória', 'Incidente', 'Outros']

export function CaseDialog({
  open,
  onOpenChange,
  data,
  onSave,
  users,
  clients,
  settings,
  lockedClientId,
}: any) {
  const { state } = useLegalStore()
  const sortedUsers = [...users].sort((a: any, b: any) => a.name.localeCompare(b.name))
  const sortedClients = [...clients].sort((a: any, b: any) => a.name.localeCompare(b.name))

  const caseTypesSettings = settings.caseTypes || []
  const sortedTypes = [...caseTypesSettings].sort((a: any, b: any) => {
    const labelA = typeof a === 'string' ? a : a.label
    const labelB = typeof b === 'string' ? b : b.label
    return labelA.localeCompare(labelB)
  })

  const caseStatusesSettings = settings.caseStatuses || []
  const sortedStatuses = [...caseStatusesSettings].sort((a: any, b: any) => {
    const labelA = typeof a === 'string' ? a : a.label
    const labelB = typeof b === 'string' ? b : b.label
    return labelA.localeCompare(labelB)
  })

  const getInitial = () => ({
    number: '',
    clientId: lockedClientId || data?.clientId || '',
    position: '',
    adverseParty: '',
    type: '',
    status: '',
    court: '',
    comarca: '',
    state: '',
    value: 0,
    startDate: new Date().toISOString().split('T')[0],
    responsibleId: '',
    isSpecial: false,
    isProblematic: false,
    description: '',
    internalNotes: '',
    alerts: '',
    parentId: data?.parentId || null,
    classification: 'DPS',
  })

  const [fd, setFd] = useState(() =>
    data && !data.isNew ? { ...data, classification: data.classification || 'DPS' } : getInitial(),
  )

  const isSubprocess = !!fd.parentId
  const selectedAlerts = fd.alerts ? fd.alerts.split(',').filter(Boolean) : []

  useEffect(() => {
    if (open) {
      setFd(
        data && !data.isNew
          ? { ...data, classification: data.classification || 'DPS' }
          : getInitial(),
      )
    }
  }, [data, open, lockedClientId])

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()

    if (!fd.number || !fd.clientId || !fd.type || !fd.status || !fd.responsibleId) {
      toast({
        title: 'Campos Obrigatórios',
        description:
          'Número, Cliente, Tipo, Status e Responsável são de preenchimento obrigatório.',
        variant: 'destructive',
      })
      return
    }

    const isDupNumber = state.cases.some((c) => c.number === fd.number && c.id !== data?.id)
    if (isDupNumber) {
      toast({
        title: 'Erro',
        description: 'Já existe um processo cadastrado com este número.',
        variant: 'destructive',
      })
      return
    }

    const payload = { ...fd, classification: fd.classification || 'DPS' }
    const { isNew, ...finalPayload } = payload
    onSave(finalPayload)
    onOpenChange(false)
  }

  const toggleAlert = (alert: string, checked: boolean) => {
    const newAlerts = checked
      ? [...selectedAlerts, alert]
      : selectedAlerts.filter((a: string) => a !== alert)
    setFd({ ...fd, alerts: newAlerts.join(',') })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
        <form onSubmit={handleSubmit} className="grid gap-4">
          <DialogHeader>
            <DialogTitle>
              {data && !data.isNew ? 'Editar' : 'Cadastrar'}{' '}
              {isSubprocess ? 'Subprocesso' : 'Processo'}
            </DialogTitle>
          </DialogHeader>
          <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
            <div className="col-span-2 flex gap-4 items-end pb-1">
              <div className="flex-1 space-y-2">
                <Label>Nº do {isSubprocess ? 'Subprocesso' : 'Processo'} (CNJ) *</Label>
                <Input
                  required
                  value={fd.number}
                  onChange={(e) => setFd({ ...fd, number: e.target.value })}
                />
              </div>
              <div className="flex gap-2">
                <Toggle
                  pressed={fd.isSpecial}
                  onPressedChange={(v) => setFd({ ...fd, isSpecial: v })}
                  variant="outline"
                  className={fd.isSpecial ? 'bg-yellow-50 border-yellow-200' : ''}
                  title="Especial"
                >
                  <Star
                    className={`h-4 w-4 ${fd.isSpecial ? 'fill-yellow-400 text-yellow-400' : 'text-slate-400'}`}
                  />
                </Toggle>
                <Toggle
                  pressed={fd.isProblematic}
                  onPressedChange={(v) => setFd({ ...fd, isProblematic: v })}
                  variant="outline"
                  className={fd.isProblematic ? 'bg-orange-50 border-orange-200' : ''}
                  title="Problemático"
                >
                  <span
                    className={`text-xl ${fd.isProblematic ? 'opacity-100' : 'opacity-40 grayscale'}`}
                  >
                    💩
                  </span>
                </Toggle>
              </div>
            </div>

            <div className="space-y-2">
              <Label>Cliente *</Label>
              <Select
                value={fd.clientId}
                onValueChange={(v) => setFd({ ...fd, clientId: v })}
                disabled={!!lockedClientId}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Selecione o Cliente" />
                </SelectTrigger>
                <SelectContent>
                  {sortedClients.map((c: any) => (
                    <SelectItem key={c.id} value={c.id}>
                      {c.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>Tipo *</Label>
              <Select value={fd.type} onValueChange={(v) => setFd({ ...fd, type: v })}>
                <SelectTrigger>
                  <SelectValue placeholder="Selecione o Tipo" />
                </SelectTrigger>
                <SelectContent>
                  {isSubprocess
                    ? SUBPROCESS_TYPES.map((t) => (
                        <SelectItem key={t} value={t}>
                          {t}
                        </SelectItem>
                      ))
                    : sortedTypes.map((t: any) => {
                        const label = typeof t === 'string' ? t : t.label
                        return (
                          <SelectItem key={label} value={label}>
                            {label}
                          </SelectItem>
                        )
                      })}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>Status *</Label>
              <Select value={fd.status} onValueChange={(v) => setFd({ ...fd, status: v })}>
                <SelectTrigger>
                  <SelectValue placeholder="Selecione o Status" />
                </SelectTrigger>
                <SelectContent>
                  {sortedStatuses.map((t: any) => {
                    const label = typeof t === 'string' ? t : t.label
                    return (
                      <SelectItem key={label} value={label}>
                        {label}
                      </SelectItem>
                    )
                  })}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label className="text-primary font-bold">Classificação *</Label>
              <Select
                value={fd.classification || 'DPS'}
                onValueChange={(v) => setFd({ ...fd, classification: v })}
              >
                <SelectTrigger className="border-primary/50">
                  <SelectValue placeholder="Selecione a Classificação" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="SB">SB</SelectItem>
                  <SelectItem value="DPS">DPS</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>Responsável *</Label>
              <Select
                value={fd.responsibleId}
                onValueChange={(v) => setFd({ ...fd, responsibleId: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Selecione o Responsável" />
                </SelectTrigger>
                <SelectContent>
                  {sortedUsers.map((u: any) => (
                    <SelectItem key={u.id} value={u.id}>
                      {u.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {!isSubprocess && (
              <div className="space-y-2">
                <Label>Posição do Cliente</Label>
                <Input
                  value={fd.position}
                  onChange={(e) => setFd({ ...fd, position: e.target.value })}
                />
              </div>
            )}

            {!isSubprocess && (
              <div className="space-y-2">
                <Label>Parte Adversa</Label>
                <Input
                  value={fd.adverseParty}
                  onChange={(e) => setFd({ ...fd, adverseParty: e.target.value })}
                />
              </div>
            )}

            <div className="space-y-2">
              <Label>Vara / Juízo</Label>
              <Input value={fd.court} onChange={(e) => setFd({ ...fd, court: e.target.value })} />
            </div>

            <div className="space-y-2">
              <Label>Comarca / UF</Label>
              <div className="flex gap-2">
                <Input
                  value={fd.comarca}
                  onChange={(e) => setFd({ ...fd, comarca: e.target.value })}
                />
                <Input
                  className="w-16"
                  value={fd.state}
                  onChange={(e) => setFd({ ...fd, state: e.target.value })}
                />
              </div>
            </div>

            {!isSubprocess && (
              <>
                <div className="space-y-2">
                  <Label>Valor da Causa</Label>
                  <Input
                    type="number"
                    value={fd.value}
                    onChange={(e) => setFd({ ...fd, value: Number(e.target.value) })}
                  />
                </div>
                <div className="space-y-2">
                  <Label>Data Início</Label>
                  <Input
                    type="date"
                    value={fd.startDate}
                    onChange={(e) => setFd({ ...fd, startDate: e.target.value })}
                  />
                </div>

                <div className="col-span-full space-y-2">
                  <Label>Alertas do Processo</Label>
                  <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 border p-4 rounded-lg bg-slate-50">
                    {PREDEFINED_ALERTS.map((alert) => (
                      <label
                        key={alert}
                        className="flex items-center gap-2 text-sm cursor-pointer border p-2 rounded bg-white hover:border-primary transition-colors"
                      >
                        <Checkbox
                          checked={selectedAlerts.includes(alert)}
                          onCheckedChange={(checked) => toggleAlert(alert, checked as boolean)}
                        />
                        <span className="leading-none">{alert}</span>
                      </label>
                    ))}
                  </div>
                </div>
              </>
            )}

            <div className="col-span-full md:col-span-2 space-y-2">
              <Label>Descrição</Label>
              <Textarea
                value={fd.description}
                onChange={(e) => setFd({ ...fd, description: e.target.value })}
              />
            </div>
            <div className="col-span-full md:col-span-1 space-y-2">
              <Label>Notas Internas</Label>
              <Textarea
                value={fd.internalNotes}
                onChange={(e) => setFd({ ...fd, internalNotes: e.target.value })}
              />
            </div>
          </div>
          <DialogFooter>
            <Button type="submit">Salvar</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
