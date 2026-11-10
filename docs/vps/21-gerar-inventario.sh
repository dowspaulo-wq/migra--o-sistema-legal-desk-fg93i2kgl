#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur — Inventário Estrutural e de Contagens do Banco de Dados
# Script: docs/vps/21-gerar-inventario.sh
# Versão: v1.2.0
# Destino de execução: VPS Hostinger de Produção (SOMENTE LEITURA)
#
# OBJETIVO:
#   Extrair inventário estrutural e métricas de contagem do PostgreSQL de produção
#   em formato JSON com umask 077 + chmod 600, sem nunca extrair dados de linhas
#   (nenhum registro ou dado de cliente; apenas metadados e contagens numéricas).
#   O JSON resultante serve como base de comparação para a auditoria de restauração
#   em laboratório independente (executada por 20-auditar-backup.sh).
#
# POLÍTICA DE SEGURANÇA E PERFORMANCE:
#   1. ESTRITAMENTE LEITURA: executa apenas consultas em information_schema,
#      pg_catalog e SELECT count(*), sem LOCK agressivo, sem ALTER, sem GRANT/REVOKE,
#      sem DROP, sem INSERT/UPDATE/DELETE.
#   2. CONTAGEM PADRÃO LEVE: por padrão utiliza estimativas de reltuples de pg_class
#      (leitura instantânea de catálogo, zero varredura de tabela, custo computacional
#      desprezível).
#   3. CONTAGEM EXATA CONTROLADA:
#      - Exige a flag explícita --contagem-exata.
#      - O script alerta sobre o custo computacional de SELECT count(*) em tabelas grandes.
#      - PROTEÇÃO DE HORÁRIO DE EXPEDIENTE: Se executado em dias úteis entre 08:00 e
#        18:00 (horário de Brasília - UTC-3), o script RECUSA a varredura pesada
#        automática e aborta com exit 15, recomendando a execução fora do expediente.
#      - Para forçar em horário comercial, exige OBRIGATORIAMENTE a flag
#        adicional --forcar-horario-expediente.
#   4. ARQUIVOS RESTRITOS: umask 077 aplicado antes da criação de arquivos,
#      chmod 600 no JSON e no log, chmod 700 no diretório de saída.
#
# PARÂMETROS / FLAGS:
#   --saida <caminho.json>          Caminho do arquivo JSON de destino (padrão:
#                                   /root/sbjur-backups/inventarios/inventario-AAAAMMDD-HHMMSS.json)
#   --contagem-exata                Realiza SELECT count(*) exato por tabela.
#   --forcar-horario-expediente     Permite --contagem-exata mesmo entre 08:00 e 18:00 BSB.
#   --container <nome>              Nome do container de produção (opcional; restrito aos
#                                   candidatos autorizados: sbljur-local_supabase-db-1 ou
#                                   sbjur-local_supabase-db-1).
#   -h, --help                      Exibe esta ajuda.
# ==============================================================================

set -u -o pipefail
umask 077

SCRIPT_VERSION="v1.2.0"
TS_STAMP="$(date +%Y%m%d-%H%M%S)"
DEFAULT_OUTPUT_DIR="/root/sbjur-backups/inventarios"
DEFAULT_OUTPUT_FILE="${DEFAULT_OUTPUT_DIR}/inventario-${TS_STAMP}.json"
OUTPUT_FILE=""
EXACT_COUNT=0
FORCE_BUSINESS_HOURS=0
CUSTOM_CONTAINER=""

PROD_CONTAINER_CANDIDATES="sbljur-local_supabase-db-1 sbjur-local_supabase-db-1"
TARGET_CONTAINER=""

EXIT_OK=0
EXIT_USAGE=10
EXIT_DOCKER_UNAVAILABLE=11
EXIT_CONTAINER_NOT_FOUND=12
EXIT_DISALLOWED_TIME=15
EXIT_QUERY_FAILED=20

# Helpers de log e console
LOG_FILE=""

say() {
    printf '%s\n' "$*"
}

say_err() {
    printf '❌ %s\n' "$*" >&2
}

