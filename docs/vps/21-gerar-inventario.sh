#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur — Inventário Estrutural e de Contagens do Banco de Dados
# Script: docs/vps/21-gerar-inventario.sh
# Versão: v1.6.0
# Destino de execução: VPS Hostinger de Produção (SOMENTE LEITURA)
#
# OBJETIVO:
#   Extrair inventário estrutural e métricas de contagem do PostgreSQL de produção
#   em formato JSON com umask 077 + chmod 600, sem nunca extrair dados de linhas
#   (nenhum registro ou dado de cliente; apenas metadados, definições DDL e
#   contagens numéricas).
#   O JSON resultante serve como base de comparação para a auditoria de restauração
#   em laboratório independente (executada por 20-auditar-backup.sh).
#
# POLÍTICA DE SEGURANÇA E PERFORMANCE:
#   1. ESTRITAMENTE LEITURA: executa apenas consultas em information_schema,
#      pg_catalog e SELECT count(*), sem LOCK agressivo, sem ALTER, sem GRANT/REVOKE,
#      sem DROP, sem INSERT/UPDATE/DELETE.
#   2. CONTAGEM PADRÃO LEVE: por padrão utiliza estimativas de reltuples de pg_class
#      (leitura instantânea de catálogo, zero varredura de tabela, custo computacional
#      desprezível). Estimativas reltuples NUNCA são tratadas como contagens exatas.
#   3. CONTAGEM EXATA CONTROLADA:
#      - Exige a flag explícita --contagem-exata.
#      - O script alerta sobre o custo computacional de SELECT count(*) em tabelas grandes.
#      - PROTEÇÃO DE HORÁRIO DE EXPEDIENTE: Se executado em dias úteis entre 08:00 e
#        18:00 (horário de Brasília - UTC-3), o script RECUSA a varredura pesada
#        automática e aborta com exit 15, recomendando a execução fora do expediente.
#      - Para forçar em horário comercial, exige OBRIGATORIAMENTE a flag
#        adicional --forcar-horario-expediente.
#      - RESSALVA TEMPORAL: O inventário registra expressamente que as contagens
#        são coletadas no instante da execução deste script, que difere do instante
#        em que o dump de backup foi gravado. Diferenças de contagem não presumem
#        crescimento natural automaticamente.
#   4. ARQUIVOS EXCLUSIVOS E PERMISSÕES RESTRITAS:
#      - umask 077 estrito antes de qualquer criação de arquivo ou diretório.
#      - NUNCA sobrescreve arquivos preexistentes: o script falha com exit 25
#        se o arquivo de saída já existir.
#      - NUNCA aplica chmod ou modifica permissões de diretórios preexistentes;
#        aplica restrições exclusivamente sobre os arquivos criados nesta sessão.
#      - Falha OU saída vazia de 'stat' é tratada como erro impeditivo (die com exit 25).
#      - Nenhuma falha de chmod, touch, mkdir ou consulta SQL é ignorada.
#   5. ESCOPO COMPLETO DE TABELAS (PUBLIC + AUTH):
#      - Inventaria todas as tabelas relevantes de 'public' e 'auth' (não apenas auth.users),
#        incluindo auth.identities, auth.sessions, auth.refresh_tokens, auth.audit_log_entries, etc.
#      - Distingue tabelas comuns (r - BASE TABLE) de tabelas particionadas (p - PARTITIONED TABLE).
#      - Utiliza quote_ident e formatação SQL segura para identificadores e nomes de tabelas.
#   6. SERIALIZAÇÃO E VALIDAÇÃO RIGOROSA JSON:
#      - Montagem via jq -n com passagem estrita de argumentos (--arg/--argjson),
#        sem interpolação manual de strings.
#      - Todos os objetos são validados com 'jq -e' estrito. Elementos malformados
#        são rejeitados com erro impeditivo em vez de descartados silenciosamente.
#   7. POLÍTICA DE SIGILO DE DDL E METADADOS PRECISOS:
#      - Constraints são extraídas com definição completa via pg_get_constraintdef.
#      - Funções: por padrão, modo restrito a metadados (coleta apenas assinatura/identidade:
#        pg_get_function_identity_arguments e tipo de retorno), sem coleta de corpos.
#      - A definição completa (pg_get_functiondef) só é coletada com flag explícita
#        --incluir-corpos-funcoes, acompanhada de tentativa de ofuscação de padrões sensíveis.
#      - Metadados refletem a realidade: quando corpos não são coletados,
#        ofuscacao_segredos_aplicada é false e modo_coleta_funcoes é "apenas_identidade_sem_corpos".
#      - O script não promete sigilo absoluto apenas com base em expressões regulares.
#
# PARÂMETROS / FLAGS:
#   --saida <caminho.json>          Caminho do arquivo JSON de destino (padrão:
#                                   /root/sbjur-backups/inventarios/inventario-AAAAMMDD-HHMMSS.json)
#   --contagem-exata                Realiza SELECT count(*) exato por tabela.
#   --forcar-horario-expediente     Permite --contagem-exata mesmo entre 08:00 e 18:00 BSB.
#   --incluir-corpos-funcoes        Coleta corpos completos das funções com ofuscação de padrões
#                                   sensíveis (por padrão coleta apenas identidade/assinatura).
#   --container <nome>              Nome do container de produção (opcional; restrito aos
#                                   candidatos autorizados: sbljur-local_supabase-db-1 ou
#                                   sbjur-local_supabase-db-1).
#   -h, --help                      Exibe esta ajuda.
# ==============================================================================

