import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Switch } from '@/components/ui/switch'
import { Label } from '@/components/ui/label'
import { Input } from '@/components/ui/input'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Download, Shield, Users, Sliders, Palette, Trash2, Plus } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'

function EditableList({
  title,
  items,
  onSave,
}: {
  title: string
  items: string[]
  onSave: (newItems: string[]) => void
}) {
  const [val, setVal] = useState('')
  const add = () => {
    if (val && !items.includes(val)) {
      onSave([...items, val])
      setVal('')
    }
  }
  const remove = (item: string) => onSave(items.filter((i) => i !== item))
  return (
    <Card className="shadow-sm">
      <CardHeader className="py-4">
        <CardTitle className="text-sm">{title}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex gap-2">
          <Input
            value={val}
            onChange={(e) => setVal(e.target.value)}
            placeholder="Nova opção..."
            className="h-8"
          />
          <Button size="sm" onClick={add}>
            <Plus className="h-4 w-4" />
          </Button>
        </div>
        <div className="flex flex-wrap gap-2">
          {items.map((i) => (
            <div
              key={i}
              className="flex items-center gap-1 bg-muted px-2 py-1 rounded text-sm border"
            >
              <span>{i}</span>
              <Trash2 className="h-3 w-3 text-red-500 cursor-pointer" onClick={() => remove(i)} />
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  )
}

export default function Settings() {
  const { state, updateItem, updateUser, addLog } = useLegalStore()

  if (state.currentUser.role !== 'Admin') {
    return (
      <div className="p-8 text-center text-destructive font-bold">
        Acesso negado. Apenas Administradores.
      </div>
    )
  }

  const s = state.settings

  return (
    <div className="space-y-6 max-w-5xl">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Configurações do Sistema</h1>
        <p className="text-muted-foreground">Personalização, Opções, Backup e Acessos.</p>
      </div>

      <Tabs defaultValue="options" className="w-full">
        <TabsList className="mb-4">
          <TabsTrigger value="options">
            <Sliders className="h-4 w-4 mr-2" /> Opções Globais
          </TabsTrigger>
          <TabsTrigger value="users">
            <Users className="h-4 w-4 mr-2" /> Usuários & Permissões
          </TabsTrigger>
          <TabsTrigger value="general">
            <Shield className="h-4 w-4 mr-2" /> Avançado
          </TabsTrigger>
        </TabsList>

        <TabsContent value="options" className="grid md:grid-cols-2 gap-4">
          <EditableList
            title="Status de Processos"
            items={s.caseStatuses || []}
            onSave={(items) => updateItem('settings', s.id, { caseStatuses: items })}
          />
          <EditableList
            title="Tipos de Processos"
            items={s.caseTypes || []}
            onSave={(items) => updateItem('settings', s.id, { caseTypes: items })}
          />
          <EditableList
            title="Tipos de Compromissos"
            items={s.appointmentTypes || []}
            onSave={(items) => updateItem('settings', s.id, { appointmentTypes: items })}
          />
          <EditableList
            title="Status de Tarefas"
            items={s.taskStatuses || []}
            onSave={(items) => updateItem('settings', s.id, { taskStatuses: items })}
          />
        </TabsContent>

        <TabsContent value="users">
          <Card>
            <CardHeader>
              <CardTitle>Gestão de Colaboradores</CardTitle>
              <CardDescription>
                Defina nível de acesso, financeiro e cor de identificação.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Nome</TableHead>
                    <TableHead>Nível</TableHead>
                    <TableHead>Financeiro</TableHead>
                    <TableHead>Cor Identidade</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {state.users.map((u) => (
                    <TableRow key={u.id}>
                      <TableCell className="font-medium">{u.name}</TableCell>
                      <TableCell>
                        <select
                          className="border rounded p-1 text-sm bg-white"
                          value={u.role}
                          onChange={(e) =>
                            updateUser(u.id, { role: e.target.value as 'Admin' | 'User' })
                          }
                          disabled={u.id === state.currentUser.id}
                        >
                          <option value="Admin">Admin</option>
                          <option value="User">Colaborador</option>
                        </select>
                      </TableCell>
                      <TableCell>
                        <Switch
                          checked={u.canViewFinance}
                          onCheckedChange={(v) => updateUser(u.id, { canViewFinance: v })}
                          disabled={u.id === state.currentUser.id}
                        />
                      </TableCell>
                      <TableCell>
                        <div className="flex items-center gap-2">
                          <input
                            type="color"
                            value={u.color || '#3b82f6'}
                            onChange={(e) => updateUser(u.id, { color: e.target.value })}
                            className="h-8 w-8 rounded cursor-pointer border-0 p-0"
                          />
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="general" className="space-y-6">
          <Card>
            <CardHeader>
              <CardTitle>Preferências Globais</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex items-center justify-between border-b pb-4">
                <div className="space-y-0.5">
                  <Label className="text-base">Exibir Financeiro no Dashboard</Label>
                  <p className="text-sm text-muted-foreground">
                    Visível apenas para quem tem permissão.
                  </p>
                </div>
                <Switch
                  checked={s.showFinanceDashboard}
                  onCheckedChange={(v) => updateItem('settings', s.id, { showFinanceDashboard: v })}
                />
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle>Segurança e Backup</CardTitle>
            </CardHeader>
            <CardContent>
              <Button
                onClick={() => {
                  addLog('Exportar', 'Backup', 'Backup JSON')
                  toast({ title: 'Sucesso', description: 'Download iniciado' })
                }}
                variant="outline"
              >
                <Download className="mr-2 h-4 w-4" /> Exportar Dados (JSON)
              </Button>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  )
}
