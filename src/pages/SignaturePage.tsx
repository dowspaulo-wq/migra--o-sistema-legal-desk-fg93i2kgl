import { useState, useEffect, useMemo } from 'react'
import { useParams } from 'react'
import { getSignatureByToken, confirmSignature } from '@/services/document-signatures'
import { SelfieCaptureStep } from '@/components/signature/SelfieCaptureStep'
import { SignaturePad } from '@/components/signature/SignaturePad'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import {
  Check,
  Camera,
  MapPin,
  Edit3,
  CheckCircle2,
  ShieldCheck,
  AlertCircle,
  FileText,
  Loader2,
} from 'lucide-react'
import { toast } from '@/hooks/use-toast'

export default function SignaturePage() {
  const { token } = useParams<{ token: string }>()
  const [loading, setLoading] = useState(true)
  const [docData, setDocData] = useState<any>(null)
  const [error, setError] = useState<string | null>(null)

  const [confirmedSelfie, setConfirmedSelfie] = useState<string | null>(null)
  const [geolocation, setGeolocation] = useState<{ latitude: number; longitude: number } | null>(
    null,
  )
  const [geoLoading, setGeoLoading] = useState(false)
  const [signatureData, setSignatureData] = useState<string | null>(null)

  const [submitting, setSubmitting] = useState(false)
  const [signedSuccess, setSignedSuccess] = useState(false)

  useEffect(() => {
    if (!token) {
      setError('Token de assinatura não fornecido.')
      setLoading(false)
      return
    }
    setLoading(true)
    getSignatureByToken(token).then(({ data, error }) => {
      setLoading(false)
      if (error || !data) {
        setError(error?.message || 'Documento não encontrado ou link expirado.')
      } else {
        setDocData(data)
        if (data.status === 'signed') {
          setSignedSuccess(true)
        }
      }
    })
  }, [token])

  const requestGeolocation = () => {
    if (!navigator.geolocation) {
      toast({
        title: 'Geolocalização não suportada',
        description: 'Seu navegador não suporta geolocalização.',
        variant: 'destructive',
      })
      return
    }
    setGeoLoading(true)
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setGeolocation({ latitude: pos.coords.latitude, longitude: pos.coords.longitude })
        setGeoLoading(false)
        toast({ title: 'Localização obtida!', description: 'Coordenadas capturadas com sucesso.' })
      },
      () => {
        setGeoLoading(false)
        toast({
          title: 'Erro de localização',
          description:
            'Não foi possível obter sua localização. Por favor, autorize a permissão no navegador.',
          variant: 'destructive',
        })
      },
    )
  }

  const handleSubmitSignature = async () => {
    if (!token || !confirmedSelfie || !signatureData) return
    setSubmitting(true)
    const { error } = await confirmSignature(token, {
      selfie: confirmedSelfie,
      signature: signatureData,
      geolocation,
    })
    setSubmitting(false)
    if (error) {
      toast({
        title: 'Erro ao assinar',
        description: error.message || 'Falha ao processar assinatura.',
        variant: 'destructive',
      })
    } else {
      setSignedSuccess(true)
      toast({ title: 'Sucesso!', description: 'Documento assinado com sucesso.' })
    }
  }

  const generatedDocHtml = useMemo(() => {
    if (!docData) return ''
    if (docData.documentContent) return docData.documentContent
    if (docData.document_content) return docData.document_content

    const client = docData.clients || {}
    const process = docData.cases || {}
    const clientName = client.name || 'OUTORGANTE / CLIENTE'
    const clientDoc = client.document || 'CPF/CNPJ'
    const clientAddr =
      [client.street, client.number, client.neighborhood, client.city, client.state]
        .filter(Boolean)
        .join(', ') || 'Endereço não cadastrado'

    if (docData.doc_type === 'procuracao') {
      return `
        <div class="space-y-4">
          <h2 class="text-center font-bold text-base text-slate-900 uppercase">PROCURAÇÃO AD JUDICIA ET EXTRA</h2>
          <p><strong>OUTORGANTE:</strong> ${clientName}, inscrito(a) no CPF/CNPJ sob o nº ${clientDoc}, residente e domiciliado(a) em ${clientAddr}.</p>
          <p><strong>OUTORGADOS:</strong> DPSjur Advocacia e Consultoria Jurídica e seus advogados integrantes.</p>
          <p><strong>PODERES:</strong> Por este instrumento particular de procuração, o(a) Outorganate concede aos Outorgados amplos e gerais poderes para o foro em geral, conferidos pelo artigo 105 do Código de Processo Civil, para representá-lo(a) em juízo ou fora dele, propor ações, defender, transigir, assinar compromissos, confessar, desistir, receber e dar quitação.</p>
          <p class="text-right mt-6">Data: ${new Date().toLocaleDateString('pt-BR')}</p>
        </div>
      `
    }

    if (docData.doc_type === 'hipossuficiencia') {
      return `
        <div class="space-y-4">
          <h2 class="text-center font-bold text-base text-slate-900 uppercase">DECLARAÇÃO DE HIPOSSUFICIÊNCIA ECONÔMICA</h2>
          <p>Eu, <strong>${clientName}</strong>, portador(a) do CPF nº <strong>${clientDoc}</strong>, declaro para os devidos fins de direito e sob as penas da lei, nos termos do art. 98 do Código de Processo Civil, que não possuo recursos financeiros suficientes para arcar com as custas processuais e honorários advocatícios sem prejuízo do sustento próprio e de minha família.</p>
          <p class="text-right mt-6">Data: ${new Date().toLocaleDateString('pt-BR')}</p>
        </div>
      `
    }

    return `
      <div class="space-y-4">
        <h2 class="text-center font-bold text-base text-slate-900 uppercase">CONTRATO DE PRESTAÇÃO DE SERVIÇOS ADVOCATÍCIOS</h2>
        <p><strong>CONTRATANTE:</strong> ${clientName}, CPF/CNPJ nº ${clientDoc}, residente em ${clientAddr}.</p>
        <p><strong>CONTRATADO:</strong> DPSjur Advocacia.</p>
        <p><strong>OBJETO:</strong> Prestação de serviços de assessoria e representação jurídica no processo nº ${process.number || 'A ser autuado'}.</p>
        <p class="text-right mt-6">Data: ${new Date().toLocaleDateString('pt-BR')}</p>
      </div>
    `
  }, [docData])

  if (loading) {
    return (
      <div className="min-h-screen bg-slate-50 flex flex-col items-center justify-center p-4">
        <Loader2 className="h-8 w-8 text-blue-600 animate-spin mb-3" />
        <p className="text-sm font-medium text-slate-600">
          Carregando documento para assinatura...
        </p>
      </div>
    )
  }

  if (error || !docData) {
    return (
      <div className="min-h-screen bg-slate-50 flex items-center justify-center p-4">
        <Card className="max-w-md w-full text-center p-6 space-y-4 shadow-sm border-red-100">
          <AlertCircle className="h-12 w-12 text-red-500 mx-auto" />
          <h2 className="text-xl font-bold text-slate-900">Link Inválido ou Expirado</h2>
          <p className="text-sm text-slate-600">
            {error || 'Não foi possível carregar o documento solicitado.'}
          </p>
        </Card>
      </div>
    )
  }

  if (signedSuccess) {
    return (
      <div className="min-h-screen bg-slate-50 flex items-center justify-center p-4">
        <Card className="max-w-lg w-full text-center p-8 space-y-4 shadow-lg border-emerald-200">
          <CheckCircle2 className="h-16 w-16 text-emerald-600 mx-auto animate-bounce" />
          <h2 className="text-2xl font-bold text-slate-900">Documento Assinado!</h2>
          <p className="text-sm text-slate-600 leading-relaxed">
            Sua assinatura eletrônica foi concluída com sucesso e registrada com selfie e validações
            de segurança jurídica.
          </p>
          <div className="pt-2">
            <Badge
              variant="outline"
              className="bg-emerald-50 text-emerald-700 border-emerald-300 py-1.5 px-4 text-xs font-semibold"
            >
              <ShieldCheck className="h-4 w-4 mr-1.5" /> Assinatura Eletrônica Válida e Autenticada
            </Badge>
          </div>
        </Card>
      </div>
    )
  }

  const isSelfieDone = Boolean(confirmedSelfie)
  const isGeoDone = Boolean(geolocation)
  const isSigDone = Boolean(signatureData)
  const canFinalize = isSelfieDone && isSigDone

  return (
    <div className="min-h-screen bg-slate-50 py-8 px-4 sm:px-6">
      <div className="max-w-3xl mx-auto space-y-6">
        <div className="bg-white p-6 rounded-xl border shadow-sm flex items-center justify-between flex-wrap gap-3">
          <div>
            <h1 className="text-xl font-bold text-slate-900">Assinatura Eletrônica de Documento</h1>
            <p className="text-xs text-slate-500 mt-1">
              Siga as 4 etapas abaixo para concluir a assinatura com validade jurídica
            </p>
          </div>
          <Badge variant="outline" className="bg-blue-50 text-blue-700 border-blue-200">
            {docData.doc_type === 'procuracao'
              ? 'Procuração Ad Judicia'
              : docData.doc_type === 'hipossuficiencia'
                ? 'Declaração de Hipossuficiência'
                : 'Contrato de Serviços'}
          </Badge>
        </div>

        <Card className="shadow-sm">
          <CardHeader className="pb-3 border-b">
            <CardTitle className="text-base font-bold text-slate-900 flex items-center gap-2">
              <FileText className="h-5 w-5 text-blue-600" /> Processo de Assinatura
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-6 pt-6">
            {/* Step 1 */}
            <div className="space-y-2">
              <div className="flex items-center gap-3">
                <div className="w-7 h-7 rounded-full bg-emerald-500 text-white flex items-center justify-center shrink-0">
                  <Check className="h-4 w-4 stroke-[3]" />
                </div>
                <span className="font-semibold text-emerald-700 text-sm">
                  1. Visualização do Documento
                </span>
              </div>
              <div className="ml-10 bg-slate-50 border rounded-lg p-4 max-h-60 overflow-y-auto text-xs text-slate-800 leading-relaxed shadow-inner">
                <div dangerouslySetInnerHTML={{ __html: generatedDocHtml }} />
              </div>
            </div>

            {/* Step 2 */}
            <div className="space-y-2">
              <div className="flex items-center gap-3">
                <div
                  className={`w-7 h-7 rounded-full flex items-center justify-center shrink-0 ${
                    isSelfieDone ? 'bg-emerald-500 text-white' : 'bg-slate-200 text-slate-600'
                  }`}
                >
                  {isSelfieDone ? (
                    <Check className="h-4 w-4 stroke-[3]" />
                  ) : (
                    <Camera className="h-4 w-4" />
                  )}
                </div>
                <span
                  className={`font-semibold text-sm ${isSelfieDone ? 'text-emerald-700' : 'text-slate-800'}`}
                >
                  2. Captura de Selfie
                </span>
              </div>
              <div className="ml-10">
                <SelfieCaptureStep
                  confirmedSelfie={confirmedSelfie}
                  onConfirm={(selfieData) => setConfirmedSelfie(selfieData)}
                  onRetake={() => setConfirmedSelfie(null)}
                />
              </div>
            </div>

            {/* Step 3 */}
            <div className="space-y-2">
              <div className="flex items-center gap-3">
                <div
                  className={`w-7 h-7 rounded-full flex items-center justify-center shrink-0 ${
                    isGeoDone ? 'bg-emerald-500 text-white' : 'bg-slate-200 text-slate-600'
                  }`}
                >
                  {isGeoDone ? (
                    <Check className="h-4 w-4 stroke-[3]" />
                  ) : (
                    <MapPin className="h-4 w-4" />
                  )}
                </div>
                <span
                  className={`font-semibold text-sm ${isGeoDone ? 'text-emerald-700' : 'text-slate-800'}`}
                >
                  3. Geolocalização
                </span>
              </div>
              <div className="ml-10">
                {isGeoDone ? (
                  <Badge
                    variant="outline"
                    className="bg-emerald-50 text-emerald-700 border-emerald-200 px-3 py-1 text-xs"
                  >
                    <Check className="h-3.5 w-3.5 mr-1" /> Coordenadas Registradas
                  </Badge>
                ) : (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={requestGeolocation}
                    disabled={geoLoading}
                    className="text-xs bg-white text-slate-700"
                  >
                    <MapPin className="h-3.5 w-3.5 mr-1.5" />
                    {geoLoading ? 'Obtendo localização...' : 'Permitir Geolocalização'}
                  </Button>
                )}
              </div>
            </div>

            {/* Step 4 */}
            <div className="space-y-2">
              <div className="flex items-center gap-3">
                <div
                  className={`w-7 h-7 rounded-full flex items-center justify-center shrink-0 ${
                    isSigDone ? 'bg-emerald-500 text-white' : 'bg-slate-200 text-slate-600'
                  }`}
                >
                  {isSigDone ? (
                    <Check className="h-4 w-4 stroke-[3]" />
                  ) : (
                    <Edit3 className="h-4 w-4" />
                  )}
                </div>
                <span
                  className={`font-semibold text-sm ${isSigDone ? 'text-emerald-700' : 'text-slate-800'}`}
                >
                  4. Desenhar Assinatura Digital
                </span>
              </div>
              <div className="ml-10">
                <SignaturePad onSave={(sig) => setSignatureData(sig)} />
              </div>
            </div>

            <div className="pt-4 border-t flex justify-end">
              <Button
                onClick={handleSubmitSignature}
                disabled={!canFinalize || submitting}
                className="bg-emerald-600 hover:bg-emerald-700 text-white px-8 h-11 text-base font-semibold shadow-md"
              >
                {submitting ? (
                  <>
                    <Loader2 className="h-4 w-4 mr-2 animate-spin" /> Enviando...
                  </>
                ) : (
                  'Finalizar Assinatura'
                )}
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