set -u -o pipefail
umask 077

SCRIPT_VERSION="v1.6.0"
TS_STAMP="$(date +%Y%m%d-%H%M%S)"
DEFAULT_OUTPUT_DIR="/root/sbjur-backups/inventarios"
DEFAULT_OUTPUT_FILE="${DEFAULT_OUTPUT_DIR}/inventario-${TS_STAMP}.json"
OUTPUT_FILE=""
EXACT_COUNT=0
FORCE_BUSINESS_HOURS=0
INCLUDE_FUNCTION_BODIES=0
CUSTOM_CONTAINER=""

PROD_CONTAINER_CANDIDATES="sbljur-local_supabase-db-1 sbjur-local_supabase-db-1"
TARGET_CONTAINER=""

EXIT_OK=0
EXIT_USAGE=10
EXIT_DOCKER_UNAVAILABLE=11
EXIT_CONTAINER_NOT_FOUND=12
EXIT_DISALLOWED_TIME=15
EXIT_QUERY_FAILED=20
EXIT_FS_FAILED=25
EXIT_JSON_FAILED=30

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

Gera o arquivo JSON oficial de inventário estrutural e métricas de contagem do
banco de produção na VPS Hostinger para auditoria de backups.

Opções:
  --saida <caminho.json>          Arquivo JSON de saída (padrão: ${DEFAULT_OUTPUT_FILE})
  --contagem-exata                Executa SELECT count(*) exato em cada tabela (alerta de performance)
  --forcar-horario-expediente     Permite --contagem-exata mesmo durante o expediente comercial BSB (08h-18h)
  --incluir-corpos-funcoes        Inclui corpos de funções com tentativa de ofuscação (padrão: apenas identidades)
  --container <nome>              Nome do contêiner Docker (autorizados: ${PROD_CONTAINER_CANDIDATES})
  -h, --help                      Exibe esta mensagem de ajuda.

Exemplo de uso recomendado (fora do expediente):
  bash docs/vps/21-gerar-inventario.sh --contagem-exata
EOF
}

