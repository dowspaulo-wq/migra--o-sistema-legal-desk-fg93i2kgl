import { useState } from 'react'
import { useAuth } from '@/hooks/use-auth'
import { Navigate } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Scale } from 'lucide-react'
import { toast } from '@/hooks/use-toast'

export default function Login() {
  const { signIn, user } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)

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

  return (
    <div className="flex items-center justify-center min-h-screen bg-slate-50 p-4">
      <Card className="w-full max-w-md shadow-lg border-t-4 border-t-primary">
        <CardHeader className="text-center pb-2">
          <div className="mx-auto bg-primary/10 w-16 h-16 flex items-center justify-center rounded-full mb-4">
            <Scale className="h-8 w-8 text-primary" />
          </div>
          <CardTitle className="text-2xl font-bold text-slate-800">SBJur System</CardTitle>
          <CardDescription>Acesse a plataforma de gestão jurídica.</CardDescription>
        </CardHeader>
        <CardContent>
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
              <Label>Senha</Label>
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
          <div className="mt-6 p-4 bg-slate-100 rounded text-xs text-slate-600 text-center">
            <p>
              <strong>Demo Credentials:</strong>
            </p>
            <p>Admin: admin@sbjur.com | 123456</p>
            <p>User: user@sbjur.com | 123456</p>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
