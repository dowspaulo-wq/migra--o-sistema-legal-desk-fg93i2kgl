import { useEffect, useState, useCallback } from 'react'
import {
  Database,
  Download,
  RefreshCw,
  Clock,
  CheckCircle2,
  AlertCircle,
  HardDrive,
  Calendar,
  Save,
  FileCode,
  FileJson,
  FileSpreadsheet,
  Layers,
  ArrowDownToLine,
  Info,
} from 'lucide-react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { toast } from '@/hooks/use-toast'
import useLegalStore from '@/stores/useLegalStore'
import { supabase } from '@/lib/supabase/client'

interface BackupLog {
  id: string
  file_name: string
  format: string
  file_size_bytes: number
  tables_included: string[]
  total_records: number
  status: string
  error_message: string | null
  trigger_type: string
  created_at: string
}

interface BackupScheduleConfig {
  frequency: 'daily' | 'weekly' | 'monthly'
  time: string
  dayOfWeek?: string
  generateSql: boolean
  generateJson: boolean
  generateXlsx: boolean
  enabled: boolean
  lastSavedAt?: string
}

const STORAGE_KEY_SCHEDULE = 'sbjur_backup_schedule_config'

export default function Backups() {
  const { state } = useLegalStore()
  const [logs, setLogs] = useState<BackupLog[]>([])
  const [loadingLogs, setLoadingLogs] = useState<boolean>(true)
  const [triggeringBackup, setTriggeringBackup] = useState<boolean>(false)
  const [downloadingFile, setDownloadingFile] = useState<string | null>(null)

  // Scheduling State
  const [schedule, setSchedule] = useState<BackupScheduleConfig>(() => {
    try {
      const saved = localStorage.getItem(STORAGE_KEY_SCHEDULE)
      if (saved) {
        return JSON.parse(saved)
      }
    } catch (e) {
      console.error('Falha ao carregar configuração de agendamento:', e)
    }
    return {
      frequency: 'daily',
      time: '03:00',
      dayOfWeek: '1',
      generateSql: true,
      generateJson: true,
      generateXlsx: true,
      enabled: true,
    }
  })
  const [savingSchedule, setSavingSchedule] = useState<boolean>(false)

  const isAdmin = ['Admin', 'ADM', 'admin'].includes(state.currentUser?.role || '')

  const fetchBackupLogs = useCallback(async () => {
    try {
      setLoadingLogs(true)
      const { data, error } = await supabase
        .from('backup_logs')
        .select('*')
        .order('created_at', { ascending: false })

      if (error) {
        throw error
      }
      setLogs((data as BackupLog[]) || [])
    } catch (error: any) {
      console.error('Erro ao buscar logs de backup:', error)
      toast({
        title: 'Erro ao carregar histórico',
        description: error?.message || 'Não foi possível carregar os registros de backup.',
        variant: 'destructive',
      })
    } finally {
      setLoadingLogs(false)
    }
  }, [])

  useEffect(() => {
    if (isAdmin) {
      fetchBackupLogs()
    }
  }, [isAdmin, fetchBackupLogs])

  const handleManualBackup = async () => {
    try {
      setTriggeringBackup(true)
      toast({
        title: 'Iniciando backup...',
        description: 'Extraindo dados e gerando arquivos de segurança.',
      })

      const { data, error } = await supabase.functions.invoke('database-backup', {
        body: {
          triggerType: 'manual',
          generateSql: schedule.generateSql ?? true,
          generateJson: schedule.generateJson ?? true,
          generateXlsx: schedule.generateXlsx ?? true,
        },
      })

      if (error) {
        throw error
      }

      const totalRecs = data?.total_records ?? 'N/A'
      const uploadedCount = data?.uploaded_files?.length ?? 0

      toast({
        title: 'Backup concluído com sucesso!',
        description: `${uploadedCount} arquivo(s) gerado(s) com ${totalRecs} registros salvos no bucket.`,
      })

      // Recarregar lista de logs
      await fetchBackupLogs()
    } catch (err: any) {
      console.error('Erro ao acionar backup manual:', err)
      toast({
        title: 'Falha ao realizar backup',
        description: err?.message || 'Ocorreu um erro durante a execução da rotina de backup.',
        variant: 'destructive',
      })
    } finally {
      setTriggeringBackup(false)
    }
  }

  const handleDownloadBackup = async (fileName: string) => {
    try {
      setDownloadingFile(fileName)
      const { data, error } = await supabase.storage.from('backups').download(fileName)

      if (error) {
        throw error
      }

      if (data) {
        const url = URL.createObjectURL(data)
        const a = document.createElement('a')
        a.href = url
        a.download = fileName
        document.body.appendChild(a)
        a.click()
        document.body.removeChild(a)
        URL.revokeObjectURL(url)

        toast({
          title: 'Download iniciado',
          description: `Arquivo ${fileName} baixado com sucesso.`,
        })
      }
    } catch (err: any) {
      console.error('Erro ao baixar arquivo de backup:', err)
      toast({
        title: 'Falha no download',
        description:
          err?.message || 'Não foi possível baixar o arquivo do bucket de armazenamento.',
        variant: 'destructive',
      })
    } finally {
      setDownloadingFile(null)
    }
  }

  const handleSaveSchedule = () => {
    try {
      setSavingSchedule(true)
      const updated = {
        ...schedule,
        lastSavedAt: new Date().toISOString(),
      }
      localStorage.setItem(STORAGE_KEY_SCHEDULE, JSON.stringify(updated))
      setSchedule(updated)

      toast({
        title: 'Agendamento salvo com sucesso!',
        description: `Rotina configurada para frequência ${
          schedule.frequency === 'daily'
            ? 'diária'
            : schedule.frequency === 'weekly'
              ? 'semanal'
              : 'mensal'
        } às ${schedule.time}.`,
      })
    } catch (err: any) {
      toast({
        title: 'Erro ao salvar preferências',
        description: err?.message || 'Falha ao gravar no armazenamento local.',
        variant: 'destructive',
      })
    } finally {
      setSavingSchedule(false)
    }
  }

  const formatFileSize = (bytes: number) => {
    if (!bytes || bytes === 0) return '0 B'
    const k = 1024
    const sizes = ['B', 'KB', 'MB', 'GB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
  }

  const formatDateTime = (dateStr: string) => {
    if (!dateStr) return '--'
    const date = new Date(dateStr)
    if (isNaN(date.getTime())) return '--'
    return date.toLocaleString('pt-BR', {
      timeZone: 'America/Sao_Paulo',
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    })
  }

  if (!isAdmin) {
    return (
      <div className="p-8 text-center text-destructive font-bold">
        Acesso negado. Apenas administradores podem gerenciar backups do banco de dados.
      </div>
    )
  }

  const completedCount = logs.filter((l) => l.status === 'completed').length
  const failedCount = logs.filter((l) => l.status === 'failed').length
  const lastBackup = logs.length > 0 ? logs[0] : null

  return (
    <div className="space-y-6 pb-12">
      {/* Top Header */}
      <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight flex items-center gap-2">
            <Database className="h-8 w-8 text-primary" />
            Backups do Banco de Dados
          </h1>
          <p className="text-muted-foreground mt-1">
            Gestão de cópias de segurança integrais, histórico de snapshots e rotinas automáticas.
          </p>
        </div>

        <div className="flex items-center gap-3">
          <Button
            variant="outline"
            onClick={fetchBackupLogs}
            disabled={loadingLogs || triggeringBackup}
            className="flex items-center gap-2"
          >
            <RefreshCw className={`h-4 w-4 ${loadingLogs ? 'animate-spin' : ''}`} />
            Atualizar
          </Button>

          <Button
            onClick={handleManualBackup}
            disabled={triggeringBackup}
            className="flex items-center gap-2 shadow-sm font-semibold"
          >
            {triggeringBackup ? (
              <>
                <RefreshCw className="h-4 w-4 animate-spin" />
                Gerando Backup...
              </>
            ) : (
              <>
                <HardDrive className="h-4 w-4" />
                Fazer backup agora
              </>
            )}
          </Button>
        </div>
      </div>

      {/* Overview Metric Cards */}
      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Último Backup Realizado</CardTitle>
            <Clock className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-xl font-bold">
              {lastBackup ? formatDateTime(lastBackup.created_at) : 'Nenhum registro'}
            </div>
            <p className="text-xs text-muted-foreground mt-1">
              {lastBackup
                ? `${lastBackup.file_name} (${formatFileSize(lastBackup.file_size_bytes)})`
                : 'Execute o primeiro backup acima'}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Backups com Sucesso</CardTitle>
            <CheckCircle2 className="h-4 w-4 text-emerald-500" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-emerald-600">{completedCount}</div>
            <p className="text-xs text-muted-foreground mt-1">
              Disponíveis no armazenamento seguro (Bucket `backups`)
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Falhas Registradas</CardTitle>
            <AlertCircle className="h-4 w-4 text-destructive" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-destructive">{failedCount}</div>
            <p className="text-xs text-muted-foreground mt-1">
              Política de retenção: 7 dias de snapshots
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Section: Programar Backups Automáticos */}
      <Card>
        <CardHeader>
          <div className="flex items-center gap-2">
            <Calendar className="h-5 w-5 text-primary" />
            <CardTitle>Programação de Backups Automáticos</CardTitle>
          </div>
          <CardDescription>
            Defina a frequência e o horário de preferência para a rotina periódica de cópias de
            segurança.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid gap-6 md:grid-cols-3 items-end">
            <div className="space-y-2">
              <Label htmlFor="frequency-select">Frequência</Label>
              <Select
                value={schedule.frequency}
                onValueChange={(val: 'daily' | 'weekly' | 'monthly') =>
                  setSchedule((prev) => ({ ...prev, frequency: val }))
                }
              >
                <SelectTrigger id="frequency-select">
                  <SelectValue placeholder="Selecione a frequência" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="daily">Diária (Todos os dias)</SelectItem>
                  <SelectItem value="weekly">Semanal (Uma vez por semana)</SelectItem>
                  <SelectItem value="monthly">Mensal (Primeiro dia do mês)</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label htmlFor="time-input">Horário de Execução (Horário de Brasília)</Label>
              <Input
                id="time-input"
                type="time"
                value={schedule.time}
                onChange={(e) =>
                  setSchedule((prev) => ({ ...prev, time: e.target.value || '03:00' }))
                }
              />
            </div>

            <div className="flex items-center gap-3">
              <Button
                onClick={handleSaveSchedule}
                disabled={savingSchedule}
                className="w-full flex items-center justify-center gap-2"
              >
                <Save className="h-4 w-4" />
                Salvar Programação
              </Button>
            </div>
          </div>

          <div className="mt-4 flex items-center gap-2 text-xs text-muted-foreground bg-muted/50 p-3 rounded-lg border">
            <Info className="h-4 w-4 text-primary shrink-0" />
            <span>
              Configuração atual:{' '}
              <strong className="text-foreground">
                Frequência{' '}
                {schedule.frequency === 'daily'
                  ? 'Diária'
                  : schedule.frequency === 'weekly'
                    ? 'Semanal'
                    : 'Mensal'}
              </strong>{' '}
              às <strong className="text-foreground">{schedule.time}</strong> (Formatos: JSON, SQL e
              Excel XLSX).
              {schedule.lastSavedAt && (
                <span className="ml-2">
                  (Última alteração salva em: {formatDateTime(schedule.lastSavedAt)})
                </span>
              )}
            </span>
          </div>
        </CardContent>
      </Card>

      {/* Section: Histórico de Backups Realizados */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <div>
            <div className="flex items-center gap-2">
              <Layers className="h-5 w-5 text-primary" />
              <CardTitle>Histórico de Backups</CardTitle>
            </div>
            <CardDescription className="mt-1">
              Registros da tabela{' '}
              <code className="text-xs bg-muted px-1 py-0.5 rounded">backup_logs</code> com dados de
              cada snapshot gerado.
            </CardDescription>
          </div>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Data / Hora</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Nome do Arquivo</TableHead>
                <TableHead>Formato</TableHead>
                <TableHead>Tamanho</TableHead>
                <TableHead>Registros</TableHead>
                <TableHead>Tipo</TableHead>
                <TableHead className="text-right">Ação</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {loadingLogs ? (
                <TableRow>
                  <TableCell colSpan={8} className="text-center py-10 text-muted-foreground">
                    <div className="flex items-center justify-center gap-2">
                      <RefreshCw className="h-4 w-4 animate-spin text-primary" />
                      Carregando histórico de backups...
                    </div>
                  </TableCell>
                </TableRow>
              ) : logs.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={8} className="text-center py-10 text-muted-foreground">
                    <div className="max-w-md mx-auto space-y-2">
                      <p className="font-medium text-foreground">Nenhum backup encontrado</p>
                      <p className="text-xs">
                        Clique em <strong>"Fazer backup agora"</strong> para gerar a primeira cópia
                        de segurança completa das tabelas do sistema.
                      </p>
                    </div>
                  </TableCell>
                </TableRow>
              ) : (
                logs.map((log) => {
                  const isCompleted = log.status === 'completed'
                  const isDownloading = downloadingFile === log.file_name

                  return (
                    <TableRow key={log.id}>
                      <TableCell className="font-medium whitespace-nowrap text-xs">
                        {formatDateTime(log.created_at)}
                      </TableCell>

                      <TableCell>
                        {isCompleted ? (
                          <Badge
                            variant="secondary"
                            className="bg-emerald-100 text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300 gap-1 border-0"
                          >
                            <CheckCircle2 className="h-3 w-3" />
                            Concluído
                          </Badge>
                        ) : (
                          <Badge
                            variant="destructive"
                            className="gap-1"
                            title={log.error_message || 'Erro durante a execução'}
                          >
                            <AlertCircle className="h-3 w-3" />
                            Falha
                          </Badge>
                        )}
                      </TableCell>

                      <TableCell
                        className="font-mono text-xs max-w-[220px] truncate"
                        title={log.file_name}
                      >
                        {log.file_name}
                      </TableCell>

                      <TableCell>
                        <Badge variant="outline" className="text-xs uppercase font-mono">
                          {log.format?.toLowerCase() === 'json' ? (
                            <span className="flex items-center gap-1">
                              <FileJson className="h-3 w-3 text-amber-500" />
                              JSON
                            </span>
                          ) : log.format?.toLowerCase() === 'sql' ? (
                            <span className="flex items-center gap-1">
                              <FileCode className="h-3 w-3 text-blue-500" />
                              SQL
                            </span>
                          ) : log.format?.toLowerCase() === 'xlsx' ||
                            log.format?.toLowerCase() === 'excel' ? (
                            <span className="flex items-center gap-1">
                              <FileSpreadsheet className="h-3 w-3 text-emerald-600" />
                              XLSX
                            </span>
                          ) : (
                            log.format || 'N/A'
                          )}
                        </Badge>
                      </TableCell>

                      <TableCell className="text-xs text-muted-foreground whitespace-nowrap">
                        {formatFileSize(log.file_size_bytes)}
                      </TableCell>

                      <TableCell className="text-xs font-semibold">
                        {log.total_records > 0 ? log.total_records.toLocaleString('pt-BR') : '--'}
                      </TableCell>

                      <TableCell>
                        <Badge
                          variant="secondary"
                          className="text-[10px] tracking-wide uppercase font-medium"
                        >
                          {log.trigger_type === 'manual' ? 'Manual' : 'Automático'}
                        </Badge>
                      </TableCell>

                      <TableCell className="text-right">
                        {isCompleted && log.file_name && log.file_name !== 'failed_backup' ? (
                          <Button
                            size="sm"
                            variant="ghost"
                            className="h-8 px-2 text-xs flex items-center gap-1 ml-auto"
                            disabled={isDownloading}
                            onClick={() => handleDownloadBackup(log.file_name)}
                          >
                            {isDownloading ? (
                              <RefreshCw className="h-3.5 w-3.5 animate-spin" />
                            ) : (
                              <ArrowDownToLine className="h-3.5 w-3.5 text-primary" />
                            )}
                            <span>Baixar</span>
                          </Button>
                        ) : (
                          <span className="text-xs text-muted-foreground">--</span>
                        )}
                      </TableCell>
                    </TableRow>
                  )
                })
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  )
}
