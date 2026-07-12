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

  useEffect(() => {
    if (open && data) {
      setFormData({
        id: data.id,
        title: data.title || '',
        description: data.description || '',
        dueDate: data.dueDate || '',
        status: data.status || 'Pendente',
        priority: data.priority || 'Média',
        responsibleId: data.responsibleId || '',
        relatedProcessId: data.relatedProcessId || '',
        type: data.type || 'Outro',
        clientId: data.clientId || '',
        internalNotes: data.internalNotes || '',
        isNew: data.isNew || false,
      })
    }
  }, [open, data])

  const handleSave = () => {
    const { isNew, ...payload } = formData
    if (payload.clientId === 'none') payload.clientId = null
    if (payload.relatedProcessId === 'none') payload.relatedProcessId = null
    onSave(payload)
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
            <Label>Título</Label>
            <Input
              value={formData.title}
              onChange={(e) => setFormData({ ...formData, title: e.target.value })}
            />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>Data de Vencimento</Label>
              <Input
                type="date"
                value={formData.dueDate}
                onChange={(e) => setFormData({ ...formData, dueDate: e.target.value })}
              />
            </div>
            <div className="space-y-2">
              <Label>Prioridade</Label>
              <Select
                value={formData.priority}
                onValueChange={(v) => setFormData({ ...formData, priority: v })}
              >
                <SelectTrigger>
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
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>Status</Label>
              <Select
                value={formData.status}
                onValueChange={(v) => setFormData({ ...formData, status: v })}
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
                <SelectTrigger>
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
            </div>
            <div className="space-y-2">
              <Label>Tipo</Label>
              <Select
                value={formData.type}
                onValueChange={(v) => setFormData({ ...formData, type: v })}
              >
                <SelectTrigger>
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
            </div>
          </div>

          <div className="space-y-2">
            <Label>Responsável</Label>
            <Select
              value={formData.responsibleId}
              onValueChange={(v) => setFormData({ ...formData, responsibleId: v })}
            >
              <SelectTrigger>
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
          </div>

          <div className="space-y-2">
            <Label>Cliente Relacionado</Label>
            <Select
              value={formData.clientId || 'none'}
              onValueChange={(v) => setFormData({ ...formData, clientId: v })}
              disabled={!!data?.lockedClientId}
            >
              <SelectTrigger>
                <SelectValue placeholder="Selecione um cliente..." />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="none">Sem Cliente</SelectItem>
                {clients?.map((c: any) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label>Processo Relacionado</Label>
            <Select
              value={formData.relatedProcessId || 'none'}
              onValueChange={(v) => setFormData({ ...formData, relatedProcessId: v })}
              disabled={!!data?.lockedProcessId}
            >
              <SelectTrigger>
                <SelectValue placeholder="Selecione um processo..." />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="none">Sem Processo</SelectItem>
                {cases?.map((c: any) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.number}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label>Descrição</Label>
            <RichTextEditor
              value={formData.description || ''}
              onChange={(v) => setFormData({ ...formData, description: v })}
              className="min-h-[120px]"
            />
          </div>
        </div>

        <DialogFooter className="flex justify-between w-full sm:justify-between">
          {!formData.isNew && onDelete ? (
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
            <Button variant="outline" onClick={() => onOpenChange(false)}>
              Cancelar
            </Button>
            <Button onClick={handleSave}>Salvar</Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
