import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Switch } from '@/components/ui/switch'
import { Label } from '@/components/ui/label'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Download, Shield, Users, Save } from 'lucide-react'
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

export default function Settings() {
  const { state, updateItem, updateUser, addLog } = useLegalStore()

  const handleBackup = (format: string) => {
    addLog('Exportar', 'Backup', `Backup gerado em formato ${format}`)
    toast({ title: 'Backup Gerado', description: `Arquivo ${format} baixado com sucesso.` })
  }

  if (state.currentUser.role !== 'Admin') {
    return (
      <div className="p-8 text-center text-destructive font-bold">
        Acesso negado. Apenas Administradores.
      </div>
    )
  }

  return (
    <div className="space-y-6 max-w-5xl">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Configurações do Sistema</h1>
        <p className="text-muted-foreground">Personalização, Backup e Gestão de Acessos.</p>
      </div>

      <Tabs defaultValue="general" className="w-full">
        <TabsList className="mb-4">
          <TabsTrigger value="general">
            <Shield className="h-4 w-4 mr-2" /> Geral
          </TabsTrigger>
          <TabsTrigger value="users">
            <Users className="h-4 w-4 mr-2" /> Controle de Usuários (RBAC)
          </TabsTrigger>
        </TabsList>

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
                    Visível apenas para quem tem permissão financeira.
                  </p>
                </div>
                <Switch
                  checked={state.settings.showFinanceDashboard}
                  onCheckedChange={(v) =>
                    updateItem('settings', state.settings.id, { showFinanceDashboard: v })
                  }
                />
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Segurança e Backup</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="flex gap-4">
                <Button onClick={() => handleBackup('JSON')} variant="outline">
                  <Download className="mr-2 h-4 w-4" /> Exportar Dados (JSON)
                </Button>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="users">
          <Card>
            <CardHeader>
              <CardTitle>Gestão de Permissões</CardTitle>
              <CardDescription>
                Defina o nível de acesso de cada colaborador ao sistema e ao financeiro.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Nome do Colaborador</TableHead>
                    <TableHead>Nível (Role)</TableHead>
                    <TableHead>Acesso ao Financeiro</TableHead>
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
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  )
}
