import { useEffect, useMemo, useState } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
  DialogDescription,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { Input } from '@/components/ui/input'
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group'
import { Badge } from '@/components/ui/badge'
import { Checkbox } from '@/components/ui/checkbox'
import { type Lead } from '@/stores/useLeadsStore'
import { findExistingClients } from '@/stores/useLeadsStore'
import { sanitizeDocument } from '@/lib/utils'
import { toast } from '@/hooks/use-toast'
import { AlertTriangle, CheckCircle2, Link2, UserPlus } from 'lucide-react'

interface ConvertLeadDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  lead: Lead | null
  clients: Array<Record<string, any>>
  onConvert: (
    lead: Lead,
    mode: 'create' | 'link',
    clientPayload: Record<string, unknown> | null,
    existingClientId: string | null,
  ) => Promise<{ ok: boolean; clientId?: string }>
}

const onlyDigits = (v: string) => (v || '').replace(/\D/g, '')

export function ConvertLeadDialog({
  open,
  onOpenChange,
  lead,
  clients,
  onConvert,
}: ConvertLeadDialogProps) {
  const [mode, setMode] = useState<'create' | 'link'>('create')
  const [confirmChecked, setConfirmChecked] = useState(false)
  const [running, setRunning] = useState(false)

  // Campos obrigatórios mínimos para criar cliente a partir do lead
  const [name, setName] = useState('')
  const [phone, setPhone] = useState('')
  const [email, setEmail] = useState('')
  const [document, setDocument] = useState('')
  const [city, setCity] = useState('')
  const [state, setState] = useState('')

  // Match pré-calculado a partir dos dados do lead
  const preMatches = useMemo(() => {
    if (!lead) return { byDocument: [], byName: [], byPhone: [] }
    return findExistingClients(clients, '', lead.name || '', lead.phone || '')
  }, [lead, clients])

  const preMatchesFlat = useMemo(
    () => [
      ...preMatches.byDocument,
      ...preMatches.byName.filter((c) => !preMatches.byDocument.includes(c)),
      ...preMatches.byPhone.filter(
        (c) => !preMatches.byDocument.includes(c) && !preMatches.byName.includes(c),
      ),
    ],
    [preMatches],
  )

  useEffect(() => {
    if (open && lead) {
      setConfirmChecked(false)
      setRunning(false)
      setMode(preMatchesFlat.length > 0 ? 'link' : 'create')
      setName(lead.name || '')
      setPhone(lead.phone || '')
      setEmail(lead.email || '')
      setDocument('')
      setCity(lead.city || '')
      setState(lead.state || '')
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, lead?.id])

  // Pesquisa clientes existentes por documento / nome / telefone em tempo real
  const matches = useMemo(() => {
    if (!open) return { byDocument: [], byName: [], byPhone: [] }
    return findExistingClients(clients, document, name, phone)
  }, [open, document, name, phone, clients])

  const matchesFlat = useMemo(
    () => [
      ...matches.byDocument,
      ...matches.byName.filter((c) => !matches.byDocument.includes(c)),
      ...matches.byPhone.filter(
        (c) => !matches.byDocument.includes(c) && !matches.byName.includes(c),
      ),
    ],
    [matches],
  )

  if (!lead) return null

  const handleSubmit = async () => {
    if (!confirmChecked) {
      toast({
        title: 'Confirmação obrigatória',
        description: 'Marque a caixa confirmando que a contratação foi efetivamente confirmada.',
        variant: 'destructive',
      })
      return
    }
    if (mode === 'link') {
      if (matchesFlat.length === 0) {
        toast({
          title: 'Nenhum cliente selecionado',
          description: 'Localize o cliente existente antes de vincular.',
          variant: 'destructive',
        })
        return
      }
      setRunning(true)
      const res = await onConvert(lead, 'link', null, matchesFlat[0].id)
      setRunning(false)
      if (res.ok) onOpenChange(false)
      return
    }
    // modo criar
    if (!name.trim() || (!phone.trim() && !email.trim())) {
      toast({
        title: 'Dados insuficientes',
        description: 'Nome e (telefone ou e-mail) são obrigatórios para criar o cliente.',
        variant: 'destructive',
      })
      return
    }
    setRunning(true)
    const payload: Record<string, unknown> = {
      name: name.trim().toUpperCase(),
      phone: phone.trim() || null,
      email: email.trim() || null,
      document: sanitizeDocument(document) || null,
      city: city.trim() || null,
      state: state.trim() || null,
      status: 'Ativo',
    }
    const res = await onConvert(lead, 'create', payload, null)
    setRunning(false)
    if (res.ok) onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[640px] max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Converter lead em cliente</DialogTitle>
          <DialogDescription>
            Conversão manual e definitiva. O lead sai do funil, mantém o histórico, e o cliente é
            criado ou vinculado — só então o lead é marcado como "Contratado".
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          {/* Duplicidade com clientes existentes */}
          {preMatchesFlat.length > 0 && (
            <div className="rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm">
              <div className="flex items-center gap-2 font-medium text-amber-900">
                <AlertTriangle className="h-4 w-4" />
                Possível cliente já cadastrado
              </div>
              <div className="mt-1 text-xs text-amber-800">
                Encontrei clientes com nome/telefone semelhantes. Prefira VINCULAR em vez de criar
                duplicado.
              </div>
              <ul className="mt-2 space-y-1">
                {preMatchesFlat.slice(0, 5).map((c) => (
                  <li key={c.id} className="text-xs text-amber-900">
                    • {c.name} {c.phone ? `· ${c.phone}` : ''} {c.document ? `· ${c.document}` : ''}
                  </li>
                ))}
              </ul>
            </div>
          )}

          <RadioGroup
            value={mode}
            onValueChange={(v) => setMode(v as 'create' | 'link')}
            className="grid grid-cols-2 gap-3"
          >
            <label
              className={`flex items-start gap-2 rounded-lg border p-3 cursor-pointer ${
                mode === 'create' ? 'border-primary bg-primary/5' : ''
              }`}
            >
              <RadioGroupItem value="create" className="mt-0.5" />
              <div>
                <div className="flex items-center gap-1.5 text-sm font-medium">
                  <UserPlus className="h-4 w-4" /> Criar novo cliente
                </div>
                <div className="text-xs text-muted-foreground">
                  Cria o cadastro com os dados do lead; só peça o que falta.
                </div>
              </div>
            </label>
            <label
              className={`flex items-start gap-2 rounded-lg border p-3 cursor-pointer ${
                mode === 'link' ? 'border-primary bg-primary/5' : ''
              }`}
            >
              <RadioGroupItem value="link" className="mt-0.5" />
              <div>
                <div className="flex items-center gap-1.5 text-sm font-medium">
                  <Link2 className="h-4 w-4" /> Vincular a cliente existente
                </div>
                <div className="text-xs text-muted-foreground">
                  O lead é marcado como convertido apontando para o cliente já cadastrado.
                </div>
              </div>
            </label>
          </RadioGroup>

          {mode === 'link' ? (
            <div className="space-y-2">
              <Label>Localizar cliente (nome, telefone ou documento)</Label>
              <Input
                placeholder="Digite para pesquisar..."
                value={document || phone || ''}
                onChange={(e) => {
                  const v = e.target.value
                  setDocument(onlyDigits(v).length >= 5 ? v : '')
                  setPhone(v)
                }}
              />
              {matchesFlat.length > 0 ? (
                <div className="rounded-lg border divide-y max-h-48 overflow-y-auto">
                  {matchesFlat.slice(0, 8).map((c) => (
                    <button
                      key={c.id}
                      type="button"
                      className="w-full text-left px-3 py-2 hover:bg-slate-50 text-sm"
                      onClick={() => {
                        setDocument(c.document || '')
                        setPhone(c.phone || '')
                        setName(c.name || '')
                      }}
                    >
                      <div className="font-medium">{c.name}</div>
                      <div className="text-xs text-muted-foreground">
                        {[c.phone, c.email, c.document].filter(Boolean).join(' · ') || '—'}
                      </div>
                    </button>
                  ))}
                </div>
              ) : (
                <div className="text-xs text-muted-foreground">
                  Nenhum cliente encontrado com esses dados.
                </div>
              )}
            </div>
          ) : (
            <div className="grid grid-cols-2 gap-3">
              <div className="col-span-2 space-y-1">
                <Label>Nome *</Label>
                <Input value={name} onChange={(e) => setName(e.target.value.toUpperCase())} />
              </div>
              <div className="space-y-1">
                <Label>Telefone</Label>
                <Input value={phone} onChange={(e) => setPhone(e.target.value)} />
              </div>
              <div className="space-y-1">
                <Label>E-mail</Label>
                <Input value={email} onChange={(e) => setEmail(e.target.value)} />
              </div>
              <div className="space-y-1">
                <Label>CPF/CNPJ</Label>
                <Input
                  value={document}
                  onChange={(e) => setDocument(e.target.value)}
                  placeholder="Opcional"
                />
              </div>
              <div className="grid grid-cols-[1fr_80px] gap-2">
                <div className="space-y-1">
                  <Label>Cidade</Label>
                  <Input value={city} onChange={(e) => setCity(e.target.value)} />
                </div>
                <div className="space-y-1">
                  <Label>UF</Label>
                  <Input value={state} onChange={(e) => setState(e.target.value.toUpperCase())} />
                </div>
              </div>
            </div>
          )}

          {/* Confirmação explícita */}
          <label className="flex items-start gap-2 rounded-lg border p-3 cursor-pointer bg-slate-50">
            <Checkbox
              checked={confirmChecked}
              onCheckedChange={(v) => setConfirmChecked(v === true)}
              className="mt-0.5"
            />
            <span className="text-sm">
              Confirmo que <strong>{lead.name}</strong> efetivamente contratou os serviços do
              escritório. Entendo que esta ação marca o lead como <Badge>Contratado</Badge> e não
              pode ser desfeita por aqui.
            </span>
          </label>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={running}>
            Cancelar
          </Button>
          <Button
            className="bg-emerald-600 hover:bg-emerald-700"
            onClick={handleSubmit}
            disabled={running || !confirmChecked}
          >
            <CheckCircle2 className="h-4 w-4 mr-1" />
            {running ? 'Convertendo...' : 'Confirmar conversão'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
