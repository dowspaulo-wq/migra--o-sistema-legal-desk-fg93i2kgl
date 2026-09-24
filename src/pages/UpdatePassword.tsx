import { useState, useEffect, useRef } from 'react'
import { useNavigate, Link } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
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

  // Track if session setup was already completed to prevent duplicate executions
  const initializedRef = useRef(false)

  useEffect(() => {
    if (initializedRef.current) return
    initializedRef.current = true

    let isMounted = true

    const establishSession = async () => {
      try {
        // 1. Check if Supabase auth already has an active session (e.g. from localStorage or early parse)
        const { data: initialData } = await supabase.auth.getSession()
        if (initialData?.session) {
          if (isMounted) {
            setHasSession(true)
            setSessionError(null)
          }
          return
        }

        // 2. Inspect URL hash or query string for auth tokens or PKCE code
        const hash = window.location.hash ? window.location.hash.substring(1) : ''
        const search = window.location.search ? window.location.search.substring(1) : ''

        const hashParams = new URLSearchParams(hash)
        const searchParams = new URLSearchParams(search)

        // Check for error parameters in the URL
        const errorDesc =
          hashParams.get('error_description') ||
          searchParams.get('error_description') ||
          hashParams.get('error') ||
          searchParams.get('error')

        if (errorDesc) {
          console.error('[UpdatePassword] URL error detected:', errorDesc)
          if (isMounted) {
            setHasSession(false)
            setSessionError(decodeURIComponent(errorDesc.replace(/\+/g, ' ')))
          }
          return
        }

        // Check for PKCE exchange code (?code=... or #code=...)
        const code = searchParams.get('code') || hashParams.get('code')
        if (code) {
          console.log('[UpdatePassword] Exchanging auth code for session...')
          const { data: exchangeData, error: exchangeError } =
            await supabase.auth.exchangeCodeForSession(code)
          if (!exchangeError && exchangeData?.session) {
            if (isMounted) {
              setHasSession(true)
              setSessionError(null)
            }
            return
          }
          if (exchangeError) {
            console.warn('[UpdatePassword] exchangeCodeForSession error:', exchangeError)
          }
        }

        // Check for implicit flow tokens in hash (#access_token=...&refresh_token=...)
        const accessToken = hashParams.get('access_token') || searchParams.get('access_token')
        const refreshToken =
          hashParams.get('refresh_token') || searchParams.get('refresh_token') || ''

        if (accessToken) {
          console.log('[UpdatePassword] Setting session from URL tokens...')
          const { data: sessionData, error: sessionErr } = await supabase.auth.setSession({
            access_token: accessToken,
            refresh_token: refreshToken,
          })

          if (!sessionErr && sessionData?.session) {
            if (isMounted) {
              setHasSession(true)
              setSessionError(null)
            }
            return
          }
          if (sessionErr) {
            console.warn('[UpdatePassword] setSession error:', sessionErr)
          }
        }

        // 3. Fallback: wait a moment for supabase.auth.onAuthStateChange if the client is still parsing in background
        const timeoutPromise = new Promise<{ session: any }>((resolve) =>
          setTimeout(() => resolve({ session: null }), 1800),
        )

        const authStatePromise = new Promise<{ session: any }>((resolve) => {
          const {
            data: { subscription },
          } = supabase.auth.onAuthStateChange((event, session) => {
            if (
              session &&
              (event === 'SIGNED_IN' ||
                event === 'PASSWORD_RECOVERY' ||
                event === 'INITIAL_SESSION')
            ) {
              subscription.unsubscribe()
              resolve({ session })
            }
          })
        })

        const winner = await Promise.race([authStatePromise, timeoutPromise])
        if (winner?.session) {
          if (isMounted) {
            setHasSession(true)
            setSessionError(null)
          }
          return
        }

        // Final check after waiting
        const { data: finalCheck } = await supabase.auth.getSession()
        if (finalCheck?.session) {
          if (isMounted) {
            setHasSession(true)
            setSessionError(null)
          }
        } else {
          if (isMounted) {
            setHasSession(false)
            setSessionError('O link de recuperação é inválido ou expirou. Solicite um novo link.')
          }
        }
      } catch (err: any) {
        console.error('[UpdatePassword] Session verification error:', err)
        if (isMounted) {
          setHasSession(false)
          setSessionError(err?.message || 'Falha ao verificar sessão de recuperação.')
        }
      }
    }

    establishSession()

    return () => {
      isMounted = false
    }
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

    // Ensure we have an active session right before calling updateUser
    let activeSession = (await supabase.auth.getSession()).data?.session
    if (!activeSession) {
      // Attempt re-capturing tokens from hash if still present
      const hash = window.location.hash ? window.location.hash.substring(1) : ''
      const hashParams = new URLSearchParams(hash)
      const accessToken = hashParams.get('access_token')
      const refreshToken = hashParams.get('refresh_token') || ''

      if (accessToken) {
        const { data: retrySession } = await supabase.auth.setSession({
          access_token: accessToken,
          refresh_token: refreshToken,
        })
        activeSession = retrySession?.session ?? null
      }
    }

    if (!activeSession) {
      setLoading(false)
      setHasSession(false)
      setSessionError('Sessão expirada. Por favor, solicite um novo link de recuperação.')
      toast({
        title: 'Sessão expirada',
        description:
          'Sua sessão de recuperação expirou. Por favor, solicite um novo link no login.',
        variant: 'destructive',
      })
      return
    }

    const { error } = await supabase.auth.updateUser({ password: newPassword })
    setLoading(false)

    if (error) {
      console.error('[UpdatePassword] Error from supabase.auth.updateUser:', error)
      const errorDetail = error.message || error.toString()
      toast({
        title: 'Erro ao atualizar senha',
        description: `Não foi possível atualizar sua senha: ${errorDetail}`,
        variant: 'destructive',
      })
      return
    }

    // Sign out to clean up recovery session tokens and ensure fresh login
    try {
      await supabase.auth.signOut()
    } catch (signOutErr) {
      console.warn('SignOut error after password change (ignorable):', signOutErr)
    }

    toast({
      title: 'Senha alterada com sucesso!',
      description: 'Sua senha foi redefinida com sucesso. Faça login agora com a nova senha.',
    })

    navigate('/login', { replace: true })
  }

  if (hasSession === null) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-slate-50">
        <div className="animate-pulse text-slate-500 font-medium">
          Verificando link de recuperação...
        </div>
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
            <CardTitle className="text-2xl font-bold text-slate-800">
              Link Inválido ou Expirado
            </CardTitle>
            <CardDescription>
              {sessionError || 'O link de recuperação é inválido ou expirou.'}
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-2">
            <Button
              type="button"
              className="w-full h-12 text-base"
              onClick={() => navigate('/login', { replace: true })}
            >
              Solicitar novo link
            </Button>
            <Button
              type="button"
              variant="ghost"
              className="w-full"
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
                  disabled={loading}
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
                  disabled={loading}
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