die() {
    local msg="$1" code="$2"
    say_err "${msg}"
    if [ -n "${LOG_FILE}" ] && [ -f "${LOG_FILE}" ]; then
        say "   Detalhes técnicos registrados em: ${LOG_FILE}" >&2
        printf '%s ABORTADO (exit %s): %s\n' "$(date '+%F %T')" "${code}" "${msg}" >> "${LOG_FILE}"
    fi
    exit "${code}"
}

log() {
    if [ -n "${LOG_FILE}" ]; then
        printf '%s %s\n' "$(date '+%F %T')" "$*" >> "${LOG_FILE}"
    fi
}

show_help() {
    cat <<EOF
Uso: bash $0 [OPÇÕES]

Opções:
  --saida <caminho>               Caminho do arquivo JSON de destino.
  --contagem-exata                Executa SELECT count(*) exato em cada tabela do schema public.
                                  (Por padrão, utiliza pg_class.reltuples para zero impacto)
  --forcar-horario-expediente     Permite --contagem-exata mesmo durante o expediente comercial (08:00 - 18:00 BSB).
  --container <nome>              Nome do contêiner Docker do PostgreSQL.
  -h, --help                      Mostra esta ajuda.

Exemplos:
  # Modo leve rápido (estimativas de catálogo):
  bash $0

  # Modo exato fora do expediente:
  bash $0 --contagem-exata

  # Modo exato forçado em horário de expediente (com cautela):
  bash $0 --contagem-exata --forcar-horario-expediente --saida /tmp/inventario.json
EOF
}

# Processamento de argumentos
while [ $# -gt 0 ]; do
    case "$1" in
        --saida)
            [ $# -ge 2 ] || die "Parâmetro --saida requer um caminho de arquivo." "${EXIT_USAGE}"
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --contagem-exata)
            EXACT_COUNT=1
            shift
            ;;
        --forcar-horario-expediente)
            FORCE_BUSINESS_HOURS=1
            shift
            ;;
        --container)
            [ $# -ge 2 ] || die "Parâmetro --container requer o nome do contêiner." "${EXIT_USAGE}"
            CUSTOM_CONTAINER="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit "${EXIT_OK}"
            ;;
        *)
            die "Opção desconhecida: $1 (consulte $0 --help)" "${EXIT_USAGE}"
            ;;
    esac
done

if [ -z "${OUTPUT_FILE}" ]; then
    OUTPUT_FILE="${DEFAULT_OUTPUT_FILE}"
fi

OUTPUT_DIR="$(dirname "${OUTPUT_FILE}")"
mkdir -p "${OUTPUT_DIR}" 2>/dev/null || true
chmod 700 "${OUTPUT_DIR}" 2>/dev/null || true

LOG_FILE="${OUTPUT_DIR}/inventario-${TS_STAMP}-$$.log"
touch "${LOG_FILE}" 2>/dev/null || die "Não foi possível criar o arquivo de log: ${LOG_FILE}" "${EXIT_QUERY_FAILED}"
chmod 600 "${LOG_FILE}" 2>/dev/null || true

log "Iniciando geração de inventário (${SCRIPT_VERSION}) - PID $$"
log "Destino do JSON: ${OUTPUT_FILE}"
log "Modo de contagem: $([ ${EXACT_COUNT} -eq 1 ] && echo 'EXATA (SELECT count(*))' || echo 'ESTIMADA (pg_class.reltuples)')"

