#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur — Testes Negativos de Validação de JSON de Inventário
# ==============================================================================
# Este script testa propositalmente os validadores jq de inventário contra
# diversos cenários de JSONs malformados, parciais ou inválidos.
#
# Cada teste DEVE FALHAR na validação jq estrita. Se qualquer teste passar
# erroneamente em um JSON inválido, o script reporta ERRO (exit 1).
# Se todos os JSONs inválidos forem corretamente rejeitados, exit 0.
# ==============================================================================

set -euo pipefail

TOTAL_TESTES=0
TESTES_PASSARAM=0
TESTES_FALHARAM=0

say() {
    printf '%s\n' "$*"
}

say_ok() {
    printf '  ✅ [REJEIÇÃO ESPERADA OK] %s\n' "$*"
}

say_fail() {
    printf '  ❌ [FALHA - DEVERIA REJEITAR MAS ACEITOU] %s\n' "$*" >&2
}

TMP_DIR="$(mktemp -d /tmp/sbjur-json-neg-tests-XXXXXX 2>/dev/null || mktemp -d -t 'sbjur-json-neg')"
trap 'rm -rf "${TMP_DIR}"' EXIT

say "================================================================================"
say " INICIANDO SUÍTE DE TESTES NEGATIVOS DOS VALIDADORES JSON DE INVENTÁRIO (v1.6.0)"
say "================================================================================"

# Expressão validadora de esquema raiz (utilizada no script 20)
VALIDAR_SCHEMA_INV='
    if type != "object" then error("raiz não é objeto")
    elif ((.sumario | type) != "object") then error("sumario ausente ou inválido")
    elif ((.sumario.total_tabelas_public | type) != "number") then error("total_tabelas_public deve ser número")
    elif ((.sumario.total_tabelas_auth | type) != "number") then error("total_tabelas_auth deve ser número")
    elif ((.tabelas | type) != "array") then error("tabelas deve ser array")
    elif ((.constraints | type) != "array") then error("constraints deve ser array")
    elif ((.funcoes | type) != "array") then error("funcoes deve ser array")
    elif ((.tabelas | length) == 0) then error("tabelas não pode ser array vazio em inventário válido")
    else empty end
'

# Expressão validadora estrita de elementos de tabelas (utilizada no script 21 e 20)
VALIDAR_TABELAS_ITENS='
    if type != "array" then error("tabelas não é um array")
    elif length == 0 then error("tabelas vazio")
    else .[] | (
        if (type != "object") then error("elemento de tabelas não é objeto")
        elif ((.schema | type) != "string") then error("schema em tabelas não é string")
        elif ((.tabela | type) != "string") then error("tabela em tabelas não é string")
        elif ((.contagem | type) != "number") then error("contagem em tabelas não é número")
        elif ((.tipo_contagem | type) != "string") then error("tipo_contagem em tabelas não é string")
        elif (.tipo_contagem != "exata" and .tipo_contagem != "estimada_reltuples") then error("tipo_contagem inválido")
        else empty end
    ) end
'

# Expressão validadora estrita de constraints
VALIDAR_CONSTRAINTS_ITENS='
    if type != "array" then error("constraints não é um array")
    else .[] | (
        if (type != "object") then error("elemento de constraints não é objeto")
        elif ((.schema | type) != "string") then error("schema em constraints não é string")
        elif ((.tabela | type) != "string") then error("tabela em constraints não é string")
        elif ((.nome | type) != "string") then error("nome em constraints não é string")
        elif ((.tipo | type) != "string") then error("tipo em constraints não é string")
        elif ((.definicao | type) != "string") then error("definicao em constraints não é string")
        else empty end
    ) end
'

# Expressão validadora estrita de funções
VALIDAR_FUNCOES_ITENS='
    if type != "array" then error("funcoes não é um array")
    else .[] | (
        if (type != "object") then error("elemento de funcoes não é objeto")
        elif ((.schema | type) != "string") then error("schema em funcoes não é string")
        elif ((.nome | type) != "string") then error("nome em funcoes não é string")
        elif ((.identidade | type) != "string") then error("identidade em funcoes não é string")
        elif ((.tipo_retorno | type) != "string") then error("tipo_retorno em funcoes não é string")
        elif ((.linguagem | type) != "string") then error("linguagem em funcoes não é string")
        elif ((.inclui_corpo | type) != "boolean") then error("inclui_corpo em funcoes não é booleano")
        elif (.inclui_corpo == true and ((.definicao | type) != "string")) then error("definicao obrigatória quando inclui_corpo=true")
        else empty end
    ) end
'

rodar_teste_negativo() {
    local nome="$1"
    local json_content="$2"
    local filtro_jq="$3"

    TOTAL_TESTES=$((TOTAL_TESTES + 1))
    local f="${TMP_DIR}/test_${TOTAL_TESTES}.json"
    printf '%s' "${json_content}" > "${f}"

    if jq -e "${filtro_jq}" "${f}" >/dev/null 2>&1; then
        say_fail "Teste #${TOTAL_TESTES}: ${nome}"
        TESTES_FALHARAM=$((TESTES_FALHARAM + 1))
    else
        say_ok "Teste #${TOTAL_TESTES}: ${nome}"
        TESTES_PASSARAM=$((TESTES_PASSARAM + 1))
    fi
}

say "📋 [GRUPO 1] Testes Negativos de Esquema Raiz e Campos Obrigatórios:"

