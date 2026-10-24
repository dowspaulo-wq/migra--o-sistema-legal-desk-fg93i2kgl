import { supabase } from '@/lib/supabase/client'
import PizZip from 'pizzip'
import Docxtemplater from 'docxtemplater'
import { isSuccessFeeType } from '@/lib/fee-types'

export interface ManualFieldDefinition {
  key: string
  label: string
  type: 'text' | 'currency' | 'percentage' | 'date'
  defaultValue?: string
}

export interface DocumentTemplate {
  id: string
  name: string
  file_path: string
  category: string
  created_at: string
  manual_fields?: ManualFieldDefinition[]
  description?: string
  updated_at?: string
}

export interface PlaceholderDocumentation {
  key: string
  label: string
  example: string
  group: 'Cliente' | 'Processo' | 'Escritório' | 'Data / Sistema' | 'Campos Manuais'
  aliases?: string[]
  description?: string
}

export const AVAILABLE_PLACEHOLDERS: PlaceholderDocumentation[] = [
  // Cliente
  {
    key: 'cliente.nome',
    label: 'Nome Completo',
    example: 'João da Silva',
    group: 'Cliente',
    aliases: ['client_name', 'cliente', 'nome_cliente', 'client', 'nome'],
  },
  {
    key: 'cliente.cpf',
    label: 'CPF',
    example: '123.456.789-00',
    group: 'Cliente',
    aliases: ['cpf', 'cpf_cliente', 'client_cpf'],
  },
  {
    key: 'cliente.rg',
    label: 'RG',
    example: '12.345.678-9',
    group: 'Cliente',
    aliases: ['rg', 'rg_cliente', 'client_rg'],
  },
  {
    key: 'cliente.documento',
    label: 'Documento Principal (CPF/CNPJ)',
    example: '123.456.789-00',
    group: 'Cliente',
    aliases: ['document', 'documento', 'cnpj', 'cnpj_cliente', 'client_cnpj'],
  },
  {
    key: 'cliente.tipo',
    label: 'Tipo de Pessoa (Física/Jurídica)',
    example: 'Pessoa Física',
    group: 'Cliente',
    aliases: ['client_type', 'tipo_cliente', 'tipo_pessoa'],
  },
  {
    key: 'cliente.email',
    label: 'E-mail',
    example: 'cliente@exemplo.com',
    group: 'Cliente',
    aliases: ['email', 'client_email', 'email_cliente'],
  },
  {
    key: 'cliente.telefone',
    label: 'Telefone / Celular / WhatsApp',
    example: '(11) 98765-4321',
    group: 'Cliente',
    aliases: ['phone', 'telefone', 'celular', 'whatsapp', 'client_phone', 'telefone_cliente'],
  },
  {
    key: 'cliente.estadoCivil',
    label: 'Estado Civil',
    example: 'Casado(a)',
    group: 'Cliente',
    aliases: ['marital_status', 'estado_civil', 'estadocivil', 'civil_status'],
  },
  {
    key: 'cliente.profissao',
    label: 'Profissão',
    example: 'Engenheiro Civil',
    group: 'Cliente',
    aliases: ['profession', 'profissao', 'job', 'ocupacao'],
  },
  {
    key: 'cliente.dataNascimento',
    label: 'Data de Nascimento',
    example: '15/04/1985',
    group: 'Cliente',
    aliases: ['birth_date', 'birthdate', 'data_nascimento', 'nascimento', 'birthday'],
  },
  {
    key: 'cliente.endereco',
    label: 'Endereço Completo',
    example: 'Rua das Flores, 123, Apto 45 - Centro, São Paulo - SP, CEP 01234-567',
    group: 'Cliente',
    aliases: ['address', 'endereco', 'full_address', 'endereco_completo'],
  },
  {
    key: 'cliente.rua',
    label: 'Rua / Logradouro',
    example: 'Rua das Flores',
    group: 'Cliente',
    aliases: ['street', 'rua', 'logradouro', 'street_name'],
  },
  {
    key: 'cliente.numero',
    label: 'Número',
    example: '123',
    group: 'Cliente',
    aliases: ['number', 'numero', 'numero_endereco'],
  },
  {
    key: 'cliente.ruaNumero',
    label: 'Rua e Número (composto)',
    example: 'Rua das Flores, 123',
    group: 'Cliente',
    aliases: ['number_street', 'numberstreet', 'numero_rua', 'rua_numero', 'street_number_br'],
    description: 'Combina rua e número ("Rua, Nº"). Fallback automático se um deles faltar.',
  },
  {
    key: 'cliente.numeroRua',
    label: 'Número e Rua (composto invertido)',
    example: '123, Rua das Flores',
    group: 'Cliente',
    aliases: ['street_number'],
    description: 'Combina número e rua ("Nº, Rua"). Fallback automático se um deles faltar.',
  },
  {
    key: 'cliente.complemento',
    label: 'Complemento',
    example: 'Apto 45',
    group: 'Cliente',
    aliases: ['complement', 'complemento'],
  },
  {
    key: 'cliente.bairro',
    label: 'Bairro',
    example: 'Centro',
    group: 'Cliente',
    aliases: ['neighborhood', 'bairro', 'district'],
  },
  {
    key: 'cliente.cidade',
    label: 'Cidade',
    example: 'São Paulo',
    group: 'Cliente',
    aliases: ['city', 'cidade'],
  },
  {
    key: 'cliente.estado',
    label: 'UF / Estado',
    example: 'SP',
    group: 'Cliente',
    aliases: ['state', 'uf', 'estado'],
  },
  {
    key: 'cliente.cep',
    label: 'CEP / Código Postal',
    example: '01234-567',
    group: 'Cliente',
    aliases: ['cep', 'zip_code', 'zipcode', 'postal_code'],
  },
  {
    key: 'cliente.nacionalidade',
    label: 'Nacionalidade',
    example: 'Brasileiro(a)',
    group: 'Cliente',
    aliases: ['nationality', 'nacionalidade'],
  },

  // Processo
  {
    key: 'processo.numero',
    label: 'Número CNJ do Processo',
    example: '0001234-56.2026.8.26.0100',
    group: 'Processo',
    aliases: ['process_number', 'numero_processo', 'processo_numero', 'case_number', 'numero_acao'],
  },
  {
    key: 'processo.numeroProcesso',
    label: 'Número do Processo (alias)',
    example: '0001234-56.2026.8.26.0100',
    group: 'Processo',
    aliases: ['processo'],
  },
  {
    key: 'processo.nome',
    label: 'Nome da Ação / Descrição',
    example: 'Ação Indenizatória por Danos Morais',
    group: 'Processo',
    aliases: ['action_name', 'nome_acao', 'acao', 'action', 'tipo_acao'],
  },
  {
    key: 'processo.tipo',
    label: 'Tipo de Ação',
    example: 'Cível',
    group: 'Processo',
    aliases: ['action_type', 'tipo_processo'],
  },
  {
    key: 'processo.status',
    label: 'Status Processual',
    example: 'Em andamento',
    group: 'Processo',
    aliases: ['process_status', 'status_processo'],
  },
  {
    key: 'processo.vara',
    label: 'Vara / Juízo',
    example: '2ª Vara Cível',
    group: 'Processo',
    aliases: ['court', 'vara', 'juizo'],
  },
  {
    key: 'processo.comarca',
    label: 'Comarca',
    example: 'Sorocaba',
    group: 'Processo',
    aliases: ['comarca', 'jurisdiction'],
  },
  {
    key: 'processo.estado',
    label: 'UF do Processo',
    example: 'SP',
    group: 'Processo',
    aliases: ['process_state', 'uf_processo'],
  },
  {
    key: 'processo.sistema',
    label: 'Sistema Processual (PJe, e-SAJ, etc.)',
    example: 'PJe / e-SAJ',
    group: 'Processo',
    aliases: ['process_system', 'sistema_processual', 'sistema'],
  },
  {
    key: 'processo.posicao',
    label: 'Posição do Cliente no Processo',
    example: 'Autor',
    group: 'Processo',
    aliases: ['client_position', 'posicao_cliente', 'posicao'],
  },
  {
    key: 'processo.parteContraria',
    label: 'Parte Contrária (Réu / Adverso)',
    example: 'Banco Exemplo S.A.',
    group: 'Processo',
    aliases: [
      'adverse_party',
      'parte_contraria',
      'reu',
      'parte_adversa',
      'adverseParty',
      'defendant',
    ],
  },
  {
    key: 'processo.adverseParty',
    label: 'Parte Contrária (alias)',
    example: 'Banco Exemplo S.A.',
    group: 'Processo',
  },
  {
    key: 'processo.valorCausa',
    label: 'Valor da Causa (formatado R$)',
    example: 'R$ 50.000,00',
    group: 'Processo',
    aliases: ['valor_causa', 'case_value', 'valor_da_causa', 'cause_value'],
  },
  {
    key: 'processo.valorCausaExtenso',
    label: 'Valor da Causa por Extenso',
    example: 'cinquenta mil reais',
    group: 'Processo',
    aliases: ['valor_causa_extenso', 'case_value_words'],
  },
  {
    key: 'processo.valorCausaNumero',
    label: 'Valor da Causa (apenas número)',
    example: '50000,00',
    group: 'Processo',
    aliases: ['valor_causa_num', 'case_value_number'],
  },
  {
    key: 'processo.tipoHonorarios',
    label: 'Tipo de Honorários',
    example: 'Honorários Contratuais',
    group: 'Processo',
    aliases: ['fee_type', 'tipo_honorarios'],
  },
  {
    key: 'processo.valorHonorarios',
    label: 'Valor dos Honorários (R$)',
    example: 'R$ 1.000,00',
    group: 'Processo',
    aliases: ['fee_value', 'valor_honorarios', 'honorarios'],
  },
  {
    key: 'processo.percentualHonorarios',
    label: 'Percentual de Honorários / Êxito',
    example: '30%',
    group: 'Processo',
    aliases: ['fee_percentage', 'percentual_honorarios', 'percentual_exito'],
  },
  {
    key: 'processo.parcelasHonorarios',
    label: 'Qtd de Parcelas de Honorários',
    example: '5',
    group: 'Processo',
    aliases: ['fee_installments', 'parcelas_honorarios', 'parcelas'],
  },

  // Escritório
  {
    key: 'escritorio.nome',
    label: 'Nome do Escritório / Advogado',
    example: 'Douglas Santos Advocacia',
    group: 'Escritório',
    aliases: ['office_name', 'nome_escritorio', 'escritorio', 'law_firm', 'escritorio_nome'],
  },
  {
    key: 'escritorio.advogado',
    label: 'Advogado Responsável',
    example: 'Douglas Paulino dos Santos',
    group: 'Escritório',
    aliases: ['lawyer_name', 'advogado', 'advogado_responsavel', 'lawyer'],
  },
  {
    key: 'escritorio.oab',
    label: 'Número da OAB / UF',
    example: 'OAB/SP 430.509',
    group: 'Escritório',
    aliases: ['oab', 'oab_advogado', 'lawyer_oab'],
  },
  {
    key: 'escritorio.cnpj',
    label: 'CNPJ do Escritório',
    example: '53.649.030/0001-20',
    group: 'Escritório',
    aliases: ['office_cnpj', 'cnpj_escritorio'],
  },
  {
    key: 'escritorio.endereco',
    label: 'Endereço do Escritório',
    example: 'Rua São Bento, 273 - Centro, Sorocaba - SP, CEP 18010-031',
    group: 'Escritório',
    aliases: ['office_address', 'endereco_escritorio'],
  },
  {
    key: 'escritorio.telefone',
    label: 'Telefone do Escritório',
    example: '(15) 3042-1234',
    group: 'Escritório',
    aliases: ['office_phone', 'telefone_escritorio'],
  },
  {
    key: 'escritorio.email',
    label: 'E-mail do Escritório',
    example: 'contato@advdouglaspsantos.com.br',
    group: 'Escritório',
    aliases: ['office_email', 'email_escritorio'],
  },
  {
    key: 'escritorio.cidade',
    label: 'Cidade do Escritório',
    example: 'Sorocaba',
    group: 'Escritório',
    aliases: ['office_city', 'cidade_escritorio'],
  },
  {
    key: 'escritorio.estado',
    label: 'UF do Escritório',
    example: 'SP',
    group: 'Escritório',
    aliases: ['office_state', 'uf_escritorio'],
  },

  // Data / Sistema
  {
    key: 'dataAtual',
    label: 'Data Atual (DD/MM/AAAA)',
    example: '24/10/2026',
    group: 'Data / Sistema',
    aliases: ['current_date', 'data_atual', 'data', 'hoje', 'today'],
  },
  {
    key: 'dataAtualExtenso',
    label: 'Data Atual por Extenso',
    example: '24 de outubro de 2026',
    group: 'Data / Sistema',
    aliases: ['current_date_full', 'data_extenso', 'data_atual_extenso'],
  },
  {
    key: 'diaAtual',
    label: 'Dia do Mês Atual (DD)',
    example: '24',
    group: 'Data / Sistema',
    aliases: ['current_day', 'dia_atual', 'dia'],
  },
  {
    key: 'mesAtual',
    label: 'Mês Atual por Extenso',
    example: 'outubro',
    group: 'Data / Sistema',
    aliases: ['current_month', 'mes_atual', 'mes'],
  },
  {
    key: 'anoAtual',
    label: 'Ano Atual (AAAA)',
    example: '2026',
    group: 'Data / Sistema',
    aliases: ['current_year', 'ano_atual', 'ano', 'year'],
  },
  {
    key: 'cidadeDataAtual',
    label: 'Cidade e Data Atual',
    example: 'Sorocaba/SP, 24 de outubro de 2026',
    group: 'Data / Sistema',
    aliases: ['city_date', 'cidade_data'],
  },

  // Campos Manuais Dinâmicos Comuns
  {
    key: 'valorHonorarios',
    label: 'Valor dos Honorários (manual)',
    example: 'R$ 1.000,00',
    group: 'Campos Manuais',
    aliases: ['honorarios_valor', 'fee_amount'],
    description: 'Definido no modelo pelo advogado',
  },
  {
    key: 'formaPagamento',
    label: 'Forma de Pagamento (manual)',
    example: 'Entrada de R$ 1.500,00 + 3 parcelas de R$ 500,00',
    group: 'Campos Manuais',
    aliases: ['payment_method', 'forma_pagamento', 'condicoes_pagamento'],
    description: 'Texto livre editado na geração',
  },
  {
    key: 'percentualExito',
    label: 'Percentual de Êxito (manual)',
    example: '30%',
    group: 'Campos Manuais',
    aliases: ['success_fee', 'exito_percentual'],
    description: 'Percentual aplicado sobre o proveito econômico',
  },
  {
    key: 'nomeAcao',
    label: 'Nome Específico da Ação (manual)',
    example: 'Ação de Alimentos c/c Guarda',
    group: 'Campos Manuais',
    aliases: ['action_title', 'titulo_acao'],
    description: 'Se desejar sobrescrever o nome da ação do processo',
  },
]

