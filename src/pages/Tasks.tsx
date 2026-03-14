import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Checkbox } from '@/components/ui/checkbox'
import useLegalStore from '@/stores/useLegalStore'

export default function Tasks() {
  const { state, updateTask } = useLegalStore()
  const pending = state.tasks.filter((t) => !t.completed)
  const completed = state.tasks.filter((t) => t.completed)

  return (
    <div className="space-y-6 max-w-4xl">
      <div>
        <h1 className="text-3xl font-bold tracking-tight text-slate-800 dark:text-slate-100">
          Tarefas
        </h1>
        <p className="text-muted-foreground mt-1">Sua lista de pendências diárias.</p>
      </div>

      <Card className="shadow-sm">
        <CardHeader>
          <CardTitle>Pendentes ({pending.length})</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {pending.map((task) => (
            <div
              key={task.id}
              className="flex items-center space-x-3 bg-slate-50 p-3 rounded-lg border"
            >
              <Checkbox
                id={task.id}
                checked={task.completed}
                onCheckedChange={(c) => updateTask(task.id, !!c)}
                className="h-5 w-5"
              />
              <div className="grid gap-1.5 leading-none">
                <label
                  htmlFor={task.id}
                  className="text-sm font-medium leading-none cursor-pointer"
                >
                  {task.title}
                </label>
                <p className="text-xs font-semibold text-amber-600">Vence: {task.dueDate}</p>
              </div>
            </div>
          ))}
          {pending.length === 0 && (
            <p className="text-muted-foreground">Nenhuma tarefa pendente!</p>
          )}
        </CardContent>
      </Card>

      <Card className="shadow-sm opacity-70">
        <CardHeader>
          <CardTitle>Concluídas ({completed.length})</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          {completed.map((task) => (
            <div key={task.id} className="flex items-center space-x-3 p-2">
              <Checkbox
                id={task.id}
                checked={task.completed}
                onCheckedChange={(c) => updateTask(task.id, !!c)}
                className="h-5 w-5"
              />
              <span className="text-sm text-muted-foreground line-through">{task.title}</span>
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  )
}
