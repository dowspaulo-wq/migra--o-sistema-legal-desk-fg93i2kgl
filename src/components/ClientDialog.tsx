import { useState, useEffect } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
import { Label } from '@/components/ui/label'
import { Input } from '@/components/ui/input'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Button } from '@/components/ui/button'
import { Toggle } from '@/components/ui/toggle'
import { Textarea } from '@/components/ui/textarea'
import { Star } from 'lucide-react'
import { RichTextEditor } from '@/components/RichTextEditor'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'
import { BRAZILIAN_STATES, fetchCepData } from '@/lib/cep'
import { sanitizeDocument } from '@/lib/utils'
import {
  formatDocument,
  isValidDocumentFormat,
  getDocumentMaskPlaceholder,
  getDocumentMaxLength,
} from '@/lib/document-format'

function getEmptyForm(users: any[]) {
  const douglasUser = users.find((u: any) => u.name && u.name.toLowerCase().includes('douglas'))
  return {
    name: '',
    document: '',
    type: '',
    email: '',
    phone: '',
    address: '',
    cep: '',
    street: '',
    number: '',
    complement: '',
    neighborhood: '',
    city: '',
    state: '',
    birthday: '',
    status: '',
    isSpecial: false,
    observacoes: '',
    marital_status: '',
    responsibleId: douglasUser ? douglasUser.id : '',
    captacao: '',
  }
}

