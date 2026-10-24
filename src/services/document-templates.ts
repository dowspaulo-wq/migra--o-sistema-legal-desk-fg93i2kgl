import { supabase } from '@/lib/supabase/client'
import PizZip from 'pizzip'
import Docxtemplater from 'docxtemplater'

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
  description?: string
}

export const AVAILABLE_PLACEHOLDERS: PlaceholderDocumentation[] = [
  // Cliente
  { key: 'cliente.nome', label: 'Nome Completo', example: 'João da Silva', group: 'Cliente' },
  { key: 'cliente.cpf', label: 'CPF / Documento', example: '123.456.789-00', group: 'Cliente' },
  { key: 'cliente.rg', label: 'RG', example: '12.345.678-9', group: 'Cliente' },
  {
    key: 'cliente.documento',
    label: 'Documento Principal (CPF/CNPJ)',
    example: '123.456.789-00',
    group: 'Cliente',
  },
  {
    key: 'cliente.tipo',
    label: 'Tipo de Pessoa (Física/Jurídica)',
    example: 'Pessoa Física',
    group: 'Cliente',
  },
  { key: 'cliente.email', label: 'E-mail', example: 'cliente@exemplo.com', group: 'Cliente' },
  {
    key: 'cliente.telefone',
    label: 'Telefone / WhatsApp',
    example: '(11) 98765-4321',
    group: 'Cliente',
  },
  { key: 'cliente.estadoCivil', label: 'Estado Civil', example: 'Casado(a)', group: 'Cliente' },
  { key: 'cliente.profissao', label: 'Profissão', example: 'Engenheiro Civil', group: 'Cliente' },
  {
    key: 'cliente.dataNascimento',
    label: 'Data de Nascimento',
    example: '15/04/1985',
    group: 'Cliente',
  },
  {
    key: 'cliente.endereco',
    label: 'Endereço Completo',
    example: 'Rua das Flores, 123, Apto 45 - Centro, São Paulo - SP, CEP 01234-567',
    group: 'Cliente',
  },
  { key: 'cliente.rua', label: 'Rua / Logradouro', example: 'Rua das Flores', group: 'Cliente' },
  { key: 'cliente.numero', label: 'Número', example: '123', group: 'Cliente' },
  { key: 'cliente.complemento', label: 'Complemento', example: 'Apto 45', group: 'Cliente' },
  { key: 'cliente.bairro', label: 'Bairro', example: 'Centro', group: 'Cliente' },
  { key: 'cliente.cidade', label: 'Cidade', example: 'São Paulo', group: 'Cliente' },
  { key: 'cliente.estado', label: 'UF / Estado', example: 'SP', group: 'Cliente' },
  { key: 'cliente.cep', label: 'CEP', example: '01234-567', group: 'Cliente' },
  {
    key: 'cliente.nacionalidade',
    label: 'Nacionalidade',
    example: 'Brasileiro(a)',
    group: 'Cliente',
  },

  // Processo
  {
    key: 'processo.numero',
    label: 'Número CNJ do Processo',
    example: '0001234-56.2026.8.26.0100',
    group: 'Processo',
  },
  {
    key: 'processo.numeroProcesso',
    label: 'Número do Processo (alias)',
    example: '0001234-56.2026.8.26.0100',
    group: 'Processo',
  },
  {
    key: 'processo.nome',
    label: 'Nome da Ação / Descrição',
    example: 'Ação Indenizatória por Danos Morais',
    group: 'Processo',
  },
  { key: 'processo.tipo', label: 'Tipo de Ação', example: 'Cível', group: 'Processo' },
  {
    key: 'processo.status',
    label: 'Status Processual',
    example: 'Em andamento',
    group: 'Processo',
  },
  { key: 'processo.vara', label: 'Vara / Juízo', example: '2ª Vara Cível', group: 'Processo' },
  { key: 'processo.comarca', label: 'Comarca', example: 'Sorocaba', group: 'Processo' },
  { key: 'processo.estado', label: 'UF do Processo', example: 'SP', group: 'Processo' },
  {
    key: 'processo.sistema',
    label: 'Sistema Processual',
    example: 'PJe / esaj',
    group: 'Processo',
  },
  {
    key: 'processo.posicao',
    label: 'Posição do Cliente no Processo',
    example: 'Autor',
    group: 'Processo',
  },
  {
    key: 'processo.parteContraria',
    label: 'Parte Contrária (Réu/Adverso)',
    example: 'Banco Exemplo S.A.',
    group: 'Processo',
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
  },
  {
    key: 'processo.valorCausaExtenso',
    label: 'Valor da Causa por Extenso',
    example: 'cinquenta mil reais',
    group: 'Processo',
  },
  {
    key: 'processo.valorCausaNumero',
    label: 'Valor da Causa (apenas número)',
    example: '50000,00',
    group: 'Processo',
  },
  {
    key: 'processo.tipoHonorarios',
    label: 'Tipo de Honorários',
    example: 'Honorários Contratuais',
    group: 'Processo',
  },
  {
    key: 'processo.valorHonorarios',
    label: 'Valor dos Honorários (R$)',
    example: 'R$ 5.000,00',
    group: 'Processo',
  },
  {
    key: 'processo.percentualHonorarios',
    label: 'Percentual de Honorários / Êxito',
    example: '30%',
    group: 'Processo',
  },
  {
    key: 'processo.parcelasHonorarios',
    label: 'Qtd de Parcelas de Honorários',
    example: '5',
    group: 'Processo',
  },

  // Escritório
  {
    key: 'escritorio.nome',
    label: 'Nome do Escritório / Advogado',
    example: 'Douglas Santos Advocacia',
    group: 'Escritório',
  },
  {
    key: 'escritorio.advogado',
    label: 'Advogado Responsável',
    example: 'Douglas Paulino dos Santos',
    group: 'Escritório',
  },
  {
    key: 'escritorio.oab',
    label: 'Número da OAB / UF',
    example: 'OAB/SP 123.456',
    group: 'Escritório',
  },
  {
    key: 'escritorio.cnpj',
    label: 'CNPJ do Escritório',
    example: '00.000.000/0001-00',
    group: 'Escritório',
  },
  {
    key: 'escritorio.endereco',
    label: 'Endereço do Escritório',
    example: 'Av. Paulista, 1000 - Bela Vista, São Paulo - SP',
    group: 'Escritório',
  },
  {
    key: 'escritorio.telefone',
    label: 'Telefone do Escritório',
    example: '(11) 3333-4444',
    group: 'Escritório',
  },
  {
    key: 'escritorio.email',
    label: 'E-mail do Escritório',
    example: 'contato@advdouglaspsantos.com.br',
    group: 'Escritório',
  },
  {
    key: 'escritorio.cidade',
    label: 'Cidade do Escritório',
    example: 'Sorocaba',
    group: 'Escritório',
  },
  { key: 'escritorio.estado', label: 'UF do Escritório', example: 'SP', group: 'Escritório' },

  // Data / Sistema
  {
    key: 'dataAtual',
    label: 'Data Atual (DD/MM/AAAA)',
    example: '24/10/2026',
    group: 'Data / Sistema',
  },
  {
    key: 'dataAtualExtenso',
    label: 'Data Atual por Extenso',
    example: '24 de outubro de 2026',
    group: 'Data / Sistema',
  },
  { key: 'diaAtual', label: 'Dia do Mês Atual (DD)', example: '24', group: 'Data / Sistema' },
  { key: 'mesAtual', label: 'Mês Atual por Extenso', example: 'outubro', group: 'Data / Sistema' },
  { key: 'anoAtual', label: 'Ano Atual (AAAA)', example: '2026', group: 'Data / Sistema' },
  {
    key: 'cidadeDataAtual',
    label: 'Cidade e Data Atual',
    example: 'Sorocaba/SP, 24 de outubro de 2026',
    group: 'Data / Sistema',
  },

  // Campos Manuais Dinâmicos Comuns
  {
    key: 'valorHonorarios',
    label: 'Valor dos Honorários (manual)',
    example: 'R$ 5.000,00',
    group: 'Campos Manuais',
    description: 'Definido no modelo pelo advogado',
  },
  {
    key: 'formaPagamento',
    label: 'Forma de Pagamento (manual)',
    example: 'Entrada de R$ 1.500,00 + 3 parcelas de R$ 500,00',
    group: 'Campos Manuais',
    description: 'Texto livre editado na geração',
  },
  {
    key: 'percentualExito',
    label: 'Percentual de Êxito (manual)',
    example: '30%',
    group: 'Campos Manuais',
    description: 'Percentual aplicado sobre o proveito econômico',
  },
  {
    key: 'nomeAcao',
    label: 'Nome Específico da Ação (manual)',
    example: 'Ação de Alimentos c/c Guarda',
    group: 'Campos Manuais',
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
      throw new Error(
        `Não foi possível baixar o modelo .docx (${filePath}): ${error?.message || second.error?.message}`,
      )
    }
    data = second.data
  }
  return await data.arrayBuffer()
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
 * Constrói o mapa de dados completo a partir do cliente, processo, escritório e inputs manuais
 */
