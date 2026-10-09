import { useState, useEffect } from 'react'
import { RichTextEditor } from '@/components/RichTextEditor'
import { stripHtml } from '@/lib/utils'
import { Lock, PlusCircle } from 'lucide-react'

export interface ProtectedRichTextProps {
  initialValue: string
  onChange: (val: string) => void
  isAdmin: boolean
  placeholderNew?: string
  className?: string
  minHeight?: string
}

export function ProtectedRichText({
  initialValue,
  onChange,
  isAdmin,
  placeholderNew = 'Digite o novo conteúdo para acrescentar...',
  className,
}: ProtectedRichTextProps) {
  // Se for admin, o comportamento é edição livre direta do valor completo
  const [adminValue, setAdminValue] = useState(initialValue || '')

  // Se for colaborador, separa o conteúdo original bloqueado e a nova adição
  const [additionHtml, setAdditionHtml] = useState('')

  // Atualiza estado interno quando initialValue muda externamente
  useEffect(() => {
    setAdminValue(initialValue || '')
    setAdditionHtml('')
  }, [initialValue])

  const hasInitialContent = Boolean(stripHtml(initialValue).trim())

  // Para ADM: editor normal direto
  if (isAdmin) {
    return (
      <RichTextEditor
        value={adminValue}
        onChange={(val) => {
          setAdminValue(val)
          onChange(val)
        }}
        className={className}
      />
    )
  }

  // Para Colaborador quando NÃO há conteúdo anterior gravado:
  // pode digitar livremente como se fosse novo
  if (!hasInitialContent) {
    return (
      <RichTextEditor
        value={adminValue}
        onChange={(val) => {
          setAdminValue(val)
          onChange(val)
        }}
        className={className}
      />
    )
  }

  // Para Colaborador com conteúdo existente:
  // Bloco travado (somente leitura) do texto antigo + editor para acrescentar novo texto
  const handleAdditionChange = (newHtml: string) => {
    setAdditionHtml(newHtml)

    const cleanAddition = stripHtml(newHtml).trim()
    if (!cleanAddition) {
      // Se não há texto novo real, o valor salvo é o original intacto
      onChange(initialValue)
    } else {
      // Junta o original com a adição
      const combined = `${initialValue.trim()}<br /><br />${newHtml.trim()}`
      onChange(combined)
    }
  }

  return (
    <div className="space-y-2">
      {/* Bloco de conteúdo anterior protegido */}
      <div className="rounded-md border border-amber-200/80 bg-amber-50/40 p-3 text-sm">
        <div className="flex items-center gap-1.5 pb-2 mb-2 border-b border-amber-200/60 text-xs font-semibold text-amber-900">
          <Lock className="h-3.5 w-3.5 text-amber-700" />
          <span>Conteúdo anterior registrado (protegido contra exclusão)</span>
        </div>
        <div
          className="prose prose-sm max-w-none text-slate-800 break-words max-h-48 overflow-y-auto pr-1"
          dangerouslySetInnerHTML={{ __html: initialValue }}
        />
      </div>

      {/* Bloco para inserção de novo texto */}
      <div className="space-y-1">
        <div className="flex items-center gap-1 text-xs font-medium text-muted-foreground">
          <PlusCircle className="h-3.5 w-3.5 text-primary" />
          <span>{placeholderNew}</span>
        </div>
        <RichTextEditor
          value={additionHtml}
          onChange={handleAdditionChange}
          className={className}
        />
      </div>
    </div>
  )
}