rodar_teste_negativo \
    "Raiz do JSON não é objeto (é array)" \
    '[{"sumario": {}}]' \
    "${VALIDAR_SCHEMA_INV}"

rodar_teste_negativo \
    "Campo sumario ausente" \
    '{"versao": "1.6.0", "tabelas": [], "constraints": [], "funcoes": []}' \
    "${VALIDAR_SCHEMA_INV}"

rodar_teste_negativo \
    "total_tabelas_public não numérico (string)" \
    '{"sumario": {"total_tabelas_public": "17", "total_tabelas_auth": 10}, "tabelas": [{"schema":"public","tabela":"clients","contagem":1,"tipo_contagem":"exata"}], "constraints": [], "funcoes": []}' \
    "${VALIDAR_SCHEMA_INV}"

rodar_teste_negativo \
    "total_tabelas_auth ausente no sumario" \
    '{"sumario": {"total_tabelas_public": 17}, "tabelas": [{"schema":"public","tabela":"clients","contagem":1,"tipo_contagem":"exata"}], "constraints": [], "funcoes": []}' \
    "${VALIDAR_SCHEMA_INV}"

rodar_teste_negativo \
    "Array tabelas vazio quando inventário exige tabelas existentes" \
    '{"sumario": {"total_tabelas_public": 0, "total_tabelas_auth": 0}, "tabelas": [], "constraints": [], "funcoes": []}' \
    "${VALIDAR_SCHEMA_INV}"

rodar_teste_negativo \
    "Campo constraints não é array (é objeto)" \
    '{"sumario": {"total_tabelas_public": 1, "total_tabelas_auth": 1}, "tabelas": [{"schema":"public","tabela":"clients","contagem":1,"tipo_contagem":"exata"}], "constraints": {}, "funcoes": []}' \
    "${VALIDAR_SCHEMA_INV}"

rodar_teste_negativo \
    "Campo funcoes não é array (é null)" \
    '{"sumario": {"total_tabelas_public": 1, "total_tabelas_auth": 1}, "tabelas": [{"schema":"public","tabela":"clients","contagem":1,"tipo_contagem":"exata"}], "constraints": [], "funcoes": null}' \
    "${VALIDAR_SCHEMA_INV}"

say ""
say "📋 [GRUPO 2] Testes Negativos de Itens de Tabelas (Tipos e Valores Permitidos):"

rodar_teste_negativo \
    "Tabela com contagem como string em vez de número" \
    '[{"schema": "public", "tabela": "cases", "contagem": "500", "tipo_contagem": "exata"}]' \
    "${VALIDAR_TABELAS_ITENS}"

rodar_teste_negativo \
    "Tabela com tipo_contagem desconhecido/inválido" \
    '[{"schema": "public", "tabela": "cases", "contagem": 500, "tipo_contagem": "chute"}]' \
    "${VALIDAR_TABELAS_ITENS}"

rodar_teste_negativo \
    "Tabela com schema ausente ou nulo" \
    '[{"tabela": "cases", "contagem": 500, "tipo_contagem": "exata"}]' \
    "${VALIDAR_TABELAS_ITENS}"

rodar_teste_negativo \
    "Elemento da lista de tabelas não é objeto (é string)" \
    '["public.clients", "public.cases"]' \
    "${VALIDAR_TABELAS_ITENS}"

say ""
say "📋 [GRUPO 3] Testes Negativos de Constraints e Funções (Integridade DDL):"

rodar_teste_negativo \
    "Constraint com definicao ausente" \
    '[{"schema": "public", "tabela": "cases", "nome": "cases_pkey", "tipo": "p"}]' \
    "${VALIDAR_CONSTRAINTS_ITENS}"

rodar_teste_negativo \
    "Constraint com nome não-string (número)" \
    '[{"schema": "public", "tabela": "cases", "nome": 12345, "tipo": "p", "definicao": "PRIMARY KEY (id)"}]' \
    "${VALIDAR_CONSTRAINTS_ITENS}"

rodar_teste_negativo \
    "Função com inclui_corpo=true mas definicao ausente" \
    '[{"schema": "public", "nome": "calcular_honorarios", "identidade": "integer", "tipo_retorno": "numeric", "linguagem": "plpgsql", "inclui_corpo": true}]' \
    "${VALIDAR_FUNCOES_ITENS}"

rodar_teste_negativo \
    "Função com inclui_corpo não-booleano (string 'true')" \
    '[{"schema": "public", "nome": "calcular_honorarios", "identidade": "integer", "tipo_retorno": "numeric", "linguagem": "plpgsql", "inclui_corpo": "true", "definicao": "..."}]' \
    "${VALIDAR_FUNCOES_ITENS}"

say ""
say "================================================================================"
say " RESULTADO DOS TESTES NEGATIVOS:"
say "   Total de testes executados .: ${TOTAL_TESTES}"
say "   Rejeições corretas (OK) ....: ${TESTES_PASSARAM}"
say "   Falhas (aceitou inválido) ..: ${TESTES_FALHARAM}"
say "================================================================================"

if [ "${TESTES_FALHARAM}" -eq 0 ]; then
    say "🎉 TODOS OS TESTES NEGATIVOS PASSARAM COM SUCESSO (100% de rejeição esperada)."
    exit 0
else
    say "💥 FALHA NA SUÍTE DE TESTES NEGATIVOS (${TESTES_FALHARAM} falhas detectadas)." >&2
    exit 1
fi