# Verificação de segurança de horário de expediente para contagem exata
if [ "${EXACT_COUNT}" -eq 1 ]; then
    # Checar horário de Brasília (UTC-3)
    BSB_HOUR="$(TZ="America/Sao_Paulo" date +%H)"
    BSB_DAY="$(TZ="America/Sao_Paulo" date +%u)" # 1=segunda ... 7=domingo
    say "⚠️  ALERTA: A contagem exata (--contagem-exata) executa SELECT count(*) em todas as tabelas públicas."
    say "   Isto consome I/O e CPU do banco de produção."

    # Expediente comercial: segunda a sexta (1 a 5), das 08:00 às 17:59 (hora 08 a 17)
    if [ "${BSB_DAY}" -ge 1 ] && [ "${BSB_DAY}" -le 5 ] && [ "${BSB_HOUR}" -ge 8 ] && [ "${BSB_HOUR}" -lt 18 ]; then
        if [ "${FORCE_BUSINESS_HOURS}" -ne 1 ]; then
            log "RECUSA: tentativa de contagem exata durante expediente (Hora BSB: ${BSB_HOUR}, Dia: ${BSB_DAY}) sem --forcar-horario-expediente."
            say_err "EXECUÇÃO RECUSADA POR SEGURANÇA OPERACIONAL!"
            say_err "Horário atual de Brasília: ${BSB_HOUR}h (dentro do expediente comercial de 08:00 às 18:00, seg-sex)."
            say_err "Varreduras pesadas com SELECT count(*) não devem rodar automaticamente durante o expediente."
            say_err "Recomenda-se executar fora do horário de expediente ou usar o modo padrão (estimativas leves)."
            say_err "Para forçar conscientemente neste horário, adicione a flag: --forcar-horario-expediente"
            exit "${EXIT_DISALLOWED_TIME}"
        else
            say "⚠️  ATENÇÃO: Flag --forcar-horario-expediente informada. Prosseguindo com contagem exata em horário de expediente por autorização explícita."
            log "Contagem exata forçada em horário de expediente pelo operador."
        fi
    else
        say "ℹ️  Horário verificado: fora do expediente comercial de Brasília. Prosseguindo com contagem exata."
    fi
fi

# Checagem de disponibilidade do Docker
if ! command -v docker >/dev/null 2>&1; then
    die "Docker não encontrado no PATH do sistema." "${EXIT_DOCKER_UNAVAILABLE}"
fi
if ! docker info >>"${LOG_FILE}" 2>&1; then
    die "Docker inacessível ou sem permissão de execução." "${EXIT_DOCKER_UNAVAILABLE}"
fi

# Localização estrita do contêiner de produção
find_prod_container() {
    local c count_found=0 found_list=""

    if [ -n "${CUSTOM_CONTAINER}" ]; then
        if [ "${CUSTOM_CONTAINER}" = "dpsjur-db" ]; then
            die "O contêiner 'dpsjur-db' está explicitamente fora de escopo deste procedimento." "${EXIT_CONTAINER_NOT_FOUND}"
        fi
        local valid=0
        for c in ${PROD_CONTAINER_CANDIDATES}; do
            if [ "${c}" = "${CUSTOM_CONTAINER}" ]; then
                valid=1
                break
            fi
        done
        if [ "${valid}" -ne 1 ]; then
            die "Contêiner '${CUSTOM_CONTAINER}' não é um candidato autorizado (${PROD_CONTAINER_CANDIDATES})." "${EXIT_CONTAINER_NOT_FOUND}"
        fi
        if docker ps --format '{{.Names}}' 2>>"${LOG_FILE}" | grep -qx -- "${CUSTOM_CONTAINER}"; then
            TARGET_CONTAINER="${CUSTOM_CONTAINER}"
            return
        else
            die "Contêiner informado '${CUSTOM_CONTAINER}' não está em execução." "${EXIT_CONTAINER_NOT_FOUND}"
        fi
    fi

    for c in ${PROD_CONTAINER_CANDIDATES}; do
        if docker ps --format '{{.Names}}' 2>>"${LOG_FILE}" | grep -qx -- "${c}"; then
            found_list="${found_list} ${c}"
            count_found=$((count_found + 1))
        fi
    done

    if [ "${count_found}" -eq 1 ]; then
        TARGET_CONTAINER="$(echo "${found_list}" | awk '{print $1}')"
        return
    elif [ "${count_found}" -gt 1 ]; then
        die "Múltiplos contêineres candidatos em execução (${found_list# }). Especifique via --container <nome>." "${EXIT_CONTAINER_NOT_FOUND}"
    fi

    die "Nenhum contêiner candidato autorizado (${PROD_CONTAINER_CANDIDATES}) foi localizado em execução." "${EXIT_CONTAINER_NOT_FOUND}"
}

find_prod_container
say "🔍 Contêiner identificado para inventário: ${TARGET_CONTAINER}"
log "Contêiner alvo: ${TARGET_CONTAINER}"

