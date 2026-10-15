import { useEffect, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { supabase } from '@/lib/supabase/client'
import { toast } from '@/hooks/use-toast'
import { Loader2 } from 'lucide-react'
import { useAuth } from '@/hooks/use-auth'

export default function GoogleCallback() {
  const [searchParams] = useSearchParams()
  const navigate = useNavigate()
  const [status, setStatus] = useState('Conectando ao Google...')
  const { loading, user } = useAuth()
  const [processed, setProcessed] = useState(false)

  useEffect(() => {
    if (loading || processed) return

    if (!user) {
      toast({
        title: 'Sessão inválida',
        description: 'Autenticação perdida no retorno. Por favor, faça login e tente novamente.',
        variant: 'destructive',
      })
      navigate('/login', { replace: true })
      return
    }

    const handleCallback = async () => {
      setProcessed(true)
      const code = searchParams.get('code')
      const error = searchParams.get('error')

      if (error) {
        toast({
          title: 'Erro de Autorização',
          description: 'A permissão ao Google Calendar foi negada ou cancelada.',
          variant: 'destructive',
        })
        navigate('/agenda', { replace: true })
        return
      }

      if (!code) {
        navigate('/agenda', { replace: true })
        return
      }

      setStatus('Finalizando integração e sincronizando eventos...')

      try {
        const redirectUri = `${window.location.origin}/google-callback`

        // Carrega credenciais da tabela settings como garantia adicional
        let clientIdFallback = ''
        let clientSecretFallback = ''
        try {
          const { data: sett } = await supabase
            .from('settings')
            .select('googleClientId, googleClientSecret')
            .limit(1)
            .maybeSingle()
          if (sett) {
            clientIdFallback = (sett as any).googleClientId?.trim() || ''
            clientSecretFallback = (sett as any).googleClientSecret?.trim() || ''
          }
        } catch {
          // fallback silencioso
        }

        const headers: Record<string, string> = {}
        if (clientIdFallback) headers['x-google-client-id'] = clientIdFallback
        if (clientSecretFallback) headers['x-google-client-secret'] = clientSecretFallback

        const { data, error: invokeError } = await supabase.functions.invoke('google-calendar', {
          body: {
            action: 'exchange_code',
            code,
            redirectUri,
            clientId: clientIdFallback || undefined,
            clientSecret: clientSecretFallback || undefined,
          },
          headers,
        })

        if (invokeError) {
          let errorMsg = invokeError.message || 'Falha ao autenticar com o Google'
          try {
            const ctx = (invokeError as any).context
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
                    // fallback
                  }
                }
              }
            }
          } catch {
            // fallback
          }
          throw new Error(errorMsg)
        }
        if (data?.error) throw new Error(data.error)

        toast({
          title: 'Google Calendar Conectado!',
          description: 'Sua conta foi integrada com sucesso.',
        })

        setStatus('Sincronizando agenda...')
        await supabase.functions.invoke('google-calendar', {
          body: { action: 'sync' },
        })

        navigate('/agenda', { replace: true })
      } catch (err: any) {
        console.error('Google Callback Error:', err)
        toast({
          title: 'Falha na Integração',
          description: err.message || 'Ocorreu um erro ao conectar com o Google Calendar.',
          variant: 'destructive',
        })
        navigate('/agenda', { replace: true })
      }
    }

    handleCallback()
  }, [searchParams, navigate, loading, user, processed])

  return (
    <div className="flex flex-col items-center justify-center min-h-screen bg-background">
      <Loader2 className="h-10 w-10 animate-spin text-primary mb-4" />
      <h2 className="text-xl font-semibold">{status}</h2>
      <p className="text-muted-foreground mt-2">Por favor, aguarde enquanto configuramos tudo.</p>
    </div>
  )
}
