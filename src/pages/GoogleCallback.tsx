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
        description: 'Por favor, faça login novamente.',
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
        const { data, error: invokeError } = await supabase.functions.invoke('google-calendar', {
          body: { action: 'callback', code, redirectUri },
        })

        if (invokeError) throw invokeError
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