# Execução segura de consulta SQL só-leitura
exec_psql_json() {
    local query="$1"
    local out rc
    if command -v timeout >/dev/null 2>&1; then
        out="$(timeout 60 docker exec "${TARGET_CONTAINER}" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -t -A -c "${query}" 2>>"${LOG_FILE}")"
        rc=$?
    else
        out="$(docker exec "${TARGET_CONTAINER}" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -t -A -c "${query}" 2>>"${LOG_FILE}")"
        rc=$?
    fi
    if [ "${rc}" -ne 0 ]; then
        log "FALHA na consulta exec_psql_json (exit ${rc}): ${query}"
        return "${rc}"
    fi
    printf '%s\n' "${out}"
}

exec_psql_raw() {
    local query="$1"
    local out rc
    if command -v timeout >/dev/null 2>&1; then
        out="$(timeout 60 docker exec "${TARGET_CONTAINER}" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -t -A -F '|' -c "${query}" 2>>"${LOG_FILE}")"
        rc=$?
    else
        out="$(docker exec "${TARGET_CONTAINER}" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -t -A -F '|' -c "${query}" 2>>"${LOG_FILE}")"
        rc=$?
    fi
    if [ "${rc}" -ne 0 ]; then
        log "FALHA na consulta exec_psql_raw (exit ${rc}): ${query}"
        return "${rc}"
    fi
    printf '%s\n' "${out}"
}

say "📋 Coletando metadados de catálogo (esquemas, tabelas, constraints, funções, triggers, extensões, roles)..."

# 1. Metadados do servidor
if ! PG_VERSION="$(exec_psql_raw "SELECT version()")"; then
    die "Falha ao consultar versão detalhada do PostgreSQL no contêiner." "${EXIT_QUERY_FAILED}"
fi
PG_VERSION="$(printf '%s\n' "${PG_VERSION}" | head -n 1)"

if ! PG_MAJOR_RAW="$(exec_psql_raw "SHOW server_version")"; then
    die "Falha ao consultar server_version do PostgreSQL no contêiner." "${EXIT_QUERY_FAILED}"
fi
PG_MAJOR="$(printf '%s\n' "${PG_MAJOR_RAW}" | head -n 1 | awk -F. '{print $1}' | tr -d '[:space:]')"

if ! DB_NAME_RAW="$(exec_psql_raw "SELECT current_database()")"; then
    die "Falha ao consultar current_database no contêiner." "${EXIT_QUERY_FAILED}"
fi
DB_NAME="$(printf '%s\n' "${DB_NAME_RAW}" | head -n 1 | tr -d '[:space:]')"

if [ -z "${PG_MAJOR}" ]; then
    die "Falha ao extrair versão do PostgreSQL no contêiner." "${EXIT_QUERY_FAILED}"
fi

# 2. Esquemas visíveis
if ! SCHEMAS_JSON="$(exec_psql_json "
SELECT COALESCE(json_agg(nspname ORDER BY nspname), '[]'::json)
FROM pg_namespace
WHERE nspname NOT LIKE 'pg\_%' AND nspname <> 'information_schema';
")" || [ -z "${SCHEMAS_JSON}" ]; then
    die "Falha ao consultar esquemas do banco no contêiner." "${EXIT_QUERY_FAILED}"
fi

# 3. Extensões instaladas
if ! EXTENSIONS_JSON="$(exec_psql_json "
SELECT COALESCE(json_agg(json_build_object(
    'nome', extname,
    'versao', extversion,
    'schema', nspname
) ORDER BY extname), '[]'::json)
FROM pg_extension e
JOIN pg_namespace n ON n.oid = e.extnamespace;
")" || [ -z "${EXTENSIONS_JSON}" ]; then
    die "Falha ao consultar extensões do banco no contêiner." "${EXIT_QUERY_FAILED}"
fi

# 4. Roles visíveis (apenas nomes e privilégios de atributos de catálogo, sem senhas/hashes)
if ! ROLES_JSON="$(exec_psql_json "
SELECT COALESCE(json_agg(json_build_object(
    'nome', rolname,
    'superusuario', rolsuper,
    'heranca', rolinherit,
    'criar_role', rolcreaterole,
    'criar_db', rolcreatedb,
    'pode_login', rolcanlogin,
    'conexao_limite', rolconnlimit
) ORDER BY rolname), '[]'::json)
FROM pg_roles
WHERE rolname NOT LIKE 'pg\_%';
")" || [ -z "${ROLES_JSON}" ]; then
    die "Falha ao consultar roles no contêiner." "${EXIT_QUERY_FAILED}"
