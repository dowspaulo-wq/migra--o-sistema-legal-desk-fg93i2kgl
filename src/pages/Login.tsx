import { useState } from 'react'
import { useAuth } from '@/hooks/use-auth'
import { Navigate } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Scale, ArrowLeft } from 'lucide-react'
import { toast } from '@/hooks/use-toast'

export default function Login() {
  const { signIn, resetPassword, user } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [isResetMode, setIsResetMode] = useState(false)

  if (user) return <Navigate to="/" replace />

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    const { error } = await signIn(email, password)
    setLoading(false)
    if (error) {
      if (
        error.message.toLowerCase().includes('not confirmed') ||
        error.message.toLowerCase().includes('email não confirmado')
      ) {
        toast({
          title: 'Acesso bloqueado',
          description: 'Por favor, confirme seu e-mail para acessar o sistema.',
          variant: 'destructive',
        })
      } else {
        toast({
          title: 'Erro de autenticação',
          description: 'Email ou senha inválidos',
          variant: 'destructive',
        })
      }
    }
  }

  const handleResetPassword = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!email) {
      toast({
        title: 'Campo obrigatório',
        description: 'Por favor, informe seu email para recuperar a senha.',
        variant: 'destructive',
      })
      return
    }

    setLoading(true)
    const { error } = await resetPassword(email)
    setLoading(false)

    if (error) {
      toast({
        title: 'Erro ao enviar email',
        description: error.message,
        variant: 'destructive',
      })
    } else {
      toast({
        title: 'Email enviado!',
        description: 'Verifique sua caixa de entrada para redefinir sua senha.',
      })
      setIsResetMode(false)
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
                  placeholder="dowspaulo@gmail.com"
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
