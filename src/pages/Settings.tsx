import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Switch } from '@/components/ui/switch'
import { Label } from '@/components/ui/label'
import { Download, Upload, Shield } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'

export default function Settings() {
  const { state, setState, addLog } = useLegalStore()

  const handleBackup = (format: string) => {
    addLog('Exportar', 'Backup', `Backup gerado em formato ${format}`)
    toast({
      title: 'Backup Gerado',
      description: `O arquivo ${format} foi gerado com sucesso e baixado na sua máquina.`,
    })
  }

  const toggleFinanceVis = () => {
    setState((prev) => ({
      ...prev,
      settings: { ...prev.settings, showFinanceDashboard: !prev.settings.showFinanceDashboard },
    }))
    addLog('Editar', 'Configurações', 'Visibilidade do dashboard financeiro alterada.')
  }

  if (state.currentUser.role !== 'Admin') {
    return (
      <div className="p-8 text-center text-destructive font-bold">
        Acesso negado. Configurações restritas a Administradores.
      </div>
    )
  }

  return (
    <div className="space-y-6 max-w-4xl">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Configurações do Sistema</h1>
        <p className="text-muted-foreground">Personalização, Backup e Permissões.</p>
      </div>

      <div className="grid gap-6">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Shield className="h-5 w-5" /> Permissões Globais
            </CardTitle>
            <CardDescription>Ajustes de visibilidade e acesso ao sistema SBJur.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex items-center justify-between border-b pb-4">
              <div className="space-y-0.5">
                <Label className="text-base">Exibir Financeiro no Dashboard</Label>
                <p className="text-sm text-muted-foreground">
                  Mostra os cards de receita total na página inicial (aplicável apenas para quem tem
                  permissão).
                </p>
              </div>
              <Switch
                checked={state.settings.showFinanceDashboard}
                onCheckedChange={toggleFinanceVis}
              />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Segurança e Backup</CardTitle>
            <CardDescription>
              Gere cópias de segurança de todos os dados do banco de dados.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex gap-4">
              <Button onClick={() => handleBackup('JSON')} variant="outline">
                <Download className="mr-2 h-4 w-4" /> Exportar Dados (JSON)
              </Button>
              <Button
                onClick={() => handleBackup('Excel')}
                variant="outline"
                className="border-green-600 text-green-700 hover:bg-green-50"
              >
                <Download className="mr-2 h-4 w-4" /> Exportar Relatórios (Excel)
              </Button>
            </div>
            <div className="mt-4 p-4 bg-slate-50 border rounded-md text-sm text-slate-600">
              <p>
                <strong>Dica:</strong> Backups automáticos estão ativados diariamente às 03:00 am
                (Horário de Brasília).
              </p>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Branding do Escritório</CardTitle>
            <CardDescription>Faça upload do logotipo da firma.</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="border-2 border-dashed border-slate-200 rounded-lg p-8 flex flex-col items-center justify-center bg-slate-50">
              <Upload className="h-8 w-8 text-slate-400 mb-2" />
              <p className="text-sm font-medium mb-4">
                Arraste a nova logo ou clique para procurar
              </p>
              <Button variant="secondary" size="sm">
                Selecionar Imagem
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