/**
 * Busca a lista de modelos de documentos ordenados por data de criação
 */
export async function fetchDocumentTemplates(): Promise<{ data: DocumentTemplate[]; error: any }> {
  try {
    const { data, error } = await supabase
      .from('document_templates' as any)
      .select('*')
      .order('created_at', { ascending: false })

    if (error) throw error

    const parsed: DocumentTemplate[] = (data || []).map((item: any) => ({
      id: item.id,
      name: item.name,
      file_path: item.file_path,
      category: item.category || 'Geral',
      created_at: item.created_at,
      manual_fields: Array.isArray(item.manual_fields) ? item.manual_fields : [],
      description: item.description || '',
      updated_at: item.updated_at || item.created_at,
    }))

    return { data: parsed, error: null }
  } catch (err: any) {
    return { data: [], error: err }
  }
}

/**
 * Upload de novo modelo .docx no Storage e registro no banco
 */
export async function uploadDocumentTemplate(
  file: File,
  category: string,
  manualFields: ManualFieldDefinition[] = [],
  description = '',
): Promise<{ data: DocumentTemplate | null; error: any }> {
  const ext = file.name.split('.').pop()?.toLowerCase()
  if (ext !== 'docx') {
    return {
      data: null,
      error: { message: 'Formato não suportado. Utilize apenas arquivos .docx' },
    }
  }

  // Tenta upload no bucket document_templates e fallback para document-templates
  const fileName = `${Date.now()}_${file.name.replace(/\s+/g, '_')}`
  let uploadBucket = 'document_templates'
  let { error: uploadError } = await supabase.storage.from(uploadBucket).upload(fileName, file)

  if (uploadError) {
    uploadBucket = 'document-templates'
    const secondTry = await supabase.storage.from(uploadBucket).upload(fileName, file)
    if (secondTry.error) {
      return { data: null, error: secondTry.error }
    }
  }

  const { data, error } = await supabase
    .from('document_templates' as any)
    .insert({
      name: file.name.replace(/\.docx$/i, ''),
      file_path: fileName,
      category: category || 'Geral',
      manual_fields: manualFields,
      description,
      updated_at: new Date().toISOString(),
    })
    .select()
    .single()

  if (error) {
    return { data: null, error }
  }

  return {
    data: {
      id: (data as any).id,
      name: (data as any).name,
      file_path: (data as any).file_path,
      category: (data as any).category,
      created_at: (data as any).created_at,
      manual_fields: (data as any).manual_fields || [],
      description: (data as any).description || '',
      updated_at: (data as any).updated_at,
    },
    error: null,
  }
}

