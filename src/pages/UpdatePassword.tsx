import { useState, useEffect } from 'react'
import { Navigate, useNavigate, Link } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Scale, Eye, EyeOff, Lock, AlertCircle, ArrowLeft, CheckCircle2 } from 'lucide-react'
import { supabase } from '@/lib/supabase/client'
import { toast } from '@/hooks/use-toast'

export default function UpdatePassword() {
  const navigate = useNavigate()
  const [newPassword, setNewPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [showConfirm, setShowConfirm] = useState(false)
  const [loading, setLoading] = useState(false)
  const [hasSession, setHasSession] = useState<boolean | null>(null)
  const [sessionError, setSessionError] = useState<string | null>(null)

  useEffect(() => {
    const checkSession = async () => {
      const { data, error } = await supabase.auth.getSession()
      if (error || !data.session) {
        setHasSession(false)
        setSessionError('O link de recuperação é inválido ou expirou.')
      } else {
        setHasSession(true)
      }
    }
    checkSession()
  }, [])

  const passwordTooShort = newPassword.length > 0 && newPassword.length < 8
  const passwordsDoNotMatch = confirmPassword.length > 0 && newPassword !== confirmPassword
  const canSubmit =
    newPassword.length >= 8 &&
    confirmPassword.length >= 8 &&
    newPassword === confirmPassword &&
    !loading

  const handleUpdate = async (e: React.FormEvent) => {
    e.preventDefault()

    if (newPassword.length < 8) {
      toast({
        title: 'Senha muito curta',
        description: 'A senha deve ter no mínimo 8 caracteres.',
        variant: 'destructive',
      })
      return
    }

    if (newPassword !== confirmPassword) {
      toast({
        title: 'As senhas não coincidem',
        description: 'Por favor, verifique se as senhas são iguais.',
        variant: 'destructive',
      })
      return
    }

    setLoading(true)
    const { error } = await supabase.auth.updateUser({ password: newPassword })
    setLoading(false)

    if (error) {
      toast({
        title: 'Erro ao atualizar senha',
        description: 'Não foi possível atualizar sua senha. Tente novamente.',
        variant: 'destructive',
      })
      return
    }

    await supabase.auth.signOut()

    toast({
      title: 'Senha alterada com sucesso!',
      description: 'Faça login com sua nova senha.',
    })

    navigate('/login', { replace: true })
  }

  if (hasSession === null) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-slate-50">
        <div className="animate-pulse text-slate-400">Verificando sessão...</div>
      </div>
    )
  }

  if (!hasSession) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-slate-50 p-4">
        <Card className="w-full max-w-md shadow-lg border-t-4 border-t-destructive">
          <CardHeader className="text-center pb-2">
            <div className="mx-auto bg-destructive/10 w-16 h-16 flex items-center justify-center rounded-full mb-4">
              <AlertCircle className="h-8 w-8 text-destructive" />
            </div>
            <CardTitle className="text-2xl font-bold text-slate-800">Link Expirado</CardTitle>
            <CardDescription>
              {sessionError || 'O link de recuperação é inválido ou expirou.'}
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Button
              type="button"
              className="w-full h-12 text-base"
              onClick={() => navigate('/login', { replace: true })}
            >
              Solicitar um novo link
            </Button>
            <Button
              type="button"
              variant="ghost"
              className="w-full mt-2"
              onClick={() => navigate('/login', { replace: true })}
            >
              <ArrowLeft className="w-4 h-4 mr-2" /> Voltar para o login
            </Button>
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="flex items-center justify-center min-h-screen bg-slate-50 p-4">
      <Card className="w-full max-w-md shadow-lg border-t-4 border-t-primary">
        <CardHeader className="text-center pb-2">
          <div className="mx-auto bg-primary/10 w-16 h-16 flex items-center justify-center rounded-full mb-4">
            <Scale className="h-8 w-8 text-primary" />
          </div>
          <CardTitle className="text-2xl font-bold text-slate-800">Definir Nova Senha</CardTitle>
          <CardDescription>Digite sua nova senha para recuperar o acesso.</CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleUpdate} className="space-y-4">
            <div className="space-y-2">
              <Label>Nova Senha</Label>
              <div className="relative">
                <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
                <Input
                  required
                  type={showPassword ? 'text' : 'password'}
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                  placeholder="••••••••"
                  className="pl-9 pr-10"
                  minLength={8}
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600"
                >
                  {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>
              {passwordTooShort && (
                <p className="text-sm text-destructive">A senha deve ter no mínimo 8 caracteres.</p>
              )}
              {newPassword.length >= 8 && (
                <p className="text-sm text-green-600 flex items-center gap-1">
                  <CheckCircle2 className="w-3.5 h-3.5" /> Senha válida
                </p>
              )}
            </div>

            <div className="space-y-2">
              <Label>Confirmar Nova Senha</Label>
              <div className="relative">
                <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
                <Input
                  required
                  type={showConfirm ? 'text' : 'password'}
                  value={confirmPassword}
                  onChange={(e) => setConfirmPassword(e.target.value)}
                  placeholder="••••••••"
                  className="pl-9 pr-10"
                  minLength={8}
                />
                <button
                  type="button"
                  onClick={() => setShowConfirm(!showConfirm)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600"
                >
                  {showConfirm ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>
              {passwordsDoNotMatch && (
                <p className="text-sm text-destructive">As senhas não coincidem.</p>
              )}
              {confirmPassword.length >= 8 && confirmPassword === newPassword && (
                <p className="text-sm text-green-600 flex items-center gap-1">
                  <CheckCircle2 className="w-3.5 h-3.5" /> As senhas coincidem
                </p>
              )}
            </div>

            <Button type="submit" className="w-full h-12 text-base" disabled={!canSubmit}>
              {loading ? 'Atualizando...' : 'Atualizar Senha'}
            </Button>

            <Link
              to="/login"
              className="block text-center text-sm text-primary hover:underline font-medium"
            >
              Voltar para o login
            </Link>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
