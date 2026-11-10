// Test runner in pure Node.js (executes json validation negative tests)
// Simulates the exact jq schema rules and evaluates the negative test cases.

const VALIDAR_SCHEMA_INV = (obj) => {
  if (typeof obj !== 'object' || obj === null || Array.isArray(obj)) throw new Error("raiz não é objeto");
  if (typeof obj.sumario !== 'object' || obj.sumario === null || Array.isArray(obj.sumario)) throw new Error("sumario ausente ou inválido");
  if (typeof obj.sumario.total_tabelas_public !== 'number') throw new Error("total_tabelas_public deve ser número");
  if (typeof obj.sumario.total_tabelas_auth !== 'number') throw new Error("total_tabelas_auth deve ser número");
  if (!Array.isArray(obj.tabelas)) throw new Error("tabelas deve ser array");
  if (!Array.isArray(obj.constraints)) throw new Error("constraints deve ser array");
  if (!Array.isArray(obj.funcoes)) throw new Error("funcoes deve ser array");
  if (obj.tabelas.length === 0) throw new Error("tabelas não pode ser array vazio em inventário válido");
  return true;
};

const VALIDAR_TABELAS_ITENS = (arr) => {
  if (!Array.isArray(arr)) throw new Error("tabelas não é um array");
  if (arr.length === 0) throw new Error("tabelas vazio");
  for (const item of arr) {
    if (typeof item !== 'object' || item === null || Array.isArray(item)) throw new Error("elemento de tabelas não é objeto");
    if (typeof item.schema !== 'string') throw new Error("schema em tabelas não é string");
    if (typeof item.tabela !== 'string') throw new Error("tabela em tabelas não é string");
    if (typeof item.contagem !== 'number') throw new Error("contagem em tabelas não é número");
    if (typeof item.tipo_contagem !== 'string') throw new Error("tipo_contagem em tabelas não é string");
    if (item.tipo_contagem !== 'exata' && item.tipo_contagem !== 'estimada_reltuples') throw new Error("tipo_contagem inválido");
  }
  return true;
};

const VALIDAR_CONSTRAINTS_ITENS = (arr) => {
  if (!Array.isArray(arr)) throw new Error("constraints não é um array");
  for (const item of arr) {
    if (typeof item !== 'object' || item === null || Array.isArray(item)) throw new Error("elemento de constraints não é objeto");
    if (typeof item.schema !== 'string') throw new Error("schema em constraints não é string");
    if (typeof item.tabela !== 'string') throw new Error("tabela em constraints não é string");
    if (typeof item.nome !== 'string') throw new Error("nome em constraints não é string");
    if (typeof item.tipo !== 'string') throw new Error("tipo em constraints não é string");
    if (typeof item.definicao !== 'string') throw new Error("definicao em constraints não é string");
  }
  return true;
};

const VALIDAR_FUNCOES_ITENS = (arr) => {
  if (!Array.isArray(arr)) throw new Error("funcoes não é um array");
  for (const item of arr) {
    if (typeof item !== 'object' || item === null || Array.isArray(item)) throw new Error("elemento de funcoes não é objeto");
    if (typeof item.schema !== 'string') throw new Error("schema em funcoes não é string");
    if (typeof item.nome !== 'string') throw new Error("nome em funcoes não é string");
    if (typeof item.identidade !== 'string') throw new Error("identidade em funcoes não é string");
    if (typeof item.tipo_retorno !== 'string') throw new Error("tipo_retorno em funcoes não é string");
    if (typeof item.linguagem !== 'string') throw new Error("linguagem em funcoes não é string");
    if (typeof item.inclui_corpo !== 'boolean') throw new Error("inclui_corpo em funcoes não é booleano");
    if (item.inclui_corpo === true && typeof item.definicao !== 'string') throw new Error("definicao obrigatória quando inclui_corpo=true");
  }
  return true;
};

