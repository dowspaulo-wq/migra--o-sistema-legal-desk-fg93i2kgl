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
import { Checkbox } from '@/components/ui/checkbox'
import { Star, ScanLine, Loader2, X, CheckCircle2 } from 'lucide-react'
import { ProtectedRichText } from '@/components/ProtectedRichText'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'
import { BRAZILIAN_STATES, fetchCepData } from '@/lib/cep'
import { sanitizeDocument, formatPhone, sanitizeClientPhone, isValidClientPhone } from '@/lib/utils'
import {
  formatDocument,
  isValidDocumentFormat,
  getDocumentMaskPlaceholder,
  getDocumentMaxLength,
} from '@/lib/document-format'
import {
  extractTextFromPdfOrScanned,
  runTesseractOcr,
  parseDocumentText,
  ExtractedClientData,
} from '@/lib/ocr-document-scanner'

function getEmptyForm(users: any[]) {
  const douglasUser = users.find((u: any) => u.name && u.name.toLowerCase().includes('douglas'))
  return {
    name: '',
    document: '',
    type: '',
    email: '',
    phone: '',
    no_phone: false,
    no_email: false,
    phone_na: false,
    email_na: false,
    address: '',
    cep: '',
    street: '',
    number: '',
    complement: '',
    neighborhood: '',
    city: '',
    state: '',
    birthday: '',
    hide_birthday: false,
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
  const isAdmin = ['admin', 'adm'].includes((state.currentUser?.role || '').toLowerCase())
  const sortedUsers = [...users].sort((a: any, b: any) => a.name.localeCompare(b.name))
  const sortedCaptacao = [...(settings?.captacaoOptions || [])].sort((a: string, b: string) =>
    a.localeCompare(b),
  )

  const [formErrors, setFormErrors] = useState<Record<string, string>>({})
  const [cepLoading, setCepLoading] = useState(false)
  const [ocrLoading, setOcrLoading] = useState(false)
  const [ocrProgress, setOcrProgress] = useState(0)
  const [ocrStatusText, setOcrStatusText] = useState('')
  const [ocrNotice, setOcrNotice] = useState<string | null>(null)
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
    setOcrLoading(false)
    setOcrNotice(null)
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
    setOcrNotice(null)
    setFd(getEmptyForm(users))
  }

  const handleDocumentScan = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    // Limpa o input imediatamente para que o mesmo arquivo possa ser relido e o ponteiro não seja retido
    e.target.value = ''
    if (!file) return

    setOcrLoading(true)
    setOcrProgress(5)
    setOcrStatusText('Lendo documento...')
    setOcrNotice(null)

    try {
      let rawText = ''
      const isPdf = file.type === 'application/pdf' || file.name.toLowerCase().endsWith('.pdf')

      if (isPdf) {
        rawText = await extractTextFromPdfOrScanned(file, (p, msg) => {
          setOcrProgress(p)
          setOcrStatusText(msg)
        })
      } else {
        // Imagem (PNG, JPG, WEBP, etc.)
        setOcrProgress(15)
        setOcrStatusText('Carregando imagem em memória...')
        rawText = await runTesseractOcr(file, (p, msg) => {
          setOcrProgress(p)
          setOcrStatusText(msg)
        })
      }

      const parsed: ExtractedClientData = parseDocumentText(rawText)

      const appliedFields: string[] = []
      setFd((prev: any) => {
        const updated = { ...prev }

        if (parsed.name && !prev.name) {
          updated.name = parsed.name
          appliedFields.push('Nome')
        } else if (parsed.name) {
          updated.name = parsed.name // Sobrescreve com o documento lido
          appliedFields.push('Nome')
        }

        if (parsed.document) {
          updated.document = parsed.document
          if (parsed.type) updated.type = parsed.type
          appliedFields.push(parsed.type === 'PJ' ? 'CNPJ' : 'CPF')
        }

        if (parsed.birthday) {
          updated.birthday = parsed.birthday
          appliedFields.push('Nascimento')
        }

        if (parsed.email && !prev.email) {
          updated.email = parsed.email
          updated.no_email = false
          appliedFields.push('E-mail')
        }

        if (parsed.phone && !prev.phone) {
          updated.phone = parsed.phone
          updated.no_phone = false
          appliedFields.push('Celular')
        }

        if (parsed.cep) {
          updated.cep = parsed.cep
          appliedFields.push('CEP')
        }

        if (parsed.street) {
          updated.street = parsed.street
          appliedFields.push('Rua')
        }

        if (parsed.number) {
          updated.number = parsed.number
          appliedFields.push('Número')
        }

        if (parsed.complement) {
          updated.complement = parsed.complement
        }

        if (parsed.neighborhood) {
          updated.neighborhood = parsed.neighborhood
          appliedFields.push('Bairro')
        }

        if (parsed.city) {
          updated.city = parsed.city
          appliedFields.push('Cidade')
        }

        if (parsed.state) {
          updated.state = parsed.state
          appliedFields.push('UF')
        }

        // Se encontrou RG, CNH, categoria ou filiação (mãe/pai), anota nas observações
        const extraNotes: string[] = []
        if (parsed.rg) {
          extraNotes.push(`Doc. Identidade/RG extraído: ${parsed.rg}`)
          appliedFields.push('RG')
        }
        if (parsed.cnhRegister) {
          extraNotes.push(`CNH Nº Registro: ${parsed.cnhRegister}`)
          appliedFields.push('Registro CNH')
        }
        if (parsed.cnhCategory) {
          extraNotes.push(`Categoria CNH: ${parsed.cnhCategory}`)
        }
        if (parsed.motherName) {
          extraNotes.push(`Mãe (Filiação): ${parsed.motherName}`)
          appliedFields.push('Mãe')
        }
        if (parsed.fatherName) {
          extraNotes.push(`Pai (Filiação): ${parsed.fatherName}`)
          appliedFields.push('Pai')
        }

        if (extraNotes.length > 0) {
          const joinedExtra = extraNotes.join('\n')
          if (!updated.observacoes) {
            updated.observacoes = joinedExtra
          } else {
            // Adiciona apenas as anotações que ainda não estejam presentes
            const newLines = extraNotes.filter((n) => !updated.observacoes.includes(n))
            if (newLines.length > 0) {
              updated.observacoes = `${updated.observacoes}\n\n${newLines.join('\n')}`
            }
          }
        }

        return updated
      })

      // Se temos CEP extraído mas rua/bairro/cidade faltou, busca via CEP
      if (parsed.cep && (!parsed.street || !parsed.city)) {
        const cleanCep = parsed.cep.replace(/\D/g, '')
        if (cleanCep.length === 8) {
          fetchCepData(cleanCep).then((cData) => {
            if (cData) {
              setFd((curr: any) => ({
                ...curr,
                street: curr.street || cData.street,
                neighborhood: curr.neighborhood || cData.neighborhood,
                city: curr.city || cData.city,
                state: curr.state || cData.state,
              }))
            }
          })
        }
      }

      if (appliedFields.length > 0) {
        setOcrNotice(
          `Campos pré-preenchidos: ${appliedFields.join(', ')}. Confira os dados extraídos antes de salvar.`,
        )
        toast({
          title: 'Documento lido com sucesso',
          description: `${appliedFields.length} campo(s) pré-preenchido(s). O arquivo foi descartado da memória.`,
        })
      } else {
        setOcrNotice(
          'Documento lido, mas nenhum campo específico foi reconhecido com certeza. O arquivo foi descartado.',
        )
        toast({
          title: 'Nenhum campo identificado',
          description:
            'A leitura terminou mas os campos não foram reconhecidos. Preencha manualmente.',
          variant: 'default',
        })
      }
    } catch (err: any) {
      console.error('Erro na leitura de documento OCR:', err)
      toast({
        title: 'Falha na leitura do documento',
        description: err?.message || 'Não foi possível ler o documento no navegador.',
        variant: 'destructive',
      })
    } finally {
      setOcrLoading(false)
      setOcrProgress(0)
      setOcrStatusText('')
    }
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
    const emailExempt = !!fd.no_email || !!fd.email_na
    const phoneExempt = !!fd.no_phone || !!fd.phone_na

    if (!emailExempt) {
      if (!fd.email?.trim()) {
        mandatoryErrors.email = 'Este campo é obrigatório'
      }
    }
    if (!phoneExempt) {
      if (!fd.phone?.trim()) {
        mandatoryErrors.phone = 'Este campo é obrigatório'
      } else if (!isValidClientPhone(fd.phone)) {
        mandatoryErrors.phone = 'Informe DDD + número (8 ou 9 dígitos). Ex.: (31) 98765-4321'
      }
    }
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
      const missingList: string[] = []
      if (!emailExempt && !fd.email?.trim()) missingList.push('E-mail')
      if (!phoneExempt && (!fd.phone?.trim() || !isValidClientPhone(fd.phone)))
        missingList.push('Celular')
      if (!fd.document?.trim() || !isValidDocumentFormat(fd.document, fd.type)) {
        missingList.push(fd.type === 'PJ' ? 'CNPJ' : 'CPF')
      }
      toast({
        title: 'Campos Obrigatórios',
        description: `Verifique os campos: ${missingList.join(', ')}.`,
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

    const sanitizedPhone = phoneExempt ? '' : sanitizeClientPhone(fd.phone)
    const sanitizedEmail = emailExempt ? '' : (fd.email || '').trim()

    const payload = {
      ...fd,
      marital_status: fd.type === 'PJ' ? null : fd.marital_status || null,
      address: fullAddress,
      phone: sanitizedPhone,
      email: sanitizedEmail,
      no_phone: !!fd.no_phone,
      no_email: !!fd.no_email,
      phone_na: fd.type === 'PJ' ? !!fd.phone_na : false,
      email_na: fd.type === 'PJ' ? !!fd.email_na : false,
      hide_birthday: !!fd.hide_birthday,
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

          {/* Área de OCR / Leitura de Documento no Navegador (Privacidade total) */}
          <div className="rounded-lg border border-dashed border-blue-300 bg-blue-50/50 p-3 text-sm transition-colors">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
              <div className="flex items-start sm:items-center gap-2">
                <ScanLine className="h-4 w-4 text-blue-600 mt-0.5 sm:mt-0 flex-shrink-0" />
                <div>
                  <span className="font-medium text-blue-950">
                    Ler documento (RG / CNH / Comprovante de endereço)
                  </span>
                  <p className="text-xs text-blue-700/80">
                    Processado 100% no seu navegador. O arquivo não é salvo nem enviado a nenhum
                    servidor.
                  </p>
                </div>
              </div>
              <div className="flex items-center gap-2 flex-shrink-0">
                <label
                  className={`inline-flex items-center justify-center rounded-md border border-blue-300 bg-white px-3 py-1.5 text-xs font-medium text-blue-800 shadow-sm transition-colors hover:bg-blue-100 hover:text-blue-900 focus-within:ring-2 focus-within:ring-blue-500 focus-within:ring-offset-2 ${
                    ocrLoading ? 'opacity-60 cursor-not-allowed' : 'cursor-pointer'
                  }`}
                >
                  <input
                    type="file"
                    accept="image/png,image/jpeg,image/jpg,image/webp,application/pdf"
                    onChange={handleDocumentScan}
                    disabled={ocrLoading}
                    className="sr-only"
                  />
                  {ocrLoading ? (
                    <>
                      <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin text-blue-600" />
                      Lendo...
                    </>
                  ) : (
                    <>
                      <ScanLine className="mr-1.5 h-3.5 w-3.5 text-blue-600" />
                      Carregar arquivo
                    </>
                  )}
                </label>
              </div>
            </div>

            {ocrLoading && (
              <div className="mt-2.5 space-y-1.5">
                <div className="flex justify-between text-xs text-blue-900">
                  <span className="flex items-center gap-1.5">
                    <Loader2 className="h-3 w-3 animate-spin text-blue-600" />
                    {ocrStatusText || 'Lendo documento...'}
                  </span>
                  <span className="font-mono text-[11px]">{ocrProgress}%</span>
                </div>
                <div className="h-1.5 w-full overflow-hidden rounded-full bg-blue-200">
                  <div
                    className="h-full bg-blue-600 transition-all duration-300"
                    style={{ width: `${ocrProgress}%` }}
                  />
                </div>
              </div>
            )}

            {ocrNotice && !ocrLoading && (
              <div className="mt-2.5 flex items-start justify-between gap-2 rounded bg-white/80 p-2 text-xs text-blue-900 border border-blue-200">
                <div className="flex items-start gap-1.5">
                  <CheckCircle2 className="h-3.5 w-3.5 text-emerald-600 mt-0.5 flex-shrink-0" />
                  <span>{ocrNotice}</span>
                </div>
                <button
                  type="button"
                  onClick={() => setOcrNotice(null)}
                  className="text-blue-400 hover:text-blue-600 flex-shrink-0"
                  title="Fechar aviso"
                >
                  <X className="h-3.5 w-3.5" />
                </button>
              </div>
            )}
          </div>

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
                    phone_na: v === 'PJ' ? fd.phone_na : false,
                    email_na: v === 'PJ' ? fd.email_na : false,
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
              <div className="pt-1">
                <label className="flex items-center gap-1.5 text-xs text-muted-foreground cursor-pointer select-none hover:text-foreground">
                  <Checkbox
                    checked={!!fd.hide_birthday}
                    onCheckedChange={(checked) =>
                      setFd((prev: any) => ({ ...prev, hide_birthday: !!checked }))
                    }
                  />
                  <span>Não exibir aniversário no calendário</span>
                </label>
              </div>
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
              <Label className={fd.no_email || fd.email_na ? 'text-muted-foreground' : ''}>
                E-mail {!fd.no_email && !fd.email_na && <span className="text-red-500">*</span>}
              </Label>
              <Input
                type="email"
                disabled={!!fd.no_email || !!fd.email_na}
                placeholder={
                  fd.email_na ? 'Não se aplica' : fd.no_email ? 'Sem e-mail' : 'exemplo@email.com'
                }
                className={
                  fd.no_email || fd.email_na
                    ? 'bg-muted/50 cursor-not-allowed text-muted-foreground'
                    : ''
                }
                value={fd.no_email || fd.email_na ? '' : fd.email || ''}
                onChange={(e) => {
                  setFd({ ...fd, email: e.target.value })
                  setFormErrors((prev) => ({ ...prev, email: '' }))
                }}
              />
              <div className="flex flex-wrap items-center gap-4 pt-1">
                <label className="flex items-center gap-1.5 text-xs text-muted-foreground cursor-pointer select-none hover:text-foreground">
                  <Checkbox
                    checked={!!fd.no_email}
                    onCheckedChange={(checked) => {
                      const isChecked = !!checked
                      setFd((prev: any) => ({
                        ...prev,
                        no_email: isChecked,
                        ...(isChecked ? { email_na: false, email: '' } : {}),
                      }))
                      if (isChecked) {
                        setFormErrors((prev) => ({ ...prev, email: '' }))
                      }
                    }}
                  />
                  <span>Sem e-mail</span>
                </label>
                {fd.type === 'PJ' && (
                  <label className="flex items-center gap-1.5 text-xs text-muted-foreground cursor-pointer select-none hover:text-foreground">
                    <Checkbox
                      checked={!!fd.email_na}
                      onCheckedChange={(checked) => {
                        const isChecked = !!checked
                        setFd((prev: any) => ({
                          ...prev,
                          email_na: isChecked,
                          ...(isChecked ? { no_email: false, email: '' } : {}),
                        }))
                        if (isChecked) {
                          setFormErrors((prev) => ({ ...prev, email: '' }))
                        }
                      }}
                    />
                    <span>Não se aplica</span>
                  </label>
                )}
              </div>
              {formErrors.email && <p className="text-xs text-red-500">{formErrors.email}</p>}
            </div>

            <div className="space-y-2">
              <Label className={fd.no_phone || fd.phone_na ? 'text-muted-foreground' : ''}>
                Celular (com DDD){' '}
                {!fd.no_phone && !fd.phone_na && <span className="text-red-500">*</span>}
              </Label>
              <Input
                disabled={!!fd.no_phone || !!fd.phone_na}
                placeholder={
                  fd.phone_na ? 'Não se aplica' : fd.no_phone ? 'Sem telefone' : '(31) 98765-4321'
                }
                className={
                  fd.no_phone || fd.phone_na
                    ? 'bg-muted/50 cursor-not-allowed text-muted-foreground'
                    : ''
                }
                value={fd.no_phone || fd.phone_na ? '' : formatPhone(fd.phone || '')}
                onChange={(e) => {
                  const rawDigits = sanitizeClientPhone(e.target.value)
                  setFd({ ...fd, phone: rawDigits })
                  setFormErrors((prev) => ({ ...prev, phone: '' }))
                }}
                inputMode="numeric"
                maxLength={15}
              />
              <div className="flex flex-wrap items-center gap-4 pt-1">
                <label className="flex items-center gap-1.5 text-xs text-muted-foreground cursor-pointer select-none hover:text-foreground">
                  <Checkbox
                    checked={!!fd.no_phone}
                    onCheckedChange={(checked) => {
                      const isChecked = !!checked
                      setFd((prev: any) => ({
                        ...prev,
                        no_phone: isChecked,
                        ...(isChecked ? { phone_na: false, phone: '' } : {}),
                      }))
                      if (isChecked) {
                        setFormErrors((prev) => ({ ...prev, phone: '' }))
                      }
                    }}
                  />
                  <span>Sem telefone</span>
                </label>
                {fd.type === 'PJ' && (
                  <label className="flex items-center gap-1.5 text-xs text-muted-foreground cursor-pointer select-none hover:text-foreground">
                    <Checkbox
                      checked={!!fd.phone_na}
                      onCheckedChange={(checked) => {
                        const isChecked = !!checked
                        setFd((prev: any) => ({
                          ...prev,
                          phone_na: isChecked,
                          ...(isChecked ? { no_phone: false, phone: '' } : {}),
                        }))
                        if (isChecked) {
                          setFormErrors((prev) => ({ ...prev, phone: '' }))
                        }
                      }}
                    />
                    <span>Não se aplica</span>
                  </label>
                )}
              </div>
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
              <ProtectedRichText
                initialValue={client ? client.observacoes || '' : ''}
                isAdmin={isAdmin}
                onChange={(v) => setFd({ ...fd, observacoes: v })}
                placeholderNew="Adicionar novo texto às observações..."
                className="min-h-[100px]"
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
