import { useState, useEffect, useRef } from 'react'
import { useParams } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Check, Camera, MapPin, Pen, FileText, Loader2, AlertCircle } from 'lucide-react'
import { SignaturePad, SignaturePadHandle } from '@/components/SignaturePad'
import { getSignatureByToken, confirmSignature } from '@/services/document-signatures'
import { toast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'

const docTypeLabels: Record<string, string> = {
  procuracao: 'Procuração Ad Judicia',
  hipossuficiencia: 'Declaração de Hipossuficiência',
  contrato: 'Contrato de Prestação de Serviços',
}

function StepIcon({ done, icon: Icon }: { done: boolean; icon: any }) {
  return (
    <div
      className={cn(
        'w-8 h-8 rounded-full flex items-center justify-center shrink-0',
        done ? 'bg-green-500 text-white' : 'bg-slate-200 text-slate-500',
      )}
    >
      {done ? <Check className="h-4 w-4" /> : <Icon className="h-4 w-4" />}
    </div>
  )
}

export default function SignaturePage() {
  const { token } = useParams<{ token: string }>()
  const [doc, setDoc] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [submitting, setSubmitting] = useState(false)
  const [done, setDone] = useState(false)
  const [stepViewed, setStepViewed] = useState(false)
  const [selfie, setSelfie] = useState<string | null>(null)
  const [geo, setGeo] = useState<{ latitude: number; longitude: number } | null>(null)
  const [sigDrawn, setSigDrawn] = useState(false)
  const sigRef = useRef<SignaturePadHandle>(null)

  useEffect(() => {
    if (!token) return
    getSignatureByToken(token).then(({ data, error }) => {
      if (error || !data) {
        toast({ title: 'Erro', description: 'Documento não encontrado.', variant: 'destructive' })
      } else {
        setDoc(data)
      }
      setLoading(false)
    })
  }, [token])

  const handleSelfie = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    const reader = new FileReader()
    reader.onload = () => setSelfie(reader.result as string)
    reader.readAsDataURL(file)
  }

  const handleGeo = () => {
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setGeo({ latitude: pos.coords.latitude, longitude: pos.coords.longitude })
        toast({ title: 'Localização capturada' })
      },
      () =>
        toast({
          title: 'Erro',
          description: 'Não foi possível obter a localização.',
          variant: 'destructive',
        }),
    )
  }

  const allDone = stepViewed && !!selfie && !!geo && sigDrawn

  const handleSubmit = async () => {
    if (!allDone || !token) return
    const signature = sigRef.current?.toDataURL()
    if (!signature) return
    setSubmitting(true)
    const { error } = await confirmSignature(token, {
      selfie: selfie!,
      signature,
      geolocation: geo,
    })
    setSubmitting(false)
    if (error) {
      toast({ title: 'Erro', description: error.message, variant: 'destructive' })
      return
    }
    setDone(true)
    toast({ title: 'Sucesso', description: 'Documento assinado com sucesso!' })
  }

  if (loading)
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    )

  if (done)
    return (
      <div className="min-h-screen flex flex-col items-center justify-center gap-4 bg-slate-50">
        <div className="w-20 h-20 rounded-full bg-green-100 flex items-center justify-center">
          <Check className="h-10 w-10 text-green-600" />
        </div>
        <h1 className="text-2xl font-bold">Documento Assinado!</h1>
        <p className="text-muted-foreground">Sua assinatura foi registrada com sucesso.</p>
      </div>
    )

  if (!doc)
    return (
      <div className="min-h-screen flex flex-col items-center justify-center gap-4 bg-slate-50">
        <AlertCircle className="h-12 w-12 text-red-500" />
        <p className="text-lg font-medium">Documento não encontrado.</p>
      </div>
    )

  return (
    <div className="min-h-screen bg-slate-50 p-4 max-w-3xl mx-auto space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>{docTypeLabels[doc.doc_type] || doc.doc_type}</CardTitle>
          <CardDescription>Revise o documento e complete as etapas para assinar.</CardDescription>
        </CardHeader>
        <CardContent>
          <iframe
            srcDoc={doc.documentContent}
            className="w-full h-96 border rounded-md bg-white"
            title="Documento"
          />
          <Button
            className="mt-3 w-full sm:w-auto"
            variant={stepViewed ? 'outline' : 'default'}
            onClick={() => setStepViewed(true)}
          >
            {stepViewed ? (
              <>
                <Check className="h-4 w-4 mr-2" /> Documento visualizado
              </>
            ) : (
              'Confirmar leitura do documento'
            )}
          </Button>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Etapas da Assinatura</CardTitle>
        </CardHeader>
        <CardContent className="space-y-5">
          <div className="flex items-center gap-3">
            <StepIcon done={stepViewed} icon={FileText} />
            <span
              className={cn(
                'text-sm',
                stepViewed ? 'text-green-600 font-medium' : 'text-muted-foreground',
              )}
            >
              1. Visualizar documento
            </span>
          </div>
          <div className="space-y-2">
            <div className="flex items-center gap-3">
              <StepIcon done={!!selfie} icon={Camera} />
              <span
                className={cn(
                  'text-sm',
                  selfie ? 'text-green-600 font-medium' : 'text-muted-foreground',
                )}
              >
                2. Capturar selfie
              </span>
            </div>
            <input
              type="file"
              accept="image/*"
              capture="user"
              onChange={handleSelfie}
              className="text-sm ml-11"
            />
            {selfie && (
              <img src={selfie} alt="Selfie" className="w-32 h-32 rounded-lg object-cover ml-11" />
            )}
          </div>
          <div className="space-y-2">
            <div className="flex items-center gap-3">
              <StepIcon done={!!geo} icon={MapPin} />
              <span
                className={cn(
                  'text-sm',
                  geo ? 'text-green-600 font-medium' : 'text-muted-foreground',
                )}
              >
                3. Permitir geolocalização
              </span>
            </div>
            <Button
              variant="outline"
              size="sm"
              onClick={handleGeo}
              disabled={!!geo}
              className="ml-11"
            >
              {geo ? (
                <>
                  <Check className="h-4 w-4 mr-2" /> Localização obtida
                </>
              ) : (
                'Capturar localização'
              )}
            </Button>
          </div>
          <div className="space-y-2">
            <div className="flex items-center gap-3">
              <StepIcon done={sigDrawn} icon={Pen} />
              <span
                className={cn(
                  'text-sm',
                  sigDrawn ? 'text-green-600 font-medium' : 'text-muted-foreground',
                )}
              >
                4. Desenhar assinatura
              </span>
            </div>
            <div className="ml-11">
              <SignaturePad ref={sigRef} onChange={setSigDrawn} />
            </div>
          </div>
          <Button className="w-full" onClick={handleSubmit} disabled={!allDone || submitting}>
            {submitting ? (
              <>
                <Loader2 className="h-4 w-4 mr-2 animate-spin" /> Assinando...
              </>
            ) : (
              'Confirmar Assinatura'
            )}
          </Button>
        </CardContent>
      </Card>
    </div>
  )
}