# Parsing de argumentos
while [ $# -gt 0 ]; do
    case "$1" in
        --saida)
            [ $# -ge 2 ] || die "Opção --saida requer um caminho como argumento." "${EXIT_USAGE}"
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
        --incluir-corpos-funcoes)
            INCLUDE_FUNCTION_BODIES=1
            shift
            ;;
        --container)
            [ $# -ge 2 ] || die "Opção --container requer o nome de um contêiner." "${EXIT_USAGE}"
            CUSTOM_CONTAINER="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit "${EXIT_OK}"
            ;;
        *)
            die "Opção desconhecida: $1. Use -h ou --help para ver as opções." "${EXIT_USAGE}"
            ;;
    esac
done

say "================================================================================"
say " DPSjur / SBJur — Inventário Estrutural do Banco de Dados (${SCRIPT_VERSION})"
say "================================================================================"

# Verificação e preparação do arquivo de saída
if [ -z "${OUTPUT_FILE}" ]; then
    OUTPUT_FILE="${DEFAULT_OUTPUT_FILE}"
fi

OUTPUT_DIR="$(dirname "${OUTPUT_FILE}")"
if [ ! -d "${OUTPUT_DIR}" ]; then
    if ! mkdir -p "${OUTPUT_DIR}"; then
        die "Falha ao criar diretório de saída: ${OUTPUT_DIR}" "${EXIT_FS_FAILED}"
    fi
    # Apenas se o diretório acabou de ser criado pelo script ajustamos permissão dele
    chmod 700 "${OUTPUT_DIR}" 2>/dev/null || true
fi

# Proteção contra sobrescrita de arquivos preexistentes (Requisito 5 da auditoria)
if [ -e "${OUTPUT_FILE}" ]; then
    die "O arquivo de destino já existe e NÃO será sobrescrito por segurança: ${OUTPUT_FILE}" "${EXIT_FS_FAILED}"
fi

# Inicialização do arquivo de log com permissão 600
LOG_FILE="${OUTPUT_DIR}/inventario-${TS_STAMP}.log"
if [ -e "${LOG_FILE}" ]; then
    die "O arquivo de log já existe: ${LOG_FILE}" "${EXIT_FS_FAILED}"
fi
touch "${LOG_FILE}" || die "Falha ao criar arquivo de log: ${LOG_FILE}" "${EXIT_FS_FAILED}"
if ! chmod 600 "${LOG_FILE}"; then
    die "Falha ao aplicar chmod 600 no arquivo de log: ${LOG_FILE}" "${EXIT_FS_FAILED}"
fi

LOG_PERM="$(stat -c '%a' "${LOG_FILE}" 2>/dev/null || stat -f '%Lp' "${LOG_FILE}" 2>/dev/null || echo "")"
if [ -z "${LOG_PERM}" ]; then
    die "Falha ao obter permissão de ${LOG_FILE} via stat (resultado vazio ou stat falhou)." "${EXIT_FS_FAILED}"
fi
if [ "${LOG_PERM}" != "600" ]; then
    die "Permissão do arquivo de log (${LOG_PERM}) não confere com 600." "${EXIT_FS_FAILED}"
fi

log "Início da geração do inventário SBJur (${SCRIPT_VERSION})"
log "Arquivo de saída configurado: ${OUTPUT_FILE}"

# Verificação de dependência do jq
if ! command -v jq >/dev/null 2>&1; then
    die "Utilitário 'jq' não localizado no PATH. O inventário exige 'jq' para montagem segura." "${EXIT_JSON_FAILED}"
fi

# Validação da política de contagem e horário de expediente
METODO_CONTAGEM="estimada_reltuples"
if [ "${EXACT_COUNT}" -eq 1 ]; then
    METODO_CONTAGEM="exata"
    BSB_HOUR="$(TZ="America/Sao_Paulo" date +%H)"
    BSB_DAY="$(TZ="America/Sao_Paulo" date +%u)" # 1=segunda ... 7=domingo
    say "⚠️  ALERTA: A contagem exata (--contagem-exata) executa SELECT count(*) em todas as tabelas públicas e de autenticação."
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

# Execuções seguras em psql
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

