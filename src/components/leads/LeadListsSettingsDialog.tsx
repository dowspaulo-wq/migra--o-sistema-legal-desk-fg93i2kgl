import { useState } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { toast } from '@/hooks/use-toast'
import { Plus, ArrowUp, ArrowDown, Pencil, Check, X } from 'lucide-react'

// ============================================================
// EDITOR DE LISTAS DO MÓDULO DE LEADS
// Permite editar origem, etapa, área jurídica, assunto e tipo
// de interação dentro da própria aba Leads (estilo Settings).
// Etapas: id estável + rótulo editável (não quebra conversão).
// ============================================================

export interface LeadStageConfig {
  id: string
  label: string
}

export interface LeadListsConfig {
  leadOrigins: string[]
  leadStages: LeadStageConfig[]
  leadAreas: string[]
  leadSubjects: string[]
  leadInteractionTypes: string[]
}

interface LeadListsSettingsDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  config: LeadListsConfig
  onSave: (config: LeadListsConfig) => Promise<boolean>
}

function StringListEditor({
  title,
  description,
  items,
  onChange,
}: {
  title: string
  description: string
  items: string[]
  onChange: (items: string[]) => void
}) {
  const [newItem, setNewItem] = useState('')
  const [editingIdx, setEditingIdx] = useState<number | null>(null)
  const [editValue, setEditValue] = useState('')
  const [dragIdx, setDragIdx] = useState<number | null>(null)
  const [dragOverIdx, setDragOverIdx] = useState<number | null>(null)

  const move = (from: number, to: number) => {
    if (to < 0 || to >= items.length) return
    const next = [...items]
    const [it] = next.splice(from, 1)
    next.splice(to, 0, it)
    onChange(next)
  }

  const add = () => {
    const v = newItem.trim()
    if (!v) return
    if (items.some((i) => i.toLowerCase() === v.toLowerCase())) {
      toast({
        title: 'Item duplicado',
        description: `"${v}" já existe na lista.`,
        variant: 'destructive',
      })
      return
    }
    onChange([...items, v])
    setNewItem('')
  }

  const rename = (idx: number) => {
    const v = editValue.trim()
    if (!v) return
    if (items.some((i, j) => j !== idx && i.toLowerCase() === v.toLowerCase())) {
      toast({
        title: 'Item duplicado',
        description: `"${v}" já existe na lista.`,
        variant: 'destructive',
      })
      return
    }
    const next = [...items]
    next[idx] = v
    onChange(next)
    setEditingIdx(null)
    setEditValue('')
  }

  const remove = (idx: number) => {
    onChange(items.filter((_, j) => j !== idx))
  }

  return (
    <div className="space-y-2">
      <div>
        <Label className="text-sm font-medium">{title}</Label>
        <p className="text-xs text-muted-foreground">{description}</p>
      </div>
      <div className="rounded-lg border divide-y">
        {items.length === 0 && (
          <div className="p-3 text-xs text-muted-foreground">Nenhum item na lista.</div>
        )}
        {items.map((item, idx) => (
          <div
            key={`${item}-${idx}`}
            className={`flex items-center gap-2 px-2 py-1.5 ${
              dragOverIdx === idx && dragIdx !== null && dragIdx !== idx ? 'bg-sky-50' : ''
            }`}
            draggable={editingIdx !== idx}
            onDragStart={() => setDragIdx(idx)}
            onDragOver={(e) => {
              e.preventDefault()
              setDragOverIdx(idx)
            }}
            onDragLeave={() => setDragOverIdx(null)}
            onDrop={(e) => {
              e.preventDefault()
              if (dragIdx !== null && dragIdx !== idx) move(dragIdx, idx)
              setDragIdx(null)
              setDragOverIdx(null)
            }}
            onDragEnd={() => {
              setDragIdx(null)
              setDragOverIdx(null)
            }}
          >
            {editingIdx === idx ? (
              <>
                <Input
                  autoFocus
                  value={editValue}
                  onChange={(e) => setEditValue(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') {
                      e.preventDefault()
                      rename(idx)
                    }
                    if (e.key === 'Escape') setEditingIdx(null)
                  }}
                  className="h-7 text-sm"
                />
                <Button
                  type="button"
                  size="icon"
                  variant="ghost"
                  className="h-7 w-7"
                  onClick={() => rename(idx)}
                >
                  <Check className="h-3.5 w-3.5 text-emerald-600" />
                </Button>
                <Button
                  type="button"
                  size="icon"
                  variant="ghost"
                  className="h-7 w-7"
                  onClick={() => setEditingIdx(null)}
                >
                  <X className="h-3.5 w-3.5" />
                </Button>
              </>
            ) : (
              <>
                <span className="text-xs text-muted-foreground w-5 text-right">{idx + 1}</span>
                <span className="flex-1 text-sm">{item}</span>
                <div className="flex items-center gap-0.5">
                  <Button
                    type="button"
                    size="icon"
                    variant="ghost"
                    className="h-7 w-7"
                    disabled={idx === 0}
                    onClick={() => move(idx, idx - 1)}
                  >
                    <ArrowUp className="h-3.5 w-3.5" />
                  </Button>
                  <Button
                    type="button"
                    size="icon"
                    variant="ghost"
                    className="h-7 w-7"
                    disabled={idx === items.length - 1}
                    onClick={() => move(idx, idx + 1)}
                  >
                    <ArrowDown className="h-3.5 w-3.5" />
                  </Button>
                  <Button
                    type="button"
                    size="icon"
                    variant="ghost"
                    className="h-7 w-7"
                    onClick={() => {
                      setEditingIdx(idx)
                      setEditValue(item)
                    }}
                  >
                    <Pencil className="h-3.5 w-3.5" />
                  </Button>
                  <Button
                    type="button"
                    size="icon"
                    variant="ghost"
                    className="h-7 w-7 text-rose-600 hover:text-rose-700"
                    onClick={() => remove(idx)}
                  >
                    <X className="h-3.5 w-3.5" />
                  </Button>
                </div>
              </>
            )}
          </div>
        ))}
      </div>
      <div className="flex gap-2">
        <Input
          value={newItem}
          onChange={(e) => setNewItem(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault()
              add()
            }
          }}
          placeholder="Novo item..."
          className="h-8 text-sm"
        />
        <Button type="button" size="sm" variant="outline" onClick={add}>
          <Plus className="h-4 w-4 mr-1" /> Adicionar
        </Button>
      </div>
    </div>
  )
}

