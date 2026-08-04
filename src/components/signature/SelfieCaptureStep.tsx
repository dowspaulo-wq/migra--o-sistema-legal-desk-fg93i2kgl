import { useState, useRef, useEffect, useCallback } from 'react'
import { Button } from '@/components/ui/button'
import { Camera, RefreshCw, Check, AlertCircle } from 'lucide-react'

interface SelfieCaptureStepProps {
  onConfirm: (selfieDataUrl: string) => void
  onRetake?: () => void
  confirmedSelfie: string | null
}

export function SelfieCaptureStep({
  onConfirm,
  onRetake,
  confirmedSelfie,
}: SelfieCaptureStepProps) {
  const [stream, setStream] = useState<MediaStream | null>(null)
  const [cameraActive, setCameraActive] = useState(false)
  const [capturedPhoto, setCapturedPhoto] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const videoRef = useRef<HTMLVideoElement>(null)
  const canvasRef = useRef<HTMLCanvasElement>(null)

  const stopStream = useCallback(() => {
    if (stream) {
      stream.getTracks().forEach((track) => track.stop())
      setStream(null)
    }
    setCameraActive(false)
  }, [stream])

  const startCamera = async () => {
    setError(null)
    try {
      const mediaStream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'user', width: { ideal: 1280 }, height: { ideal: 720 } },
        audio: false,
      })
      setStream(mediaStream)
      setCameraActive(true)
    } catch (err: any) {
      setError(
        err.name === 'NotAllowedError'
          ? 'Permissão para acessar a câmera foi negada. Por favor, permita o acesso à câmera nas configurações do navegador.'
          : 'Não foi possível acessar a câmera do dispositivo.',
      )
    }
  }

  useEffect(() => {
    if (cameraActive && stream && videoRef.current) {
      videoRef.current.srcObject = stream
    }
  }, [cameraActive, stream])

  useEffect(() => {
    return () => {
      if (stream) {
        stream.getTracks().forEach((t) => t.stop())
      }
    }
  }, [stream])

  const takePhoto = () => {
    if (!videoRef.current || !canvasRef.current) return
    const video = videoRef.current
    const canvas = canvasRef.current
    canvas.width = video.videoWidth || 640
    canvas.height = video.videoHeight || 480
    const ctx = canvas.getContext('2d')
    if (ctx) {
      ctx.translate(canvas.width, 0)
      ctx.scale(-1, 1)
      ctx.drawImage(video, 0, 0, canvas.width, canvas.height)
      const dataUrl = canvas.toDataURL('image/png')
      setCapturedPhoto(dataUrl)
      stopStream()
    }
  }

  const handleRetake = () => {
    setCapturedPhoto(null)
    if (onRetake) onRetake()
    startCamera()
  }

  const handleConfirm = () => {
    if (capturedPhoto) {
      onConfirm(capturedPhoto)
    }
  }

  if (confirmedSelfie) {
    return (
      <div className="flex items-center gap-4 bg-emerald-50/60 p-3 rounded-lg border border-emerald-200 mt-2">
        <img
          src={confirmedSelfie}
          alt="Selfie confirmada"
          className="w-16 h-16 object-cover rounded-md border border-emerald-300 shadow-sm"
        />
        <div className="flex-1">
          <p className="text-xs font-semibold text-emerald-800">Selfie confirmada com sucesso</p>
          <p className="text-[11px] text-emerald-600">
            Sua foto foi capturada e vinculada ao documento
          </p>
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={handleRetake}
          className="text-xs h-8 border-emerald-300 text-emerald-700 hover:bg-emerald-100 bg-white"
        >
          <RefreshCw className="h-3.5 w-3.5 mr-1" /> Alterar Foto
        </Button>
      </div>
    )
  }

  return (
    <div className="mt-2 space-y-3">
      <canvas ref={canvasRef} className="hidden" />

      {error && (
        <div className="flex items-start gap-2 bg-red-50 text-red-700 p-3 rounded-md text-xs border border-red-200">
          <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
          <div className="space-y-1">
            <p>{error}</p>
            <Button
              variant="outline"
              size="sm"
              onClick={startCamera}
              className="h-7 text-xs mt-1 bg-white"
            >
              Tentar Novamente
            </Button>
          </div>
        </div>
      )}

      {!cameraActive && !capturedPhoto && (
        <Button
          onClick={startCamera}
          className="bg-emerald-600 hover:bg-emerald-700 text-white font-medium"
        >
          <Camera className="h-4 w-4 mr-2" /> Abrir Câmera
        </Button>
      )}

      {cameraActive && (
        <div className="space-y-3 max-w-sm">
          <div className="relative rounded-lg overflow-hidden border-2 border-emerald-500 bg-black aspect-[4/3] shadow-md">
            <video
              ref={videoRef}
              autoPlay
              playsInline
              muted
              className="w-full h-full object-cover -scale-x-100"
            />
            <div className="absolute inset-0 border-2 border-dashed border-white/40 rounded-full m-8 pointer-events-none flex items-center justify-center">
              <span className="text-white/80 text-[11px] bg-black/50 px-2 py-0.5 rounded backdrop-blur-sm">
                Centralize seu rosto
              </span>
            </div>
          </div>
          <div className="flex gap-2">
            <Button
              onClick={takePhoto}
              className="w-full bg-emerald-600 hover:bg-emerald-700 text-white font-medium"
            >
              <Camera className="h-4 w-4 mr-2" /> Tirar Foto
            </Button>
            <Button variant="ghost" onClick={stopStream} size="sm">
              Cancelar
            </Button>
          </div>
        </div>
      )}

      {capturedPhoto && (
        <div className="space-y-3 max-w-sm">
          <div className="rounded-lg overflow-hidden border border-slate-200 bg-slate-900 aspect-[4/3] shadow-inner">
            <img
              src={capturedPhoto}
              alt="Pré-visualização da selfie"
              className="w-full h-full object-cover"
            />
          </div>
          <div className="flex gap-2">
            <Button variant="outline" onClick={handleRetake} className="flex-1">
              <RefreshCw className="h-4 w-4 mr-2" /> Tirar Novamente
            </Button>
            <Button
              onClick={handleConfirm}
              className="flex-1 bg-emerald-600 hover:bg-emerald-700 text-white font-medium"
            >
              <Check className="h-4 w-4 mr-2" /> Confirmar
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}