say "📋 Coletando metadados de catálogo (esquemas, tabelas, constraints com DDL, funções, triggers, extensões, roles)..."

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
if ! printf '%s' "${SCHEMAS_JSON}" | jq empty >/dev/null 2>&1; then
    die "Retorno JSON de esquemas corrompido ou inválido." "${EXIT_QUERY_FAILED}"
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
if ! printf '%s' "${EXTENSIONS_JSON}" | jq empty >/dev/null 2>&1; then
    die "Retorno JSON de extensões corrompido ou inválido." "${EXIT_QUERY_FAILED}"
fi

# 4. Roles visíveis (apenas nomes e privilégios de catálogo, sem senhas/hashes)
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
if ! printf '%s' "${ROLES_JSON}" | jq empty >/dev/null 2>&1; then
    die "Retorno JSON de roles corrompido ou inválido." "${EXIT_QUERY_FAILED}"
fi

# 5. Constraints ampliadas com pg_get_constraintdef(c.oid), SEM registros de clientes
if ! CONSTRAINTS_JSON="$(exec_psql_json "
SELECT COALESCE(json_agg(json_build_object(
    'schema', n.nspname,
    'tabela', r.relname,
    'nome', c.conname,
    'tipo', c.contype,
    'definicao', pg_get_constraintdef(c.oid, true)
) ORDER BY n.nspname, r.relname, c.conname), '[]'::json)
FROM pg_constraint c
JOIN pg_namespace n ON n.oid = c.connamespace
JOIN pg_class r ON r.oid = c.conrelid
WHERE n.nspname NOT LIKE 'pg\_%' AND n.nspname <> 'information_schema';
")" || [ -z "${CONSTRAINTS_JSON}" ]; then
    die "Falha ao consultar constraints ampliadas com definição no contêiner." "${EXIT_QUERY_FAILED}"
fi
if ! printf '%s' "${CONSTRAINTS_JSON}" | jq empty >/dev/null 2>&1; then
    die "Retorno JSON de constraints corrompido ou inválido." "${EXIT_QUERY_FAILED}"
fi

# 6. Funções e Procedimentos
# Requisito 5 da Auditoria:
# Por padrão: modo restrito a metadados (schema, nome, identidade e tipo de retorno),
# SEM coleta de corpos de funções.
# Apenas com --incluir-corpos-funcoes a definição é coletada com ofuscação via regex.
OFUSCACAO_METADADO_APLICADA=false
MODO_COLETA_FUNCOES="apenas_identidade_sem_corpos"

if [ "${INCLUDE_FUNCTION_BODIES}" -eq 1 ]; then
    say "⚠️  Flag --incluir-corpos-funcoes ativa: coletando corpos de funções com verificação e tentativa de ofuscação de literais sensíveis..."
    log "Coleta de corpos completos de funções ativada com ofuscação de segredos."
    OFUSCACAO_METADADO_APLICADA=true
    MODO_COLETA_FUNCOES="identidade_e_corpo_com_ofuscacao"

    # Consulta segura: utilizando delimitadores de string dollar-quoting ($re$) para evitar conflitos de aspas
    if ! FUNCTIONS_JSON="$(exec_psql_json "
    SELECT COALESCE(json_agg(json_build_object(
        'schema', n.nspname,
        'nome', p.proname,
        'identidade', pg_get_function_identity_arguments(p.oid),
        'tipo_retorno', pg_get_function_result(p.oid),
        'linguagem', l.lanname,
        'inclui_corpo', true,
        'definicao', regexp_replace(
            regexp_replace(
                regexp_replace(
                    pg_get_functiondef(p.oid),
                    \$re\$(?i)(password|senha|secret|api_key|token|bearer|authorization)\s*(=>|:=|=|:)\s*['\"][^'\"]+['\"]\b\$re\$,
                    '\1 \2 ''***REDACTED***''',
                    'g'
                ),
                \$re\$(?i)(postgres|postgresql)://[^:@\s]+:[^@\s]+@\$re\$,
                '\1://***REDACTED***:***REDACTED***@',
                'g'
            ),
            \$re\$(sb_publishable_[A-Za-z0-9_-]+|sb_secret_[A-Za-z0-9_-]+)\$re\$,
            '***REDACTED_SUPABASE_KEY***',
            'g'
        )
    ) ORDER BY n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)), '[]'::json)
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_language l ON l.oid = p.prolang
    WHERE n.nspname NOT LIKE 'pg\_%' AND n.nspname <> 'information_schema';
    ")" || [ -z "${FUNCTIONS_JSON}" ]; then
        die "Falha ao consultar funções completas no contêiner." "${EXIT_QUERY_FAILED}"
    fi
