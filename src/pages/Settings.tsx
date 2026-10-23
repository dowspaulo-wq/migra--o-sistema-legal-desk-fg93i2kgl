import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Switch } from '@/components/ui/switch'
import { Badge } from '@/components/ui/badge'
import { Label } from '@/components/ui/label'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import {
  Download,
  Shield,
  Users,
  Sliders,
  Trash2,
  Plus,
  UserCircle,
  Edit2,
  Check,
  X,
  Wallet,
  Link2,
  Eye,
  EyeOff,
  ExternalLink,
  Calendar,
  RefreshCw,
  LogOut,
  FileSpreadsheet,
} from 'lucide-react'
import { FinancialEntitiesTab } from '@/components/FinancialEntitiesTab'
import { SystemManagement } from '@/components/SystemManagement'
import { OnboardingSettingsTab } from '@/components/OnboardingSettingsTab'
import { AutomationSettingsTab } from '@/components/AutomationSettingsTab'
import { UserCheck, Zap } from 'lucide-react'
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
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import {
  Form,
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormMessage,
  FormDescription,
} from '@/components/ui/form'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import * as z from 'zod'
import { supabase } from '@/lib/supabase/client'

const userSchema = z.object({
  name: z.string().min(2, 'Nome é obrigatório'),
  email: z.string().email('E-mail inválido'),
  password: z.string().min(6, 'A senha deve ter no mínimo 6 caracteres'),
  role: z.enum(['Admin', 'User']),
  canViewFinance: z.boolean(),
  color: z.string(),
})

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
      const newItems = [...items, val].sort((a, b) => a.localeCompare(b))
      onSave(newItems)
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
            onKeyDown={(e) => e.key === 'Enter' && add()}
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

function EditableColorList({ title, items, onSave, onRename }: any) {
  const [val, setVal] = useState('')
  const [color, setColor] = useState('#3b82f6')
  const [editingItem, setEditingItem] = useState<any>(null)

  const getFallbackColor = (label: string) => {
    const lower = label.toLowerCase()
    if (lower === 'em andamento') return '#22c55e'
    if (lower === 'concluído' || lower === 'concluido') return '#f1f5f9'
    if (lower === 'suspenso') return '#eab308'
    if (lower === 'aguardando documentos') return '#ef4444'
    if (lower === 'pendente') return '#f97316'
    return '#3b82f6'
  }

  const normalized = items.map((i: any) =>
    typeof i === 'string' ? { label: i, color: getFallbackColor(i) } : i,
  )

  const addOrSave = () => {
    if (!val) return
    if (editingItem) {
      if (normalized.some((i: any) => i.label === val && i.label !== editingItem.label)) {
        toast({ title: 'Erro', description: 'Opção já existe', variant: 'destructive' })
        return
      }
      const newItems = normalized.map((i: any) =>
        i.label === editingItem.label ? { label: val, color } : i,
      )
      onSave(newItems)
      if (onRename && editingItem.label !== val) {
        onRename(editingItem.label, val)
      }
      setEditingItem(null)
      setVal('')
      setColor('#3b82f6')
    } else {
      if (!normalized.some((i: any) => i.label === val)) {
        const newItems = [...normalized, { label: val, color }].sort((a, b) =>
          a.label.localeCompare(b.label),
        )
        onSave(newItems)
        setVal('')
        setColor('#3b82f6')
      }
    }
  }

  const remove = (label: string) => onSave(normalized.filter((i: any) => i.label !== label))

  const startEdit = (item: any) => {
    setEditingItem(item)
    setVal(item.label)
    setColor(item.color || '#3b82f6')
  }

  const cancelEdit = () => {
    setEditingItem(null)
    setVal('')
    setColor('#3b82f6')
  }

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
            placeholder={editingItem ? 'Editar opção...' : 'Nova opção...'}
            className="flex-1 h-9"
            onKeyDown={(e) => e.key === 'Enter' && addOrSave()}
          />
          <Input
            type="color"
            value={color}
            onChange={(e) => setColor(e.target.value)}
            className="w-12 h-9 p-0.5 cursor-pointer border-0 rounded bg-transparent"
          />
          {editingItem ? (
            <>
              <Button
                size="sm"
                onClick={addOrSave}
                className="h-9 w-9 p-0 bg-green-600 hover:bg-green-700 text-white"
              >
                <Check className="h-4 w-4" />
              </Button>
              <Button size="sm" variant="outline" onClick={cancelEdit} className="h-9 w-9 p-0">
                <X className="h-4 w-4" />
              </Button>
            </>
          ) : (
            <Button size="sm" onClick={addOrSave} className="h-9 w-9 p-0">
              <Plus className="h-4 w-4" />
            </Button>
          )}
        </div>
        <div className="flex flex-wrap gap-2">
          {normalized.map((i: any) => {
            const isLight =
              i.color.toLowerCase() === '#f1f5f9' || i.color.toLowerCase() === '#ffffff'
            return (
              <div
                key={i.label}
                className="flex items-center gap-2 px-2 py-1 rounded text-sm border font-medium group"
                style={{
                  backgroundColor: i.color,
                  borderColor: isLight ? '#e2e8f0' : i.color,
                  color: isLight ? '#333' : '#fff',
                }}
              >
                <span>{i.label}</span>
                <div className="flex items-center gap-1 opacity-50 md:opacity-0 group-hover:opacity-100 transition-opacity">
                  <Edit2
                    className="h-3 w-3 cursor-pointer hover:scale-110 transition-transform"
                    onClick={() => startEdit(i)}
                  />
                  <Trash2
                    className="h-3 w-3 cursor-pointer hover:scale-110 transition-transform text-red-500 hover:text-red-600"
                    onClick={() => remove(i.label)}
                  />
                </div>
              </div>
            )
          })}
        </div>
      </CardContent>
    </Card>
  )
}