/**
 * Atualiza metadados (nome, categoria, descrição e campos manuais) de um modelo existente
 */
export async function updateDocumentTemplate(
  id: string,
  updates: {
    name?: string
    category?: string
    description?: string
    manual_fields?: ManualFieldDefinition[]
  },
): Promise<{ error: any }> {
  const { error } = await supabase
    .from('document_templates' as any)
    .update({
      ...updates,
      updated_at: new Date().toISOString(),
    })
    .eq('id', id)

  return { error }
}

/**
 * Exclui um modelo do Storage e do banco
 */
export async function deleteDocumentTemplate(
  id: string,
  filePath: string,
): Promise<{ error: any }> {
  await supabase.storage.from('document_templates').remove([filePath])
  await supabase.storage.from('document-templates').remove([filePath])

  const { error } = await supabase
    .from('document_templates' as any)
    .delete()
    .eq('id', id)

  return { error }
}

/**
 * Baixa o buffer do modelo .docx a partir dos buckets de storage
 */
export async function downloadTemplateBuffer(filePath: string): Promise<ArrayBuffer> {
  // Tenta primeiro no bucket document_templates
  let { data, error } = await supabase.storage.from('document_templates').download(filePath)
  if (error || !data) {
    const second = await supabase.storage.from('document-templates').download(filePath)
    if (second.error || !second.data) {
      const detail = error?.message || second.error?.message || 'Arquivo não encontrado'
      throw new Error(
        `Falha ao baixar o arquivo do modelo (${filePath}): ${detail}. Verifique se o arquivo existe no armazenamento.`,
      )
    }
    data = second.data
  }

  const buffer = await data.arrayBuffer()
  if (!buffer || buffer.byteLength === 0) {
    throw new Error('Não foi possível ler o arquivo do modelo — o arquivo está vazio.')
  }

  return buffer
}

/**
 * Helpers para formatação amigável
 */