function StageListEditor({
  stages,
  onChange,
}: {
  stages: LeadStageConfig[]
  onChange: (stages: LeadStageConfig[]) => void
}) {
  const [editingIdx, setEditingIdx] = useState<number | null>(null)
  const [editValue, setEditValue] = useState('')
  const [dragIdx, setDragIdx] = useState<number | null>(null)
  const [dragOverIdx, setDragOverIdx] = useState<number | null>(null)

  const move = (from: number, to: number) => {
    if (to < 0 || to >= stages.length) return
    const next = [...stages]
    const [it] = next.splice(from, 1)
    next.splice(to, 0, it)
    onChange(next)
  }

  const rename = (idx: number) => {
    const v = editValue.trim()
    if (!v) return
    if (stages.some((s, j) => j !== idx && s.label.toLowerCase() === v.toLowerCase())) {
      toast({
        title: 'Etapa duplicada',
        description: `Já existe uma etapa com o nome "${v}".`,
        variant: 'destructive',
      })
      return
    }
    const next = [...stages]
    next[idx] = { ...next[idx], label: v }
    onChange(next)
    setEditingIdx(null)
    setEditValue('')
  }

  return (
    <div className="space-y-2">
      <div>
        <Label className="text-sm font-medium">Etapas do funil</Label>
        <p className="text-xs text-muted-foreground">
          Renomeie e reordene as 8 etapas. A etapa "Contratado" é alcançada pela conversão manual do
          lead em cliente, e a conversão continua disponível nas etapas "Qualificado" e "Proposta
          enviada" — não é possível adicionar nem remover etapas.
        </p>
      </div>
      <div className="rounded-lg border divide-y">
        {stages.map((s, idx) => (
          <div
            key={s.id}
            className={`flex items-center gap-2 px-2 py-1.5 ${
              dragOverIdx === idx && dragIdx !== null && dragIdx !== idx ? 'bg-sky-50' : ''
            }`}
            draggable={editingIdx !== idx}
            onDragStart={() => setDragIdx(idx)}
            onDragOver={(e) => {
              e.preventDefault()
              setDragOverIdx(idx)
            }}
            onDragLeave={() => setDragOverIdx(null)}
            onDrop={(e) => {
              e.preventDefault()
              if (dragIdx !== null && dragIdx !== idx) move(dragIdx, idx)
              setDragIdx(null)
              setDragOverIdx(null)
            }}
            onDragEnd={() => {
              setDragIdx(null)
              setDragOverIdx(null)
            }}
          >
            {editingIdx === idx ? (
              <>
                <Input
                  autoFocus
                  value={editValue}
                  onChange={(e) => setEditValue(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') {
                      e.preventDefault()
                      rename(idx)
                    }
                    if (e.key === 'Escape') setEditingIdx(null)
                  }}
                  className="h-7 text-sm"
                />
                <Button
                  type="button"
                  size="icon"
                  variant="ghost"
                  className="h-7 w-7"
                  onClick={() => rename(idx)}
                >
                  <Check className="h-3.5 w-3.5 text-emerald-600" />
                </Button>
                <Button
                  type="button"
                  size="icon"
                  variant="ghost"
                  className="h-7 w-7"
                  onClick={() => setEditingIdx(null)}
                >
                  <X className="h-3.5 w-3.5" />
                </Button>
              </>
            ) : (
              <>
                <span className="text-xs text-muted-foreground w-5 text-right">{idx + 1}</span>
                <span className="flex-1 text-sm">{s.label}</span>
                <div className="flex items-center gap-0.5">
                  <Button
                    type="button"
                    size="icon"
                    variant="ghost"
                    className="h-7 w-7"
                    disabled={idx === 0}
                    onClick={() => move(idx, idx - 1)}
                  >
                    <ArrowUp className="h-3.5 w-3.5" />
                  </Button>
                  <Button
                    type="button"
                    size="icon"
                    variant="ghost"
                    className="h-7 w-7"
                    disabled={idx === stages.length - 1}
                    onClick={() => move(idx, idx + 1)}
                  >
                    <ArrowDown className="h-3.5 w-3.5" />
                  </Button>
                  <Button
                    type="button"
                    size="icon"
                    variant="ghost"
                    className="h-7 w-7"
                    onClick={() => {
                      setEditingIdx(idx)
                      setEditValue(s.label)
                    }}
                  >
                    <Pencil className="h-3.5 w-3.5" />
                  </Button>
                </div>
              </>
            )}
          </div>
        ))}
      </div>
      <p className="text-xs text-muted-foreground">
        Ao renomear uma etapa, os leads já existentes passam a exibir o novo nome automaticamente.
      </p>
    </div>
  )
}