export default function Settings() {
  const { state, updateItem, updateUser, addLog, addUser, renameType } = useLegalStore()
  const [isCreateOpen, setIsCreateOpen] = useState(false)
  const [isSubmitting, setIsSubmitting] = useState(false)

  const form = useForm<z.infer<typeof userSchema>>({
    resolver: zodResolver(userSchema),
    defaultValues: {
      name: '',
      email: '',
      password: '',
      role: 'User',
      canViewFinance: false,
      color: '#3b82f6',
    },
  })

  const isAdmin = state.currentUser.role === 'Admin'
  const s = state.settings

  const [asaasApiKeyInput, setAsaasApiKeyInput] = useState(s.asaasApiKey || '')
  const [asaasApiUrlInput, setAsaasApiUrlInput] = useState(
    s.asaasApiUrl || 'https://api.asaas.com/v3',
  )
  const [showAsaasKey, setShowAsaasKey] = useState(false)
  const [isSavingAsaas, setIsSavingAsaas] = useState(false)

  // Google Calendar Integration states
  const [googleClientIdInput, setGoogleClientIdInput] = useState(s.googleClientId || '')
  const [googleClientSecretInput, setGoogleClientSecretInput] = useState(s.googleClientSecret || '')
  const [showGoogleSecret, setShowGoogleSecret] = useState(false)
  const [isSavingGoogle, setIsSavingGoogle] = useState(false)
  const [isConnectingGoogle, setIsConnectingGoogle] = useState(false)

  // Google Sheets Mirror states
  const [googleServiceAccountInput, setGoogleServiceAccountInput] = useState(
    s.googleServiceAccount || '',
  )
  const [showServiceAccountJson, setShowServiceAccountJson] = useState(false)
  const [isSavingServiceAccount, setIsSavingServiceAccount] = useState(false)
  const [isSyncingSheets, setIsSyncingSheets] = useState(false)
  const [sheetsSyncResult, setSheetsSyncResult] = useState<any | null>(null)

  // Sincroniza se os settings carregarem depois
  const currentApiKeyInStore = s.asaasApiKey || ''
  const currentApiUrlInStore = s.asaasApiUrl || 'https://api.asaas.com/v3'
  if (asaasApiKeyInput === '' && currentApiKeyInStore !== '') {
    setAsaasApiKeyInput(currentApiKeyInStore)
  }
  if (
    asaasApiUrlInput === 'https://api.asaas.com/v3' &&
    currentApiUrlInStore !== 'https://api.asaas.com/v3'
  ) {
    setAsaasApiUrlInput(currentApiUrlInStore)
  }

  const currentGoogleClientId = s.googleClientId || ''
  const currentGoogleClientSecret = s.googleClientSecret || ''
  if (googleClientIdInput === '' && currentGoogleClientId !== '') {
    setGoogleClientIdInput(currentGoogleClientId)
  }
  if (googleClientSecretInput === '' && currentGoogleClientSecret !== '') {
    setGoogleClientSecretInput(currentGoogleClientSecret)
  }

  const currentGoogleServiceAccount = s.googleServiceAccount || ''
  if (googleServiceAccountInput === '' && currentGoogleServiceAccount !== '') {
    setGoogleServiceAccountInput(currentGoogleServiceAccount)
  }

  const handleSaveAsaas = async () => {
    setIsSavingAsaas(true)
    try {
      const cleanKey = asaasApiKeyInput.trim()
      const cleanUrl = asaasApiUrlInput.trim() || 'https://api.asaas.com/v3'

      await updateItem('settings', s.id, {
        asaasApiKey: cleanKey || null,
        asaasApiUrl: cleanUrl,
      })

      addLog('Atualizar', 'Configurações', 'Configurações de integração com Asaas atualizadas.')

      toast({
        title: 'Integração salva',
        description: cleanKey
          ? 'Chave da API do Asaas atualizada com sucesso!'
          : 'Configurações salvas (sem chave cadastrada).',
      })
    } catch (err: any) {
      const rawMsg = err?.message || err?.details || String(err)
      let userFriendlyMsg = rawMsg

      if (
        rawMsg.toLowerCase().includes('column') &&
        rawMsg.toLowerCase().includes('does not exist')
      ) {
        userFriendlyMsg =
          'A coluna da chave do Asaas ainda não foi criada no banco PostgreSQL do VPS. Execute o script "03-aplicar-migracao-asaas.sh" no terminal do VPS via SSH para criar as colunas necessárias na tabela settings.'
      } else if (
        rawMsg.toLowerCase().includes('permission denied') ||
        rawMsg.toLowerCase().includes('policy')
      ) {
        userFriendlyMsg =
          'Permissão negada ao atualizar as configurações. Verifique as políticas de RLS ou certifique-se de estar conectado com perfil Administrador.'
      }

      toast({
        title: 'Erro ao salvar credenciais do Asaas',
        description: userFriendlyMsg,
        variant: 'destructive',
      })
    } finally {
      setIsSavingAsaas(false)
    }
  }

  const handleSaveGoogle = async () => {
    setIsSavingGoogle(true)
    try {
      const cleanId = googleClientIdInput.trim()
      const cleanSecret = googleClientSecretInput.trim()

      await updateItem('settings', s.id, {
        googleClientId: cleanId || null,
        googleClientSecret: cleanSecret || null,
      })

      addLog('Atualizar', 'Configurações', 'Credenciais OAuth do Google Calendar atualizadas.')

      toast({
        title: 'Credenciais salvas',
        description: cleanId
          ? 'Client ID e Secret do Google salvos com sucesso!'
          : 'Configurações do Google salvas (sem credenciais cadastradas).',
      })
    } catch (err: any) {
      toast({
        title: 'Erro ao salvar credenciais do Google',
        description: err.message || 'Erro ao salvar configurações do Google',
        variant: 'destructive',
      })
    } finally {
      setIsSavingGoogle(false)
    }
  }

  const handleConnectGoogle = async () => {
    setIsConnectingGoogle(true)
    try {
      const redirectUri = `${window.location.origin}/google-callback`
      const currentClientId = googleClientIdInput.trim() || (s as any).googleClientId?.trim() || ''
      const currentClientSecret =
        googleClientSecretInput.trim() || (s as any).googleClientSecret?.trim() || ''

      // Verificação preventiva no frontend
      if (!currentClientId) {
        throw new Error(
          'Preencha e salve o Google Client ID no campo acima antes de conectar sua conta Google.',
        )
      }

      const headers: Record<string, string> = {}
      if (currentClientId) headers['x-google-client-id'] = currentClientId
      if (currentClientSecret) headers['x-google-client-secret'] = currentClientSecret

      const { data, error } = await supabase.functions.invoke('google-calendar', {
        body: {
          action: 'getAuthUrl',
          redirectUri,
          clientId: currentClientId || undefined,
          clientSecret: currentClientSecret || undefined,
        },
        headers,
      })

      if (error) {
        let errorMsg = error.message || 'Erro ao gerar URL de autorização'
        try {
          const ctx = (error as any).context
          if (ctx) {
            if (typeof ctx.json === 'function') {
              const body = await ctx.json().catch(() => null)
              if (body?.error) errorMsg = body.error
            } else if (typeof ctx.text === 'function') {
              const text = await ctx.text().catch(() => '')
              if (text) {
                try {
                  const parsed = JSON.parse(text)
                  if (parsed?.error) errorMsg = parsed.error
                } catch {
                  // mantém errorMsg
                }
              }
            }
          }
        } catch {
          // fallback
        }

        // Se ainda for a mensagem crua de non-2xx
        if (
          errorMsg.includes('non-2xx') ||
          errorMsg.includes('Edge Function returned a non-2xx status code')
        ) {
          // Fallback resiliente direto no cliente: constrói a URL oficial do Google OAuth
          // diretamente com o client_id configurado, sem depender da resposta do edge-runtime
          const scope = encodeURIComponent(
            'https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.readonly',
          )
          const directAuthUrl = `https://accounts.google.com/o/oauth2/v2/auth?client_id=${encodeURIComponent(
            currentClientId,
          )}&redirect_uri=${encodeURIComponent(
            redirectUri,
          )}&response_type=code&scope=${scope}&access_type=offline&prompt=consent`
          console.warn(
            'Edge function retornou non-2xx; usando fallback seguro direto de getAuthUrl com client_id da settings.',
          )
          window.location.href = directAuthUrl
          return
        }

        throw new Error(errorMsg)
      }

      if (data?.error) throw new Error(data.error)
      if (data?.url) {
        window.location.href = data.url
        return
      }

      // Se a função respondeu sem URL mas temos o Client ID salvo, redireciona via fallback seguro
      if (currentClientId) {
        const scope = encodeURIComponent(
          'https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.readonly',
        )
        const directAuthUrl = `https://accounts.google.com/o/oauth2/v2/auth?client_id=${encodeURIComponent(
          currentClientId,
        )}&redirect_uri=${encodeURIComponent(
          redirectUri,
        )}&response_type=code&scope=${scope}&access_type=offline&prompt=consent`
        window.location.href = directAuthUrl
        return
      }

      throw new Error('URL de autorização não retornada pelo Google.')
    } catch (err: any) {
      toast({
        title: 'Erro ao conectar Google Agenda',
        description:
          err.message ||
          'Verifique se o Client ID e Client Secret estão salvos acima antes de conectar.',
        variant: 'destructive',
      })
    } finally {
      setIsConnectingGoogle(false)
    }
  }

  const handleSaveGoogleServiceAccount = async () => {
    setIsSavingServiceAccount(true)
    try {
      const cleanJson = googleServiceAccountInput.trim()

      if (cleanJson) {
        try {
          const parsed = JSON.parse(cleanJson)
          if (!parsed.client_email || !parsed.private_key) {
            toast({
              title: 'Aviso sobre o JSON',
              description:
                'O JSON informado parece não conter os campos client_email e private_key típicos de uma Service Account do Google.',
              variant: 'destructive',
            })
          }
        } catch {
          toast({
            title: 'Formato inválido',
            description: 'O texto colado não é um JSON válido. Verifique se copiou todo o arquivo.',
            variant: 'destructive',
          })
          setIsSavingServiceAccount(false)
          return
        }
      }

      await updateItem('settings', s.id, {
        googleServiceAccount: cleanJson || null,
      })

      addLog('Atualizar', 'Configurações', 'Google Service Account (JSON) atualizada.')

      toast({
        title: 'Service Account salva',
        description: cleanJson
          ? 'JSON da Service Account salvo com sucesso!'
          : 'Service Account removida das configurações.',
      })
    } catch (err: any) {
      toast({
        title: 'Erro ao salvar Service Account',
        description: err.message || 'Erro ao salvar credenciais',
        variant: 'destructive',
      })
    } finally {
      setIsSavingServiceAccount(false)
    }
  }

  const handleTestSyncSheets = async () => {
    setIsSyncingSheets(true)
    setSheetsSyncResult(null)
    try {
      const { data, error } = await supabase.functions.invoke('sync-clients-sheets', {
        body: {},
      })

      if (error) {
        let msg = error.message || 'Falha ao acionar sincronização'
        try {
          const ctx = (error as any).context
          if (ctx && typeof ctx.json === 'function') {
            const body = await ctx.json().catch(() => null)
            if (body?.error || body?.message) msg = body.error || body.message
          }
        } catch {
          // ignore
        }
        throw new Error(msg)
      }

      if (!data?.success) {
        throw new Error(data?.message || data?.error || 'Erro na sincronização')
      }

      setSheetsSyncResult(data)
      toast({
        title: 'Sincronização concluída com sucesso!',
        description: `${data.totalProcessed ?? 0} clientes na base: +${data.inserted ?? 0} inseridos, ~${data.updated ?? 0} atualizados, -${data.removed ?? 0} removidos.`,
      })
    } catch (err: any) {
      toast({
        title: 'Erro no espelhamento do Sheets',
        description:
          err.message || 'Verifique as configurações da Service Account e permissões da planilha.',
        variant: 'destructive',
      })
    } finally {
      setIsSyncingSheets(false)
    }
  }

  const handleDisconnectGoogle = async () => {
    try {
      await updateItem('settings', s.id, { googleCalendarTokens: null })
      toast({
        title: 'Google Agenda desconectado',
        description:
          'Os tokens de acesso foram removidos. Você pode reconectar a qualquer momento.',
      })
      addLog('Atualizar', 'Configurações', 'Google Agenda desconectado do sistema.')
    } catch (err: any) {
      toast({
        title: 'Erro ao desconectar',
        description: err.message || 'Erro ao limpar tokens.',
        variant: 'destructive',
      })
    }
  }

  const handleAvatarUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return

    try {
      const fileExt = file.name.split('.').pop()
      const fileName = `${state.currentUser.id}-${Math.random()}.${fileExt}`

      const { error: uploadError } = await supabase.storage.from('avatars').upload(fileName, file)

      if (uploadError) throw uploadError

      const {
        data: { publicUrl },
      } = supabase.storage.from('avatars').getPublicUrl(fileName)

      await updateUser(state.currentUser.id, { avatar_url: publicUrl })
      toast({ title: 'Sucesso', description: 'Foto de perfil atualizada' })
    } catch (err: any) {
      toast({
        title: 'Erro',
        description: err.message || 'Erro ao enviar foto',
        variant: 'destructive',
      })
    }
  }

  const handleToggleUserActive = async (userItem: any) => {
    if (userItem.id === state.currentUser.id) {
      toast({
        title: 'Ação não permitida',
        description: 'Você não pode desativar seu próprio usuário.',
        variant: 'destructive',
      })
      return
    }

    const currentStatus = userItem.is_active !== false
    const newStatus = !currentStatus
    const statusLabel = newStatus ? 'ativado' : 'desativado'

    try {
      const { error } = await supabase
        .from('profiles')
        .update({ is_active: newStatus })
        .eq('id', userItem.id)

      if (error) throw new Error(error.message)
      updateUser(userItem.id, { is_active: newStatus })
      toast({
        title: 'Status atualizado',
        description: `Usuário ${userItem.name} foi ${statusLabel} com sucesso.`,
      })
      addLog(
        'Atualizar',
        'Usuário',
        `Usuário ${userItem.name} (${userItem.email}) foi ${statusLabel}.`,
      )
    } catch (err: any) {
      toast({
        title: 'Erro ao alterar status',
        description: err.message || 'Não foi possível alterar o status do usuário.',
        variant: 'destructive',
      })
    }
  }

  const handleUpdateUser = async (userId: string, updates: any) => {
    try {
      const { error } = await supabase.from('profiles').update(updates).eq('id', userId)
      if (error) throw new Error(error.message)
      updateUser(userId, updates)
      toast({ title: 'Sucesso', description: 'Usuário atualizado.' })
    } catch (err: any) {
      toast({
        title: 'Erro',
        description: err.message || 'Erro ao atualizar',
        variant: 'destructive',
      })
    }
  }

  const onSubmitUser = async (values: z.infer<typeof userSchema>) => {
    setIsSubmitting(true)
    try {
      const { data, error } = await supabase.functions.invoke('create-user', { body: values })
      if (error) throw new Error(error.message || 'Erro ao criar usuário')
      if (data?.error) throw new Error(data.error)

      toast({ title: 'Sucesso', description: 'Usuário criado com sucesso' })
      setIsCreateOpen(false)
      form.reset()

      const userId = data?.data?.user?.id
      if (userId) {
        const { data: profile } = await supabase
          .from('profiles')
          .select('*')
          .eq('id', userId)
          .single()
        if (profile) addUser(profile)
      }
      addLog('Criar', 'Usuário', `Usuário ${values.email} criado.`)
    } catch (err: any) {
      toast({ title: 'Erro', description: err.message, variant: 'destructive' })
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <div className="space-y-6 max-w-5xl">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Configurações</h1>
        <p className="text-muted-foreground">Personalização, Opções, Backup e Acessos.</p>
      </div>

      <Tabs defaultValue="profile" className="w-full">
        <TabsList className="mb-4">
          <TabsTrigger value="profile">
            <UserCircle className="h-4 w-4 mr-2" /> Meu Perfil
          </TabsTrigger>
          {isAdmin && (
            <>
              <TabsTrigger value="options">
                <Sliders className="h-4 w-4 mr-2" /> Opções Globais
              </TabsTrigger>
              <TabsTrigger value="onboarding">
                <UserCheck className="h-4 w-4 mr-2" /> Onboarding de Cliente
              </TabsTrigger>
              <TabsTrigger value="automacao">
                <Zap className="h-4 w-4 mr-2" /> Regras de Automação
              </TabsTrigger>
              <TabsTrigger value="financeiro">
                <Wallet className="h-4 w-4 mr-2" /> Financeiro
              </TabsTrigger>
              <TabsTrigger value="integracoes">
                <Link2 className="h-4 w-4 mr-2" /> Integrações
              </TabsTrigger>
              <TabsTrigger value="users">
                <Users className="h-4 w-4 mr-2" /> Usuários & Permissões
              </TabsTrigger>
              <TabsTrigger value="general">
                <Shield className="h-4 w-4 mr-2" /> Avançado
              </TabsTrigger>
              <TabsTrigger value="backup">
                <Download className="h-4 w-4 mr-2" /> Backup
              </TabsTrigger>
            </>
          )}
        </TabsList>

        <TabsContent value="profile" className="space-y-6">
          <Card>
            <CardHeader>
              <CardTitle>Meu Perfil</CardTitle>
              <CardDescription>Atualize sua foto de perfil.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex items-center gap-6">
                <div className="h-24 w-24 rounded-full overflow-hidden bg-muted border">
                  {state.currentUser.avatar_url ? (
                    <img
                      src={state.currentUser.avatar_url}
                      alt="Avatar"
                      className="h-full w-full object-cover"
                    />
                  ) : (
                    <UserCircle className="h-full w-full text-muted-foreground p-2" />
                  )}
                </div>
                <div>
                  <Label
                    htmlFor="avatar-upload"
                    className="cursor-pointer bg-primary text-primary-foreground hover:bg-primary/90 px-4 py-2 rounded-md text-sm font-medium inline-block"
                  >
                    Alterar Foto
                  </Label>
                  <Input
                    id="avatar-upload"
                    type="file"
                    accept="image/*"
                    className="hidden"
                    onChange={handleAvatarUpload}
                  />
                  <p className="text-xs text-muted-foreground mt-2">
                    Recomendado: 256x256px. Máx: 2MB.
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        {isAdmin && (
          <>
            <TabsContent value="options" className="grid md:grid-cols-2 gap-4">
              <EditableColorList
                title="Status de Processos (Com Cores)"
                items={s.caseStatuses || []}
                onSave={(items: any[]) => updateItem('settings', s.id, { caseStatuses: items })}
                onRename={(oldLabel: string, newLabel: string) =>
                  renameType('cases', 'status', oldLabel, newLabel)
                }
              />
              <EditableColorList
                title="Tipos de Processos (Com Cores)"
                items={s.caseTypes || []}
                onSave={(items: any[]) => updateItem('settings', s.id, { caseTypes: items })}
                onRename={(oldLabel: string, newLabel: string) =>
                  renameType('cases', 'type', oldLabel, newLabel)
                }
              />
              <EditableColorList
                title="Tipos de Agendamento (Com Cores)"
                items={s.appointmentTypes || []}
                onSave={(items: any[]) => updateItem('settings', s.id, { appointmentTypes: items })}
                onRename={(oldLabel: string, newLabel: string) =>
                  renameType('appointments', 'type', oldLabel, newLabel)
                }
              />
              <EditableList
                title="Tipos de Tarefas"
                items={s.taskTypes || []}
                onSave={(items) => updateItem('settings', s.id, { taskTypes: items })}
              />
              <EditableList
                title="Status de Tarefas"
                items={s.taskStatuses || []}
                onSave={(items) => updateItem('settings', s.id, { taskStatuses: items })}
              />
              <EditableList
                title="Fontes de Captação"
                items={s.captacaoOptions || []}
                onSave={(items) => updateItem('settings', s.id, { captacaoOptions: items })}
              />
              <EditableList
                title="Posições do Cliente"
                items={s.clientPositions || []}
                onSave={(items) => updateItem('settings', s.id, { clientPositions: items })}
              />
              <EditableColorList
                title="Subprocessos (Editar Nomes)"
                items={s.subprocessTypes || ['Recurso', 'Precatória', 'Incidente', 'Outros']}
                onSave={(items: any[]) => updateItem('settings', s.id, { subprocessTypes: items })}
                onRename={(oldLabel: string, newLabel: string) =>
                  renameType('cases', 'type', oldLabel, newLabel)
                }
              />
            </TabsContent>

            <TabsContent value="onboarding" className="space-y-6">
              <OnboardingSettingsTab />
            </TabsContent>

            <TabsContent value="automacao" className="space-y-6">
              <AutomationSettingsTab />
            </TabsContent>

            <TabsContent value="financeiro" className="space-y-6">
              <FinancialEntitiesTab />
            </TabsContent>

            <TabsContent value="integracoes" className="space-y-6">
              <Card className="shadow-sm border">
                <CardHeader>
                  <div className="flex items-center justify-between">
                    <div>
                      <CardTitle className="text-xl flex items-center gap-2">
                        <Link2 className="h-5 w-5 text-blue-600" />
                        Integração Asaas
                      </CardTitle>
                      <CardDescription className="mt-1">
                        Configure as credenciais da API do Asaas para cobranças, PIX/Boleto e
                        extrato de conciliação.
                      </CardDescription>
                    </div>
                    {s.asaasApiKey ? (
                      <Badge className="bg-emerald-600 hover:bg-emerald-600 text-white font-normal text-xs">
                        Configurada
                      </Badge>
                    ) : (
                      <Badge
                        variant="outline"
                        className="border-amber-400 text-amber-700 bg-amber-50 font-normal text-xs"
                      >
                        Chave ausente
                      </Badge>
                    )}
                  </div>
                </CardHeader>
                <CardContent className="space-y-6">
                  <div className="rounded-lg bg-blue-50/70 p-4 border border-blue-200 text-xs text-blue-900 space-y-1.5">
                    <p className="font-semibold text-sm text-blue-950">
                      Onde obter sua chave da API:
                    </p>
                    <p>
                      Acesse sua conta no{' '}
                      <a
                        href="https://www.asaas.com"
                        target="_blank"
                        rel="noreferrer"
                        className="underline font-semibold inline-flex items-center gap-1 hover:text-blue-700"
                      >
                        Asaas <ExternalLink className="h-3 w-3 inline" />
                      </a>{' '}
                      → <strong>Minha Conta</strong> → <strong>Configurações da Conta</strong> →{' '}
                      <strong>Integrações</strong> → <strong>Chaves de API</strong>.
                    </p>
                    <p className="text-blue-800">
                      Cole a chave abaixo. As chamadas do app aos serviços de sincronização e
                      extrato enviarão essa chave com segurança para as Edge Functions.
                    </p>
                  </div>

                  <div className="space-y-4">
                    <div className="space-y-2">
                      <Label htmlFor="asaas-api-key" className="text-sm font-semibold">
                        Chave da API do Asaas (API Key)
                      </Label>
                      <div className="relative">
                        <Input
                          id="asaas-api-key"
                          type={showAsaasKey ? 'text' : 'password'}
                          value={asaasApiKeyInput}
                          onChange={(e) => setAsaasApiKeyInput(e.target.value)}
                          placeholder="$aact_YTU5YTE0M2M6N2Z..."
                          className="pr-10 font-mono text-sm"
                          disabled={!isAdmin || isSavingAsaas}
                        />
                        <button
                          type="button"
                          onClick={() => setShowAsaasKey((prev) => !prev)}
                          className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                          title={showAsaasKey ? 'Ocultar chave' : 'Mostrar chave'}
                        >
                          {showAsaasKey ? (
                            <EyeOff className="h-4 w-4" />
                          ) : (
                            <Eye className="h-4 w-4" />
                          )}
                        </button>
                      </div>
                      <p className="text-xs text-muted-foreground">
                        A chave é salva de forma protegida no banco de dados e enviada apenas via
                        HTTPS aos serviços autorizados.
                      </p>
                    </div>

                    <div className="space-y-2">
                      <Label htmlFor="asaas-api-url" className="text-sm font-semibold">
                        URL da API do Asaas
                      </Label>
                      <Input
                        id="asaas-api-url"
                        type="text"
                        value={asaasApiUrlInput}
                        onChange={(e) => setAsaasApiUrlInput(e.target.value)}
                        placeholder="https://api.asaas.com/v3"
                        className="font-mono text-sm"
                        disabled={!isAdmin || isSavingAsaas}
                      />
                      <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                        <span>
                          Padrão produção:{' '}
                          <code className="bg-muted px-1.5 py-0.5 rounded font-mono">
                            https://api.asaas.com/v3
                          </code>
                        </span>
                        <span>•</span>
                        <span>
                          Sandbox/testes:{' '}
                          <code className="bg-muted px-1.5 py-0.5 rounded font-mono">
                            https://api-sandbox.asaas.com/v3
                          </code>
                        </span>
                      </div>
                    </div>

                    <div className="pt-2 flex justify-end">
                      <Button
                        onClick={handleSaveAsaas}
                        disabled={!isAdmin || isSavingAsaas}
                        className="bg-blue-600 hover:bg-blue-700"
                      >
                        {isSavingAsaas ? 'Salvando...' : 'Salvar Configurações do Asaas'}
                      </Button>
                    </div>
                  </div>
                </CardContent>
              </Card>

              {/* CARD GOOGLE CALENDAR */}
              <Card className="shadow-sm border">
                <CardHeader>
                  <div className="flex items-center justify-between">
                    <div>
                      <CardTitle className="text-xl flex items-center gap-2">
                        <Calendar className="h-5 w-5 text-primary" />
                        Google Agenda (Google Calendar)
                      </CardTitle>
                      <CardDescription className="mt-1">
                        Sincronização bidirecional entre os compromissos da Agenda DPSjur e a conta
                        Google.
                      </CardDescription>
                    </div>
                    {s.googleCalendarTokens ? (
                      <Badge className="bg-emerald-600 hover:bg-emerald-600 text-white font-normal text-xs">
                        Conta conectada
                      </Badge>
                    ) : (
                      <Badge
                        variant="outline"
                        className="border-amber-400 text-amber-700 bg-amber-50 font-normal text-xs"
                      >
                        Não conectada
                      </Badge>
                    )}
                  </div>
                </CardHeader>
                <CardContent className="space-y-6">
                  <div className="rounded-lg bg-amber-50/70 p-4 border border-amber-200 text-xs text-amber-950 space-y-1.5">
                    <p className="font-semibold text-sm text-amber-950">
                      Como funciona a sincronização do Google Agenda:
                    </p>
                    <p>
                      1. As credenciais do aplicativo OAuth (Client ID e Secret) podem ser salvas
                      diretamente abaixo ou no arquivo de variáveis de ambiente do EasyPanel.
                    </p>
                    <p>
                      2. Com as credenciais salvas, clique em{' '}
                      <strong>"Conectar Conta Google"</strong> abaixo ou no botão{' '}
                      <strong>"Sincronizar"</strong> na página da Agenda.
                    </p>
                    <p className="text-muted-foreground">
                      URI de redirecionamento configurada no Google Cloud Console:{' '}
                      <code className="bg-white/80 px-1 py-0.5 rounded font-mono text-xs border">
                        {typeof window !== 'undefined'
                          ? `${window.location.origin}/google-callback`
                          : 'https://sistema.advdouglaspsantos.com.br/google-callback'}
                      </code>
                    </p>
                  </div>

                  <div className="space-y-4">
                    <div className="space-y-2">
                      <Label htmlFor="google-client-id" className="text-sm font-semibold">
                        Google Client ID
                      </Label>
                      <Input
                        id="google-client-id"
                        type="text"
                        value={googleClientIdInput}
                        onChange={(e) => setGoogleClientIdInput(e.target.value)}
                        placeholder="Ex: 1234567890-abc...apps.googleusercontent.com"
                        className="font-mono text-sm"
                        disabled={!isAdmin || isSavingGoogle}
                      />
                    </div>

                    <div className="space-y-2">
                      <Label htmlFor="google-client-secret" className="text-sm font-semibold">
                        Google Client Secret
                      </Label>
                      <div className="relative">
                        <Input
                          id="google-client-secret"
                          type={showGoogleSecret ? 'text' : 'password'}
                          value={googleClientSecretInput}
                          onChange={(e) => setGoogleClientSecretInput(e.target.value)}
                          placeholder="Ex: GOCSPX-..."
                          className="pr-10 font-mono text-sm"
                          disabled={!isAdmin || isSavingGoogle}
                        />
                        <button
                          type="button"
                          onClick={() => setShowGoogleSecret((prev) => !prev)}
                          className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                          title={showGoogleSecret ? 'Ocultar secret' : 'Mostrar secret'}
                        >
                          {showGoogleSecret ? (
                            <EyeOff className="h-4 w-4" />
                          ) : (
                            <Eye className="h-4 w-4" />
                          )}
                        </button>
                      </div>
                    </div>

                    <div className="pt-2 flex flex-wrap items-center justify-between gap-2 border-t">
                      <div className="flex items-center gap-2">
                        {s.googleCalendarTokens ? (
                          <Button
                            variant="outline"
                            onClick={handleDisconnectGoogle}
                            disabled={!isAdmin}
                            className="text-red-600 border-red-200 hover:bg-red-50 hover:text-red-700"
                          >
                            <LogOut className="h-4 w-4 mr-2" />
                            Desconectar Conta Google
                          </Button>
                        ) : (
                          <Button
                            onClick={handleConnectGoogle}
                            disabled={!isAdmin || isConnectingGoogle}
                            className="bg-emerald-600 hover:bg-emerald-700 text-white"
                          >
                            {isConnectingGoogle ? (
                              <RefreshCw className="h-4 w-4 mr-2 animate-spin" />
                            ) : (
                              <Calendar className="h-4 w-4 mr-2" />
                            )}
                            Conectar Conta Google
                          </Button>
                        )}
                      </div>

                      <Button onClick={handleSaveGoogle} disabled={!isAdmin || isSavingGoogle}>
                        {isSavingGoogle ? 'Salvando...' : 'Salvar Credenciais do Google'}
                      </Button>
                    </div>
                  </div>
                </CardContent>
              </Card>

              {/* CARD GOOGLE SHEETS - ESPELHAMENTO DE CLIENTES */}
              <Card className="shadow-sm border">
                <CardHeader>
                  <div className="flex items-center justify-between">
                    <div>
                      <CardTitle className="text-xl flex items-center gap-2">
                        <FileSpreadsheet className="h-5 w-5 text-emerald-600" />
                        Espelhamento de Clientes (Google Sheets)
                      </CardTitle>
                      <CardDescription className="mt-1">
                        Sincronização diária (espelho completo) de todos os clientes com a planilha{' '}
                        <strong>Clientes DPS — lista Google Ads (Customer Match)</strong>.
                      </CardDescription>
                    </div>
                    {s.googleServiceAccount ? (
                      <Badge className="bg-emerald-600 hover:bg-emerald-600 text-white font-normal text-xs">
                        Service Account salva
                      </Badge>
                    ) : (
                      <Badge
                        variant="outline"
                        className="border-amber-400 text-amber-700 bg-amber-50 font-normal text-xs"
                      >
                        Service Account ausente
                      </Badge>
                    )}
                  </div>
                </CardHeader>
                <CardContent className="space-y-6">
                  <div className="rounded-lg bg-emerald-50/70 p-4 border border-emerald-200 text-xs text-emerald-950 space-y-2">
                    <p className="font-semibold text-sm text-emerald-950">
                      Como configurar o espelhamento automático:
                    </p>
                    <ol className="list-decimal list-inside space-y-1 text-emerald-900">
                      <li>
                        Acesse o <strong>Google Cloud Console</strong> e crie uma{' '}
                        <strong>Service Account</strong> no seu projeto.
                      </li>
                      <li>
                        Ative a <strong>Google Sheets API</strong> no Google Cloud.
                      </li>
                      <li>
                        Gere uma chave JSON para a Service Account (formato{' '}
                        <code>service_account.json</code>) e copie todo o conteúdo.
                      </li>
                      <li>
                        Abra a planilha Google Ads Customer Match no Google Sheets (ID:{' '}
                        <code className="bg-white/80 px-1 py-0.5 rounded font-mono text-xs border">
                          181rftkYO4nVnAVsc-mKuYjBqDsm-_YnoiGWtEqf2Ahw
                        </code>
                        ) e{' '}
                        <strong>
                          compartilhe com o e-mail da Service Account com permissão de Editor
                        </strong>
                        .
                      </li>
                      <li>
                        Cole o JSON completo abaixo e clique em{' '}
                        <strong>"Salvar Service Account"</strong>.
                      </li>
                    </ol>
                    <div className="pt-1 text-emerald-800">
                      <p>
                        <strong>Rotina diária:</strong> executada automaticamente todo dia às{' '}
                        <strong>06:00 (Brasília)</strong> via cron no VPS.
                      </p>
                      <p className="mt-0.5">
                        <strong>Regras de espelho:</strong> lê todos os clientes, normaliza e-mail
                        (minúsculo), aniversário (YYYY-MM-DD, vazio se inválido), telefone intacto e
                        realiza upsert por ID na aba <code>Página1</code>.
                      </p>
                    </div>
                  </div>

                  <div className="space-y-4">
                    <div className="space-y-2">
                      <div className="flex items-center justify-between">
                        <Label htmlFor="google-service-account" className="text-sm font-semibold">
                          Google Service Account (JSON)
                        </Label>
                        <button
                          type="button"
                          onClick={() => setShowServiceAccountJson((prev) => !prev)}
                          className="text-xs text-muted-foreground hover:text-foreground flex items-center gap-1"
                        >
                          {showServiceAccountJson ? (
                            <>
                              <EyeOff className="h-3.5 w-3.5" /> Ocultar JSON
                            </>
                          ) : (
                            <>
                              <Eye className="h-3.5 w-3.5" /> Exibir JSON
                            </>
                          )}
                        </button>
                      </div>
                      <Textarea
                        id="google-service-account"
                        value={googleServiceAccountInput}
                        onChange={(e) => setGoogleServiceAccountInput(e.target.value)}
                        placeholder={`{\n  "type": "service_account",\n  "project_id": "...",\n  "private_key_id": "...",\n  "private_key": "-----BEGIN PRIVATE KEY-----\\n...",\n  "client_email": "dpsjur-sheets@...iam.gserviceaccount.com",\n  ...\n}`}
                        rows={showServiceAccountJson ? 10 : 4}
                        className={`font-mono text-xs ${!showServiceAccountJson && googleServiceAccountInput ? 'blur-sm select-none' : ''}`}
                        disabled={!isAdmin || isSavingServiceAccount}
                      />
                      <p className="text-xs text-muted-foreground">
                        O JSON é armazenado de forma segura no banco de dados e usado exclusivamente
                        pela função de sincronização.
                      </p>
                    </div>

                    <div className="space-y-2 pt-2 border-t">
                      <Label className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                        Planilha Destino Vinculada
                      </Label>
                      <div className="flex items-center gap-2 p-2 rounded bg-muted/40 border text-xs font-mono break-all">
                        <span className="text-muted-foreground select-none">ID:</span>
                        <span>181rftkYO4nVnAVsc-mKuYjBqDsm-_YnoiGWtEqf2Ahw</span>
                        <a
                          href="https://docs.google.com/spreadsheets/d/181rftkYO4nVnAVsc-mKuYjBqDsm-_YnoiGWtEqf2Ahw"
                          target="_blank"
                          rel="noreferrer"
                          className="ml-auto underline text-emerald-700 hover:text-emerald-900 inline-flex items-center gap-1 shrink-0 font-sans font-medium"
                        >
                          Abrir Planilha <ExternalLink className="h-3 w-3" />
                        </a>
                      </div>
                    </div>

                    {sheetsSyncResult && (
                      <div className="rounded-lg bg-emerald-50 border border-emerald-200 p-3 text-xs text-emerald-950 space-y-1">
                        <p className="font-semibold text-emerald-900">
                          Última sincronização manual executada com sucesso:
                        </p>
                        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 pt-1 font-mono text-center">
                          <div className="bg-white/80 p-1.5 rounded border">
                            <div className="text-muted-foreground text-[10px]">TOTAL BASE</div>
                            <div className="font-bold text-sm">
                              {sheetsSyncResult.totalProcessed ?? 0}
                            </div>
                          </div>
                          <div className="bg-white/80 p-1.5 rounded border text-emerald-700">
                            <div className="text-muted-foreground text-[10px]">INSERIDOS</div>
                            <div className="font-bold text-sm">
                              +{sheetsSyncResult.inserted ?? 0}
                            </div>
                          </div>
                          <div className="bg-white/80 p-1.5 rounded border text-blue-700">
                            <div className="text-muted-foreground text-[10px]">ATUALIZADOS</div>
                            <div className="font-bold text-sm">
                              ~{sheetsSyncResult.updated ?? 0}
                            </div>
                          </div>
                          <div className="bg-white/80 p-1.5 rounded border text-amber-700">
                            <div className="text-muted-foreground text-[10px]">REMOVIDOS</div>
                            <div className="font-bold text-sm">
                              -{sheetsSyncResult.removed ?? 0}
                            </div>
                          </div>
                        </div>
                        {sheetsSyncResult.timestamp && (
                          <p className="text-[11px] text-emerald-800 text-right pt-1">
                            Executado em:{' '}
                            {new Date(sheetsSyncResult.timestamp).toLocaleString('pt-BR')}
                          </p>
                        )}
                      </div>
                    )}

                    <div className="pt-2 flex flex-wrap items-center justify-between gap-2 border-t">
                      <Button
                        type="button"
                        variant="outline"
                        onClick={handleTestSyncSheets}
                        disabled={!isAdmin || isSyncingSheets || !googleServiceAccountInput.trim()}
                        className="border-emerald-600 text-emerald-700 hover:bg-emerald-50"
                      >
                        {isSyncingSheets ? (
                          <>
                            <RefreshCw className="h-4 w-4 mr-2 animate-spin" />
                            Sincronizando agora...
                          </>
                        ) : (
                          <>
                            <RefreshCw className="h-4 w-4 mr-2" />
                            Sincronizar Planilha Agora
                          </>
                        )}
                      </Button>

                      <Button
                        onClick={handleSaveGoogleServiceAccount}
                        disabled={!isAdmin || isSavingServiceAccount}
                        className="bg-emerald-600 hover:bg-emerald-700 text-white"
                      >
                        {isSavingServiceAccount ? 'Salvando...' : 'Salvar Service Account'}
                      </Button>
                    </div>
                  </div>
                </CardContent>
              </Card>
            </TabsContent>

            <TabsContent value="users">
              <Card>
                <CardHeader className="flex flex-row items-center justify-between pb-2">
                  <div>
                    <CardTitle>Gestão de Colaboradores</CardTitle>
                    <CardDescription>
                      Defina nível de acesso, financeiro e cor de identificação. (Agenda é exclusiva
                      para Admins).
                    </CardDescription>
                  </div>
                  <Dialog open={isCreateOpen} onOpenChange={setIsCreateOpen}>
                    <DialogTrigger asChild>
                      <Button size="sm">
                        <Plus className="mr-2 h-4 w-4" /> Novo Usuário
                      </Button>
                    </DialogTrigger>
                    <DialogContent className="max-w-md">
                      <DialogHeader>
                        <DialogTitle>Adicionar Usuário</DialogTitle>
                      </DialogHeader>
                      <Form {...form}>
                        <form onSubmit={form.handleSubmit(onSubmitUser)} className="space-y-4">
                          <FormField
                            control={form.control}
                            name="name"
                            render={({ field }) => (
                              <FormItem>
                                <FormLabel>Nome Completo</FormLabel>
                                <FormControl>
                                  <Input {...field} />
                                </FormControl>
                                <FormMessage />
                              </FormItem>
                            )}
                          />
                          <FormField
                            control={form.control}
                            name="email"
                            render={({ field }) => (
                              <FormItem>
                                <FormLabel>E-mail</FormLabel>
                                <FormControl>
                                  <Input type="email" {...field} />
                                </FormControl>
                                <FormMessage />
                              </FormItem>
                            )}
                          />
                          <FormField
                            control={form.control}
                            name="password"
                            render={({ field }) => (
                              <FormItem>
                                <FormLabel>Senha</FormLabel>
                                <FormControl>
                                  <Input type="password" {...field} />
                                </FormControl>
                                <FormMessage />
                              </FormItem>
                            )}
                          />
                          <div className="grid grid-cols-2 gap-4">
                            <FormField
                              control={form.control}
                              name="role"
                              render={({ field }) => (
                                <FormItem>
                                  <FormLabel>Nível de Acesso</FormLabel>
                                  <Select onValueChange={field.onChange} defaultValue={field.value}>
                                    <FormControl>
                                      <SelectTrigger>
                                        <SelectValue placeholder="Selecione..." />
                                      </SelectTrigger>
                                    </FormControl>
                                    <SelectContent>
                                      <SelectItem value="User">Colaborador</SelectItem>
                                      <SelectItem value="Admin">Admin</SelectItem>
                                    </SelectContent>
                                  </Select>
                                  <FormMessage />
                                </FormItem>
                              )}
                            />
                            <FormField
                              control={form.control}
                              name="color"
                              render={({ field }) => (
                                <FormItem>
                                  <FormLabel>Cor</FormLabel>
                                  <FormControl>
                                    <div className="flex items-center gap-2">
                                      <Input
                                        type="color"
                                        className="h-10 w-14 p-1 cursor-pointer"
                                        {...field}
                                      />
                                    </div>
                                  </FormControl>
                                  <FormMessage />
                                </FormItem>
                              )}
                            />
                          </div>
                          <FormField
                            control={form.control}
                            name="canViewFinance"
                            render={({ field }) => (
                              <FormItem className="flex flex-row items-center justify-between rounded-lg border p-3 shadow-sm">
                                <div className="space-y-0.5">
                                  <FormLabel>Acesso ao Financeiro</FormLabel>
                                  <FormDescription>
                                    Permite visualizar a área financeira.
                                  </FormDescription>
                                </div>
                                <FormControl>
                                  <Switch checked={field.value} onCheckedChange={field.onChange} />
                                </FormControl>
                              </FormItem>
                            )}
                          />
                          <div className="flex flex-row items-center justify-between rounded-lg border p-3 shadow-sm opacity-60 bg-muted/50">
                            <div className="space-y-0.5">
                              <Label className="text-sm font-medium">Acesso à Agenda</Label>
                              <p className="text-sm text-muted-foreground">
                                Exclusivo para Administradores.
                              </p>
                            </div>
                            <Switch checked={form.watch('role') === 'Admin'} disabled />
                          </div>
                          <Button type="submit" className="w-full" disabled={isSubmitting}>
                            {isSubmitting ? 'Salvando...' : 'Salvar Usuário'}
                          </Button>
                        </form>
                      </Form>
                    </DialogContent>
                  </Dialog>
                </CardHeader>
                <CardContent>
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Status</TableHead>
                        <TableHead>Nome</TableHead>
                        <TableHead>E-mail</TableHead>
                        <TableHead>Nível</TableHead>
                        <TableHead>Financeiro</TableHead>
                        <TableHead>Agenda</TableHead>
                        <TableHead>Cor Identidade</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {(state.users as any[]).map((u) => {
                        const isActive = u.is_active !== false
                        const isSelf = u.id === state.currentUser.id
                        return (
                          <TableRow
                            key={u.id}
                            className={
                              !isActive
                                ? 'opacity-50 bg-muted/30 transition-opacity'
                                : 'transition-opacity'
                            }
                          >
                            <TableCell>
                              <div className="flex items-center gap-2">
                                <Switch
                                  checked={isActive}
                                  onCheckedChange={() => handleToggleUserActive(u)}
                                  disabled={isSelf}
                                  title={
                                    isSelf
                                      ? 'Você não pode desativar seu próprio usuário'
                                      : isActive
                                        ? 'Desativar usuário'
                                        : 'Ativar usuário'
                                  }
                                />
                                <Badge
                                  variant={isActive ? 'default' : 'secondary'}
                                  className={
                                    isActive
                                      ? 'bg-emerald-600 hover:bg-emerald-600 text-white font-normal text-xs'
                                      : 'bg-muted text-muted-foreground font-normal text-xs'
                                  }
                                >
                                  {isActive ? 'Ativo' : 'Inativo'}
                                </Badge>
                              </div>
                            </TableCell>
                            <TableCell className="font-medium">
                              <div className="flex items-center gap-2">
                                <span>{u.name}</span>
                                {isSelf && (
                                  <span className="text-xs text-muted-foreground font-normal">
                                    (você)
                                  </span>
                                )}
                              </div>
                            </TableCell>
                            <TableCell>{u.email || '—'}</TableCell>
                            <TableCell>
                              <select
                                className="border rounded p-1 text-sm bg-white"
                                value={u.role}
                                onChange={(e) =>
                                  handleUpdateUser(u.id, {
                                    role: e.target.value as 'Admin' | 'User',
                                  })
                                }
                                disabled={isSelf}
                              >
                                <option value="Admin">Admin</option>
                                <option value="User">Colaborador</option>
                              </select>
                            </TableCell>
                            <TableCell>
                              <Switch
                                checked={u.canViewFinance}
                                onCheckedChange={(v) =>
                                  handleUpdateUser(u.id, { canViewFinance: v })
                                }
                                disabled={isSelf}
                              />
                            </TableCell>
                            <TableCell>
                              <Switch checked={u.role === 'Admin'} disabled />
                            </TableCell>
                            <TableCell>
                              <div className="flex items-center gap-2">
                                <input
                                  type="color"
                                  value={u.color || '#3b82f6'}
                                  onChange={(e) => updateUser(u.id, { color: e.target.value })}
                                  onBlur={(e) => handleUpdateUser(u.id, { color: e.target.value })}
                                  className="h-8 w-8 rounded cursor-pointer border-0 p-0"
                                />
                              </div>
                            </TableCell>
                          </TableRow>
                        )
                      })}
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
                      onCheckedChange={(v) =>
                        updateItem('settings', s.id, { showFinanceDashboard: v })
                      }
                    />
                  </div>
                </CardContent>
              </Card>

              <SystemManagement />
            </TabsContent>

            <TabsContent value="backup" className="space-y-6">
              <Card>
                <CardHeader>
                  <CardTitle>Backup do Sistema</CardTitle>
                  <CardDescription>
                    Faça o download de todos os dados do sistema em formato de planilha (CSV
                    consolidado).
                  </CardDescription>
                </CardHeader>
                <CardContent>
                  <Button
                    onClick={async () => {
                      setIsSubmitting(true)
                      try {
                        const [
                          { data: clients },
                          { data: cases },
                          { data: tasks },
                          { data: appointments },
                          { data: transactions },
                          { data: suppliers },
                          { data: petitions },
                        ] = await Promise.all([
                          supabase.from('clients').select('*'),
                          supabase.from('cases').select('*'),
                          supabase.from('tasks').select('*'),
                          supabase.from('appointments').select('*'),
                          supabase.from('transactions').select('*'),
                          supabase.from('suppliers').select('*'),
                          supabase.from('petitions').select('*'),
                        ])

                        const datasets = [
                          { name: 'Clientes', data: clients || [] },
                          { name: 'Processos', data: cases || [] },
                          { name: 'Tarefas', data: tasks || [] },
                          { name: 'Agenda', data: appointments || [] },
                          { name: 'Financeiro', data: transactions || [] },
                          { name: 'Fornecedores', data: suppliers || [] },
                          { name: 'Petições', data: petitions || [] },
                        ]

                        import('@/lib/export').then(({ downloadMultiCSV }) => {
                          downloadMultiCSV(
                            datasets,
                            `backup_sistema_${new Date().toISOString().split('T')[0]}.csv`,
                          )
                          toast({ title: 'Sucesso', description: 'Backup exportado com sucesso!' })
                          addLog('Exportar', 'Backup', 'Backup em Planilha CSV gerado')
                        })
                      } catch (err: any) {
                        toast({
                          title: 'Erro',
                          description: 'Falha ao gerar backup: ' + err.message,
                          variant: 'destructive',
                        })
                      } finally {
                        setIsSubmitting(false)
                      }
                    }}
                    disabled={isSubmitting}
                  >
                    <Download className="mr-2 h-4 w-4" /> Baixar Planilha de Backup
                  </Button>
                </CardContent>
              </Card>
            </TabsContent>
          </>
        )}
      </Tabs>
    </div>
  )
}
