import { useState, useRef, useEffect } from 'react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Camera, RefreshCw, Check, AlertCircle, SwitchCamera, Upload } from 'lucide-react'

interface SelfieCaptureStepProps {
  confirmedSelfie: string | null
  onConfirm: (selfieDataUrl: string) => void
  onRetake: () => void
}

export function SelfieCaptureStep({
  confirmedSelfie,
  onConfirm,
  onRetake,
}: SelfieCaptureStepProps) {
  const [isStreaming, setIsStreaming] = useState(false)
  const [facingMode, setFacingMode] = useState<'user' | 'environment'>('user')
  const [error, setError] = useState<string | null>(null)
  const videoRef = useRef<HTMLVideoElement | null>(null)
  const streamRef = useRef<MediaStream | null>(null)

  const stopStream = () => {
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((track) => track.stop())
      streamRef.current = null
    }
    setIsStreaming(false)
  }

  useEffect(() => {
    return () => {
      stopStream()
    }
  }, [])

  const startCamera = async (mode = facingMode) => {
    setError(null)
    stopStream()
    try {
      const constraints: MediaStreamConstraints = {
        video: { facingMode: mode, width: { ideal: 1280 }, height: { ideal: 720 } },
        audio: false,
      }
      const stream = await navigator.mediaDevices.getUserMedia(constraints)
      streamRef.current = stream
      if (videoRef.current) {
        videoRef.current.srcObject = stream
        await videoRef.current.play()
      }
      setIsStreaming(true)
    } catch (err: any) {
      setError(
        'Não foi possível acessar a câmera do dispositivo. Verifique a permissão do navegador.',
      )
      setIsStreaming(false)
    }
  }

  const toggleCamera = () => {
    const nextMode = facingMode === 'user' ? 'environment' : 'user'
    setFacingMode(nextMode)
    if (isStreaming) {
      startCamera(nextMode)
    }
  }

  const capturePhoto = () => {
    if (!videoRef.current) return
    const video = videoRef.current
    const canvas = document.createElement('canvas')
    canvas.width = video.videoWidth || 640
    canvas.height = video.videoHeight || 480
    const ctx = canvas.getContext('2d')
    if (!ctx) return

    if (facingMode === 'user') {
      ctx.translate(canvas.width, 0)
      ctx.scale(-1, 1)
    }
    ctx.drawImage(video, 0, 0, canvas.width, canvas.height)
    const dataUrl = canvas.toDataURL('image/png')
    stopStream()
    onConfirm(dataUrl)
  }

  const handleFileUploadFallback = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    const reader = new FileReader()
    reader.onload = (event) => {
      const res = event.target?.result as string
      if (res) onConfirm(res)
    }
    reader.readAsDataURL(file)
  }

  if (confirmedSelfie) {
    return (
      <div className="space-y-3">
        <div className="flex items-center gap-4">
          <img
            src={confirmedSelfie}
            alt="Selfie do Signatário"
            className="w-32 h-32 object-cover rounded-xl border-2 border-emerald-500 shadow-sm"
          />
          <div className="space-y-2">
            <Badge variant="outline" className="bg-emerald-50 text-emerald-700 border-emerald-300">
              <Check className="h-3.5 w-3.5 mr-1" /> Selfie Capturada
            </Badge>
            <p className="text-xs text-slate-500">
              Sua foto foi registrada para validação jurídica.
            </p>
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                onRetake()
                setError(null)
              }}
              className="text-xs bg-white text-slate-700 hover:bg-slate-50"
            >
              <RefreshCw className="h-3.5 w-3.5 mr-1.5" /> Tirar Novamente
            </Button>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {!isStreaming ? (
        <div className="bg-slate-50 border-2 border-dashed border-slate-300 rounded-xl p-6 text-center space-y-3">
          <div className="w-12 h-12 rounded-full bg-blue-50 text-blue-600 flex items-center justify-center mx-auto">
            <Camera className="h-6 w-6" />
          </div>
          <div>
            <h4 className="text-sm font-semibold text-slate-800">Captura de Selfie</h4>
            <p className="text-xs text-slate-500 max-w-sm mx-auto mt-1">
              A foto é necessária para comprovação jurídica de autoria e integridade da assinatura.
            </p>
          </div>

          {error && (
            <div className="bg-red-50 text-red-700 text-xs p-3 rounded-lg flex items-center justify-center gap-2">
              <AlertCircle className="h-4 w-4 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          <div className="flex flex-col sm:flex-row items-center justify-center gap-2 pt-2">
            <Button
              type="button"
              onClick={() => startCamera('user')}
              className="bg-blue-600 hover:bg-blue-700 text-white text-xs px-5 h-9"
            >
              <Camera className="h-4 w-4 mr-2" /> Abrir Câmera do Dispositivo
            </Button>

            <label className="cursor-pointer">
              <input
                type="file"
                accept="image/*"
                capture="user"
                onChange={handleFileUploadFallback}
                className="hidden"
              />
              <span className="inline-flex items-center justify-center rounded-md text-xs font-medium border border-slate-200 bg-white hover:bg-slate-100 text-slate-700 h-9 px-4 py-2">
                <Upload className="h-3.5 w-3.5 mr-1.5" /> Enviar da Galeria
              </span>
            </label>
          </div>
        </div>
      ) : (
        <div className="bg-slate-900 rounded-xl overflow-hidden p-4 space-y-4 max-w-md mx-auto">
          <div className="relative aspect-video sm:aspect-square bg-black rounded-lg overflow-hidden flex items-center justify-center border border-slate-800">
            <video
              ref={videoRef}
              autoPlay
              playsInline
              muted
              className={`w-full h-full object-cover ${facingMode === 'user' ? '-scale-x-100' : ''}`}
            />
            <div className="absolute inset-0 border-2 border-emerald-400/40 rounded-full m-8 pointer-events-none border-dashed" />
          </div>

          <div className="flex items-center justify-between gap-2">
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={toggleCamera}
              className="bg-slate-800 border-slate-700 text-slate-200 hover:bg-slate-700 text-xs"
            >
              <SwitchCamera className="h-3.5 w-3.5 mr-1.5" /> Inverter
            </Button>

            <Button
              type="button"
              onClick={capturePhoto}
              className="bg-emerald-600 hover:bg-emerald-700 text-white text-xs px-6 font-semibold"
            >
              <Camera className="h-4 w-4 mr-2" /> Tirar Foto
            </Button>

            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={stopStream}
              className="text-slate-400 hover:text-white text-xs"
            >
              Cancelar
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}
