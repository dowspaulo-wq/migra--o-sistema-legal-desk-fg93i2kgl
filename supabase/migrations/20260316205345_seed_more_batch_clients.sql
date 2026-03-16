INSERT INTO public.clients (
    name,
    document,
    type,
    status,
    "isSpecial"
) VALUES
('ELIENE DIAS DA ROCHA', '540.120.746-87', 'Pessoa Física', 'Ativo', false),
('DANIEL ASSIS AMANCIO DE ALMEIDA', '116.893.146-05', 'Pessoa Física', 'Ativo', false),
('CRISTHIAN ROHAN LUIZ LISBOA DE ALMEIDA', '059.717.776-70', 'Pessoa Física', 'Ativo', false),
('CLEITON BRANDÃO ANDRADE', '105.066.396-90', 'Pessoa Física', 'Ativo', false),
('CONDOMINIO RESIDENCIAL ALBATROZ', '03.615.183/0001-48', 'Pessoa Jurídica', 'Ativo', false),
('VITOR RAFAEL DE CARVALHO', '012.659.696-47', 'Pessoa Física', 'Ativo', false),
('ERNANI CORDEIRO DE OLIVEIRA', '035.703.756-17', 'Pessoa Física', 'Ativo', false),
('MICHELE DA SILVA MONTES OLIVEIRA', '003967596-37', 'Pessoa Física', 'Ativo', false),
('RAQUEL ROSA COSTA', '252.972.658-27', 'Pessoa Física', 'Ativo', false),
('GUILHERME FILIPPINI AUGUSTO', '423.825.378-76', 'Pessoa Física', 'Ativo', false),
('WILLIAM DAS CHAGAS MAGELA', '036.178.086-97', 'Pessoa Física', 'Ativo', false),
('EMILSON NOGUEIRA SANTOS', '913.835.606-68', 'Pessoa Física', 'Ativo', false),
('THIAGO MILANEZ DA SILVA', '072.103.856-57', 'Pessoa Física', 'Ativo', false),
('THALITA STHER NEPOMUCENO DUNGA', '121.099.026-12', 'Pessoa Física', 'Ativo', false),
('GERALDO DONIZETE DA COSTA', '354.783.816-91', 'Pessoa Física', 'Ativo', false)
ON CONFLICT (document) DO UPDATE SET
    name = EXCLUDED.name,
    type = EXCLUDED.type,
    status = EXCLUDED.status,
    "isSpecial" = EXCLUDED."isSpecial";