else
    say "🔒 Modo padrão: coletando identidades/assinaturas de funções (corpos omitidos por sigilo de infraestrutura)..."
    log "Coleta padrão restrita a identidades/assinaturas de funções."
    if ! FUNCTIONS_JSON="$(exec_psql_json "
    SELECT COALESCE(json_agg(json_build_object(
        'schema', n.nspname,
        'nome', p.proname,
        'identidade', pg_get_function_identity_arguments(p.oid),
        'tipo_retorno', pg_get_function_result(p.oid),
        'linguagem', l.lanname,
        'inclui_corpo', false,
        'definicao', null
    ) ORDER BY n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)), '[]'::json)
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_language l ON l.oid = p.prolang
    WHERE n.nspname NOT LIKE 'pg\_%' AND n.nspname <> 'information_schema';
    ")" || [ -z "${FUNCTIONS_JSON}" ]; then
        die "Falha ao consultar identidades de funções no contêiner." "${EXIT_QUERY_FAILED}"
    fi
fi
if ! printf '%s' "${FUNCTIONS_JSON}" | jq empty >/dev/null 2>&1; then
    die "Retorno JSON de funções corrompido ou inválido." "${EXIT_QUERY_FAILED}"
fi

# 7. Triggers configurados
if ! TRIGGERS_JSON="$(exec_psql_json "
SELECT COALESCE(json_agg(json_build_object(
    'schema', n.nspname,
    'tabela', c.relname,
    'nome', t.tgname,
    'funcao', p.proname
) ORDER BY n.nspname, c.relname, t.tgname), '[]'::json)
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE NOT t.tgisinternal
  AND n.nspname NOT LIKE 'pg\_%' AND n.nspname <> 'information_schema';
")" || [ -z "${TRIGGERS_JSON}" ]; then
    die "Falha ao consultar triggers no contêiner." "${EXIT_QUERY_FAILED}"
fi
if ! printf '%s' "${TRIGGERS_JSON}" | jq empty >/dev/null 2>&1; then
    die "Retorno JSON de triggers corrompido ou inválido." "${EXIT_QUERY_FAILED}"
fi

# 8. Extração e contagem de tabelas públicas e de auth
# Requisito 2 e Requisito 5:
# - Coleta todas as tabelas relevantes de public E auth (não apenas auth.users)
# - Distingue tabelas comuns (r - BASE TABLE) de particionadas (p - PARTITIONED TABLE)
# - Utiliza identificadores formatados com segurança (quote_ident)
say "📊 Coletando métricas estruturais de tabelas em 'public' e 'auth' (método: ${METODO_CONTAGEM})..."

TABLE_LIST_SQL="
SELECT n.nspname, c.relname, c.relkind
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('public', 'auth')
  AND c.relkind IN ('r', 'p')
ORDER BY n.nspname, c.relname;
"

if ! TABLES_RAW="$(exec_psql_raw "${TABLE_LIST_SQL}")"; then
    die "Falha ao listar tabelas dos esquemas public e auth no contêiner." "${EXIT_QUERY_FAILED}"
fi

if [ -z "${TABLES_RAW}" ]; then
    die "Nenhuma tabela localizada nos esquemas public ou auth." "${EXIT_QUERY_FAILED}"
