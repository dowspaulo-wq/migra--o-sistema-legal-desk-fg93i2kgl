const BRAZILIAN_STATES = [
  'AC',
  'AL',
  'AP',
  'AM',
  'BA',
  'CE',
  'DF',
  'ES',
  'GO',
  'MA',
  'MT',
  'MS',
  'MG',
  'PA',
  'PB',
  'PR',
  'PE',
  'PI',
  'RJ',
  'RN',
  'RS',
  'RO',
  'RR',
  'SC',
  'SP',
  'SE',
  'TO',
] as const

export { BRAZILIAN_STATES }

export interface ViaCepResponse {
  logradouro: string
  bairro: string
  localidade: string
  uf: string
  erro?: boolean
}

export async function fetchCepData(
  cep: string,
): Promise<{ street: string; neighborhood: string; city: string; state: string } | null> {
  const cleanCep = cep.replace(/\D/g, '')
  if (cleanCep.length !== 8) return null

  try {
    const response = await fetch(`https://viacep.com.br/ws/${cleanCep}/json/`)
    if (!response.ok) return null
    const data: ViaCepResponse = await response.json()
    if (data.erro) return null

    return {
      street: data.logradouro || '',
      neighborhood: data.bairro || '',
      city: data.localidade || '',
      state: data.uf || '',
    }
  } catch {
    return null
  }
}