export function ClientDialog({ open, onOpenChange, client, onSave, users, settings }: any) {
  const { state } = useLegalStore()
  const isAdmin = state.currentUser?.role === 'Admin'
  const sortedUsers = [...users].sort((a: any, b: any) => a.name.localeCompare(b.name))
  const sortedCaptacao = [...(settings?.captacaoOptions || [])].sort((a: string, b: string) =>
    a.localeCompare(b),
  )

  const [formErrors, setFormErrors] = useState<Record<string, string>>({})
  const [cepLoading, setCepLoading] = useState(false)
  const [fd, setFd] = useState(() => {
    if (client) return client

    try {
      const draft = sessionStorage.getItem('client_form_draft')
      if (draft) {
        return JSON.parse(draft)
      }
    } catch {
      /* intentionally ignored */
    }

    return getEmptyForm(users)
  })

  useEffect(() => {
    setFormErrors({})
    if (client) {
      setFd(client)
    } else if (open) {
      try {
        const draft = sessionStorage.getItem('client_form_draft')
        if (draft) {
          setFd(JSON.parse(draft))
          return
        }
      } catch {
        /* intentionally ignored */
      }

      setFd(getEmptyForm(users))
    }
  }, [client, open, users])

  useEffect(() => {
    if (!client && open) {
      sessionStorage.setItem('client_form_draft', JSON.stringify(fd))
    }
  }, [fd, client, open])

  const clearDraft = () => {
    sessionStorage.removeItem('client_form_draft')
    setFd(getEmptyForm(users))
  }

  const handleCepChange = async (value: string) => {
    setFd((prev: any) => ({ ...prev, cep: value }))
    const cleanCep = value.replace(/\D/g, '')
    if (cleanCep.length !== 8) return

    setCepLoading(true)
    const cepData = await fetchCepData(cleanCep)
    setCepLoading(false)

    if (cepData) {
      setFd((prev: any) => ({
        ...prev,
        street: cepData.street || prev.street,
        neighborhood: cepData.neighborhood || prev.neighborhood,
        city: cepData.city || prev.city,
        state: cepData.state || prev.state,
      }))
    } else {
      toast({
        title: 'CEP não encontrado',
        description: 'Não foi possível buscar o endereço. Preencha manualmente.',
        variant: 'destructive',
      })
    }
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()

    if (!fd.name || !fd.type || !fd.status || !fd.responsibleId) {
      toast({
        title: 'Campos Obrigatórios',
        description: 'Nome, Tipo, Status e Responsável são de preenchimento obrigatório.',
        variant: 'destructive',
      })
      return
    }

    const mandatoryErrors: Record<string, string> = {}
    if (!fd.email?.trim()) mandatoryErrors.email = 'Este campo é obrigatório'
    if (!fd.phone?.trim()) mandatoryErrors.phone = 'Este campo é obrigatório'
    if (!fd.document?.trim()) {
      mandatoryErrors.document = 'Este campo é obrigatório'
    } else if (!isValidDocumentFormat(fd.document, fd.type)) {
      mandatoryErrors.document =
        fd.type === 'PJ'
          ? 'O CNPJ deve estar no formato 00.000.000/0000-00.'
          : 'O CPF deve estar no formato 000.000.000-00.'
    }
    if (Object.keys(mandatoryErrors).length > 0) {
      setFormErrors(mandatoryErrors)
      toast({
        title: 'Campos Obrigatórios',
        description: 'E-mail, Celular e CPF/CNPJ são de preenchimento obrigatório.',
        variant: 'destructive',
      })
      return
    }
    setFormErrors({})

    const requiredAddressFields = [
      { key: 'cep', label: 'CEP' },
      { key: 'street', label: 'Rua' },
      { key: 'number', label: 'Número' },
      { key: 'neighborhood', label: 'Bairro' },
      { key: 'city', label: 'Cidade' },
    ]
    const missingFields = requiredAddressFields.filter(
      (f) => !fd[f.key] || !String(fd[f.key]).trim(),
    )
    if (missingFields.length > 0) {
      toast({
        title: 'Campos de Endereço Obrigatórios',
        description: `Os seguintes campos são obrigatórios para integração com ASAAS: ${missingFields.map((f) => f.label).join(', ')}.`,
        variant: 'destructive',
      })
      return
    }

    const isDupName = state.clients.some(
      (c) => c.name.toLowerCase() === fd.name.toLowerCase() && c.id !== client?.id,
    )
    const isDupDoc = fd.document
      ? state.clients.some(
          (c) =>
            sanitizeDocument(c.document) === sanitizeDocument(fd.document) && c.id !== client?.id,
        )
      : false

    if (isDupName || isDupDoc) {
      toast({
        title: 'Erro',
        description: 'Já existe um cliente cadastrado com este Nome ou CPF/CNPJ.',
        variant: 'destructive',
      })
      return
    }

    const fullAddress = [fd.street, fd.number, fd.complement, fd.neighborhood, fd.city]
      .filter(Boolean)
      .join(', ')

    let formattedPhone = fd.phone?.replace(/\D/g, '') || ''
    if (formattedPhone && !formattedPhone.startsWith('55') && !/^0+$/.test(formattedPhone)) {
      formattedPhone = `55${formattedPhone}`
    }

    const payload = {
      ...fd,
      marital_status: fd.type === 'PJ' ? null : fd.marital_status || null,
      address: fullAddress,
      phone: formattedPhone,
    }
    const { isNew, ...finalPayload } = payload

    if (!client) {
      sessionStorage.removeItem('client_form_draft')
    }

    onSave(finalPayload)
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[600px] max-h-[90vh] overflow-y-auto">
        <form onSubmit={handleSubmit} className="grid gap-4">
          <DialogHeader>
            <DialogTitle>{client ? 'Editar' : 'Cadastrar'} Cliente</DialogTitle>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="col-span-2 flex justify-between items-end gap-4 pb-1">
              <div className="flex-1 space-y-2">
                <Label>Nome Completo *</Label>
                <Input
                  required
                  value={fd.name}
                  onChange={(e) => setFd({ ...fd, name: e.target.value })}
                />
              </div>
              <div className="flex gap-2">
                <Toggle
                  pressed={fd.isSpecial}
                  onPressedChange={(v) => setFd({ ...fd, isSpecial: v })}
                  variant="outline"
                  className={fd.isSpecial ? 'bg-yellow-50 border-yellow-200' : ''}
                  title="Cliente Especial"
                >
                  <Star
                    className={`h-4 w-4 ${fd.isSpecial ? 'fill-yellow-400 text-yellow-400' : 'text-slate-400'}`}
                  />
                </Toggle>
              </div>
            </div>

            <div className="space-y-2">
              <Label>
                {fd.type === 'PJ' ? 'CNPJ' : 'CPF'} <span className="text-red-500">*</span>
              </Label>
              <Input
                value={fd.document}
                onChange={(e) => {
                  const formatted = formatDocument(e.target.value, fd.type)
                  setFd({ ...fd, document: formatted })
                  setFormErrors((prev) => ({ ...prev, document: '' }))
                }}
                inputMode="numeric"
                maxLength={getDocumentMaxLength(fd.type)}
                placeholder={getDocumentMaskPlaceholder(fd.type)}
              />
              {formErrors.document && <p className="text-xs text-red-500">{formErrors.document}</p>}
            </div>

            <div className="space-y-2">
              <Label>Tipo *</Label>
              <Select
                value={fd.type}
                onValueChange={(v) => {
                  const reFormatted = fd.document ? formatDocument(fd.document, v) : ''
                  const isShorter = sanitizeDocument(fd.document).length > (v === 'PJ' ? 14 : 11)
                  setFd({
                    ...fd,
                    type: v,
                    document: isShorter ? '' : reFormatted,
                    marital_status: v === 'PJ' ? '' : fd.marital_status,
                  })
                  setFormErrors((prev) => ({ ...prev, document: '' }))
                }}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Selecione o Tipo" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="PF">PF</SelectItem>
                  <SelectItem value="PJ">PJ</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>Status *</Label>
              <Select value={fd.status} onValueChange={(v) => setFd({ ...fd, status: v })}>
                <SelectTrigger>
                  <SelectValue placeholder="Selecione o Status" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Ativo">Ativo</SelectItem>
                  <SelectItem value="Baixado">Baixado</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>Responsável *</Label>
              <Select
                value={fd.responsibleId}
                onValueChange={(v) => setFd({ ...fd, responsibleId: v })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Selecione o Responsável" />
                </SelectTrigger>
                <SelectContent>
                  {sortedUsers.map((u: any) => (
                    <SelectItem key={u.id} value={u.id}>
                      {u.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>Nascimento</Label>
              <Input
                type="date"
                value={fd.birthday}
                onChange={(e) => setFd({ ...fd, birthday: e.target.value })}
              />
            </div>

            <div className="space-y-2">
              <Label className={fd.type === 'PJ' ? 'text-muted-foreground' : ''}>
                Estado Civil
              </Label>
              <Select
                disabled={fd.type === 'PJ'}
                value={fd.type === 'PJ' ? '' : fd.marital_status || ''}
                onValueChange={(v) => setFd({ ...fd, marital_status: v })}
              >
                <SelectTrigger className={fd.type === 'PJ' ? 'bg-muted/50 cursor-not-allowed' : ''}>
                  <SelectValue
                    placeholder={
                      fd.type === 'PJ' ? 'Não aplicável para PJ' : 'Selecione o Estado Civil'
                    }
                  />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Solteiro(a)">Solteiro(a)</SelectItem>
                  <SelectItem value="Casado(a)">Casado(a)</SelectItem>
                  <SelectItem value="Divorciado(a)">Divorciado(a)</SelectItem>
                  <SelectItem value="Viúvo(a)">Viúvo(a)</SelectItem>
                  <SelectItem value="União Estável">União Estável</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>
                E-mail <span className="text-red-500">*</span>
              </Label>
              <Input
                type="email"
                value={fd.email}
                onChange={(e) => {
                  setFd({ ...fd, email: e.target.value })
                  setFormErrors((prev) => ({ ...prev, email: '' }))
                }}
              />
              {formErrors.email && <p className="text-xs text-red-500">{formErrors.email}</p>}
            </div>

            <div className="space-y-2">
              <Label>
                Celular (com DDI 55) <span className="text-red-500">*</span>
              </Label>
              <Input
                value={fd.phone || ''}
                onChange={(e) => {
                  const numericValue = e.target.value.replace(/\D/g, '')
                  setFd({ ...fd, phone: numericValue })
                  setFormErrors((prev) => ({ ...prev, phone: '' }))
                }}
                onBlur={() => {
                  if (fd.phone) {
                    let digits = fd.phone.replace(/\D/g, '')
                    if (digits && !digits.startsWith('55') && !/^0+$/.test(digits)) {
                      setFd((prev: any) => ({ ...prev, phone: `55${digits}` }))
                    }
                  }
                }}
                inputMode="numeric"
                placeholder="5531999999999"
              />
              {formErrors.phone && <p className="text-xs text-red-500">{formErrors.phone}</p>}
            </div>

            <div className="space-y-2">
              <Label>Captação</Label>
              <Select value={fd.captacao} onValueChange={(v) => setFd({ ...fd, captacao: v })}>
                <SelectTrigger>
                  <SelectValue placeholder="Selecione a Captação" />
                </SelectTrigger>
                <SelectContent>
                  {sortedCaptacao.map((c: string) => (
                    <SelectItem key={c} value={c}>
                      {c}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="col-span-2">
              <div className="flex items-center gap-2 mb-3">
                <div className="h-px flex-1 bg-border" />
                <span className="text-xs font-medium text-muted-foreground">Endereço</span>
                <div className="h-px flex-1 bg-border" />
              </div>
            </div>

            <div className="col-span-2 space-y-2">
              <Label>CEP *</Label>
              <Input
                value={fd.cep || ''}
                onChange={(e) => handleCepChange(e.target.value)}
                placeholder="00000-000"
              />
              {cepLoading && <p className="text-xs text-muted-foreground">Buscando endereço...</p>}
            </div>

            <div className="col-span-2 space-y-2">
              <Label>Rua *</Label>
              <Input
                value={fd.street || ''}
                onChange={(e) => setFd({ ...fd, street: e.target.value })}
              />
            </div>

            <div className="space-y-2">
              <Label>Número *</Label>
              <Input
                value={fd.number || ''}
                onChange={(e) => setFd({ ...fd, number: e.target.value })}
              />
            </div>

            <div className="space-y-2">
              <Label>Complemento</Label>
              <Input
                value={fd.complement || ''}
                onChange={(e) => setFd({ ...fd, complement: e.target.value })}
              />
            </div>

            <div className="col-span-2 space-y-2">
              <Label>Bairro *</Label>
              <Input
                value={fd.neighborhood || ''}
                onChange={(e) => setFd({ ...fd, neighborhood: e.target.value })}
              />
            </div>

            <div className="col-span-2 grid grid-cols-4 gap-4">
              <div className="col-span-3 space-y-2">
                <Label>Cidade *</Label>
                <Input
                  value={fd.city || ''}
                  onChange={(e) => setFd({ ...fd, city: e.target.value })}
                />
              </div>
              <div className="col-span-1 space-y-2">
                <Label>UF</Label>
                <Select value={fd.state || ''} onValueChange={(v) => setFd({ ...fd, state: v })}>
                  <SelectTrigger>
                    <SelectValue placeholder="UF" />
                  </SelectTrigger>
                  <SelectContent>
                    {BRAZILIAN_STATES.map((uf) => (
                      <SelectItem key={uf} value={uf}>
                        {uf}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>

            <div className="col-span-2 space-y-2">
              <Label>Observações</Label>
              <RichTextEditor
                value={fd.observacoes || ''}
                onChange={(v) => setFd({ ...fd, observacoes: v })}
                readOnly={!isAdmin}
                className={!isAdmin ? 'bg-muted/50 cursor-not-allowed' : ''}
              />
            </div>
          </div>
          <DialogFooter className="sm:justify-between w-full">
            {!client ? (
              <Button type="button" variant="outline" onClick={clearDraft}>
                Limpar
              </Button>
            ) : (
              <div />
            )}
            <Button type="submit">Salvar</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
