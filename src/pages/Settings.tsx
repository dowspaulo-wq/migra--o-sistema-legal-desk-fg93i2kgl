import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Switch } from '@/components/ui/switch'
import { Label } from '@/components/ui/label'
import { Input } from '@/components/ui/input'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Download, Shield, Users, Sliders, Trash2, Plus, UserCircle } from 'lucide-react'
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

function EditableColorList({ title, items, onSave }: any) {
  const [val, setVal] = useState('')
  const [color, setColor] = useState('#3b82f6')

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

  const add = () => {
    if (val && !normalized.some((i: any) => i.label === val)) {
      const newItems = [...normalized, { label: val, color }].sort((a, b) =>
        a.label.localeCompare(b.label),
      )
      onSave(newItems)
      setVal('')
    }
  }
  const remove = (label: string) => onSave(normalized.filter((i: any) => i.label !== label))

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
            className="flex-1 h-9"
            onKeyDown={(e) => e.key === 'Enter' && add()}
          />
          <Input
            type="color"
            value={color}
            onChange={(e) => setColor(e.target.value)}
            className="w-12 h-9 p-0.5 cursor-pointer border-0 rounded bg-transparent"
          />
          <Button size="sm" onClick={add} className="h-9">
            <Plus className="h-4 w-4" />
          </Button>
        </div>
        <div className="flex flex-wrap gap-2">
          {normalized.map((i: any) => {
            const isLight =
              i.color.toLowerCase() === '#f1f5f9' || i.color.toLowerCase() === '#ffffff'
            return (
              <div
                key={i.label}
                className="flex items-center gap-2 px-2 py-1 rounded text-sm border font-medium"
                style={{
                  backgroundColor: i.color,
                  borderColor: isLight ? '#e2e8f0' : i.color,
                  color: isLight ? '#333' : '#fff',
                }}
              >
                <span>{i.label}</span>
                <Trash2
                  className="h-3 w-3 cursor-pointer opacity-70 hover:opacity-100 transition-opacity"
                  onClick={() => remove(i.label)}
                />
              </div>
            )
          })}
        </div>
      </CardContent>
    </Card>
  )
}

export default function Settings() {
  const { state, updateItem, updateUser, addLog, addUser } = useLegalStore()
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
              <TabsTrigger value="users">
                <Users className="h-4 w-4 mr-2" /> Usuários & Permissões
              </TabsTrigger>
              <TabsTrigger value="general">
                <Shield className="h-4 w-4 mr-2" /> Avançado
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
              />
              <EditableColorList
                title="Tipos de Processos (Com Cores)"
                items={s.caseTypes || []}
                onSave={(items: any[]) => updateItem('settings', s.id, { caseTypes: items })}
              />
              <EditableColorList
                title="Tipos de Agendamento (Com Cores)"
                items={s.appointmentTypes || []}
                onSave={(items: any[]) => updateItem('settings', s.id, { appointmentTypes: items })}
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
            </TabsContent>

            <TabsContent value="users">
              <Card>
                <CardHeader className="flex flex-row items-center justify-between pb-2">
                  <div>
                    <CardTitle>Gestão de Colaboradores</CardTitle>
                    <CardDescription>
                      Defina nível de acesso, financeiro e cor de identificação.
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
                        <TableHead>Nome</TableHead>
                        <TableHead>E-mail</TableHead>
                        <TableHead>Nível</TableHead>
                        <TableHead>Financeiro</TableHead>
                        <TableHead>Cor Identidade</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {(state.users as any[]).map((u) => (
                        <TableRow key={u.id}>
                          <TableCell className="font-medium">{u.name}</TableCell>
                          <TableCell>{u.email || '—'}</TableCell>
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
                      onCheckedChange={(v) =>
                        updateItem('settings', s.id, { showFinanceDashboard: v })
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
          </>
        )}
      </Tabs>
    </div>
  )
}