fi

# 5. Constraints / Foreign Keys
if ! CONSTRAINTS_JSON="$(exec_psql_json "
SELECT COALESCE(json_agg(json_build_object(
    'schema', constraint_schema,
    'tabela', table_name,
    'nome', constraint_name,
    'tipo', constraint_type
) ORDER BY constraint_schema, table_name, constraint_name), '[]'::json)
FROM information_schema.table_constraints
WHERE constraint_schema NOT LIKE 'pg\_%' AND constraint_schema <> 'information_schema';
")" || [ -z "${CONSTRAINTS_JSON}" ]; then
    die "Falha ao consultar constraints no contêiner." "${EXIT_QUERY_FAILED}"
fi

# 6. Funções (apenas catálogo: schema, nome, linguagem)
if ! FUNCTIONS_JSON="$(exec_psql_json "
SELECT COALESCE(json_agg(json_build_object(
    'schema', n.nspname,
    'nome', p.proname,
    'linguagem', l.lanname
) ORDER BY n.nspname, p.proname), '[]'::json)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
JOIN pg_language l ON l.oid = p.prolang
WHERE n.nspname NOT LIKE 'pg\_%' AND n.nspname <> 'information_schema';
")" || [ -z "${FUNCTIONS_JSON}" ]; then
    die "Falha ao consultar funções no contêiner." "${EXIT_QUERY_FAILED}"
fi

# 7. Triggers
if ! TRIGGERS_JSON="$(exec_psql_json "
SELECT COALESCE(json_agg(json_build_object(
    'schema', trigger_schema,
    'tabela', event_object_table,
    'nome', trigger_name,
    'evento', event_manipulation,
    'momento', action_timing
) ORDER BY trigger_schema, event_object_table, trigger_name), '[]'::json)
FROM information_schema.triggers
WHERE trigger_schema NOT LIKE 'pg\_%' AND trigger_schema <> 'information_schema';
")" || [ -z "${TRIGGERS_JSON}" ]; then
    die "Falha ao consultar triggers no contêiner." "${EXIT_QUERY_FAILED}"
fi

# 8. Tabelas e Contagens
TABLES_JSON=""
if [ "${EXACT_COUNT}" -eq 1 ]; then
    say "🔢 Calculando contagens exatas por tabela via SELECT count(*)..."
    # Obter lista de tabelas públicas
    if ! TAB_LIST="$(exec_psql_raw "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename")"; then
        die "Falha ao listar tabelas do schema public para contagem exata." "${EXIT_QUERY_FAILED}"
    fi
    TAB_ENTRIES=""
    TOTAL_RECORDS=0
    TOTAL_TABLES=0

    while IFS= read -r t; do
        [ -n "${t}" ] || continue
        TOTAL_TABLES=$((TOTAL_TABLES + 1))
        cnt_raw="$(exec_psql_raw "SELECT count(*) FROM public.\"${t}\"")" || die "Falha ao executar SELECT count(*) na tabela public.\"${t}\"." "${EXIT_QUERY_FAILED}"
        cnt="$(printf '%s\n' "${cnt_raw}" | tr -d '[:space:]')"
        case "${cnt}" in
            ''|*[!0-9]*)
                die "Resultado inválido de contagem na tabela public.\"${t}\": '${cnt}'." "${EXIT_QUERY_FAILED}"
                ;;
        esac
        TOTAL_RECORDS=$((TOTAL_RECORDS + cnt))
        
        entry="$(printf '{"schema":"public","tabela":"%s","contagem":%s,"tipo_contagem":"exata"}' "${t}" "${cnt}")"
        if [ -z "${TAB_ENTRIES}" ]; then
            TAB_ENTRIES="${entry}"
        else
            TAB_ENTRIES="${TAB_ENTRIES},${entry}"
        fi
    done <<< "${TAB_LIST}"

    # auth.users como referência padrão do ecossistema Supabase
    auth_cnt_raw="$(exec_psql_raw "SELECT count(*) FROM auth.users")" || die "Falha ao executar SELECT count(*) na tabela auth.users." "${EXIT_QUERY_FAILED}"
    auth_cnt="$(printf '%s\n' "${auth_cnt_raw}" | tr -d '[:space:]')"
    case "${auth_cnt}" in
        ''|*[!0-9]*)
            die "Resultado inválido de contagem em auth.users: '${auth_cnt}'." "${EXIT_QUERY_FAILED}"
            ;;
    esac
    entry_auth="$(printf '{"schema":"auth","tabela":"users","contagem":%s,"tipo_contagem":"exata"}' "${auth_cnt}")"
    if [ -n "${TAB_ENTRIES}" ]; then
        TAB_ENTRIES="${TAB_ENTRIES},${entry_auth}"
    else
        TAB_ENTRIES="${entry_auth}"
    fi

    TABLES_JSON="[${TAB_ENTRIES}]"
    METODO_CONTAGEM="exata"