function formatCurrency(val: any): string {
  if (val == null || val === '') return ''
  const num =
    typeof val === 'number'
      ? val
      : Number(
          String(val)
            .replace(/[^\d.,-]/g, '')
            .replace(',', '.'),
        )
  if (isNaN(num)) return String(val)
  return `R$ ${num.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

function formatPercentage(val: any): string {
  if (val == null || val === '') return ''
  const str = String(val).trim()
  if (str.endsWith('%')) return str
  return `${str}%`
}

function numeroPorExtenso(valor: number): string {
  if (isNaN(valor) || valor <= 0) return ''
  // Implementação pragmática para valores comuns em honorários e causas
  const unidades = ['', 'um', 'dois', 'três', 'quatro', 'cinco', 'seis', 'sete', 'oito', 'nove']
  const dezenas1 = [
    'dez',
    'onze',
    'doze',
    'treze',
    'quatorze',
    'quinze',
    'dezesseis',
    'dezessete',
    'dezoito',
    'dezenove',
  ]
  const dezenas = [
    '',
    '',
    'vinte',
    'trinta',
    'quarenta',
    'cinquenta',
    'sessenta',
    'setenta',
    'oitenta',
    'noventa',
  ]
  const centenas = [
    '',
    'cento',
    'duzentos',
    'trezentos',
    'quatrocentos',
    'quinhentos',
    'seiscentos',
    'setecentos',
    'oitocentos',
    'novecentos',
  ]

  function converterGrupo(n: number): string {
    if (n === 100) return 'cem'
    const c = Math.floor(n / 100)
    const d = Math.floor((n % 100) / 10)
    const u = n % 10
    const partes: string[] = []
    if (c > 0) partes.push(centenas[c])
    if (d === 1) {
      partes.push(dezenas1[u])
    } else {
      if (d > 1) partes.push(dezenas[d])
      if (u > 0) partes.push(unidades[u])
    }
    return partes.join(' e ')
  }

  const inteiro = Math.floor(valor)
  const centavos = Math.round((valor - inteiro) * 100)

  if (inteiro === 0 && centavos > 0) {
    return `${centavos} centavos`
  }

  const milhoes = Math.floor(inteiro / 1000000)
  const milhares = Math.floor((inteiro % 1000000) / 1000)
  const resto = inteiro % 1000

  const partesTexto: string[] = []
  if (milhoes > 0) {
    partesTexto.push(milhoes === 1 ? 'um milhão' : `${converterGrupo(milhoes)} milhões`)
  }
  if (milhares > 0) {
    partesTexto.push(milhares === 1 ? 'mil' : `${converterGrupo(milhares)} mil`)
  }
  if (resto > 0) {
    partesTexto.push(converterGrupo(resto))
  }

  let resultado = partesTexto.join(' e ') + (inteiro === 1 ? ' real' : ' reais')
  if (centavos > 0) {
    resultado += ` e ${centavos} centavos`
  }
  return resultado
}

/**
 * Calcula dados de honorários, percentual de êxito e parcelas do processo:
 * 1. fee_value: soma das parcelas dos planos de pagamento do processo, excluindo êxito. Fallback no campo atual.
 * 2. fee_percentage: percentual de êxito cadastrado no processo ("30%"). Se não houver, string vazia -> aciona [PREENCHER: ...].
 * 3. fee_installments: número de parcelas do plano ("5"); vazio se não houver plano.
 */
function calculateProcessFees(params: {
  caseItem?: any
  paymentPlans?: any[]
  transactions?: any[]
  transactionCases?: any[]
}): {
  feeValueFormatted: string
  feePercentageFormatted: string
  feeInstallments: string
} {
  const { caseItem = {}, paymentPlans = [], transactions = [], transactionCases = [] } = params
  const caseId = caseItem?.id ? String(caseItem.id) : null

  const isTxLinkedToCase = (t: any): boolean => {
    if (!caseId || !t) return false
    if (t.processId && String(t.processId) === caseId) return true
    return transactionCases.some(
      (tc: any) => String(tc?.case_id) === caseId && String(tc?.transaction_id) === String(t?.id),
    )
  }

  const isPlanLinkedToCase = (p: any): boolean => {
    if (!caseId || !p) return false
    if (p.processId && String(p.processId) === caseId) return true
    return transactions.some(
      (t: any) => t.plan_id && String(t.plan_id) === String(p.id) && isTxLinkedToCase(t),
    )
  }

  // 1. Planos de pagamento vinculados ao processo (excluindo registros de êxito)
  const linkedPlans = paymentPlans.filter(isPlanLinkedToCase)
  const nonSuccessPlans = linkedPlans.filter(
    (p: any) => !isSuccessFeeType(p.title) && !isSuccessFeeType(p.notes),
  )

  let totalParcelasSum = 0
  let totalInstallmentsCount = 0
  let hasParcelasFromPlans = false

  const accountedPlanIds = new Set<string>()

  if (nonSuccessPlans.length > 0) {
    for (const plan of nonSuccessPlans) {
      accountedPlanIds.add(String(plan.id))
      const count = Math.max(1, parseInt(String(plan.installmentsCount), 10) || 1)
      const instAmount = Number(plan.installmentAmount) || 0
      const planTotal = instAmount > 0 ? instAmount * count : Number(plan.totalAmount) || 0

      if (planTotal > 0 || count > 0) {
        totalParcelasSum += planTotal
        totalInstallmentsCount += count
        hasParcelasFromPlans = true
      }
    }
  }

  // 2. Transações de parcelas vinculadas ao processo não associadas aos planos já computados acima
  const linkedTxns = transactions.filter(isTxLinkedToCase)
  const nonSuccessTxns = linkedTxns.filter((t: any) => {
    if (t.plan_id && accountedPlanIds.has(String(t.plan_id))) return false
    if (t.type === 'expense') return false
    const cat = t.category || ''
    const desc = t.description || ''
    return !isSuccessFeeType(cat) && !isSuccessFeeType(desc)
  })

  // Se houver transações de honorários parcelados avulsos (sem payment_plan)
  if (!hasParcelasFromPlans && nonSuccessTxns.length > 0) {
    const sumTxns = nonSuccessTxns.reduce((acc: number, t: any) => acc + (Number(t.amount) || 0), 0)
    if (sumTxns > 0) {
      totalParcelasSum = sumTxns
      hasParcelasFromPlans = true
      const maxInstTotal = Math.max(
        0,
        ...nonSuccessTxns.map((t: any) => parseInt(String(t.installment_total || 0), 10) || 0),
      )
      totalInstallmentsCount = maxInstTotal > 0 ? maxInstTotal : nonSuccessTxns.length
    }
  }

  // 1. {{fee_value}} → soma dos valores das parcelas dos planos; fallback no campo atual do processo
  let feeValueFormatted = ''
  if (hasParcelasFromPlans && totalParcelasSum > 0) {
    feeValueFormatted = formatCurrency(totalParcelasSum)
  } else if (caseItem.feeValue != null) {
    feeValueFormatted = formatCurrency(caseItem.feeValue)
  }

  // 3. {{fee_installments}} → número de parcelas do plano ("5"); vazio se não houver plano
  let feeInstallments = ''
  if (hasParcelasFromPlans && totalInstallmentsCount > 0) {
    feeInstallments = String(totalInstallmentsCount)
  } else if (caseItem.feeInstallments) {
    feeInstallments = String(caseItem.feeInstallments)
  }

  // 2. {{fee_percentage}} → o percentual de êxito cadastrado no processo (ex.: "30%").
  // Se não houver percentual, string vazia -> aciona o [PREENCHER: ...] padrão existente
  let foundPercentage: number | null = null

  // A. Do próprio registro do caso (se preenchido e > 0)
  if (caseItem.feePercentage != null && Number(caseItem.feePercentage) > 0) {
    foundPercentage = Number(caseItem.feePercentage)
  } else if (caseItem.fee_percentage != null && Number(caseItem.fee_percentage) > 0) {
    foundPercentage = Number(caseItem.fee_percentage)
  }

  // B. De transação de honorários de êxito vinculada ao processo
  if (foundPercentage == null) {
    const successTx = linkedTxns.find((t: any) => {
      const isSucc = isSuccessFeeType(t.category) || isSuccessFeeType(t.description)
      return isSucc && t.percentage != null && Number(t.percentage) > 0
    })
    if (successTx) {
      foundPercentage = Number(successTx.percentage)
    }
  }

  // C. De plano de pagamento vinculado ao processo que tenha feePercentage > 0
  if (foundPercentage == null) {
    const planWithPct = linkedPlans.find(
      (p: any) => p.feePercentage != null && Number(p.feePercentage) > 0,
    )
    if (planWithPct) {
      foundPercentage = Number(planWithPct.feePercentage)
    }
  }

  // D. De qualquer transação vinculada com percentage > 0
  if (foundPercentage == null) {
    const anyTxWithPct = linkedTxns.find(
      (t: any) => t.percentage != null && Number(t.percentage) > 0,
    )
    if (anyTxWithPct) {
      foundPercentage = Number(anyTxWithPct.percentage)
    }
  }

  const feePercentageFormatted =
    foundPercentage != null && foundPercentage > 0 ? formatPercentage(foundPercentage) : ''

  return {
    feeValueFormatted,
    feePercentageFormatted,
    feeInstallments,
  }
}

/**
 * Constrói o mapa de dados completo a partir do cliente, processo, escritório e inputs manuais
 */
export function buildDocumentDataMap(params: {
  client?: any
  caseItem?: any
  settings?: any
  manualValues?: Record<string, any>
  paymentPlans?: any[]
  transactions?: any[]
  transactionCases?: any[]
}): Record<string, any> {
  const {
    client = {},
    caseItem = {},
    settings = {},
    manualValues = {},
    paymentPlans = [],
    transactions = [],
    transactionCases = [],
  } = params

  const hoje = new Date()
  const dia = String(hoje.getDate()).padStart(2, '0')
  const mesNumero = hoje.getMonth()
  const meses = [
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ]
  const mesExtenso = meses[mesNumero]
  const ano = String(hoje.getFullYear())
  const dataAtual = `${dia}/${String(mesNumero + 1).padStart(2, '0')}/${ano}`
  const dataAtualExtenso = `${dia} de ${mesExtenso} de ${ano}`

  // Endereço completo do cliente
  const enderecoPartes = [
    client.street || client.address,
    client.number ? `nº ${client.number}` : null,
    client.complement,
    client.neighborhood ? `Bairro ${client.neighborhood}` : null,
    client.city && client.state ? `${client.city}/${client.state}` : client.city || client.state,
    client.cep ? `CEP ${client.cep}` : null,
  ].filter(Boolean)
  const enderecoCompleto = enderecoPartes.join(', ')

  const valorCausaNum = caseItem.value != null ? Number(caseItem.value) : 0
  const valorCausaFormatado = caseItem.value != null ? formatCurrency(caseItem.value) : ''
  const valorCausaExtenso = valorCausaNum > 0 ? numeroPorExtenso(valorCausaNum) : ''

  // Cálculos dinâmicos e precisos de honorários a partir dos registros do processo
  const { feeValueFormatted, feePercentageFormatted, feeInstallments } = calculateProcessFees({
    caseItem,
    paymentPlans,
    transactions,
    transactionCases,
  })

  const cidadeEscritorio = 'Sorocaba'
  const estadoEscritorio = 'SP'

  // Monta objeto com suporte a notação com ponto "cliente.nome" E objeto aninhado cliente: { nome }
  const clienteObj = {
    nome: client.name || '',
    cpf: client.document || '',
    rg: client.rg || '',
    documento: client.document || '',
    tipo: client.type || '',
    email: client.no_email || client.email_na ? '' : client.email || '',
    telefone: client.no_phone || client.phone_na ? '' : client.phone || '',
    estadoCivil: client.marital_status || '',
    profissao: client.profissao || client.profession || '',
    dataNascimento: client.birthday || '',
    endereco: enderecoCompleto,
    rua: client.street || client.address || '',
    numero: client.number || '',
    ruaNumero:
      (client.street || client.address) && client.number
        ? `${client.street || client.address}, ${client.number}`
        : client.street || client.address || client.number || '',
    numeroRua:
      client.number && (client.street || client.address)
        ? `${client.number}, ${client.street || client.address}`
        : client.number || client.street || client.address || '',
    complemento: client.complement || '',
    bairro: client.neighborhood || '',
    cidade: client.city || '',
    estado: client.state || '',
    cep: client.cep || '',
    nacionalidade: client.nacionalidade || 'Brasileiro(a)',
  }

  const processoObj = {
    numero: caseItem.number || '',
    numeroProcesso: caseItem.number || '',
    nome: caseItem.process_name || caseItem.type || '',
    tipo: caseItem.type || '',
    status: caseItem.status || '',
    vara: caseItem.court || '',
    comarca: (caseItem.comarca || '').toUpperCase(),
    estado: (caseItem.state || '').toUpperCase(),
    sistema: caseItem.system || '',
    posicao: caseItem.position || '',
    parteContraria: caseItem.adverseParty || '',
    adverseParty: caseItem.adverseParty || '',
    valorCausa: valorCausaFormatado,
    valorCausaExtenso,
    valorCausaNumero:
      valorCausaNum > 0 ? valorCausaNum.toLocaleString('pt-BR', { minimumFractionDigits: 2 }) : '',
    tipoHonorarios: caseItem.feeType || '',
    valorHonorarios: feeValueFormatted,
    percentualHonorarios: feePercentageFormatted || undefined,
    parcelasHonorarios: feeInstallments,
  }

  const escritorioObj = {
    nome: 'Douglas Santos Advocacia',
    advogado: 'Douglas Paulino dos Santos',
    oab: 'OAB/SP 430.509',
    cnpj: '53.649.030/0001-20',
    endereco: 'Rua São Bento, 273 - Centro, Sorocaba - SP, CEP 18010-031',
    telefone: '(15) 3042-1234',
    email: 'advdouglaspsantos@gmail.com',
    cidade: cidadeEscritorio,
    estado: estadoEscritorio,
  }

  const rootMap: Record<string, any> = {
    // Objetos aninhados (compatibilidade com {{cliente.nome}} em modo parser padrão)
    cliente: clienteObj,
    processo: processoObj,
    escritorio: escritorioObj,

    // Chaves planas diretas (para templates que usam delimitador simples)
    'cliente.nome': clienteObj.nome,
    'cliente.cpf': clienteObj.cpf,
    'cliente.rg': clienteObj.rg,
    'cliente.documento': clienteObj.documento,
    'cliente.tipo': clienteObj.tipo,
    'cliente.email': clienteObj.email,
    'cliente.telefone': clienteObj.telefone,
    'cliente.estadoCivil': clienteObj.estadoCivil,
    'cliente.profissao': clienteObj.profissao,
    'cliente.dataNascimento': clienteObj.dataNascimento,
    'cliente.endereco': clienteObj.endereco,
    'cliente.rua': clienteObj.rua,
    'cliente.numero': clienteObj.numero,
    'cliente.ruaNumero': clienteObj.ruaNumero,
    'cliente.numeroRua': clienteObj.numeroRua,
    'cliente.complemento': clienteObj.complemento,
    'cliente.bairro': clienteObj.bairro,
    'cliente.cidade': clienteObj.cidade,
    'cliente.estado': clienteObj.estado,
    'cliente.cep': clienteObj.cep,
    'cliente.nacionalidade': clienteObj.nacionalidade,

    'processo.numero': processoObj.numero,
    'processo.numeroProcesso': processoObj.numeroProcesso,
    'processo.nome': processoObj.nome,
    'processo.tipo': processoObj.tipo,
    'processo.status': processoObj.status,
    'processo.vara': processoObj.vara,
    'processo.comarca': processoObj.comarca,
    'processo.estado': processoObj.estado,
    'processo.sistema': processoObj.sistema,
    'processo.posicao': processoObj.posicao,
    'processo.parteContraria': processoObj.parteContraria,
    'processo.adverseParty': processoObj.adverseParty,
    'processo.valorCausa': processoObj.valorCausa,
    'processo.valorCausaExtenso': processoObj.valorCausaExtenso,
    'processo.valorCausaNumero': processoObj.valorCausaNumero,
    'processo.tipoHonorarios': processoObj.tipoHonorarios,
    'processo.valorHonorarios': processoObj.valorHonorarios,
    'processo.percentualHonorarios': processoObj.percentualHonorarios,
    'processo.parcelasHonorarios': processoObj.parcelasHonorarios,

    // Aliases diretos de honorários na raiz
    fee_value: processoObj.valorHonorarios,
    fee_percentage: processoObj.percentualHonorarios,
    fee_installments: processoObj.parcelasHonorarios,

    'escritorio.nome': escritorioObj.nome,
    'escritorio.advogado': escritorioObj.advogado,
    'escritorio.oab': escritorioObj.oab,
    'escritorio.cnpj': escritorioObj.cnpj,
    'escritorio.endereco': escritorioObj.endereco,
    'escritorio.telefone': escritorioObj.telefone,
    'escritorio.email': escritorioObj.email,
    'escritorio.cidade': escritorioObj.cidade,
    'escritorio.estado': escritorioObj.estado,

    // Data / Sistema
    dataAtual,
    dataAtualExtenso,
    diaAtual: dia,
    mesAtual: mesExtenso,
    anoAtual: ano,
    cidadeDataAtual: `${cidadeEscritorio}/${estadoEscritorio}, ${dataAtualExtenso}`,
  }

  // Mescla campos manuais digitados pelo usuário
  Object.keys(manualValues).forEach((key) => {
    const val = manualValues[key]
    rootMap[key] = val != null ? String(val) : ''
    // Também adiciona se foi digitado sem prefixo ou com prefixo
    if (key.includes('.')) {
      const [parent, child] = key.split('.')
      if (!rootMap[parent]) rootMap[parent] = {}
      if (typeof rootMap[parent] === 'object') {
        rootMap[parent][child] = val != null ? String(val) : ''
      }
    }
  })

  // Dicionário de Apelidos Bidirecional:
  // Propaga valores para apelidos curtos (em inglês e português simples) e vice-versa,
  // garantindo que {{cliente.nome}} e {{client_name}} tenham exatamente o mesmo valor.
  AVAILABLE_PLACEHOLDERS.forEach((placeholder) => {
    const mainKey = placeholder.key
    const aliases = placeholder.aliases || []
    if (aliases.length === 0) return

    // Descobre o valor presente na chave canônica ou em algum dos apelidos
    let foundValue: any = rootMap[mainKey]
    if (foundValue == null || foundValue === '') {
      // Tenta achar em algum apelido que já possa ter sido passado em manualValues
      for (const alias of aliases) {
        if (rootMap[alias] != null && rootMap[alias] !== '') {
          foundValue = rootMap[alias]
          break
        }
      }
    }

    if (foundValue != null && foundValue !== '') {
      // Garante na chave canônica
      if (rootMap[mainKey] == null || rootMap[mainKey] === '') {
        rootMap[mainKey] = foundValue
      }
      // Garante em cada apelido na raiz
      aliases.forEach((alias) => {
        if (rootMap[alias] == null || rootMap[alias] === '') {
          rootMap[alias] = foundValue
        }
      })
    }
  })

  return rootMap
}

/**
 * Traduz erros internos do docxtemplater para mensagens amigáveis em português
 */
export function formatDocxtemplaterError(err: any): string {
  if (!err) return 'Erro desconhecido ao processar o modelo .docx.'

  // Erros de parsing de zip / buffer vazio ou corrompido
  const rawMsg = typeof err.message === 'string' ? err.message : String(err)
  if (
    rawMsg.includes("Can't find end of central directory") ||
    rawMsg.includes('Corrupted zip') ||
    rawMsg.includes('not a valid zip') ||
    rawMsg.includes('end of data reached')
  ) {
    return 'Não foi possível ler o arquivo do modelo — ele pode estar corrompido ou vazio (arquivo .docx inválido).'
  }

  // Verifica se possui lista de erros estruturados (DocxtemplaterMultiError ou properties.errors)
  const errors: any[] = Array.isArray(err.properties?.errors) ? err.properties.errors : []

  if (errors.length > 0) {
    const formattedList = errors.map((subErr, idx) => {
      const id: string = subErr.properties?.id || subErr.name || ''
      const rawTag: string =
        subErr.properties?.xtag ||
        subErr.properties?.tag ||
        subErr.properties?.context ||
        subErr.properties?.closingtag ||
        subErr.properties?.openingtag ||
        ''
      const explanation: string = subErr.properties?.explanation || subErr.message || ''

      const cleanTag = rawTag
        .trim()
        .replace(/^\{+|\}+$/g, '')
        .trim()
      const tagDisplay = cleanTag ? `{{${cleanTag}}}` : rawTag ? `"${rawTag.trim()}"` : ''

      switch (id) {
        case 'unclosed_tag':
          return tagDisplay
            ? `Marcador ${tagDisplay} não fechado (faltou "}}") — corrija no modelo`
            : `Marcador não fechado (faltou "}}"): ${explanation}`

        case 'unopened_tag':
          return tagDisplay
            ? `Marcador ${tagDisplay} não aberto (faltou "{{" antes de "}}") — corrija no modelo`
            : `Marcador não aberto (faltou "{{"): ${explanation}`

        case 'duplicate_open_tag':
          return tagDisplay
            ? `Marcador ${tagDisplay} com abertura duplicada (excesso de "{") — corrija no modelo`
            : `Marcador com abertura duplicada: ${explanation}`

        case 'duplicate_close_tag':
          return tagDisplay
            ? `Marcador ${tagDisplay} com fechamento duplicado (excesso de "}") — corrija no modelo`
            : `Marcador com fechamento duplicado: ${explanation}`

        case 'closing_tag_does_not_match_opening_tag': {
          const opening = subErr.properties?.openingtag || ''
          const closing = subErr.properties?.closingtag || ''
          return `Tag de fechamento {{/${closing}}} não corresponde à tag de abertura {{#${opening}}} — corrija no modelo`
        }

        case 'unbalanced_loop_tags':
          return `Estrutura de repetição/tabela desbalanceada no modelo: ${explanation}`

        case 'loop_position_invalid':
          return tagDisplay
            ? `Bloco de repetição ${tagDisplay} em posição inválida (ex.: iniciado dentro de tabela e fechado fora)`
            : `Bloco de repetição em posição inválida no documento: ${explanation}`

        case 'scopeparser_compilation_failed':
        case 'scopeparser_execution_failed':
          return tagDisplay
            ? `Falha ao interpretar o marcador ${tagDisplay} — sintaxe inválida`
            : `Sintaxe inválida no marcador: ${explanation}`

        case 'filetype_not_identified':
          return 'O formato do arquivo não pôde ser identificado como documento Word (.docx válido).'

        case 'filetype_not_handled':
          return 'Formato de arquivo não suportado. Utilize apenas modelos em formato Word (.docx).'

        case 'invalid_xml_characters':
          return tagDisplay
            ? `Caracteres inválidos encontrados no marcador ${tagDisplay}`
            : `Caracteres inválidos no documento XML: ${explanation}`

        case 'malformed_xml':
        case 'file_has_invalid_xml':
          return 'O arquivo do modelo .docx contém XML corrompido ou mal formado.'

        default:
          if (explanation) {
            return tagDisplay ? `Erro no marcador ${tagDisplay}: ${explanation}` : explanation
          }
          return `Erro no marcador: ${id || 'sintaxe inválida'}`
      }
    })

    if (formattedList.length === 1) {
      return formattedList[0]
    }

    // Se houver múltiplos erros, lista numerada ou com bullet
    return formattedList.map((msg, i) => `${i + 1}. ${msg}`).join('\n')
  }

  // Se não tem array errors, mas o próprio err tem properties.id / explanation
  if (err.properties?.id) {
    const id = err.properties.id
    const rawTag = err.properties.xtag || err.properties.tag || err.properties.context || ''
    const cleanTag = rawTag
      .trim()
      .replace(/^\{+|\}+$/g, '')
      .trim()
    const tagDisplay = cleanTag ? `{{${cleanTag}}}` : rawTag ? `"${rawTag.trim()}"` : ''
    const explanation = err.properties.explanation || err.message || ''

    if (id === 'unclosed_tag') {
      return tagDisplay
        ? `Marcador ${tagDisplay} não fechado (faltou "}}") — corrija no modelo`
        : `Marcador não fechado: ${explanation}`
    }
    if (id === 'duplicate_open_tag') {
      return tagDisplay
        ? `Marcador ${tagDisplay} com abertura duplicada — corrija no modelo`
        : `Marcador com abertura duplicada: ${explanation}`
    }
    if (id === 'duplicate_close_tag') {
      return tagDisplay
        ? `Marcador ${tagDisplay} com fechamento duplicado — corrija no modelo`
        : `Marcador com fechamento duplicado: ${explanation}`
    }
    if (id === 'unopened_tag') {
      return tagDisplay
        ? `Marcador ${tagDisplay} não aberto — corrija no modelo`
        : `Marcador não aberto: ${explanation}`
    }
    if (explanation) {
      return explanation
    }
  }

  if (err.message && err.message !== 'Multi error') {
    return err.message
  }

  return 'O modelo contém marcadores mal formados ou com erro de sintaxe. Revise as chaves {{...}} no arquivo .docx.'
}