const tests = [
  // Grupo 1: Esquema raiz
  { name: "Raiz do JSON não é objeto (é array)", validator: VALIDAR_SCHEMA_INV, raw: '[{"sumario": {}}]' },
  { name: "Campo sumario ausente", validator: VALIDAR_SCHEMA_INV, raw: '{"versao": "1.6.0", "tabelas": [], "constraints": [], "funcoes": []}' },
  { name: "total_tabelas_public não numérico (string)", validator: VALIDAR_SCHEMA_INV, raw: '{"sumario": {"total_tabelas_public": "17", "total_tabelas_auth": 10}, "tabelas": [{"schema":"public","tabela":"clients","contagem":1,"tipo_contagem":"exata"}], "constraints": [], "funcoes": []}' },
  { name: "total_tabelas_auth ausente no sumario", validator: VALIDAR_SCHEMA_INV, raw: '{"sumario": {"total_tabelas_public": 17}, "tabelas": [{"schema":"public","tabela":"clients","contagem":1,"tipo_contagem":"exata"}], "constraints": [], "funcoes": []}' },
  { name: "Array tabelas vazio quando inventário exige tabelas existentes", validator: VALIDAR_SCHEMA_INV, raw: '{"sumario": {"total_tabelas_public": 0, "total_tabelas_auth": 0}, "tabelas": [], "constraints": [], "funcoes": []}' },
  { name: "Campo constraints não é array (é objeto)", validator: VALIDAR_SCHEMA_INV, raw: '{"sumario": {"total_tabelas_public": 1, "total_tabelas_auth": 1}, "tabelas": [{"schema":"public","tabela":"clients","contagem":1,"tipo_contagem":"exata"}], "constraints": {}, "funcoes": []}' },
  { name: "Campo funcoes não é array (é null)", validator: VALIDAR_SCHEMA_INV, raw: '{"sumario": {"total_tabelas_public": 1, "total_tabelas_auth": 1}, "tabelas": [{"schema":"public","tabela":"clients","contagem":1,"tipo_contagem":"exata"}], "constraints": [], "funcoes": null}' },

  // Grupo 2: Itens de tabelas
  { name: "Tabela com contagem como string em vez de número", validator: VALIDAR_TABELAS_ITENS, raw: '[{"schema": "public", "tabela": "cases", "contagem": "500", "tipo_contagem": "exata"}]' },
  { name: "Tabela com tipo_contagem desconhecido/inválido", validator: VALIDAR_TABELAS_ITENS, raw: '[{"schema": "public", "tabela": "cases", "contagem": 500, "tipo_contagem": "chute"}]' },
  { name: "Tabela com schema ausente ou nulo", validator: VALIDAR_TABELAS_ITENS, raw: '[{"tabela": "cases", "contagem": 500, "tipo_contagem": "exata"}]' },
  { name: "Elemento da lista de tabelas não é objeto (é string)", validator: VALIDAR_TABELAS_ITENS, raw: '["public.clients", "public.cases"]' },

  // Grupo 3: Constraints e Funções
  { name: "Constraint com definicao ausente", validator: VALIDAR_CONSTRAINTS_ITENS, raw: '[{"schema": "public", "tabela": "cases", "nome": "cases_pkey", "tipo": "p"}]' },
  { name: "Constraint com nome não-string (número)", validator: VALIDAR_CONSTRAINTS_ITENS, raw: '[{"schema": "public", "tabela": "cases", "nome": 12345, "tipo": "p", "definicao": "PRIMARY KEY (id)"}]' },
  { name: "Função com inclui_corpo=true mas definicao ausente", validator: VALIDAR_FUNCOES_ITENS, raw: '[{"schema": "public", "nome": "calcular_honorarios", "identidade": "integer", "tipo_retorno": "numeric", "linguagem": "plpgsql", "inclui_corpo": true}]' },
  { name: "Função com inclui_corpo não-booleano (string 'true')", validator: VALIDAR_FUNCOES_ITENS, raw: '[{"schema": "public", "nome": "calcular_honorarios", "identidade": "integer", "tipo_retorno": "numeric", "linguagem": "plpgsql", "inclui_corpo": "true", "definicao": "..."}]' }
];

console.log("================================================================================");
console.log(" EXECUÇÃO AUTOMATIZADA DOS TESTES NEGATIVOS JSON (v1.6.0)");
console.log("================================================================================");

let passed = 0;
let failed = 0;

tests.forEach((t, idx) => {
  let threw = false;
  let errMsg = "";
  try {
    const parsed = JSON.parse(t.raw);
    t.validator(parsed);
  } catch (err) {
    threw = true;
    errMsg = err.message;
  }

  if (threw) {
    passed++;
    console.log(`  ✅ [REJEIÇÃO ESPERADA OK] Teste #${idx + 1}: ${t.name} -> Motivo: ${errMsg}`);
  } else {
    failed++;
    console.log(`  ❌ [FALHA - ACEITOU JSON INVÁLIDO] Teste #${idx + 1}: ${t.name}`);
  }
});

console.log("================================================================================");
console.log(` Total de testes: ${tests.length} | Rejeitados com sucesso: ${passed} | Falhas: ${failed}`);
console.log("================================================================================");

if (failed > 0) {
  process.exit(1);
}