else
    say "⚡ Obtendo contagens estimadas leves via pg_class.reltuples..."
    if ! TABLES_JSON="$(exec_psql_json "
    SELECT COALESCE(json_agg(json_build_object(
        'schema', n.nspname,
        'tabela', c.relname,
        'contagem', CASE WHEN c.reltuples < 0 THEN 0 ELSE round(c.reltuples)::bigint END,
        'tipo_contagem', 'estimada_reltuples'
    ) ORDER BY n.nspname, c.relname), '[]'::json)
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r'
      AND n.nspname = 'public';
    ")" || [ -z "${TABLES_JSON}" ]; then
        die "Falha ao consultar contagens estimadas de tabelas públicas via reltuples." "${EXIT_QUERY_FAILED}"
    fi

    # Adicionar estimativa de auth.users
    if ! auth_est="$(exec_psql_json "
    SELECT COALESCE(json_build_object(
        'schema', 'auth',
        'tabela', 'users',
        'contagem', CASE WHEN c.reltuples < 0 THEN 0 ELSE round(c.reltuples)::bigint END,
        'tipo_contagem', 'estimada_reltuples'
    ), '{}'::json)
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r' AND n.nspname = 'auth' AND c.relname = 'users';
    ")"; then
        die "Falha ao consultar contagem estimada de auth.users via reltuples." "${EXIT_QUERY_FAILED}"
    fi

    if [ -n "${auth_est}" ] && [ "${auth_est}" != "{}" ]; then
        # Combinar com o array
        TABLES_JSON="$(echo "${TABLES_JSON}" | sed -E "s/\]$/ , ${auth_est} \]/")"
    fi
    METODO_CONTAGEM="estimada_reltuples"
fi

# Contagens de sumário — separação estrita entre public e auth
TOTAL_TABLES_PUBLIC_COUNT="$(printf '%s\n' "${TABLES_JSON}" | grep -o '"schema":"public"' | wc -l | tr -d '[:space:]')"
TOTAL_TABLES_AUTH_COUNT="$(printf '%s\n' "${TABLES_JSON}" | grep -o '"schema":"auth"' | wc -l | tr -d '[:space:]')"
TOTAL_TABLES_ALL_COUNT="$(printf '%s\n' "${TABLES_JSON}" | grep -o '"tabela":' | wc -l | tr -d '[:space:]')"

TOTAL_CONSTRAINTS_COUNT="$(printf '%s\n' "${CONSTRAINTS_JSON}" | grep -o '"nome":' | wc -l | tr -d '[:space:]')"
TOTAL_FUNCTIONS_COUNT="$(printf '%s\n' "${FUNCTIONS_JSON}" | grep -o '"nome":' | wc -l | tr -d '[:space:]')"
TOTAL_TRIGGERS_COUNT="$(printf '%s\n' "${TRIGGERS_JSON}" | grep -o '"nome":' | wc -l | tr -d '[:space:]')"
TOTAL_EXTENSIONS_COUNT="$(printf '%s\n' "${EXTENSIONS_JSON}" | grep -o '"nome":' | wc -l | tr -d '[:space:]')"
TOTAL_ROLES_COUNT="$(printf '%s\n' "${ROLES_JSON}" | grep -o '"nome":' | wc -l | tr -d '[:space:]')"