export function buildDocumentDataMap(params: {
  client?: any
  caseItem?: any
  settings?: any
  manualValues?: Record<string, any>
}): Record<string, any> {
  const { client = {}, caseItem = {}, settings = {}, manualValues = {} } = params

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

  const valorHonorariosNum = caseItem.feeValue != null ? Number(caseItem.feeValue) : 0
  const valorHonorariosFormatado =
    caseItem.feeValue != null ? formatCurrency(caseItem.feeValue) : ''

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
    valorHonorarios: valorHonorariosFormatado,
    percentualHonorarios: caseItem.feePercentage ? formatPercentage(caseItem.feePercentage) : '',
    parcelasHonorarios: caseItem.feeInstallments ? String(caseItem.feeInstallments) : '',
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

  return rootMap
}

/**
 * Preenche o template .docx cliente-side com docxtemplater + pizzip preservando 100% da formatação
 */
export async function generateDocxBlob(
  templateBuffer: ArrayBuffer,
  dataMap: Record<string, any>,
): Promise<Blob> {
  const zip = new PizZip(templateBuffer)

  const doc = new Docxtemplater(zip, {
    paragraphLoop: true,
    linebreaks: true,
    nullGetter: () => '', // Garante que tags ausentes virem vazio em vez de erro "undefined"
  })

  // Renderiza aplicando os dados
  doc.render(dataMap)

  const outputBlob = doc.getZip().generate({
    type: 'blob',
    mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    compression: 'DEFLATE',
  })

  return outputBlob
}

/**
 * Dispara o download de um Blob .docx no navegador
 */
export function triggerFileDownload(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename.endsWith('.docx') ? filename : `${filename}.docx`
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  setTimeout(() => URL.revokeObjectURL(url), 2000)
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
