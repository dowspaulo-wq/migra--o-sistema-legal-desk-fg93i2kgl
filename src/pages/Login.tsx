import { useState, useEffect } from 'react'
import { useAuth } from '@/hooks/use-auth'
import { Navigate, useNavigate, useSearchParams } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Scale, ArrowLeft } from 'lucide-react'
import { toast } from '@/hooks/use-toast'

export default function Login() {
  const { signIn, resetPassword, user } = useAuth()
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [isResetMode, setIsResetMode] = useState(false)

  useEffect(() => {
    if (searchParams.get('inactive') === '1') {
      toast({
        title: 'Acesso bloqueado',
        description: 'Usuário inativo. Contate o administrador.',
        variant: 'destructive',
      })
    }
  }, [searchParams])

  if (user) return <Navigate to="/" replace />

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    try {
      // 15 second client-side safety guard in case of extreme network/hang situations
      const loginPromise = signIn(email.trim(), password)
      const timeoutPromise = new Promise<{ error: any }>((resolve) =>
        setTimeout(
          () =>
            resolve({
              error: {
                message:
                  'Tempo limite de conexão excedido ao tentar entrar. Verifique sua conexão e tente novamente.',
              },
            }),
          15000,
        ),
      )

      const { error } = await Promise.race([loginPromise, timeoutPromise])
      if (error) {
        const errorMsg = (error.message || '').toLowerCase()
        if (
          error.code === 'USER_INACTIVE' ||
          errorMsg.includes('usuário inativo') ||
          errorMsg.includes('usuario inativo')
        ) {
          toast({
            title: 'Acesso bloqueado',
            description: 'Usuário inativo. Contate o administrador.',
            variant: 'destructive',
          })
        } else if (
          errorMsg.includes('not confirmed') ||
          errorMsg.includes('email não confirmado')
        ) {
          toast({
            title: 'Acesso bloqueado',
            description: 'Por favor, confirme seu e-mail para acessar o sistema.',
            variant: 'destructive',
          })
        } else if (
          errorMsg.includes('invalid login credentials') ||
          errorMsg.includes('invalid credentials') ||
          errorMsg.includes('credenciais inválidas')
        ) {
          toast({
            title: 'Erro de autenticação',
            description: 'E-mail ou senha incorretos. Verifique suas credenciais.',
            variant: 'destructive',
          })
        } else {
          toast({
            title: 'Erro ao entrar',
            description: error.message || 'Não foi possível realizar o login. Tente novamente.',
            variant: 'destructive',
          })
        }
      } else {
        toast({
          title: 'Login realizado com sucesso',
          description: 'Bem-vindo(a) ao sistema!',
        })
        navigate('/', { replace: true })
      }
    } catch (err: any) {
      console.error('Login submit error:', err)
      toast({
        title: 'Erro inesperado',
        description: err?.message || 'Falha na conexão. Tente novamente.',
        variant: 'destructive',
      })
    } finally {
      setLoading(false)
    }
  }

  const handleResetPassword = async (e: React.FormEvent) => {
    e.preventDefault()
    const cleanEmail = email.trim()
    if (!cleanEmail) {
      toast({
        title: 'Campo obrigatório',
        description: 'Por favor, informe seu email para recuperar a senha.',
        variant: 'destructive',
      })
      return
    }

    setLoading(true)
    try {
      const { error } = await resetPassword(cleanEmail)

      if (error) {
        console.error('Error requesting password reset:', error)
        // Extrai mensagem limpa do erro, evitando objetos crus ou descrições vazias
        const rawMessage =
          typeof error === 'string'
            ? error
            : error?.message ||
              error?.error_description ||
              (typeof error?.error === 'string' ? error.error : '') ||
              ''
        const rawCode = (error?.code || error?.status || '').toString().toLowerCase()
        const lowerMsg = rawMessage.toLowerCase()

        let userFriendlyMsg = 'Não foi possível enviar o link de recuperação. Tente novamente.'

        if (
          rawCode === 'over_email_send_rate_limit' ||
          rawCode === '429' ||
          lowerMsg.includes('rate limit') ||
          lowerMsg.includes('too many') ||
          lowerMsg.includes('for security purposes') ||
          lowerMsg.includes('wait')
        ) {
          userFriendlyMsg =
            'Muitas tentativas em pouco tempo. Por segurança, aguarde alguns minutos antes de tentar novamente.'
        } else if (
          lowerMsg.includes('tempo limite') ||
          lowerMsg.includes('timeout') ||
          lowerMsg.includes('network') ||
          lowerMsg.includes('conectar')
        ) {
          userFriendlyMsg =
            'Tempo limite de conexão excedido. Verifique sua internet e tente novamente.'
        } else if (rawMessage && typeof rawMessage === 'string' && rawMessage.trim() !== '{}') {
          userFriendlyMsg = rawMessage
        }

        toast({
          title: 'Erro ao recuperar senha',
          description: userFriendlyMsg,
          variant: 'destructive',
        })
      } else {
        toast({
          title: 'Link enviado com sucesso!',
          description: `Se o e-mail ${cleanEmail} estiver cadastrado no sistema, você receberá o link de recuperação em alguns instantes. Verifique também sua caixa de spam.`,
        })
        setIsResetMode(false)
      }
    } catch (err: any) {
      console.error('Unexpected exception requesting password reset:', err)
      const errText =
        typeof err === 'string'
          ? err
          : err?.message && err.message !== '{}'
            ? err.message
            : 'Ocorreu uma falha inesperada ao enviar o link. Tente novamente.'
      toast({
        title: 'Erro ao recuperar senha',
        description: errText,
        variant: 'destructive',
      })
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="flex items-center justify-center min-h-screen bg-slate-50 p-4">
      <Card className="w-full max-w-md shadow-lg border-t-4 border-t-primary">
        <CardHeader className="text-center pb-2">
          <div className="mx-auto bg-primary/10 w-16 h-16 flex items-center justify-center rounded-full mb-4">
            <Scale className="h-8 w-8 text-primary" />
          </div>
          <CardTitle className="text-2xl font-bold text-slate-800">
            {isResetMode ? 'Recuperar Senha' : 'SBJur System'}
          </CardTitle>
          <CardDescription>
            {isResetMode
              ? 'Informe seu email para receber um link de recuperação.'
              : 'Acesse a plataforma de gestão jurídica.'}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {isResetMode ? (
            <form onSubmit={handleResetPassword} className="space-y-4">
              <div className="space-y-2">
                <Label>Email Corporativo</Label>
                <Input
                  required
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="advdouglaspsantos@gmail.com"
                />
              </div>
              <Button type="submit" className="w-full h-12 text-base" disabled={loading}>
                {loading ? 'Enviando...' : 'Enviar link de recuperação'}
              </Button>
              <Button
                type="button"
                variant="ghost"
                className="w-full mt-2"
                onClick={() => setIsResetMode(false)}
              >
                <ArrowLeft className="w-4 h-4 mr-2" /> Voltar para o login
              </Button>
            </form>
          ) : (
            <form onSubmit={handleLogin} className="space-y-4">
              <div className="space-y-2">
                <Label>Email Corporativo</Label>
                <Input
                  required
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="admin@sbjur.com"
                />
              </div>
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <Label>Senha</Label>
                  <button
                    type="button"
                    onClick={() => setIsResetMode(true)}
                    className="text-sm text-primary hover:underline font-medium"
                  >
                    Esqueceu a senha?
                  </button>
                </div>
                <Input
                  required
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="••••••••"
                />
              </div>
              <Button type="submit" className="w-full h-12 text-base" disabled={loading}>
                {loading ? 'Autenticando...' : 'Entrar no Sistema'}
              </Button>
            </form>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
