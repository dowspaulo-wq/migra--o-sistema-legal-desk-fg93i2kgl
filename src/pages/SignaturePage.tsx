import { useState, useEffect, useRef, useCallback } from 'react'
import { useParams } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { CheckCircle, Camera, MapPin, FileText, AlertCircle, Loader2 } from 'lucide-react'
import { supabase } from '@/lib/supabase/client'

type SigData = {
  doc_type: string
  status: string
  document_content: string | null
  client: any
  case: any
  signed_at: string | null
}

export default function SignaturePage() {
  const { token } = useParams<{ token: string }>()
  const [data, setData] = useState<SigData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [step, setStep] = useState(0)
  const [selfie, setSelfie] = useState<string | null>(null)
  const [geo, setGeo] = useState<{ lat: number; lng: number } | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const videoRef = useRef<HTMLVideoElement>(null)
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const streamRef = useRef<MediaStream | null>(null)

  useEffect(() => {
    const load = async () => {
      const { data: result, error: err } = await supabase.functions.invoke('electronic-signature', {
        body: { action: 'getDoc', token },
      })
      if (err || result?.error) {
        setError(err?.message || result?.error || 'Erro ao carregar documento.')
      } else {
        setData(result)
        if (result.status === 'signed') setStep(5)
      }
      setLoading(false)
    }
    load()
    return () => {
      streamRef.current?.getTracks().forEach((t) => t.stop())
    }
  }, [token])

  const startCamera = useCallback(async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'user' },
      })
      streamRef.current = stream
      if (videoRef.current) videoRef.current.srcObject = stream
    } catch {
      setError('Não foi possível acessar a câmera.')
    }
  }, [])

  const captureSelfie = useCallback(() => {
    if (!videoRef.current || !canvasRef.current) return
    const v = videoRef.current
    const c = canvasRef.current
    c.width = v.videoWidth
    c.height = v.videoHeight
    c.getContext('2d')?.drawImage(v, 0, 0)
    setSelfie(c.toDataURL('image/jpeg', 0.8))
    streamRef.current?.getTracks().forEach((t) => t.stop())
    setStep(2)
  }, [])

  const getLocation = useCallback(() => {
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setGeo({ lat: pos.coords.latitude, lng: pos.coords.longitude })
        setStep(3)
      },
      () => setError('Não foi possível obter localização.'),
    )
  }, [])

  const submit = useCallback(async () => {
    setSubmitting(true)
    setError(null)
    const { data: result, error: err } = await supabase.functions.invoke('electronic-signature', {
      body: { action: 'sign', token, selfieBase64: selfie, geolocation: geo },
    })
    setSubmitting(false)
    if (err || result?.error) {
      setError(err?.message || result?.error || 'Erro ao assinar.')
    } else {
      setStep(5)
    }
  }, [token, selfie, geo])

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    )
  }

  if (error && !data) {
    return (
      <div className="flex flex-col items-center justify-center min-h-screen gap-4 p-4">
        <AlertCircle className="h-12 w-12 text-red-500" />
        <p className="text-muted-foreground">{error}</p>
      </div>
    )
  }

  if (!data) return null

  const docTitle =
    data.doc_type === 'procuracao'
      ? 'Procuração'
      : data.doc_type === 'hipossuficiencia'
        ? 'Declaração de Hipossuficiência'
        : 'Contrato de Prestação de Serviços'

  if (step === 5) {
    return (
      <div className="flex flex-col items-center justify-center min-h-screen gap-4 p-4">
        <CheckCircle className="h-16 w-16 text-green-500" />
        <h1 className="text-2xl font-bold">Documento Assinado!</h1>
        <p className="text-muted-foreground text-center">
          O documento &ldquo;{docTitle}&rdquo; foi assinado eletronicamente com sucesso.
        </p>
        {data.signed_at && (
          <Badge variant="secondary">
            Assinado em {new Date(data.signed_at).toLocaleString('pt-BR')}
          </Badge>
        )}
      </div>
    )
  }

  return (
    <div className="max-w-4xl mx-auto p-4 space-y-6">
      <div className="flex items-center gap-3">
        <FileText className="h-8 w-8 text-primary" />
        <div>
          <h1 className="text-xl font-bold">{docTitle}</h1>
          <p className="text-sm text-muted-foreground">Assinatura Eletrônica com Auditoria</p>
        </div>
        <Badge variant="outline" className="ml-auto">
          {data.client?.name}
        </Badge>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Pré-visualização do Documento</CardTitle>
        </CardHeader>
        <CardContent>
          {data.document_content && (
            <div
              className="border rounded-lg p-6 bg-white max-h-[500px] overflow-y-auto"
              dangerouslySetInnerHTML={{ __html: data.document_content }}
            />
          )}
        </CardContent>
      </Card>

      {step === 0 && (
        <div className="flex justify-center">
          <Button
            size="lg"
            onClick={() => {
              setStep(1)
              startCamera()
            }}
          >
            <Camera className="h-5 w-5 mr-2" /> Iniciar Assinatura
          </Button>
        </div>
      )}

      {step === 1 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2">
              <Camera className="h-5 w-5" /> Capture sua Selfie
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex justify-center">
              <video ref={videoRef} autoPlay playsInline className="rounded-lg max-w-sm w-full" />
            </div>
            <canvas ref={canvasRef} className="hidden" />
            <Button className="w-full" onClick={captureSelfie}>
              Capturar Foto
            </Button>
          </CardContent>
        </Card>
      )}

      {step >= 2 && selfie && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Selfie Capturada</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex justify-center">
              <img src={selfie} alt="Selfie" className="rounded-lg max-w-xs" />
            </div>
            {step === 2 && (
              <Button className="w-full" onClick={getLocation}>
                <MapPin className="h-4 w-4 mr-2" /> Permitir Coleta de Localização
              </Button>
            )}
            {geo && step >= 3 && (
              <p className="text-sm text-center text-muted-foreground">
                Localização: {geo.lat.toFixed(6)}, {geo.lng.toFixed(6)}
              </p>
            )}
            {step >= 3 && (
              <Button className="w-full" onClick={submit} disabled={submitting}>
                {submitting ? (
                  <>
                    <Loader2 className="h-4 w-4 mr-2 animate-spin" /> Assinando...
                  </>
                ) : (
                  'Confirmar Assinatura Eletrônica'
                )}
              </Button>
            )}
          </CardContent>
        </Card>
      )}

      {error && <p className="text-sm text-red-500 text-center">{error}</p>}
    </div>
  )
}
