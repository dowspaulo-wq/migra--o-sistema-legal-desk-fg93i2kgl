import { useRef, useState, useEffect, forwardRef, useImperativeHandle, useCallback } from 'react'
import { Button } from '@/components/ui/button'
import { Eraser } from 'lucide-react'

export interface SignaturePadHandle {
  toDataURL: () => string | null
  clear: () => void
  isEmpty: () => boolean
}

export const SignaturePad = forwardRef<
  SignaturePadHandle,
  { className?: string; onChange?: (hasContent: boolean) => void }
>(({ className, onChange }, ref) => {
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
      ctx.lineWidth = 2
      ctx.lineCap = 'round'
      ctx.lineJoin = 'round'
      ctx.strokeStyle = '#1e293b'
    }
    setup()
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
    if (!hasContent) updateContent(true)
  }

  const end = () => {
    drawingRef.current = false
  }

  const clear = () => {
    const canvas = canvasRef.current!
    const ctx = canvas.getContext('2d')!
    ctx.clearRect(0, 0, canvas.width, canvas.height)
    updateContent(false)
  }

  const toDataURL = () => (hasContent ? canvasRef.current?.toDataURL('image/png') || null : null)

  useImperativeHandle(ref, () => ({ toDataURL, clear, isEmpty: () => !hasContent }))

  return (
    <div className={className}>
      <canvas
        ref={canvasRef}
        className="w-full h-48 border-2 border-dashed border-slate-300 rounded-lg bg-white touch-none cursor-crosshair"
        onPointerDown={start}
        onPointerMove={draw}
        onPointerUp={end}
        onPointerLeave={end}
      />
      <Button type="button" variant="outline" size="sm" onClick={clear} className="mt-2">
        <Eraser className="h-4 w-4 mr-2" /> Limpar
      </Button>
    </div>
  )
})
SignaturePad.displayName = 'SignaturePad'
