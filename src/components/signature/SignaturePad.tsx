import { useRef, useState, useEffect, forwardRef, useImperativeHandle, useCallback } from 'react'
import { Button } from '@/components/ui/button'
import { Eraser } from 'lucide-react'

export interface SignaturePadHandle {
  toDataURL: () => string | null
  clear: () => void
  isEmpty: () => boolean
}

export interface SignaturePadProps {
  className?: string
  onChange?: (hasContent: boolean) => void
  onSave?: (dataUrl: string | null) => void
}

export const SignaturePad = forwardRef<SignaturePadHandle, SignaturePadProps>(
  ({ className, onChange, onSave }, ref) => {
    const canvasRef = useRef<HTMLCanvasElement>(null)
    const drawingRef = useRef(false)
    const [hasContent, setHasContent] = useState(false)

    const updateContent = useCallback(
      (value: boolean) => {
        setHasContent(value)
        onChange?.(value)
      },
      [onChange],
    )

    useEffect(() => {
      const canvas = canvasRef.current
      if (!canvas) return
      const ctx = canvas.getContext('2d')!

      const setup = () => {
        const rect = canvas.getBoundingClientRect()
        const dpr = window.devicePixelRatio || 1
        canvas.width = rect.width * dpr
        canvas.height = rect.height * dpr
        ctx.scale(dpr, dpr)
        ctx.lineWidth = 2.5
        ctx.lineCap = 'round'
        ctx.lineJoin = 'round'
        ctx.strokeStyle = '#0f172a'
      }

      setup()
      window.addEventListener('resize', setup)
      return () => window.removeEventListener('resize', setup)
    }, [])

    const getPos = (e: React.PointerEvent) => {
      const rect = canvasRef.current!.getBoundingClientRect()
      return { x: e.clientX - rect.left, y: e.clientY - rect.top }
    }

    const start = (e: React.PointerEvent) => {
      e.preventDefault()
      const ctx = canvasRef.current!.getContext('2d')!
      const { x, y } = getPos(e)
      ctx.beginPath()
      ctx.moveTo(x, y)
      drawingRef.current = true
    }

    const draw = (e: React.PointerEvent) => {
      if (!drawingRef.current) return
      e.preventDefault()
      const ctx = canvasRef.current!.getContext('2d')!
      const { x, y } = getPos(e)
      ctx.lineTo(x, y)
      ctx.stroke()
      if (!hasContent) {
        updateContent(true)
      }
    }

    const end = () => {
      if (drawingRef.current) {
        drawingRef.current = false
        if (canvasRef.current) {
          const dataUrl = canvasRef.current.toDataURL('image/png')
          onSave?.(dataUrl)
        }
      }
    }

    const clear = () => {
      const canvas = canvasRef.current!
      const ctx = canvas.getContext('2d')!
      ctx.clearRect(0, 0, canvas.width, canvas.height)
      updateContent(false)
      onSave?.(null)
    }

    const toDataURL = () => (hasContent ? canvasRef.current?.toDataURL('image/png') || null : null)

    useImperativeHandle(ref, () => ({ toDataURL, clear, isEmpty: () => !hasContent }))

    return (
      <div className={className}>
        <div className="relative">
          <canvas
            ref={canvasRef}
            className="w-full h-48 border-2 border-dashed border-slate-300 rounded-lg bg-white touch-none cursor-crosshair shadow-inner"
            onPointerDown={start}
            onPointerMove={draw}
            onPointerUp={end}
            onPointerLeave={end}
          />
          <p className="absolute bottom-2 right-3 text-[10px] text-slate-400 pointer-events-none select-none">
            Desenhe sua assinatura no quadro acima
          </p>
        </div>
        <div className="flex justify-between items-center mt-2">
          <span className="text-xs text-slate-500">
            {hasContent ? 'Assinatura capturada' : 'Aguardando desenho da assinatura...'}
          </span>
          <Button type="button" variant="outline" size="sm" onClick={clear} className="text-xs h-8">
            <Eraser className="h-3.5 w-3.5 mr-1.5" /> Limpar
          </Button>
        </div>
      </div>
    )
  },
)
SignaturePad.displayName = 'SignaturePad'