# Montagem do arquivo JSON estruturado final
say "💾 Gravando arquivo JSON de inventário restrito..."

cat <<EOF > "${OUTPUT_FILE}"
{
  "versao_gerador": "${SCRIPT_VERSION}",
  "timestamp_geracao": "${TS_STAMP}",
  "data_geracao_iso": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "ambiente_origem": {
    "tipo": "vps_producao",
    "container": "${TARGET_CONTAINER}",
    "database": "${DB_NAME}",
    "postgres_major": "${PG_MAJOR}",
    "postgres_versao_completa": "${PG_VERSION}"
  },
  "politica_seguranca": {
    "dados_de_clientes_incluidos": false,
    "tipo_conteudo": "metadados_e_contagens_apenas",
    "metodo_contagem": "${METODO_CONTAGEM}",
    "umask": "077",
    "permissao_arquivo": "0600"
  },
  "sumario": {
    "total_tabelas": ${TOTAL_TABLES_PUBLIC_COUNT},
    "total_tabelas_public": ${TOTAL_TABLES_PUBLIC_COUNT},
    "total_tabelas_auth": ${TOTAL_TABLES_AUTH_COUNT},
    "total_tabelas_todas": ${TOTAL_TABLES_ALL_COUNT},
    "total_constraints": ${TOTAL_CONSTRAINTS_COUNT},
    "total_funcoes": ${TOTAL_FUNCTIONS_COUNT},
    "total_triggers": ${TOTAL_TRIGGERS_COUNT},
    "total_extensoes": ${TOTAL_EXTENSIONS_COUNT},
    "total_roles": ${TOTAL_ROLES_COUNT}
  },
  "esquemas": ${SCHEMAS_JSON},
  "extensoes": ${EXTENSIONS_JSON},
  "roles": ${ROLES_JSON},
  "constraints": ${CONSTRAINTS_JSON},
  "funcoes": ${FUNCTIONS_JSON},
  "triggers": ${TRIGGERS_JSON},
  "tabelas": ${TABLES_JSON}
}
EOF

chmod 600 "${OUTPUT_FILE}" 2>/dev/null || true

# Validação do JSON gerado
if command -v jq >/dev/null 2>&1; then
    if ! jq empty "${OUTPUT_FILE}" >/dev/null 2>&1; then
        say_err "ERRO CRÍTICO: Validação sintática do JSON com 'jq' falhou. Arquivo inválido: ${OUTPUT_FILE}."
        log "ERRO: Sintaxe JSON inválida detectada por jq."
        die "Arquivo JSON de inventário gerado com erro sintático." "${EXIT_QUERY_FAILED}"
    else
        log "JSON validado com sucesso via jq."
    fi
fi

say ""
say "================================================================================"
say " INVENTÁRIO DO BANCO DE DADOS GERADO COM SUCESSO"
say "================================================================================"
say " Arquivo JSON gerado ..: ${OUTPUT_FILE} (chmod 600)"
say " Contêiner auditado ...: ${TARGET_CONTAINER}"
say " PostgreSQL Major .....: ${PG_MAJOR}"
say " Método de contagem ...: ${METODO_CONTAGEM}"
say " Total tabelas public .: ${TOTAL_TABLES_PUBLIC_COUNT}"
say " Total tabelas auth ...: ${TOTAL_TABLES_AUTH_COUNT}"
say " Total de constraints .: ${TOTAL_CONSTRAINTS_COUNT}"
say " Total de funções .....: ${TOTAL_FUNCTIONS_COUNT}"
say " Total de triggers ....: ${TOTAL_TRIGGERS_COUNT}"
say " Total de extensões ...: ${TOTAL_EXTENSIONS_COUNT}"
say " Total de roles .......: ${TOTAL_ROLES_COUNT}"
say " Log de execução ......: ${LOG_FILE} (chmod 600)"
say "================================================================================"
say " Para auditar no laboratório isolado, copie este JSON para a máquina de teste"
say " e execute: bash docs/vps/20-auditar-backup.sh --inventario <caminho.json>"
say "================================================================================"

exit "${EXIT_OK}"
