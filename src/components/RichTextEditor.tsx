import { useRef, useEffect } from 'react'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { Button } from '@/components/ui/button'
import { Bold, Underline, Smile, Palette } from 'lucide-react'
import { cn } from '@/lib/utils'

const COLORS = [
  '#000000',
  '#dc2626',
  '#ea580c',
  '#ca8a04',
  '#16a34a',
  '#0891b2',
  '#2563eb',
  '#7c3aed',
  '#db2777',
]
const EMOJIS = [
  '😀',
  '😎',
  '🤔',
  '👍',
  '👎',
  '❤️',
  '⭐',
  '⚠️',
  '✅',
  '❌',
  '📌',
  '🎯',
  '💡',
  '🔥',
  '💰',
  '⚖️',
  '🏆',
  '📋',
  '✍️',
  '🕐',
  '😢',
  '😡',
  '🤝',
  '📞',
  '📧',
  '📦',
  '🔍',
  '📝',
  '🆗',
  '🚫',
]

export function RichTextEditor({
  value,
  onChange,
  readOnly,
  className,
}: {
  value: string
  onChange?: (v: string) => void
  readOnly?: boolean
  className?: string
}) {
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (ref.current && ref.current.innerHTML !== value) {
      ref.current.innerHTML = value || ''
    }
  }, [value])

  if (readOnly) {
    return (
      <div
        className={cn('text-sm prose prose-sm max-w-none', className)}
        dangerouslySetInnerHTML={{
          __html: value || '<span class="text-muted-foreground italic">Não informado</span>',
        }}
      />
    )
  }

  const exec = (cmd: string, val?: string) => {
    ref.current?.focus()
    document.execCommand(cmd, false, val)
    if (ref.current && onChange) onChange(ref.current.innerHTML)
  }

  return (
    <div className={cn('border rounded-md overflow-hidden', className)}>
      <div className="flex items-center gap-1 border-b p-1.5 bg-muted/30 flex-wrap">
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="h-7 w-7"
          onMouseDown={(e) => {
            e.preventDefault()
            exec('bold')
          }}
          title="Negrito"
        >
          <Bold className="h-4 w-4" />
        </Button>
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="h-7 w-7"
          onMouseDown={(e) => {
            e.preventDefault()
            exec('underline')
          }}
          title="Sublinhado"
        >
          <Underline className="h-4 w-4" />
        </Button>
        <Popover>
          <PopoverTrigger asChild>
            <Button
              type="button"
              variant="ghost"
              size="icon"
              className="h-7 w-7"
              title="Cor do texto"
            >
              <Palette className="h-4 w-4" />
            </Button>
          </PopoverTrigger>
          <PopoverContent className="w-auto p-2" align="start">
            <div className="flex flex-wrap gap-1 max-w-[160px]">
              {COLORS.map((c) => (
                <button
                  key={c}
                  type="button"
                  className="w-6 h-6 rounded border border-border"
                  style={{ backgroundColor: c }}
                  onMouseDown={(e) => {
                    e.preventDefault()
                    exec('foreColor', c)
                  }}
                />
              ))}
            </div>
          </PopoverContent>
        </Popover>
        <Popover>
          <PopoverTrigger asChild>
            <Button type="button" variant="ghost" size="icon" className="h-7 w-7" title="Emoji">
              <Smile className="h-4 w-4" />
            </Button>
          </PopoverTrigger>
          <PopoverContent className="w-auto p-2" align="start">
            <div className="flex flex-wrap gap-1 max-w-[200px]">
              {EMOJIS.map((e) => (
                <button
                  key={e}
                  type="button"
                  className="text-xl hover:bg-muted rounded p-0.5"
                  onMouseDown={(ev) => {
                    ev.preventDefault()
                    exec('insertText', e)
                  }}
                >
                  {e}
                </button>
              ))}
            </div>
          </PopoverContent>
        </Popover>
      </div>
      <div
        ref={ref}
        contentEditable
        suppressContentEditableWarning
        onInput={() => ref.current && onChange?.(ref.current.innerHTML)}
        onBlur={() => ref.current && onChange?.(ref.current.innerHTML)}
        className="min-h-[60px] p-3 text-sm outline-none prose prose-sm max-w-none"
        style={{ wordBreak: 'break-word' }}
      />
    </div>
  )
}
