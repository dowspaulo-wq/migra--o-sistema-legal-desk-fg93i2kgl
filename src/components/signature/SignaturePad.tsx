import React, { useRef, useState, useEffect } from 'react'
import { Button } from '@/components/ui/button'
import { RotateCcw } from 'lucide-react'

interface SignaturePadProps {
  onSave: (dataUrl: string | null) => void
  disabled?: boolean
}

export function SignaturePad({ onSave, disabled }: SignaturePadProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const [isDrawing, setIsDrawing] = useState(false)
  const [isEmpty, setIsEmpty] = useState(true)

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const ctx = canvas.getContext('2d')
    if (!ctx) return
    ctx.lineWidth = 2.5
    ctx.lineCap = 'round'
    ctx.strokeStyle = '#0f172a'
  }, [])

  const getPos = (e: React.MouseEvent<HTMLCanvasElement> | React.TouchEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current
    if (!canvas) return { x: 0, y: 0 }
    const rect = canvas.getBoundingClientRect()
    const clientX = 'touches' in e ? e.touches[0].clientX : e.clientX
    const clientY = 'touches' in e ? e.touches[0].clientY : e.clientY
    return {
      x: (clientX - rect.left) * (canvas.width / rect.width),
      y: (clientY - rect.top) * (canvas.height / rect.height),
    }
  }

  const startDrawing = (
    e: React.MouseEvent<HTMLCanvasElement> | React.TouchEvent<HTMLCanvasElement>,
  ) => {
    if (disabled) return
    setIsDrawing(true)
    setIsEmpty(false)
    const ctx = canvasRef.current?.getContext('2d')
    const pos = getPos(e)
    ctx?.beginPath()
    ctx?.moveTo(pos.x, pos.y)
  }

  const draw = (e: React.MouseEvent<HTMLCanvasElement> | React.TouchEvent<HTMLCanvasElement>) => {
    if (!isDrawing || disabled) return
    e.preventDefault()
    const ctx = canvasRef.current?.getContext('2d')
    const pos = getPos(e)
    ctx?.lineTo(pos.x, pos.y)
    ctx?.stroke()
  }

  const stopDrawing = () => {
    if (!isDrawing) return
    setIsDrawing(false)
    const canvas = canvasRef.current
    if (canvas && !isEmpty) {
      onSave(canvas.toDataURL('image/png'))
    }
  }

  const clear = () => {
    const canvas = canvasRef.current
    const ctx = canvas?.getContext('2d')
    if (canvas && ctx) {
      ctx.clearRect(0, 0, canvas.width, canvas.height)
      setIsEmpty(true)
      onSave(null)
    }
  }

  return (
    <div className="mt-2 space-y-2">
      <div className="relative rounded-lg border-2 border-dashed border-slate-300 bg-white overflow-hidden shadow-inner">
        <canvas
          ref={canvasRef}
          width={500}
          height={180}
          className="w-full h-44 touch-none cursor-crosshair"
          onMouseDown={startDrawing}
          onMouseMove={draw}
          onMouseUp={stopDrawing}
          onMouseLeave={stopDrawing}
          onTouchStart={startDrawing}
          onTouchMove={draw}
          onTouchEnd={stopDrawing}
        />
        {isEmpty && (
          <div className="absolute inset-0 pointer-events-none flex items-center justify-center text-slate-400 text-xs">
            Desenhe sua assinatura aqui com o dedo ou mouse
          </div>
        )}
      </div>
      <div className="flex justify-end">
        <Button
          type="button"
          variant="outline"
          size="sm"
          onClick={clear}
          disabled={isEmpty || disabled}
          className="text-xs bg-white"
        >
          <RotateCcw className="h-3.5 w-3.5 mr-1" /> Limpar
        </Button>
      </div>
    </div>
  )
}
