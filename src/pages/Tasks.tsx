import { useState } from 'react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Plus, Trash, Edit } from 'lucide-react'
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
import useLegalStore from '@/stores/useLegalStore'

export default function Tasks() {
  const { state, updateItem, deleteItem, addTask } = useLegalStore()
  const [open, setOpen] = useState(false)
  const [editingId, setEditingId] = useState<string | null>(null)

  const initialFd = {
    title: '',
    description: '',
    dueDate: new Date().toISOString().split('T')[0],
    status: 'Pendente',
    priority: 'Média',
    responsibleId: state.currentUser.id,
  }
  const [fd, setFd] = useState(initialFd)

  const handleOpen = (t?: any) => {
    if (t) {
      setFd(t)
      setEditingId(t.id)
    } else {
      setFd(initialFd)
      setEditingId(null)
    }
    setOpen(true)
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (editingId) updateItem('tasks', editingId, fd)
    else addTask(fd)
    setOpen(false)
  }

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Tarefas</h1>
          <p className="text-muted-foreground">Controle de atividades.</p>
        </div>
        <Button onClick={() => handleOpen()}>
          <Plus className="mr-2 h-4 w-4" /> Nova Tarefa
        </Button>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            <DialogHeader>
              <DialogTitle>{editingId ? 'Editar' : 'Nova'} Tarefa</DialogTitle>
            </DialogHeader>
            <div className="space-y-2">
              <Label>Título *</Label>
              <Input
                required
                value={fd.title}
                onChange={(e) => setFd({ ...fd, title: e.target.value })}
              />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Vencimento</Label>
                <Input
                  type="date"
                  value={fd.dueDate}
                  onChange={(e) => setFd({ ...fd, dueDate: e.target.value })}
                />
              </div>
              <div className="space-y-2">
                <Label>Prioridade</Label>
                <Select value={fd.priority} onValueChange={(v) => setFd({ ...fd, priority: v })}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Baixa">Baixa</SelectItem>
                    <SelectItem value="Média">Média</SelectItem>
                    <SelectItem value="Alta">Alta</SelectItem>
                    <SelectItem value="Urgente">Urgente</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
            <div className="space-y-2">
              <Label>Status</Label>
              <Select value={fd.status} onValueChange={(v) => setFd({ ...fd, status: v })}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Pendente">Pendente</SelectItem>
                  <SelectItem value="Em andamento">Em andamento</SelectItem>
                  <SelectItem value="Aguarda protocolo">Aguarda protocolo</SelectItem>
                  <SelectItem value="Concluída">Concluída</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <DialogFooter>
              <Button type="submit">Salvar</Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      <div className="grid gap-3">
        {state.tasks.map((t) => (
          <Card
            key={t.id}
            className={`shadow-sm border-l-4 ${t.status === 'Concluída' ? 'opacity-60 border-l-green-500' : 'border-l-primary'}`}
          >
            <CardContent className="p-4 flex items-center justify-between gap-4">
              <div className="flex items-center gap-4">
                <input
                  type="checkbox"
                  className="h-5 w-5 rounded border-slate-300"
                  checked={t.status === 'Concluída'}
                  onChange={() =>
                    updateItem('tasks', t.id, {
                      status: t.status === 'Concluída' ? 'Pendente' : 'Concluída',
                    })
                  }
                />
                <div>
                  <p className={`font-semibold ${t.status === 'Concluída' ? 'line-through' : ''}`}>
                    {t.title}
                  </p>
                  <div className="flex gap-2 text-xs mt-1 items-center">
                    <Badge className="text-[10px]">{t.priority}</Badge>
                    <Badge variant="outline" className="text-[10px]">
                      {t.status}
                    </Badge>
                    <span className="text-muted-foreground ml-2">Vence: {t.dueDate}</span>
                  </div>
                </div>
              </div>
              <div className="flex gap-2">
                <Button variant="ghost" size="icon" onClick={() => handleOpen(t)}>
                  <Edit className="h-4 w-4" />
                </Button>
                {state.currentUser.role === 'Admin' && (
                  <Button
                    variant="ghost"
                    size="icon"
                    className="text-red-500"
                    onClick={() => deleteItem('tasks', t.id)}
                  >
                    <Trash className="h-4 w-4" />
                  </Button>
                )}
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  )
}