// Lista padrão usada quando o settings ainda não tem o campo (ex.: banco antigo)
export const LEAD_LISTS_DEFAULTS: LeadListsConfig = {
  leadOrigins: [
    'Meta Ads — Facebook',
    'Meta Ads — Instagram',
    'Google Ads',
    'Site institucional',
    'WhatsApp',
    'Indicação',
    'Contato orgânico',
    'Outros',
  ],
  leadStages: [
    { id: 'novo', label: 'Novo' },
    { id: 'aguardando', label: 'Aguardando contato' },
    { id: 'atendimento', label: 'Em atendimento' },
    { id: 'qualificado', label: 'Qualificado' },
    { id: 'proposta', label: 'Proposta enviada' },
    { id: 'contratado', label: 'Contratado' },
    { id: 'perdido', label: 'Perdido' },
    { id: 'nao-qualificado', label: 'Não qualificado' },
  ],
  leadAreas: [
    'Trabalhista',
    'Cível',
    'Família e Sucessões',
    'Previdenciário',
    'Consumidor',
    'Tributário',
    'Empresarial',
    'Outra',
  ],
  leadSubjects: [
    'Rescisão indireta',
    'Horas extras',
    'Divórcio',
    'Pensão alimentícia',
    'Inventário',
    'Aposentadoria por idade',
    'Aposentadoria por tempo',
    'Benefício por incapacidade',
    'Cobrança indevida',
    'Indenização por danos morais',
    'Execução de título',
    'Contrato',
    'Outro',
  ],
  leadInteractionTypes: [
    'Ligação',
    'Mensagem',
    'Reunião',
    'Tentativa de contato',
    'Observação',
    'Proposta',
    'Mudança de etapa',
    'Outro',
  ],
}
export function LeadListsSettingsDialog({
  open,
  onOpenChange,
  config,
  onSave,
}: LeadListsSettingsDialogProps) {
  const [draft, setDraft] = useState<LeadListsConfig>(config)
  const [draftKey, setDraftKey] = useState(0)
  const [saving, setSaving] = useState(false)
  const [activeTab, setActiveTab] = useState('origens')

  // Reinicia o rascunho com o config atual sempre que o diálogo abre
  const handleOpenChange = (next: boolean) => {
    if (next) {
      setDraft(config)
      setDraftKey((k) => k + 1)
      setActiveTab('origens')
    }
    onOpenChange(next)
  }

  const handleSave = async () => {
    // Sanidade: nunca salvar sem as 8 etapas ou sem ids
    if (draft.leadStages.length !== 8 || draft.leadStages.some((s) => !s.id || !s.label.trim())) {
      toast({
        title: 'Etapas inválidas',
        description: 'O funil precisa ter exatamente as 8 etapas, todas com nome.',
        variant: 'destructive',
      })
      return
    }
    setSaving(true)
    const ok = await onSave(draft)
    setSaving(false)
    if (ok) onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-[560px] max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Configurar listas de leads</DialogTitle>
          <DialogDescription>
            Personalize as listas usadas no cadastro, nos filtros, no funil e ao registrar
            interações. Leads antigos continuam exibindo o valor salvo mesmo que o item seja
            removido daqui.
          </DialogDescription>
        </DialogHeader>

        <Tabs value={activeTab} onValueChange={setActiveTab}>
          <TabsList className="flex flex-wrap h-auto gap-1">
            <TabsTrigger value="origens">Origem</TabsTrigger>
            <TabsTrigger value="etapas">Etapas</TabsTrigger>
            <TabsTrigger value="areas">Área jurídica</TabsTrigger>
            <TabsTrigger value="assuntos">Assunto</TabsTrigger>
            <TabsTrigger value="interacoes">Interação</TabsTrigger>
          </TabsList>

          <TabsContent value="origens" className="pt-2">
            <StringListEditor
              key={`origins-${draftKey}`}
              title="Origem do lead"
              description="De onde vêm os leads (campanhas, canais, indicações...)."
              items={draft.leadOrigins}
              onChange={(items) => setDraft({ ...draft, leadOrigins: items })}
            />
          </TabsContent>

          <TabsContent value="etapas" className="pt-2">
            <StageListEditor
              stages={draft.leadStages}
              onChange={(stages) => setDraft({ ...draft, leadStages: stages })}
            />
          </TabsContent>

          <TabsContent value="areas" className="pt-2">
            <StringListEditor
              key={`areas-${draftKey}`}
              title="Área jurídica"
              description="Áreas de atuação oferecidas no cadastro e no filtro de leads."
              items={draft.leadAreas}
              onChange={(items) => setDraft({ ...draft, leadAreas: items })}
            />
          </TabsContent>

          <TabsContent value="assuntos" className="pt-2">
            <StringListEditor
              key={`subjects-${draftKey}`}
              title="Assunto jurídico"
              description="Assuntos selecionados no cadastro do lead."
              items={draft.leadSubjects}
              onChange={(items) => setDraft({ ...draft, leadSubjects: items })}
            />
          </TabsContent>

          <TabsContent value="interacoes" className="pt-2">
            <StringListEditor
              key={`interactions-${draftKey}`}
              title="Tipo de interação"
              description="Opções do 'Registrar interação' na ficha do lead."
              items={draft.leadInteractionTypes}
              onChange={(items) => setDraft({ ...draft, leadInteractionTypes: items })}
            />
          </TabsContent>
        </Tabs>

        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
            Cancelar
          </Button>
          <Button type="button" onClick={handleSave} disabled={saving}>
            {saving ? 'Salvando...' : 'Salvar listas'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

export default LeadListsSettingsDialog
