import React, { useState, useEffect, useRef } from 'react'
import { useParams } from 'react-router-dom'
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
  CardFooter,
} from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Alert, AlertTitle, AlertDescription } from '@/components/ui/alert'
import {
  CheckCircle2,
  AlertTriangle,
  Camera,
  Loader2,
  FileText,
  Download,
  Eye,
  ArrowRight,
  RotateCcw,
  ShieldCheck,
} from 'lucide-react'
import {
  getSignatureByToken,
  confirmSignature,
  viewOrDownloadDocument,
} from '@/services/document-signatures'
import { toast } from '@/hooks/use-toast'

export default function SignaturePage() {
  const { token } = useParams<{ token: string }>()
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [docData, setDocData] = useState<any>(null)
  const [step, setStep] = useState<number>(1) // 1: Info/Review, 2: Selfie, 3: Signature, 4: Success

  // Selfie state
  const videoRef = useRef<HTMLVideoElement | null>(null)
  const [selfieStream, setSelfieStream] = useState<MediaStream | null>(null)
  const [selfieImg, setSelfieImg] = useState<string | null>(null)
  const [cameraError, setCameraError] = useState<boolean>(false)

  // Signature Pad state
  const canvasRef = useRef<HTMLCanvasElement | null>(null)
  const [isDrawing, setIsDrawing] = useState(false)
  const [hasSignature, setHasSignature] = useState(false)
  const [signatureImg, setSignatureImg] = useState<string | null>(null)

  // Geolocation & Submitting
  const [location, setLocation] = useState<{ latitude: number; longitude: number } | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const [viewingDoc, setViewingDoc] = useState(false)

  useEffect(() => {
    if (!token) {
      setError('Token de assinatura não fornecido.')
      setLoading(false)
      return
    }

    let isMounted = true
    getSignatureByToken(token)
      .then(({ data, error: fetchErr }) => {
        if (!isMounted) return
        if (fetchErr || !data) {
          setError(fetchErr?.message || 'Documento não encontrado ou link expirado.')
        } else {
          setDocData(data)
          if (data.status === 'signed') {
            setStep(4)
          }
        }
      })
      .catch((err) => {
        if (isMounted) {
          console.error('Unhandled error in SignaturePage load:', err)
          setError('Erro ao carregar os dados do documento. Tente novamente.')
        }
      })
      .finally(() => {
        if (isMounted) setLoading(false)
      })

    if ('geolocation' in navigator) {
      navigator.geolocation.getCurrentPosition(
        (pos) => {
          if (isMounted) {
            setLocation({
              latitude: pos.coords.latitude,
              longitude: pos.coords.longitude,
            })
          }
        },
        (geoErr) => {
          console.warn('Geolocation error or denied:', geoErr)
        },
        { timeout: 10000, enableHighAccuracy: true },
      )
    }

    return () => {
      isMounted = false
    }
  }, [token])

  useEffect(() => {
    if (step === 2 && !selfieImg) {
      setCameraError(false)
      navigator.mediaDevices
        ?.getUserMedia({ video: { facingMode: 'user' } })
        .then((stream) => {
          setSelfieStream(stream)
          if (videoRef.current) {
            videoRef.current.srcObject = stream
          }
        })
        .catch((err) => {
          console.warn('Camera access error:', err)
          setCameraError(true)
        })
    } else {
      stopCamera()
    }

    return () => {
      stopCamera()
    }
  }, [step, selfieImg])

  const stopCamera = () => {
    if (selfieStream) {
      selfieStream.getTracks().forEach((track) => track.stop())
      setSelfieStream(null)
    }
  }

  const takeSelfie = () => {
    if (!videoRef.current) return
    const video = videoRef.current
    const canvas = document.createElement('canvas')
    canvas.width = video.videoWidth || 640
    canvas.height = video.videoHeight || 480
    const ctx = canvas.getContext('2d')
    if (ctx) {
      ctx.drawImage(video, 0, 0, canvas.width, canvas.height)
      const dataUrl = canvas.toDataURL('image/png')
      setSelfieImg(dataUrl)
      stopCamera()
    }
  }

  const handleFileUploadSelfie = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) {
      const reader = new FileReader()
      reader.onload = (evt) => {
        if (evt.target?.result) {
          setSelfieImg(evt.target.result as string)
        }
      }
      reader.readAsDataURL(file)
    }
  }

  useEffect(() => {
    if (step === 3 && canvasRef.current) {
      const canvas = canvasRef.current
      const ctx = canvas.getContext('2d')
      if (ctx) {
        ctx.strokeStyle = '#0f172a'
        ctx.lineWidth = 3
        ctx.lineCap = 'round'
        ctx.lineJoin = 'round'
      }
    }
  }, [step])

  const startDrawing = (
    e: React.MouseEvent<HTMLCanvasElement> | React.TouchEvent<HTMLCanvasElement>,
  ) => {
    setIsDrawing(true)
    const canvas = canvasRef.current
    if (!canvas) return
    const ctx = canvas.getContext('2d')
    const rect = canvas.getBoundingClientRect()
    const clientX = 'touches' in e ? e.touches[0].clientX : e.clientX
    const clientY = 'touches' in e ? e.touches[0].clientY : e.clientY
    ctx?.beginPath()
    ctx?.moveTo(clientX - rect.left, clientY - rect.top)
  }

  const draw = (e: React.MouseEvent<HTMLCanvasElement> | React.TouchEvent<HTMLCanvasElement>) => {
    if (!isDrawing) return
    const canvas = canvasRef.current
    if (!canvas) return
    const ctx = canvas.getContext('2d')
    const rect = canvas.getBoundingClientRect()
    const clientX = 'touches' in e ? e.touches[0].clientX : e.clientX
    const clientY = 'touches' in e ? e.touches[0].clientY : e.clientY
    ctx?.lineTo(clientX - rect.left, clientY - rect.top)
    ctx?.stroke()
    setHasSignature(true)
  }

  const stopDrawing = () => {
    if (isDrawing) {
      setIsDrawing(false)
      if (canvasRef.current) {
        setSignatureImg(canvasRef.current.toDataURL('image/png'))
      }
    }
  }

  const clearSignature = () => {
    const canvas = canvasRef.current
    if (!canvas) return
    const ctx = canvas.getContext('2d')
    ctx?.clearRect(0, 0, canvas.width, canvas.height)
    setHasSignature(false)
    setSignatureImg(null)
  }

  const handleConfirmSignature = async () => {
    if (!token || !selfieImg || !signatureImg) {
      toast({
        title: 'Atenção',
        description: 'Por favor, conclua a captura da selfie e da rubrica antes de confirmar.',
        variant: 'destructive',
      })
      return
    }

    setSubmitting(true)
    try {
      const { data, error: confirmErr } = await confirmSignature(token, {
        selfie: selfieImg,
        signature: signatureImg,
        geolocation: location,
      })

      if (confirmErr) {
        toast({
          title: 'Erro ao assinar',
          description: confirmErr.message || 'Falha ao salvar a assinatura. Tente novamente.',
          variant: 'destructive',
        })
      } else {
        toast({
          title: 'Sucesso!',
          description: 'Documento assinado eletronicamente com sucesso!',
        })
        setDocData(data)
        setStep(4)
      }
    } catch (err: any) {
      console.error('Error confirming signature:', err)
      toast({
        title: 'Erro inesperado',
        description: 'Ocorreu um erro ao processar sua assinatura. Tente novamente.',
        variant: 'destructive',
      })
    } finally {
      setSubmitting(false)
    }
  }

  const handlePreviewDoc = async () => {
    if (!docData?.document_path) {
      toast({
        title: 'Atenção',
        description: 'Documento não encontrado ou ainda não processado.',
        variant: 'destructive',
      })
      return
    }
    setViewingDoc(true)
    const result = await viewOrDownloadDocument(docData.document_path, 'signature_documents')
    setViewingDoc(false)
    if (!result.success) {
      toast({
        title: 'Atenção',
        description: result.message || 'Documento não encontrado ou ainda não processado.',
        variant: 'destructive',
      })
    }
  }

  const getDocTitle = () => {
    const type = docData?.doc_type?.toLowerCase() || ''
    if (type.includes('procuracao')) return 'Procuração Ad Judicia'
    if (type.includes('hipossuficiencia')) return 'Declaração de Hipossuficiência'
    if (type.includes('contrato')) return 'Contrato de Prestação de Serviços'
    return docData?.doc_type || 'Documento Eletrônico'
  }

  if (loading) {
    return (
      <div className="min-h-screen bg-slate-50 flex items-center justify-center p-4">
        <Card className="max-w-md w-full p-8 text-center space-y-4 shadow-md">
          <Loader2 className="h-10 w-10 animate-spin text-primary mx-auto" />
          <p className="text-sm font-medium text-slate-700">
            Carregando documento para assinatura...
          </p>
        </Card>
      </div>
    )
  }

  if (error || !docData) {
    return (
      <div className="min-h-screen bg-slate-50 flex items-center justify-center p-4">
        <Card className="max-w-md w-full shadow-lg border-red-100">
          <CardHeader className="text-center pb-2">
            <AlertTriangle className="h-12 w-12 text-red-500 mx-auto mb-2" />
            <CardTitle className="text-xl text-red-600">Documento Não Encontrado</CardTitle>
            <CardDescription className="text-sm text-slate-600 mt-2">
              {error ||
                'Não foi possível encontrar os dados deste documento. O link pode ter expirado ou estar incorreto.'}
            </CardDescription>
          </CardHeader>
          <CardContent className="text-center pt-4">
            <p className="text-xs text-muted-foreground">
              Entre em contato com o escritório de advocacia responsável para solicitar um novo link
              de assinatura.
            </p>
          </CardContent>
          <CardFooter className="flex justify-center">
            <Button variant="outline" onClick={() => window.location.reload()}>
              <RotateCcw className="h-4 w-4 mr-2" /> Tentar Novamente
            </Button>
          </CardFooter>
        </Card>
      </div>
    )
  }

  const clientName = docData.clients?.name || 'Signatário'
  const clientDoc = docData.clients?.document || '—'
  const caseNumber = docData.cases?.number || '—'
  const isSigned = docData.status === 'signed' || step === 4

  return (
    <div className="min-h-screen bg-slate-100 flex flex-col items-center justify-center p-4 py-8">
      <div className="max-w-xl w-full space-y-4">
        <div className="text-center space-y-1">
          <div className="inline-flex items-center justify-center w-12 h-12 rounded-full bg-primary/10 text-primary mb-2">
            <ShieldCheck className="h-6 w-6" />
          </div>
          <h1 className="text-xl font-bold text-slate-900 tracking-tight">
            Assinatura Eletrônica Segura
          </h1>
          <p className="text-xs text-slate-500">
            DPSjur Legal System • Verificação de Identidade & Validade Jurídica
          </p>
        </div>

        {isSigned ? (
          <Card className="shadow-lg border-emerald-200 bg-white">
            <CardHeader className="text-center pb-2">
              <CheckCircle2 className="h-14 w-14 text-emerald-600 mx-auto mb-2 animate-bounce" />
              <CardTitle className="text-2xl font-bold text-emerald-800">
                Documento Assinado com Sucesso!
              </CardTitle>
              <CardDescription className="text-sm text-slate-600">
                Sua assinatura eletrônica foi registrada com validade jurídica e trilha de
                auditoria.
              </CardDescription>
            </CardHeader>

            <CardContent className="space-y-4 pt-4 text-sm">
              <div className="bg-slate-50 p-4 rounded-lg border border-slate-200 space-y-2 text-xs text-slate-700">
                <div className="flex justify-between border-b pb-1">
                  <span className="text-slate-500">Documento:</span>
                  <span className="font-semibold">{getDocTitle()}</span>
                </div>
                <div className="flex justify-between border-b pb-1">
                  <span className="text-slate-500">Signatário:</span>
                  <span className="font-semibold">{clientName}</span>
                </div>
                <div className="flex justify-between border-b pb-1">
                  <span className="text-slate-500">CPF/CNPJ:</span>
                  <span className="font-semibold">{clientDoc}</span>
                </div>
                <div className="flex justify-between border-b pb-1">
                  <span className="text-slate-500">Processo:</span>
                  <span className="font-semibold">{caseNumber}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-slate-500">Data/Hora:</span>
                  <span className="font-semibold">
                    {docData.signed_at
                      ? new Date(docData.signed_at).toLocaleString('pt-BR')
                      : new Date().toLocaleString('pt-BR')}
                  </span>
                </div>
              </div>

              {docData.document_path && (
                <Button className="w-full" onClick={handlePreviewDoc} disabled={viewingDoc}>
                  {viewingDoc ? (
                    <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                  ) : (
                    <Download className="h-4 w-4 mr-2" />
                  )}
                  Visualizar / Baixar Documento Assinado
                </Button>
              )}
            </CardContent>
          </Card>
        ) : (
          <Card className="shadow-lg border-slate-200 bg-white">
            <CardHeader className="pb-3 border-b">
              <div className="flex items-center justify-between">
                <Badge variant="outline" className="bg-slate-50 text-slate-700">
                  Etapa {step} de 3
                </Badge>
                <div className="flex gap-1">
                  {[1, 2, 3].map((i) => (
                    <div
                      key={i}
                      className={`h-2 w-8 rounded-full transition-colors ${
                        i <= step ? 'bg-primary' : 'bg-slate-200'
                      }`}
                    />
                  ))}
                </div>
              </div>
              <CardTitle className="text-lg font-bold text-slate-900 mt-2">
                {step === 1 && '1. Confirmação dos Dados e Termos'}
                {step === 2 && '2. Validação Biométrica (Selfie)'}
                {step === 3 && '3. Assinatura e Rubrica Digital'}
              </CardTitle>
            </CardHeader>

            <CardContent className="pt-4 space-y-4">
              {step === 1 && (
                <div className="space-y-4">
                  <div className="bg-slate-50 p-4 rounded-lg border space-y-2 text-xs">
                    <div className="flex items-center gap-2 text-sm font-semibold text-slate-800 border-b pb-2">
                      <FileText className="h-4 w-4 text-primary" />
                      {getDocTitle()}
                    </div>
                    <div className="grid grid-cols-2 gap-2 pt-1 text-slate-600">
                      <div>
                        <span className="block text-slate-400">Cliente / Outorgante:</span>
                        <span className="font-semibold text-slate-800">{clientName}</span>
                      </div>
                      <div>
                        <span className="block text-slate-400">CPF:</span>
                        <span className="font-semibold text-slate-800">{clientDoc}</span>
                      </div>
                      <div>
                        <span className="block text-slate-400">Processo Vinculado:</span>
                        <span className="font-semibold text-slate-800">{caseNumber}</span>
                      </div>
                      <div>
                        <span className="block text-slate-400">Validade:</span>
                        <span className="font-semibold text-emerald-600">Ad Judicia / Legal</span>
                      </div>
                    </div>
                  </div>

                  <Alert className="bg-blue-50/60 border-blue-200">
                    <ShieldCheck className="h-4 w-4 text-blue-600" />
                    <AlertTitle className="text-xs font-semibold text-blue-900">
                      Assinatura com Validade Jurídica (MP 2.200-2/2001)
                    </AlertTitle>
                    <AlertDescription className="text-xs text-blue-800">
                      Para sua segurança, nas próximas etapas registraremos sua foto (selfie),
                      rubrica e geolocalização como comprovação de autoria.
                    </AlertDescription>
                  </Alert>

                  {docData.document_path && (
                    <Button
                      variant="outline"
                      size="sm"
                      className="w-full text-xs"
                      onClick={handlePreviewDoc}
                      disabled={viewingDoc}
                    >
                      {viewingDoc ? (
                        <Loader2 className="h-3.5 w-3.5 mr-2 animate-spin" />
                      ) : (
                        <Eye className="h-3.5 w-3.5 mr-2" />
                      )}
                      Visualizar Rascunho do Documento
                    </Button>
                  )}

                  <Button className="w-full" onClick={() => setStep(2)}>
                    Continuar para Foto (Selfie) <ArrowRight className="h-4 w-4 ml-2" />
                  </Button>
                </div>
              )}

              {step === 2 && (
                <div className="space-y-4 text-center">
                  <p className="text-xs text-slate-600">
                    Posicione seu rosto de forma clara no centro da tela para confirmação de
                    identidade.
                  </p>

                  <div className="relative mx-auto w-full max-w-sm aspect-video bg-slate-900 rounded-lg overflow-hidden flex items-center justify-center border-2 border-slate-300 shadow-inner">
                    {selfieImg ? (
                      <img src={selfieImg} alt="Selfie" className="w-full h-full object-cover" />
                    ) : cameraError ? (
                      <div className="p-4 text-center space-y-3">
                        <AlertTriangle className="h-8 w-8 text-amber-400 mx-auto" />
                        <p className="text-xs text-slate-200">
                          Não foi possível acessar a câmera do dispositivo.
                        </p>
                        <label className="inline-flex items-center justify-center px-3 py-1.5 bg-primary text-white text-xs rounded cursor-pointer hover:bg-primary/90">
                          <Camera className="h-3.5 w-3.5 mr-1.5" /> Enviar Foto da Galeria
                          <input
                            type="file"
                            accept="image/*"
                            capture="user"
                            className="hidden"
                            onChange={handleFileUploadSelfie}
                          />
                        </label>
                      </div>
                    ) : (
                      <video
                        ref={videoRef}
                        autoPlay
                        playsInline
                        muted
                        className="w-full h-full object-cover"
                      />
                    )}
                  </div>

                  {selfieImg ? (
                    <div className="flex gap-2">
                      <Button
                        variant="outline"
                        className="flex-1 text-xs"
                        onClick={() => {
                          setSelfieImg(null)
                          setCameraError(false)
                        }}
                      >
                        <RotateCcw className="h-3.5 w-3.5 mr-1.5" /> Tirar Outra Foto
                      </Button>
                      <Button className="flex-1 text-xs" onClick={() => setStep(3)}>
                        Avançar <ArrowRight className="h-3.5 w-3.5 ml-1.5" />
                      </Button>
                    </div>
                  ) : (
                    !cameraError && (
                      <Button className="w-full" onClick={takeSelfie}>
                        <Camera className="h-4 w-4 mr-2" /> Capturar Foto (Selfie)
                      </Button>
                    )
                  )}
                </div>
              )}

              {step === 3 && (
                <div className="space-y-4 text-center">
                  <p className="text-xs text-slate-600">
                    Faça sua rubrica/assinatura no quadro abaixo usando o dedo ou mouse:
                  </p>

                  <div className="border-2 border-dashed border-slate-300 rounded-lg bg-slate-50 p-2 touch-none relative">
                    <canvas
                      ref={canvasRef}
                      width={400}
                      height={180}
                      className="w-full h-44 bg-white rounded border border-slate-200 cursor-crosshair"
                      onMouseDown={startDrawing}
                      onMouseMove={draw}
                      onMouseUp={stopDrawing}
                      onMouseLeave={stopDrawing}
                      onTouchStart={startDrawing}
                      onTouchMove={draw}
                      onTouchEnd={stopDrawing}
                    />
                    {!hasSignature && (
                      <div className="absolute inset-0 pointer-events-none flex items-center justify-center text-xs text-slate-400">
                        Assine aqui
                      </div>
                    )}
                  </div>

                  <div className="flex gap-2">
                    <Button
                      variant="outline"
                      size="sm"
                      className="text-xs"
                      onClick={clearSignature}
                      disabled={!hasSignature}
                    >
                      <RotateCcw className="h-3.5 w-3.5 mr-1" /> Limpar
                    </Button>
                    <Button
                      className="flex-1 text-xs"
                      disabled={!hasSignature || submitting}
                      onClick={handleConfirmSignature}
                    >
                      {submitting ? (
                        <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                      ) : (
                        <CheckCircle2 className="h-4 w-4 mr-2" />
                      )}
                      Finalizar e Assinar Documento
                    </Button>
                  </div>
                </div>
              )}
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  )
}