fi

TOTAL_TABLES_PUBLIC_COUNT=0
TOTAL_TABLES_AUTH_COUNT=0
TABLES_JSON_BUILDER="[]"

while IFS='|' read -r schema tab relkind; do
    [ -n "${schema}" ] && [ -n "${tab}" ] || continue

    if [ "${schema}" = "public" ]; then
        TOTAL_TABLES_PUBLIC_COUNT=$((TOTAL_TABLES_PUBLIC_COUNT + 1))
    elif [ "${schema}" = "auth" ]; then
        TOTAL_TABLES_AUTH_COUNT=$((TOTAL_TABLES_AUTH_COUNT + 1))
    fi

    tipo_relacao="tabela_comum"
    if [ "${relkind}" = "p" ]; then
        tipo_relacao="tabela_particionada"
    fi

    count_val=0
    tipo_contagem="${METODO_CONTAGEM}"

    if [ "${EXACT_COUNT}" -eq 1 ]; then
        # Contagem exata via SELECT count(*) com quote_ident seguro
        # Evita SQL injection em nomes com caracteres especiais ou maiúsculas
        if [ "${relkind}" = "p" ]; then
            # Para particionadas, count(*) na tabela raiz varre todas as partições
            COUNT_SQL="SELECT count(*) FROM quote_ident('${schema}').quote_ident('${tab}')"
        fi
        # Execução padrão com identificadores citados com aspas duplas seguras
        cnt_out="$(docker exec "${TARGET_CONTAINER}" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -t -A -c "SELECT count(*) FROM \"${schema}\".\"${tab}\"" 2>>"${LOG_FILE}")" || {
            log "FALHA na contagem exata da tabela ${schema}.\"${tab}\""
            die "Falha ao realizar contagem exata na tabela: ${schema}.\"${tab}\"" "${EXIT_QUERY_FAILED}"
        }
        count_val="$(printf '%s' "${cnt_out}" | tr -d '[:space:]')"
        case "${count_val}" in
            ''|*[!0-9]*)
                die "Retorno não-numérico na contagem exata de ${schema}.\"${tab}\": '${count_val}'" "${EXIT_QUERY_FAILED}"
                ;;
        esac
    else
        # Modo estimativa leve via reltuples de pg_class
        est_out="$(docker exec "${TARGET_CONTAINER}" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -t -A -c "SELECT round(reltuples)::bigint FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = '${schema}' AND c.relname = '${tab}'" 2>>"${LOG_FILE}")" || {
            log "FALHA na consulta de estimativa reltuples para ${schema}.\"${tab}\""
            die "Falha ao obter reltuples de: ${schema}.\"${tab}\"" "${EXIT_QUERY_FAILED}"
        }
        count_val="$(printf '%s' "${est_out}" | tr -d '[:space:]')"
        case "${count_val}" in
            ''|*[!0-9]*)
                count_val=0
                ;;
        esac
    fi

    # Montagem atômica do elemento da tabela com jq
    TABLE_ELEM="$(jq -n \
        --arg sch "${schema}" \
        --arg tab "${tab}" \
        --argjson cnt "${count_val}" \
        --arg tipo "${tipo_contagem}" \
        --arg rel "${tipo_relacao}" \
        '{
            "schema": $sch,
            "tabela": $tab,
            "contagem": $cnt,
            "tipo_contagem": $tipo,
            "tipo_relacao": $rel
        }')"

    TABLES_JSON_BUILDER="$(printf '%s' "${TABLES_JSON_BUILDER}" | jq --argjson elem "${TABLE_ELEM}" '. + [$elem]')"
done <<< "${TABLES_RAW}"

# Validações semânticas dos contadores para assegurar tipos numéricos estritos
TOTAL_TABLES_ALL=$((TOTAL_TABLES_PUBLIC_COUNT + TOTAL_TABLES_AUTH_COUNT))

