import { useState, useEffect } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Check } from 'lucide-react'
import { RichTextEditor } from '@/components/RichTextEditor'

const TASK_DRAFT_KEY = 'task_draft'

const loadDraft = (): Partial<any> | null => {
  try {
    const raw = localStorage.getItem(TASK_DRAFT_KEY)
    return raw ? JSON.parse(raw) : null
  } catch {
    return null
  }
}

const saveDraft = (data: any) => {
  try {
    localStorage.setItem(TASK_DRAFT_KEY, JSON.stringify(data))
  } catch {
    /* intentionally ignored */
  }
}

const clearDraft = () => {
  try {
    localStorage.removeItem(TASK_DRAFT_KEY)
  } catch {
    /* intentionally ignored */
  }
}

export function TaskDialog({
  open,
  onOpenChange,
  data,
  onSave,
  onDelete,
  users,
  currentUser,
  clients,
  cases,
  settings,
}: any) {
  const [formData, setFormData] = useState<any>({})
  const [errors, setErrors] = useState<Record<string, string>>({})
  const [submitAttempted, setSubmitAttempted] = useState(false)

  useEffect(() => {
    if (open && data) {
      setErrors({})
      setSubmitAttempted(false)
      if (data.isNew) {
        const draft = loadDraft()
        if (draft) {
          setFormData({
            id: undefined,
            title: draft.title || '',
            description: draft.description || '',
            dueDate: draft.dueDate || '',
            status: 'Pendente',
            priority: draft.priority || 'Baixa',
            responsibleId: draft.responsibleId || '',
            relatedProcessId: data.lockedProcessId || draft.relatedProcessId || '',
            type: draft.type || 'Outro',
            clientId: data.lockedClientId || draft.clientId || '',
            internalNotes: draft.internalNotes || '',
            isNew: true,
          })
          return
        }
      }
      setFormData({
        id: data.id,
        title: data.title || '',
        description: data.description || '',
        dueDate: data.dueDate || '',
        status: data.status || 'Pendente',
        priority: data.priority || 'Baixa',
        responsibleId: data.responsibleId || '',
        relatedProcessId: data.relatedProcessId || '',
        type: data.type || 'Outro',
        clientId: data.clientId || '',
        internalNotes: data.internalNotes || '',
        isNew: data.isNew || false,
      })
    }
  }, [open, data])

  useEffect(() => {
    if (open && formData.isNew && formData.title !== undefined) {
      saveDraft({
        title: formData.title,
        description: formData.description,
        dueDate: formData.dueDate,
        priority: formData.priority,
        responsibleId: formData.responsibleId,
        relatedProcessId: formData.relatedProcessId,
        type: formData.type,
        clientId: formData.clientId,
        internalNotes: formData.internalNotes,
      })
    }
  }, [formData, open])

  const validateFields = (current: any) => {
    const errs: Record<string, string> = {}
    if (!current.title || !current.title.trim()) {
      errs.title = 'Título é obrigatório.'
    }
    if (!current.dueDate || !current.dueDate.trim()) {
      errs.dueDate = 'Data de vencimento é obrigatória.'
    }
    if (!current.priority || !current.priority.trim()) {
      errs.priority = 'Prioridade é obrigatória.'
    }
    if (!current.status || !current.status.trim()) {
      errs.status = 'Status é obrigatório.'
    }
    if (!current.type || !current.type.trim()) {
      errs.type = 'Tipo de tarefa é obrigatório.'
    }
    if (!current.responsibleId || !current.responsibleId.trim()) {
      errs.responsibleId = 'Responsável é obrigatório.'
    }
    if (!current.clientId || current.clientId === 'none' || !String(current.clientId).trim()) {
      errs.clientId = 'Cliente relacionado é obrigatório.'
    }
    if (
      !current.relatedProcessId ||
      current.relatedProcessId === 'none' ||
      !String(current.relatedProcessId).trim()
    ) {
      errs.relatedProcessId = 'Processo relacionado é obrigatório.'
    }
    return errs
  }

  const handleFieldChange = (field: string, value: any) => {
    const updated = { ...formData, [field]: value }
    setFormData(updated)
    if (submitAttempted) {
      setErrors(validateFields(updated))
    }
  }

  const handleSave = () => {
    setSubmitAttempted(true)
    const errs = validateFields(formData)
    setErrors(errs)
    if (Object.keys(errs).length > 0) {
      return
    }

    const { isNew, ...payload } = formData
    if (payload.clientId === 'none') payload.clientId = null
    if (payload.relatedProcessId === 'none') payload.relatedProcessId = null
    if (isNew) clearDraft()
    onSave(payload)
    onOpenChange(false)
  }

  const handleCancel = () => {
    if (formData.isNew) clearDraft()
    onOpenChange(false)
  }

  const isCompleted = formData.status === 'Concluído'

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{formData.isNew ? 'Nova Tarefa' : 'Editar Tarefa'}</DialogTitle>
        </DialogHeader>

        <div className="grid gap-4 py-4">
          {!formData.isNew && (
            <div className="flex justify-between items-center bg-slate-50 p-3 rounded-md border">
              <span className="text-sm font-medium text-slate-700">Status da Tarefa</span>
              {(() => {
                const respUser = users?.find((u: any) => u.id === formData.responsibleId)
                const isColaborador = currentUser?.role?.toLowerCase() === 'colaborador'
                const isRespAdmin = respUser?.role?.toLowerCase() === 'admin'
                const canComplete = !(isColaborador && isRespAdmin)

                if (!canComplete && !isCompleted) {
                  return (
                    <div className="text-sm text-red-600 font-medium">
                      Colaboradores não podem concluir tarefas de Administradores.
                    </div>
                  )
                }

                return (
                  <Button
                    variant={isCompleted ? 'default' : 'outline'}
                    className={isCompleted ? 'bg-green-600 hover:bg-green-700 text-white' : ''}
                    onClick={() =>
                      setFormData((prev: any) => ({
                        ...prev,
                        status: isCompleted ? 'Pendente' : 'Concluído',
                      }))
                    }
                  >
                    <Check className="h-4 w-4 mr-2" />
                    {isCompleted ? 'Concluída' : 'Marcar como Concluída'}
                  </Button>
                )
              })()}
            </div>
          )}

          <div className="space-y-2">
            <Label className="flex items-center gap-1 font-medium">
              Título <span className="text-red-500 font-bold">*</span>
            </Label>
            <Input
              value={formData.title}
              onChange={(e) => handleFieldChange('title', e.target.value)}
              className={errors.title ? 'border-red-500 focus-visible:ring-red-500' : ''}
              placeholder="Digite o título da tarefa..."
            />
            {errors.title && <p className="text-xs text-red-500 font-medium">{errors.title}</p>}
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label className="flex items-center gap-1 font-medium">
                Data de Vencimento <span className="text-red-500 font-bold">*</span>
              </Label>
              <Input
                type="date"
                value={formData.dueDate}
                onChange={(e) => handleFieldChange('dueDate', e.target.value)}
                className={errors.dueDate ? 'border-red-500 focus-visible:ring-red-500' : ''}
              />
              {errors.dueDate && (
                <p className="text-xs text-red-500 font-medium">{errors.dueDate}</p>
              )}
            </div>
            <div className="space-y-2">
              <Label className="flex items-center gap-1 font-medium">
                Prioridade <span className="text-red-500 font-bold">*</span>
              </Label>
              <Select
                value={formData.priority}
                onValueChange={(v) => handleFieldChange('priority', v)}
              >
                <SelectTrigger
                  className={errors.priority ? 'border-red-500 focus-visible:ring-red-500' : ''}
                >
                  <SelectValue placeholder="Selecione..." />
                </SelectTrigger>
                <SelectContent>
                  {['Baixa', 'Média', 'Alta', 'Urgente'].map((p) => (
                    <SelectItem key={p} value={p}>
                      {p}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {errors.priority && (
                <p className="text-xs text-red-500 font-medium">{errors.priority}</p>
              )}
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label className="flex items-center gap-1 font-medium">
                Status <span className="text-red-500 font-bold">*</span>
              </Label>
              <Select
                value={formData.status}
                onValueChange={(v) => handleFieldChange('status', v)}
                disabled={
                  isCompleted ||
                  (() => {
                    const respUser = users?.find((u: any) => u.id === formData.responsibleId)
                    const isColaborador = currentUser?.role?.toLowerCase() === 'colaborador'
                    const isRespAdmin = respUser?.role?.toLowerCase() === 'admin'
                    return isColaborador && isRespAdmin
                  })()
                }
              >
                <SelectTrigger
                  className={errors.status ? 'border-red-500 focus-visible:ring-red-500' : ''}
                >
                  <SelectValue placeholder="Selecione..." />
                </SelectTrigger>
                <SelectContent>
                  {(settings?.taskStatuses || ['Pendente', 'Em andamento', 'Atrasada'])
                    .filter((s: string) => s !== 'Concluído')
                    .map((s: string) => (
                      <SelectItem key={s} value={s}>
                        {s}
                      </SelectItem>
                    ))}
                  {isCompleted && <SelectItem value="Concluído">Concluído</SelectItem>}
                </SelectContent>
              </Select>
              {errors.status && <p className="text-xs text-red-500 font-medium">{errors.status}</p>}
            </div>
            <div className="space-y-2">
              <Label className="flex items-center gap-1 font-medium">
                Tipo <span className="text-red-500 font-bold">*</span>
              </Label>
              <Select value={formData.type} onValueChange={(v) => handleFieldChange('type', v)}>
                <SelectTrigger
                  className={errors.type ? 'border-red-500 focus-visible:ring-red-500' : ''}
                >
                  <SelectValue placeholder="Selecione..." />
                </SelectTrigger>
                <SelectContent>
                  {(settings?.taskTypes || ['Outro']).map((t: string) => (
                    <SelectItem key={t} value={t}>
                      {t}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {errors.type && <p className="text-xs text-red-500 font-medium">{errors.type}</p>}
            </div>
          </div>

          <div className="space-y-2">
            <Label className="flex items-center gap-1 font-medium">
              Responsável <span className="text-red-500 font-bold">*</span>
            </Label>
            <Select
              value={formData.responsibleId}
              onValueChange={(v) => handleFieldChange('responsibleId', v)}
            >
              <SelectTrigger
                className={errors.responsibleId ? 'border-red-500 focus-visible:ring-red-500' : ''}
              >
                <SelectValue placeholder="Selecione..." />
              </SelectTrigger>
              <SelectContent>
                {users?.map((u: any) => (
                  <SelectItem key={u.id} value={u.id}>
                    {u.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {errors.responsibleId && (
              <p className="text-xs text-red-500 font-medium">{errors.responsibleId}</p>
            )}
          </div>

          <div className="space-y-2">
            <Label className="flex items-center gap-1 font-medium">
              Cliente Relacionado <span className="text-red-500 font-bold">*</span>
            </Label>
            <Select
              value={formData.clientId || 'none'}
              onValueChange={(v) => {
                const nextClient = v === 'none' ? '' : v
                const updated: any = { ...formData, clientId: nextClient }
                // Se o processo atual não pertencer ao novo cliente, limpa
                if (updated.relatedProcessId) {
                  const currCase = cases?.find((c: any) => c.id === updated.relatedProcessId)
                  if (currCase && currCase.clientId !== nextClient) {
                    updated.relatedProcessId = ''
                  }
                }
                setFormData(updated)
                if (submitAttempted) {
                  setErrors(validateFields(updated))
                }
              }}
              disabled={!!data?.lockedClientId}
            >
              <SelectTrigger
                className={errors.clientId ? 'border-red-500 focus-visible:ring-red-500' : ''}
              >
                <SelectValue placeholder="Selecione um cliente..." />
              </SelectTrigger>
              <SelectContent>
                {clients?.map((c: any) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {errors.clientId && (
              <p className="text-xs text-red-500 font-medium">{errors.clientId}</p>
            )}
          </div>

          <div className="space-y-2">
            <Label className="flex items-center gap-1 font-medium">
              Processo Relacionado <span className="text-red-500 font-bold">*</span>
            </Label>
            <Select
              value={formData.relatedProcessId || 'none'}
              onValueChange={(v) => {
                const nextProcess = v === 'none' ? '' : v
                const updated: any = { ...formData, relatedProcessId: nextProcess }
                if (nextProcess && (!updated.clientId || updated.clientId === 'none')) {
                  const selCase = cases?.find((c: any) => c.id === nextProcess)
                  if (selCase?.clientId) {
                    updated.clientId = selCase.clientId
                  }
                }
                setFormData(updated)
                if (submitAttempted) {
                  setErrors(validateFields(updated))
                }
              }}
              disabled={!!data?.lockedProcessId}
            >
              <SelectTrigger
                className={
                  errors.relatedProcessId ? 'border-red-500 focus-visible:ring-red-500' : ''
                }
              >
                <SelectValue placeholder="Selecione um processo..." />
              </SelectTrigger>
              <SelectContent>
                {(formData.clientId && formData.clientId !== 'none'
                  ? cases?.filter((c: any) => c.clientId === formData.clientId)
                  : cases
                )?.map((c: any) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.number}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {errors.relatedProcessId && (
              <p className="text-xs text-red-500 font-medium">{errors.relatedProcessId}</p>
            )}
          </div>

          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <Label className="font-medium">Descrição</Label>
              <span className="text-xs text-muted-foreground font-normal">(Opcional)</span>
            </div>
            <RichTextEditor
              value={formData.description || ''}
              onChange={(v) => handleFieldChange('description', v)}
              className="min-h-[120px]"
            />
          </div>
        </div>

        <DialogFooter className="flex justify-between w-full sm:justify-between">
          {!formData.isNew && onDelete && currentUser?.role === 'Admin' ? (
            <Button
              variant="destructive"
              onClick={() => {
                if (confirm('Deseja realmente excluir esta tarefa?')) {
                  onDelete(formData.id)
                  onOpenChange(false)
                }
              }}
            >
              Excluir
            </Button>
          ) : (
            <div />
          )}
          <div className="flex gap-2">
            <Button variant="outline" onClick={handleCancel}>
              Cancelar
            </Button>
            <Button onClick={handleSave}>Salvar</Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
