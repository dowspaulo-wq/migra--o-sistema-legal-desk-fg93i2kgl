import { useEffect, useState, useRef } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { supabase } from '@/lib/supabase/client'
import { toast } from '@/hooks/use-toast'
import { Loader2 } from 'lucide-react'

export default function GoogleCallback() {
  const [searchParams] = useSearchParams()
  const navigate = useNavigate()
  const [error, setError] = useState('')
  const processed = useRef(false)

  useEffect(() => {
    const code = searchParams.get('code')
    if (!code) {
      setError('Código de autorização não encontrado.')
      return
    }

    if (processed.current) return
    processed.current = true

    const exchangeCode = async () => {
      try {
        const redirectUri = `${window.location.origin}/google-callback`
        const { data, error: invokeError } = await supabase.functions.invoke('google-calendar', {
          body: { action: 'callback', code, redirectUri },
        })

        if (invokeError) throw invokeError
        if (data?.error) throw new Error(data.error)

        toast({
          title: 'Integração Concluída',
          description: 'Sua conta do Google Calendar foi conectada com sucesso.',
        })
        navigate('/agenda')
      } catch (err: any) {
        console.error(err)
        setError(err.message || 'Erro ao conectar com o Google Calendar.')
      }
    }

    exchangeCode()
  }, [searchParams, navigate])

  return (
    <div className="flex flex-col items-center justify-center min-h-screen bg-muted/30">
      <div className="bg-card p-8 rounded-lg shadow-sm border max-w-md w-full text-center">
        {error ? (
          <>
            <h2 className="text-xl font-bold text-destructive mb-2">Erro na Integração</h2>
            <p className="text-muted-foreground mb-6">{error}</p>
            <button
              onClick={() => navigate('/agenda')}
              className="bg-primary text-primary-foreground px-4 py-2 rounded-md hover:bg-primary/90 transition-colors"
            >
              Voltar para Agenda
            </button>
          </>
        ) : (
          <>
            <Loader2 className="h-8 w-8 animate-spin mx-auto text-primary mb-4" />
            <h2 className="text-xl font-bold mb-2">Conectando ao Google...</h2>
            <p className="text-muted-foreground">
              Aguarde enquanto finalizamos a integração com o seu Google Calendar.
            </p>
          </>
        )}
      </div>
    </div>
  )
}