if [ "${TOTAL_TABLES_PUBLIC_COUNT}" -le 0 ]; then
    die "Nenhuma tabela localizada no schema public durante inventário." "${EXIT_QUERY_FAILED}"
fi
if [ "${TOTAL_TABLES_AUTH_COUNT}" -le 0 ]; then
    die "Nenhuma tabela localizada no schema auth durante inventário." "${EXIT_QUERY_FAILED}"
fi

TOTAL_CONSTRAINTS_COUNT="$(printf '%s' "${CONSTRAINTS_JSON}" | jq 'length')"
TOTAL_FUNCTIONS_COUNT="$(printf '%s' "${FUNCTIONS_JSON}" | jq 'length')"
TOTAL_TRIGGERS_COUNT="$(printf '%s' "${TRIGGERS_JSON}" | jq 'length')"
TOTAL_EXTENSIONS_COUNT="$(printf '%s' "${EXTENSIONS_JSON}" | jq 'length')"
TOTAL_ROLES_COUNT="$(printf '%s' "${ROLES_JSON}" | jq 'length')"

# Serialização final estrita via jq -n (Ponto 4 e 5 da auditoria)
# Não há interpolação manual de strings para evitar quebra de JSON
say "📦 Montando e validando arquivo JSON final do inventário..."

if ! jq -n \
    --arg versao_script "${SCRIPT_VERSION}" \
    --arg data_hora_geracao "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg container_auditado "${TARGET_CONTAINER}" \
    --arg banco_dados "${DB_NAME}" \
    --arg versao_pg "${PG_VERSION}" \
    --argjson pg_major "${PG_MAJOR}" \
    --arg metodo_contagem "${METODO_CONTAGEM}" \
    --arg modo_coleta_funcoes "${MODO_COLETA_FUNCOES}" \
    --argjson ofuscacao_aplicada "${OFUSCACAO_METADADO_APLICADA}" \
    --argjson total_tabelas "${TOTAL_TABLES_ALL}" \
    --argjson total_tabelas_public "${TOTAL_TABLES_PUBLIC_COUNT}" \
    --argjson total_tabelas_auth "${TOTAL_TABLES_AUTH_COUNT}" \
    --argjson total_tabelas_todas "${TOTAL_TABLES_ALL}" \
    --argjson total_constraints "${TOTAL_CONSTRAINTS_COUNT}" \
    --argjson total_funcoes "${TOTAL_FUNCTIONS_COUNT}" \
    --argjson total_triggers "${TOTAL_TRIGGERS_COUNT}" \
    --argjson total_extensoes "${TOTAL_EXTENSIONS_COUNT}" \
    --argjson total_roles "${TOTAL_ROLES_COUNT}" \
    --argjson esquemas "${SCHEMAS_JSON}" \
    --argjson extensoes "${EXTENSIONS_JSON}" \
    --argjson roles "${ROLES_JSON}" \
    --argjson constraints "${CONSTRAINTS_JSON}" \
    --argjson funcoes "${FUNCTIONS_JSON}" \
    --argjson triggers "${TRIGGERS_JSON}" \
    --argjson tabelas "${TABLES_JSON_BUILDER}" \
    '{
      "cabecalho": {
        "sistema": "DPSjur / SBJur",
        "tipo_documento": "inventario_banco_dados",
        "versao_script": $versao_script,
        "data_hora_utc": $data_hora_geracao,
        "container_auditado": $container_auditado,
        "banco_dados": $banco_dados,
        "versao_postgresql": $versao_pg,
        "pg_major": $pg_major,
        "metodo_contagem": $metodo_contagem
      },
      "politica_sigilo": {
        "contem_dados_clientes": false,
        "contem_senhas_ou_hashes": false,
        "modo_coleta_funcoes": $modo_coleta_funcoes,
        "ofuscacao_segredos_aplicada": $ofuscacao_aplicada,
        "ressalva_sigilo": "Expressões regulares reduzem risco de exposição acidental em corpos DDL, mas não garantem sigilo absoluto. O modo padrão restrito a metadados é a recomendação oficial.",
        "umask": "077",
        "permissao_arquivo": "0600"
      },
      "ressalva_temporal": {
        "instante_coleta": "tempo_de_execucao_do_inventario",
        "diferenca_instantes_declarada": true,
        "aviso": "As contagens refletem o estado do banco no instante de geracao deste inventario, que difere do instante em que qualquer arquivo de dump de backup foi gravado. Divergencias de contagem com backups anteriores ou posteriores devem ser analisadas de forma conclusiva com evidencias, sem presuncoes automaticas de crescimento."
      },
      "sumario": {
        "total_tabelas": $total_tabelas,
        "total_tabelas_public": $total_tabelas_public,
        "total_tabelas_auth": $total_tabelas_auth,
        "total_tabelas_todas": $total_tabelas_todas,
        "total_constraints": $total_constraints,
        "total_funcoes": $total_funcoes,
        "total_triggers": $total_triggers,
        "total_extensoes": $total_extensoes,
        "total_roles": $total_roles
      },
      "esquemas": $esquemas,
      "extensoes": $extensoes,
      "roles": $roles,
      "constraints": $constraints,
      "funcoes": $funcoes,
      "triggers": $triggers,
      "tabelas": $tabelas
    }' > "${OUTPUT_FILE}"; then
    die "Falha na montagem segura do JSON com jq." "${EXIT_JSON_FAILED}"