/**
 * Extrai todas as tags/marcadores brutos presentes no arquivo .docx
 * examinando os arquivos XML do zip (document.xml, header*.xml, footer*.xml).
 */
export function extractPlaceholdersFromZip(zip: PizZip): string[] {
  const foundTags = new Set<string>()
  const tagRegex = /\{\{\s*([#/^>]?)\s*([^{}]+?)\s*\}\}/g

  const files = Object.keys(zip.files || {})
  for (const fileName of files) {
    // Foca nos XMLs do documento Word (corpo, cabeçalhos, rodapés)
    if (!fileName.startsWith('word/') || !fileName.endsWith('.xml')) continue
    try {
      const content = zip.file(fileName)?.asText() || ''
      if (!content.includes('{{')) continue

      // Remove tags XML internas que podem quebrar o marcador dentro do Word
      // Ex: {{<w:r>cliente</w:r>.<w:r>nome</w:r>}} -> {{cliente.nome}}
      const cleanContent = content.replace(/<[^>]+>/g, '')

      let match: RegExpExecArray | null
      while ((match = tagRegex.exec(cleanContent)) !== null) {
        const prefix = match[1] || ''
        const rawKey = match[2]?.trim()
        // Ignora tags de fechamento de bloco ou condicionais puras como /loop
        if (prefix === '/' || !rawKey) continue
        foundTags.add(rawKey)
      }
    } catch {
      // Ignora arquivos que não possam ser lidos como texto
    }
  }

  return Array.from(foundTags)
}

export interface GenerateDocxResult {
  blob: Blob
  unresolvedPlaceholders: string[]
}

/**
 * Preenche o template .docx client-side com docxtemplater + pizzip preservando 100% da formatação.
 * Fim do vazio silencioso: tags não resolvidas recebem "[PREENCHER: nome_do_marcador]".
 * Retorna também a lista de marcadores não resolvidos encontrados durante a geração.
 */
export async function generateDocxBlob(
  templateBuffer: ArrayBuffer,
  dataMap: Record<string, any>,
): Promise<GenerateDocxResult> {
  let zip: PizZip
  try {
    zip = new PizZip(templateBuffer)
  } catch (zipErr: any) {
    throw new Error(
      'Não foi possível ler o arquivo do modelo — ele pode estar corrompido ou vazio (falha ao abrir zip).',
    )
  }

  const unresolvedSet = new Set<string>()

  let doc: Docxtemplater
  try {
    doc = new Docxtemplater(zip, {
      paragraphLoop: true,
      linebreaks: true,
      delimiters: { start: '{{', end: '}}' },
      nullGetter: (part: any) => {
        // Docxtemplater passa um objeto part com { value, module, tag }
        // Se part for string ou tiver raw/value/tag:
        const rawTag =
          typeof part === 'string'
            ? part
            : part?.raw || part?.value || part?.tag || (part ? String(part) : '')
        const cleanTag = String(rawTag).trim()
        if (cleanTag) {
          unresolvedSet.add(cleanTag)
          return `[PREENCHER: ${cleanTag}]`
        }
        return '[PREENCHER]'
      },
    })
  } catch (initErr: any) {
    const friendly = formatDocxtemplaterError(initErr)
    throw new Error(friendly)
  }

  try {
    // Renderiza aplicando os dados
    doc.render(dataMap)
  } catch (renderErr: any) {
    const friendly = formatDocxtemplaterError(renderErr)
    throw new Error(friendly)
  }

  try {
    const outputBlob = doc.getZip().generate({
      type: 'blob',
      mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      compression: 'DEFLATE',
    })
    return {
      blob: outputBlob,
      unresolvedPlaceholders: Array.from(unresolvedSet),
    }
  } catch (genErr: any) {
    throw new Error(
      `Falha ao gerar o arquivo final: ${genErr?.message || 'erro na compactação do documento'}.`,
    )
  }
}

/**
 * Dispara o download de um Blob .docx no navegador
 */
export function triggerFileDownload(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  setTimeout(() => URL.revokeObjectURL(url), 2000)
}

/**
 * Converte um blob DOCX em PDF via endpoint Edge Function 'convert-document'
 * conectado ao motor Gotenberg/LibreOffice no VPS
 */
export async function convertDocxToPdf(
  docxBlob: Blob,
  fileName: string,
): Promise<{ pdfBlob?: Blob; error?: string; requiresScript?: boolean }> {
  try {
    // 1. Converter blob para Base64
    const arrayBuffer = await docxBlob.arrayBuffer()
    const bytes = new Uint8Array(arrayBuffer)
    let binary = ''
    for (let i = 0; i < bytes.byteLength; i++) {
      binary += String.fromCharCode(bytes[i])
    }
    const docxBase64 = btoa(binary)

    const { data, error } = await supabase.functions.invoke('convert-document', {
      body: {
        docxBase64,
        fileName: fileName.endsWith('.docx') ? fileName : `${fileName}.docx`,
      },
    })

    if (error) {
      let errorMsg = error.message || 'Erro na conversão de documento'
      let requiresScript = false
      try {
        if (typeof (error as any)?.context?.json === 'function') {
          const bodyJson = await (error as any).context.json()
          if (bodyJson?.error) errorMsg = bodyJson.error
          if (bodyJson?.requiresScript) requiresScript = true
        }
      } catch {
        // ignora erro ao ler context
      }
      return { error: errorMsg, requiresScript }
    }

    if (data?.pdfBase64) {
      const pdfBin = atob(data.pdfBase64)
      const pdfBytes = new Uint8Array(pdfBin.length)
      for (let i = 0; i < pdfBin.length; i++) {
        pdfBytes[i] = pdfBin.charCodeAt(i)
      }
      const pdfBlob = new Blob([pdfBytes], { type: 'application/pdf' })
      return { pdfBlob }
    }

    if (data?.error) {
      return { error: data.error, requiresScript: Boolean(data.requiresScript) }
    }

    return { error: 'Formato de resposta inesperado do conversor de PDF.' }
  } catch (err: any) {
    return { error: err?.message || 'Falha ao acionar serviço de conversão.' }
  }
}

/**
 * Consulta o status do serviço de conversão fiel DOCX -> PDF
 */
export async function checkPdfConverterStatus(): Promise<{
  ready: boolean
  detail?: string
}> {
  try {
    const { data, error } = await supabase.functions.invoke('convert-document', {
      body: { action: 'status' },
    })
    if (error) {
      return { ready: false, detail: error.message }
    }
    return {
      ready: data?.status === 'ready' || Boolean(data?.gotenbergOnline),
      detail: data?.detail,
    }
  } catch (e: any) {
    return { ready: false, detail: e?.message }
  }
}

/**
 * Gera nome de arquivo padronizado ex: "Contrato - Douglas Santos - 2026-10-24.docx"
 */
export function formatGeneratedFileName(templateName: string, clientName?: string): string {
  const cleanTpl = (templateName || 'Documento').replace(/\.docx$/i, '').trim()
  const cleanClient = (clientName || 'Cliente').trim().replace(/[\\/:*?"<>|]/g, '')
  const hoje = new Date().toISOString().split('T')[0]
  return `${cleanTpl} - ${cleanClient} - ${hoje}.docx`
}

/**
 * Salva o arquivo gerado no bucket de documentos e retorna o caminho salvo
 */
export async function saveGeneratedDocxToStorage(
  blob: Blob,
  fileName: string,
): Promise<{ path: string; error: any }> {
  const safeName = `${Date.now()}_${fileName.replace(/\s+/g, '_').replace(/[\\/:*?"<>|]/g, '')}`
  let bucket = 'documents'
  let { error } = await supabase.storage.from(bucket).upload(safeName, blob, {
    contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    upsert: true,
  })

  if (error) {
    bucket = 'document_templates'
    const fallback = await supabase.storage.from(bucket).upload(safeName, blob, {
      contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      upsert: true,
    })
    if (fallback.error) {
      return { path: '', error: fallback.error }
    }
  }

  return { path: `${bucket}/${safeName}`, error: null }
}