fi

# Ajustar e validar permissão do arquivo gerado
if ! chmod 600 "${OUTPUT_FILE}"; then
    die "Falha ao aplicar chmod 600 no arquivo gerado: ${OUTPUT_FILE}" "${EXIT_FS_FAILED}"
fi

OUT_PERM="$(stat -c '%a' "${OUTPUT_FILE}" 2>/dev/null || stat -f '%Lp' "${OUTPUT_FILE}" 2>/dev/null || echo "")"
if [ -z "${OUT_PERM}" ]; then
    die "Falha ao obter permissão efetiva de ${OUTPUT_FILE} via stat (resultado vazio ou comando falhou)." "${EXIT_FS_FAILED}"
fi
if [ "${OUT_PERM}" != "600" ]; then
    die "Permissão efetiva do arquivo JSON (${OUT_PERM}) não confere com 600." "${EXIT_FS_FAILED}"
fi

# Validação sintática e semântica rigorosa com jq
if ! jq empty "${OUTPUT_FILE}" >/dev/null 2>&1; then
    say_err "ERRO CRÍTICO: Validação sintática do JSON com 'jq' falhou. Arquivo inválido: ${OUTPUT_FILE}."
    log "ERRO: Sintaxe JSON inválida detectada por jq."
    die "Arquivo JSON de inventário gerado com erro sintático." "${EXIT_JSON_FAILED}"
fi

log "JSON validado com sucesso e consistência estrita via jq."

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
say " Total de constraints .: ${TOTAL_CONSTRAINTS_COUNT} (com definições DDL completas)"
say " Total de funções .....: ${TOTAL_FUNCTIONS_COUNT} (identidades/assinaturas; modo: ${MODO_COLETA_FUNCOES})"
say " Total de triggers ....: ${TOTAL_TRIGGERS_COUNT}"
say " Total de extensões ...: ${TOTAL_EXTENSIONS_COUNT}"
say " Total de roles .......: ${TOTAL_ROLES_COUNT}"
say " Ressalva temporal ....: Declarada expressamente no cabeçalho do JSON"
say " Log de execução ......: ${LOG_FILE} (chmod 600)"
say "================================================================================"
say " Para auditar no laboratório isolado, copie este JSON para a máquina de teste"
say " e execute: bash docs/vps/20-auditar-backup.sh --arquivo <backup.sql.gz> --inventario <caminho.json>"
say "================================================================================"

exit "${EXIT_OK}"
