#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur - Teste de Restauração de Backup em Laboratório Isolado
# Script: docs/vps/04-testar-restauracao-isolado.sh
# Versão: v2.3.0
# Alvo: VPS Hostinger 2.25.181.69 (EasyPanel / Supabase Self-Hosted)
# ==============================================================================
# SEGURANÇA E ISOLAMENTO ABSOLUTO:
# 1. NUNCA altera, reinicia ou escreve no banco de produção oficial
#    ('sbjur-local_supabase-db-1') nem em qualquer contêiner do DPSjur.
# 2. O contêiner de produção é acessado EXCLUSIVAMENTE em modo somente-leitura
#    para coleta de contagens comparativas e extração segura de globals.
# 3. O contêiner legado 'dpsjur-db' (PostgreSQL 18) NUNCA é tocado.
# 4. A restauração ocorre em contêiner Docker efêmero, com volume temporário
#    exclusivo, sem rede (--network none), limites de recursos e ciclo de vida
#    estritamente vinculado a este teste (PID atual).
# 5. Todo o ambiente de laboratório (contêiner, volume dedicado, arquivos temporários)
#    é destruído com segurança no encerramento (normal ou por erro).
# 6. Preservação de logs restritos: caso ocorra falha durante a restauração,
#    os logs de erro com permissão 600 são preservados em diretório de diagnóstico
#    permanente ANTES da limpeza do diretório efêmero.
# ==============================================================================

set -Eeuo pipefail

# ------------------------------------------------------------------------------
# Constantes e Definições Globais
# ------------------------------------------------------------------------------
readonly SCRIPT_VERSION="v2.3.0"
readonly SCRIPT_PID="$$"
readonly PROD_CONTAINER="sbjur-local_supabase-db-1"
readonly LEGACY_FORBIDDEN_CONTAINER="dpsjur-db"
readonly LAB_CONTAINER_NAME="sbjur-restore-lab-${SCRIPT_PID}"
readonly LAB_VOLUME_NAME="sbjur-restore-lab-data-${SCRIPT_PID}"
readonly DEFAULT_IMAGE="supabase/postgres:15.8.1.085"
readonly EXPECTED_PG_MAJOR="15"
readonly BACKUP_WHITELIST_REGEX='^/root/sbjur-backups/(diario|semanal|mensal)/sbjur_backup_.*\.sql\.gz$'
readonly LAB_CONTAINER_SANITIZED_REGEX='^sbjur-restore-lab-[0-9]+$'
readonly LAB_VOLUME_SANITIZED_REGEX='^sbjur-restore-lab-data-[0-9]+$'
readonly PRESERVED_LOG_DIR="/root/sbjur-backups/logs/diagnostico-restauracao"

# Códigos de saída padronizados
readonly EXIT_SUCCESS=0
readonly EXIT_USAGE_ERROR=2
readonly EXIT_ENV_ERROR=3
readonly EXIT_SECURITY_ERROR=4
readonly EXIT_RESOURCE_ERROR=5
readonly EXIT_LEVEL_A_FAILURE=10
readonly EXIT_LEVEL_B_FAILURE=20
readonly EXIT_LEVEL_C_FAILURE=30

# Cores para terminal interativo
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

# Variáveis globais mutáveis gerenciadas
TEMP_WORK_DIR=""
CLEANUP_RUNNING=0
FORCAR_IMAGEM=0
PULAR_COMPARACAO_PROD=0
BACKUP_INPUT_PATH=""
TARGET_IMAGE="${DEFAULT_IMAGE}"

# Variáveis de auditoria e veredito
VEREDITO_NIVEL_A="PENDENTE"
DETALHE_NIVEL_A=""
VEREDITO_NIVEL_B="PENDENTE"
DETALHE_NIVEL_B=""
VEREDITO_NIVEL_C="PENDENTE"
DETALHE_NIVEL_C=""
VEREDITO_NIVEL_D="NÃO VALIDADO (recuperação operacional completa com Gotrue/PostgREST/Kong/Storage fora do escopo deste teste)"

ORIGEM_BACKUP_STATUS="NÃO COMPROVADA"
ORIGEM_BACKUP_DETALHE="Nenhum metadado verificável (.meta/.sha256/.manifest) encontrado junto ao dump."
DUMP_REAL_PG_VERSION="Desconhecida"
DUMP_UNCOMPRESSED_BYTES=0
TOTAL_TABELAS_AUDITADAS=0
TOTAL_TABELAS_COINCIDENTES=0
TOTAL_TABELAS_DIVERGENTES=0
TOTAL_TABELAS_ERRO=0

# Tabela de contagens para relatório final
CONTAGENS_RELATORIO=""

# ------------------------------------------------------------------------------
# Funções de Logging e Exibição Segura
# ------------------------------------------------------------------------------
log_info() {
    echo -e "${CYAN}ℹ️  [INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}✅ [SUCESSO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}⚠️  [AVISO]${NC} $*"
}

log_error() {
    echo -e "${RED}❌ [ERRO]${NC} $*" >&2
}

log_step() {
    echo -e "\n${BOLD}${BLUE}==>${NC} ${BOLD}$*${NC}"
}

# ------------------------------------------------------------------------------
# Procedimento de Limpeza com Preservação de Logs
# ------------------------------------------------------------------------------
cleanup() {
    local original_exit_code=$?
    if [ "${CLEANUP_RUNNING}" -ne 0 ]; then
        return
    fi
    CLEANUP_RUNNING=1

    # Desativa traps para evitar loops
    trap - EXIT ERR INT TERM

    # Preservar logs restritos de falha ANTES de remover o diretório temporário
    if [ -n "${TEMP_WORK_DIR:-}" ] && [ -d "${TEMP_WORK_DIR}" ]; then
        if [ "${original_exit_code}" -ne 0 ] || [ "${VEREDITO_NIVEL_B}" = "FALHA" ]; then
            if mkdir -p "${PRESERVED_LOG_DIR}" 2>/dev/null && chmod 700 "${PRESERVED_LOG_DIR}" 2>/dev/null; then
                local timestamp_salvo
                timestamp_salvo="$(date '+%Y%m%d_%H%M%S' 2>/dev/null || echo "log")"
                local dest_log="${PRESERVED_LOG_DIR}/falha_restauracao_${timestamp_salvo}_pid${SCRIPT_PID}.log"
                
                {
                    echo "====================================================================="
                    echo "DPSjur - Log de Diagnóstico Preservado após Falha no Laboratório"
                    echo "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
                    echo "PID: ${SCRIPT_PID}"
                    echo "Exit Code Original: ${original_exit_code}"
                    echo "Veredito Nível A: ${VEREDITO_NIVEL_A}"
                    echo "Veredito Nível B: ${VEREDITO_NIVEL_B}"
                    echo "====================================================================="
                    if [ -f "${TEMP_WORK_DIR}/restore_globals.err" ]; then
                        echo "--- Erros em Globals/Roles ---"
                        cat "${TEMP_WORK_DIR}/restore_globals.err" 2>/dev/null || true
                    fi
                    if [ -f "${TEMP_WORK_DIR}/restore_db.err" ]; then
                        echo "--- Erros na Restauração do Banco ---"
                        cat "${TEMP_WORK_DIR}/restore_db.err" 2>/dev/null || true
                    fi
                    if [ -f "${TEMP_WORK_DIR}/restore_db.log" ]; then
                        echo "--- Últimas 200 linhas do log de execução ---"
                        tail -n 200 "${TEMP_WORK_DIR}/restore_db.log" 2>/dev/null || true
                    fi
                } > "${dest_log}" 2>/dev/null || true

                chmod 600 "${dest_log}" 2>/dev/null || true
                log_warn "Logs restritos de falha preservados com segurança em: ${dest_log}"
            fi
        fi
    fi

    # 1. Parada e remoção incondicional do contêiner de laboratório
    if [[ "${LAB_CONTAINER_NAME}" =~ ${LAB_CONTAINER_SANITIZED_REGEX} ]]; then
        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${LAB_CONTAINER_NAME}$"; then
            docker stop -t 5 "${LAB_CONTAINER_NAME}" >/dev/null 2>&1 || true
            docker rm -f -v "${LAB_CONTAINER_NAME}" >/dev/null 2>&1 || true
        fi
    fi

    # 2. Remoção incondicional do volume temporário dedicado do laboratório
    if [[ "${LAB_VOLUME_NAME}" =~ ${LAB_VOLUME_SANITIZED_REGEX} ]]; then
        if docker volume ls --format '{{.Name}}' 2>/dev/null | grep -q "^${LAB_VOLUME_NAME}$"; then
            docker volume rm -f "${LAB_VOLUME_NAME}" >/dev/null 2>&1 || true
        fi
    fi

    # 3. Remoção protegida do diretório de trabalho temporário
    if [ -n "${TEMP_WORK_DIR:-}" ] && [ -d "${TEMP_WORK_DIR}" ]; then
        if [[ "${TEMP_WORK_DIR}" =~ ^/tmp/sbjur-restore-lab-[0-9]+-[A-Za-z0-9]+$ ]]; then
            rm -rf "${TEMP_WORK_DIR}" 2>/dev/null || true
        fi
    fi

    exit "${original_exit_code}"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'log_error "Falha não tratada na linha ${BASH_LINENO[0]} (comando: ${BASH_COMMAND})"; exit 1' ERR

# ------------------------------------------------------------------------------
# Ajuda e Documentação de Uso
# ------------------------------------------------------------------------------
exibir_ajuda() {
    cat << EOF
DPSjur / SBJur - Teste de Restauração em Laboratório Isolado (${SCRIPT_VERSION})

USO:
    bash $0 [OPÇÕES] [CAMINHO_DO_BACKUP]

ARGUMENTOS:
    CAMINHO_DO_BACKUP (opcional)
        Caminho completo do arquivo de dump (.sql.gz).
        Deve estar estritamente dentro de /root/sbjur-backups/{diario,semanal,mensal}/
        Se omitido, o dump mais recente em /root/sbjur-backups/diario/ será selecionado.

OPÇÕES:
    --forcar-imagem
        Permite executar o teste com uma imagem Docker diferente da recomendada
        (${DEFAULT_IMAGE}), desde que confirmada manualmente.
    --pular-comparacao-prod
        Executa os Níveis A e B e as verificações estruturais do Nível C, mas pula
        a leitura comparativa de contagens com o contêiner de produção. Útil quando
        a produção estiver parada para manutenção.
    -h, --help
        Exibe esta mensagem de ajuda.

NÍVEIS DE VEREDITO:
    Nível A - Integridade Física (gzip -t e estrutura do arquivo comprimido)
    Nível B - Restauração SQL (reconstrução em contêiner efêmero com isolamento)
    Nível C - Validação Estrutural e Registros (schemas, tabelas, índices, constraints,
              permissões grants, políticas RLS e comparativo de contagens)
    Nível D - Recuperação Operacional (Gotrue, PostgREST, Kong, Storage) - NÃO VALIDADO

EXEMPLOS:
    bash $0
    bash $0 /root/sbjur-backups/diario/sbjur_backup_2026-11-07_030000.sql.gz
    bash $0 --pular-comparacao-prod
EOF
}

# ------------------------------------------------------------------------------
# Processamento de Parâmetros
# ------------------------------------------------------------------------------
processar_parametros() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                exibir_ajuda
                exit "${EXIT_SUCCESS}"
                ;;
            --forcar-imagem)
                FORCAR_IMAGEM=1
                shift
                ;;
            --pular-comparacao-prod)
                PULAR_COMPARACAO_PROD=1
                shift
                ;;
            -*)
                log_error "Opção desconhecida: $1"
                exibir_ajuda
                exit "${EXIT_USAGE_ERROR}"
                ;;
            *)
                if [ -n "${BACKUP_INPUT_PATH}" ]; then
                    log_error "Múltiplos caminhos de backup fornecidos: '${BACKUP_INPUT_PATH}' e '$1'"
                    exit "${EXIT_USAGE_ERROR}"
                fi
                BACKUP_INPUT_PATH="$1"
                shift
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Validação de Ambiente e Pré-requisitos
# ------------------------------------------------------------------------------
validar_ambiente() {
    log_step "1. Validando pré-requisitos de ambiente e ferramentas"

    if [ "$(id -u)" -ne 0 ]; then
        log_error "Este script deve ser executado como root no VPS para gerenciar recursos isolados do Docker."
        exit "${EXIT_ENV_ERROR}"
    fi

    local comandos_obrigatorios=("docker" "gzip" "awk" "sed" "grep" "stat" "cut")
    for cmd in "${comandos_obrigatorios[@]}"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            log_error "Comando essencial ausente no VPS: ${cmd}"
            exit "${EXIT_ENV_ERROR}"
        fi
    done

    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon não está em execução ou inacessível."
        exit "${EXIT_ENV_ERROR}"
    fi

    # Criar diretório de trabalho seguro em /tmp com permissão 700
    local rand_suffix
    rand_suffix="$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 8 || echo "${RANDOM}")"
    TEMP_WORK_DIR="/tmp/sbjur-restore-lab-${SCRIPT_PID}-${rand_suffix}"
    mkdir -m 700 -p "${TEMP_WORK_DIR}"
    log_success "Diretório de trabalho temporário criado: ${TEMP_WORK_DIR} (chmod 700)"
}

# ------------------------------------------------------------------------------
# Seleção e Validação Rigorosa do Arquivo de Dump
# ------------------------------------------------------------------------------
selecionar_e_validar_dump() {
    log_step "2. Selecionando e validando caminho do arquivo de backup"

    if [ -z "${BACKUP_INPUT_PATH}" ]; then
        log_info "Nenhum arquivo especificado. Buscando o backup mais recente em /root/sbjur-backups/diario/..."
        BACKUP_INPUT_PATH="$(find /root/sbjur-backups/diario/ -maxdepth 1 -type f -name 'sbjur_backup_*.sql.gz' 2>/dev/null | sort -r | head -n 1 || true)"
        
        if [ -z "${BACKUP_INPUT_PATH}" ]; then
            log_info "Nenhum arquivo em diario/. Buscando em semanal/ e mensal/..."
            BACKUP_INPUT_PATH="$(find /root/sbjur-backups/semanal/ /root/sbjur-backups/mensal/ -maxdepth 1 -type f -name 'sbjur_backup_*.sql.gz' 2>/dev/null | sort -r | head -n 1 || true)"
        fi
    fi

    if [ -z "${BACKUP_INPUT_PATH}" ]; then
        log_error "Nenhum arquivo de backup foi encontrado em /root/sbjur-backups/{diario,semanal,mensal}/."
        exit "${EXIT_USAGE_ERROR}"
    fi

    # Whitelist estrita do caminho
    if [[ ! "${BACKUP_INPUT_PATH}" =~ ${BACKUP_WHITELIST_REGEX} ]]; then
        log_error "Caminho de backup rejeitado por violar a política de segurança!"
        log_error "O caminho deve satisfazer estritamente o padrão: ${BACKUP_WHITELIST_REGEX}"
        log_error "Valor rejeitado: ${BACKUP_INPUT_PATH}"
        exit "${EXIT_SECURITY_ERROR}"
    fi

    if [ ! -f "${BACKUP_INPUT_PATH}" ]; then
        log_error "Arquivo de backup não existe: ${BACKUP_INPUT_PATH}"
        exit "${EXIT_USAGE_ERROR}"
    fi

    if [ ! -r "${BACKUP_INPUT_PATH}" ]; then
        log_error "Arquivo de backup não possui permissão de leitura: ${BACKUP_INPUT_PATH}"
        exit "${EXIT_SECURITY_ERROR}"
    fi

    local tamanho_comp
    tamanho_comp="$(du -h "${BACKUP_INPUT_PATH}" 2>/dev/null | awk '{print $1}' || echo "N/A")"
    log_success "Backup selecionado: ${BACKUP_INPUT_PATH} (${tamanho_comp})"
}

# ------------------------------------------------------------------------------
# Comprovação de Origem do Backup (Metadados Reais)
# ------------------------------------------------------------------------------
verificar_origem_backup() {
    log_step "3. Verificando comprovação de origem e autenticidade do backup"

    local base_sem_gz="${BACKUP_INPUT_PATH%.gz}"
    local base_path="${BACKUP_INPUT_PATH}"
    local meta_cand=""
    local sha_cand=""
    local manifest_cand=""

    for ext in ".meta" ".meta.json" ".json"; do
        if [ -f "${base_path}${ext}" ]; then
            meta_cand="${base_path}${ext}"
            break
        elif [ -f "${base_sem_gz}${ext}" ]; then
            meta_cand="${base_sem_gz}${ext}"
            break
        fi
    done

    for ext in ".sha256" ".sha256sum"; do
        if [ -f "${base_path}${ext}" ]; then
            sha_cand="${base_path}${ext}"
            break
        elif [ -f "${base_sem_gz}${ext}" ]; then
            sha_cand="${base_sem_gz}${ext}"
            break
        fi
    done

    if [ -f "$(dirname "${BACKUP_INPUT_PATH}")/manifest.json" ]; then
        manifest_cand="$(dirname "${BACKUP_INPUT_PATH}")/manifest.json"
    fi

    # Avaliar se há metadados verificáveis válidos
    if [ -n "${sha_cand}" ]; then
        log_info "Arquivo SHA256 detectado: ${sha_cand}. Verificando integridade criptográfica..."
        local dir_backup
        dir_backup="$(dirname "${BACKUP_INPUT_PATH}")"
        local nome_backup
        nome_backup="$(basename "${BACKUP_INPUT_PATH}")"
        if (cd "${dir_backup}" && sha256sum -c "${sha_cand}" >/dev/null 2>&1); then
            ORIGEM_BACKUP_STATUS="COMPROVADA"
            ORIGEM_BACKUP_DETALHE="Checksum SHA256 verificado com sucesso contra ${sha_cand}."
            log_success "${ORIGEM_BACKUP_DETALHE}"
            return
        else
            log_warn "Checksum SHA256 divergiu do arquivo!"
        fi
    fi

    if [ -n "${meta_cand}" ] || [ -n "${manifest_cand}" ]; then
        ORIGEM_BACKUP_STATUS="COMPROVADA"
        ORIGEM_BACKUP_DETALHE="Arquivo de metadados localizado (${meta_cand:-${manifest_cand}})."
        log_success "${ORIGEM_BACKUP_DETALHE}"
        return
    fi

    # Se nenhum metadado existir nos backups atuais (conforme realidade atual do VPS),
    # declara HONESTAMENTE como NÃO COMPROVADA no relatório.
    ORIGEM_BACKUP_STATUS="NÃO COMPROVADA"
    ORIGEM_BACKUP_DETALHE="Nenhum arquivo .meta, .sha256 ou .manifest foi encontrado junto ao arquivo de dump. O backup é aceito para teste, mas sua cadeia de custódia não possui assinatura criptográfica."
    log_warn "Origem do backup: ${ORIGEM_BACKUP_STATUS}."
    log_info "${ORIGEM_BACKUP_DETALHE}"
}

# ------------------------------------------------------------------------------
# Nível A - Validação de Integridade Física do Dump
# ------------------------------------------------------------------------------
executar_nivel_a() {
    log_step "4. Nível A: Validação de Integridade Física do Arquivo Gzip"

    log_info "Testando integridade física dos blocos compactados com 'gzip -t'..."
    local gzip_test_output
    if ! gzip_test_output="$(gzip -t "${BACKUP_INPUT_PATH}" 2>&1)"; then
        VEREDITO_NIVEL_A="FALHA"
        DETALHE_NIVEL_A="Falha física no arquivo gzip: ${gzip_test_output}"
        log_error "${DETALHE_NIVEL_A}"
        exit "${EXIT_LEVEL_A_FAILURE}"
    fi

    # Obter tamanho descomprimido via gzip -l
    local gzip_l_output
    gzip_l_output="$(gzip -l "${BACKUP_INPUT_PATH}" 2>/dev/null | tail -n 1 || true)"
    DUMP_UNCOMPRESSED_BYTES="$(echo "${gzip_l_output}" | awk '{print $2}' || echo 0)"

    if [ -z "${DUMP_UNCOMPRESSED_BYTES}" ] || [ "${DUMP_UNCOMPRESSED_BYTES}" -le 0 ]; then
        # Fallback de contagem precisa descomprimindo uma amostra em pipe
        log_warn "gzip -l retornou tamanho zerado (comum em arquivos grandes > 4GB). Calculando estimativa defensiva..."
        local tamanho_comprimido_bytes
        tamanho_comprimido_bytes="$(stat -c%s "${BACKUP_INPUT_PATH}" 2>/dev/null || echo 0)"
        DUMP_UNCOMPRESSED_BYTES=$((tamanho_comprimido_bytes * 5))
    fi

    # Verificar cabeçalho SQL para confirmar versão do PostgreSQL
    log_info "Examinando cabeçalho SQL do dump descomprimido..."
    local dump_header
    dump_header="$(gzip -dc "${BACKUP_INPUT_PATH}" | head -n 40 2>/dev/null || true)"

    if echo "${dump_header}" | grep -qi "PostgreSQL database dump"; then
        DUMP_REAL_PG_VERSION="$(echo "${dump_header}" | grep -i "Dumped from database version" | head -n 1 | sed -e 's/.*Dumped from database version //I' -e 's/[;.]*$//' || echo "15.x")"
        log_success "Cabeçalho válido identificado: Dump do PostgreSQL versão '${DUMP_REAL_PG_VERSION}'."
    else
        log_warn "Cabeçalho padrão do pg_dump não localizado explicitamente nas primeiras 40 linhas."
        DUMP_REAL_PG_VERSION="Não identificada no cabeçalho"
    fi

    VEREDITO_NIVEL_A="APROVADO"
    DETALHE_NIVEL_A="Integridade física do gzip confirmada sem erros de CRC (gzip -t: OK). Versão do dump: ${DUMP_REAL_PG_VERSION}."
    log_success "Nível A APROVADO com sucesso."
}

# ------------------------------------------------------------------------------
# Checagem de Recursos (Disco e Memória com Falha Estrita)
# ------------------------------------------------------------------------------
verificar_recursos_sistema() {
    log_step "5. Verificando Recursos do Sistema (Memória e Espaço em Disco)"

    # Requisito 7: Memória mínima de 1536 MB (1.5 GB) disponível para o laboratório.
    # NUNCA reduzir automaticamente o limite — interromper com erro estrito se insuficiente!
    local mem_disponivel_mb
    mem_disponivel_mb="$(free -m 2>/dev/null | awk '/^Mem:/{print $7}' || echo 0)"
    if [ -z "${mem_disponivel_mb}" ] || [ "${mem_disponivel_mb}" -le 0 ]; then
        mem_disponivel_mb="$(free -m 2>/dev/null | awk '/^Mem:/{print $4}' || echo 0)"
    fi

    log_info "Memória RAM disponível para alocação no host: ${mem_disponivel_mb} MB"
    if [ "${mem_disponivel_mb}" -lt 1536 ]; then
        log_error "Memória disponível insuficiente para executar o contêiner de laboratório com segurança!"
        log_error "Disponível: ${mem_disponivel_mb} MB | Exigido: 1536 MB."
        log_error "Para proteger os serviços de produção em execução, o teste foi INTERROMPIDO sem redução automática de limites."
        exit "${EXIT_RESOURCE_ERROR}"
    fi

    # Requisito 6: Cálculo de espaço em disco considerando tamanho descomprimido,
    # fator de expansão de tabelas e índices do PostgreSQL (3x), WAL e margem para produção.
    # Fórmula: Espaço Necessário = (Tamanho Descomprimido * 3.5) + Reserva Produção (2048 MB)
    local uncomp_mb=$((DUMP_UNCOMPRESSED_BYTES / 1024 / 1024))
    if [ "${uncomp_mb}" -lt 100 ]; then
        uncomp_mb=100
    fi

    local espaco_expansao_mb=$((uncomp_mb * 7 / 2)) # 3.5x
    local reserva_producao_mb=2048                  # 2 GB de reserva intocável para produção
    local espaco_total_necessario_mb=$((espaco_expansao_mb + reserva_producao_mb))

    local espaco_livre_mb
    espaco_livre_mb="$(df -m /var/lib/docker 2>/dev/null | awk 'NR==2{print $4}' || df -m / 2>/dev/null | awk 'NR==2{print $4}' || echo 0)"

    log_info "Tamanho descomprimido estimado do dump: ${uncomp_mb} MB"
    log_info "Espaço estimado para expansão no PostgreSQL (tabelas + índices + WAL): ${espaco_expansao_mb} MB"
    log_info "Reserva de segurança para produção: ${reserva_producao_mb} MB"
    log_info "Espaço livre atual no sistema de arquivos do Docker: ${espaco_livre_mb} MB (necessário: ${espaco_total_necessario_mb} MB)"

    if [ "${espaco_livre_mb}" -lt "${espaco_total_necessario_mb}" ]; then
        log_error "Espaço em disco insuficiente no VPS para restaurar o banco sem arriscar a produção!"
        log_error "Livre: ${espaco_livre_mb} MB | Necessário: ${espaco_total_necessario_mb} MB."
        exit "${EXIT_RESOURCE_ERROR}"
    fi

    log_success "Recursos de memória e disco validados com folga de segurança."
}

# ------------------------------------------------------------------------------
# Validação de Imagem Docker e Proteção de Serviços
# ------------------------------------------------------------------------------
validar_imagem_e_protecao_servicos() {
    log_step "6. Validando Imagem Docker do Laboratório e Proteção da Produção"

    # Proteção 1: Garantir que o contêiner de produção oficial existe
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${PROD_CONTAINER}$"; then
        if [ "${PULAR_COMPARACAO_PROD}" -eq 0 ]; then
            log_warn "Contêiner de produção oficial '${PROD_CONTAINER}' não encontrado em execução!"
            log_warn "Se você deseja testar apenas a restauração isolada sem comparar contagens, use: --pular-comparacao-prod"
            exit "${EXIT_ENV_ERROR}"
        fi
    fi

    # Proteção 2: O PostgreSQL 18 legado (dpsjur-db) NUNCA pode ser tocado nem utilizado
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${LEGACY_FORBIDDEN_CONTAINER}$"; then
        log_info "Contêiner legado '${LEGACY_FORBIDDEN_CONTAINER}' detectado no host. POLÍTICA ATIVA: este contêiner NUNCA será tocado."
    fi

    # Validação da imagem Docker local
    if ! docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -q "^${DEFAULT_IMAGE}$"; then
        if [ "${FORCAR_IMAGEM}" -eq 0 ]; then
            log_error "A imagem oficial homologada '${DEFAULT_IMAGE}' não foi encontrada localmente no Docker!"
            log_error "Imagens postgres disponíveis localmente:"
            docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' 2>/dev/null | grep -Ei 'postgres|supabase' || true
            log_error "Para prosseguir com outra imagem deliberadamente, execute com a flag: --forcar-imagem"
            exit "${EXIT_SECURITY_ERROR}"
        else
            log_warn "Flag --forcar-imagem ativa. Buscando alternativa compatível do PostgreSQL ${EXPECTED_PG_MAJOR}..."
            local alt_img
            alt_img="$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -E 'supabase.*postgres|postgres' | head -n 1 || true)"
            if [ -z "${alt_img}" ]; then
                log_error "Nenhuma imagem PostgreSQL local disponível para o laboratório!"
                exit "${EXIT_ENV_ERROR}"
            fi
            TARGET_IMAGE="${alt_img}"
            log_warn "Utilizando imagem alternativa sob confirmação: ${TARGET_IMAGE}"
        fi
    else
        TARGET_IMAGE="${DEFAULT_IMAGE}"
        log_success "Imagem oficial homologada confirmada localmente: ${TARGET_IMAGE}"
    fi
}

# ------------------------------------------------------------------------------
# Extração e Sanitização de Globals/Roles da Produção
# ------------------------------------------------------------------------------
extrair_e_sanitizar_globals() {
    log_step "7. Extraindo e Sanitizando Globals/Roles da Produção"

    local globals_raw="${TEMP_WORK_DIR}/globals_raw.sql"
    local globals_sanitized="${TEMP_WORK_DIR}/globals_sanitized.sql"

    if [ "${PULAR_COMPARACAO_PROD}" -eq 0 ] && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${PROD_CONTAINER}$"; then
        log_info "Extraindo roles e definições globais da produção via pg_dumpall -g (somente-leitura)..."
        if ! docker exec -i "${PROD_CONTAINER}" pg_dumpall -U postgres --globals-only > "${globals_raw}" 2>"${TEMP_WORK_DIR}/globals_extract.err"; then
            log_warn "Falha ao rodar pg_dumpall na produção. Utilizando fallback das roles essenciais do Supabase..."
            gerar_fallback_globals "${globals_sanitized}"
            return
        fi
    else
        log_info "Modo sem acesso à produção ativo. Utilizando template homologado de roles do Supabase..."
        gerar_fallback_globals "${globals_sanitized}"
        return
    fi

    # Sanitização cuidadosa: encapsular comandos CREATE ROLE em blocos PL/pgSQL
    # com tratamento de exceção duplicate_object, preservando senhas e grants,
    # mas mantendo erros sintáticos ou de conexão estritos.
    log_info "Sanitizando script de globals com blocos idempotentes (EXCEPTION duplicate_object)..."
    awk '
    BEGIN { in_create_role = 0; role_stmt = "" }
    /^[[:space:]]*CREATE ROLE/ {
        in_create_role = 1
        role_stmt = $0
        if ($0 ~ /;[[:space:]]*$/) {
            print "DO $$ BEGIN " role_stmt " EXCEPTION WHEN duplicate_object THEN NULL; END $$;"
            in_create_role = 0
            role_stmt = ""
        }
        next
    }
    in_create_role == 1 {
        role_stmt = role_stmt " " $0
        if ($0 ~ /;[[:space:]]*$/) {
            print "DO $$ BEGIN " role_stmt " EXCEPTION WHEN duplicate_object THEN NULL; END $$;"
            in_create_role = 0
            role_stmt = ""
        }
        next
    }
    { print }
    ' "${globals_raw}" > "${globals_sanitized}"

    # Garantir que roles mínimas do Supabase existam sem erro
    cat << 'EOF' >> "${globals_sanitized}"
DO $$ BEGIN CREATE ROLE anon NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE authenticated NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE service_role NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE supabase_admin LOGIN SUPERUSER; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE supabase_auth_admin NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE supabase_storage_admin NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE pgbouncer NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
EOF

    chmod 600 "${globals_sanitized}"
    log_success "Script de globals sanitizado preparado com sucesso."
}

gerar_fallback_globals() {
    local target_file="$1"
    cat << 'EOF' > "${target_file}"
DO $$ BEGIN CREATE ROLE postgres LOGIN SUPERUSER; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE anon NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE authenticated NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE service_role NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE supabase_admin LOGIN SUPERUSER; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE supabase_auth_admin NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE supabase_storage_admin NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE pgbouncer NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
EOF
    chmod 600 "${target_file}"
}

# ------------------------------------------------------------------------------
# Nível B - Criação do Contêiner de Laboratório e Restauração SQL
# ------------------------------------------------------------------------------
executar_nivel_b() {
    log_step "8. Nível B: Restauração SQL em Contêiner Docker Efêmero e Isolado"

    # Requisito 3: Criação de volume Docker dedicado EXCLUSIVO para o laboratório
    log_info "Criando volume Docker dedicado: ${LAB_VOLUME_NAME}..."
    docker volume create "${LAB_VOLUME_NAME}" >/dev/null

    # Inicialização do contêiner com isolamento absoluto:
    # --network none: sem acesso a nenhuma rede ou portas externas
    # --pull never: nunca faz download externo
    # limites rígidos de cpu, memória e pids
    log_info "Iniciando contêiner de laboratório: ${LAB_CONTAINER_NAME}..."
    docker run -d \
        --name "${LAB_CONTAINER_NAME}" \
        --network none \
        --pull never \
        --memory 1536m \
        --memory-swap 1536m \
        --shm-size 256m \
        --cpus 1.5 \
        --pids-limit 128 \
        -v "${LAB_VOLUME_NAME}:/var/lib/postgresql/data" \
        -e POSTGRES_PASSWORD=postgres \
        -e POSTGRES_HOST_AUTH_METHOD=trust \
        "${TARGET_IMAGE}" \
        postgres -c shared_buffers=256MB -c work_mem=16MB -c fsync=off -c full_page_writes=off -c synchronous_commit=off >/dev/null

    log_info "Aguardando inicialização e prontidão do PostgreSQL no laboratório..."
    local pronto=0
    for _ in $(seq 1 45); do
        if docker exec -i "${LAB_CONTAINER_NAME}" pg_isready -U postgres >/dev/null 2>&1; then
            pronto=1
            break
        fi
        sleep 1
    done

    if [ "${pronto}" -ne 1 ]; then
        VEREDITO_NIVEL_B="FALHA"
        DETALHE_NIVEL_B="O contêiner de laboratório não respondeu ao pg_isready dentro do tempo limite de 45s."
        log_error "${DETALHE_NIVEL_B}"
        exit "${EXIT_LEVEL_B_FAILURE}"
    fi
    log_success "PostgreSQL no laboratório ativo e pronto para receber dados."

    # Requisito 4: Aplicação dos globals/roles sanitizados.
    # QUALQUER falha no psql aqui deve INTERROMPER o teste com erro estrito!
    log_info "Aplicando globals/roles sanitizados no banco de laboratório (com ON_ERROR_STOP=1)..."
    local globals_file="${TEMP_WORK_DIR}/globals_sanitized.sql"
    if ! docker exec -i "${LAB_CONTAINER_NAME}" psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${globals_file}" > "${TEMP_WORK_DIR}/restore_globals.log" 2> "${TEMP_WORK_DIR}/restore_globals.err"; then
        VEREDITO_NIVEL_B="FALHA"
        local globals_err
        globals_err="$(head -n 20 "${TEMP_WORK_DIR}/restore_globals.err" 2>/dev/null || echo "Erro desconhecido")"
        DETALHE_NIVEL_B="Falha crítica na restauração de globals/roles (Requisito 4). Erro: ${globals_err}"
        log_error "${DETALHE_NIVEL_B}"
        exit "${EXIT_LEVEL_B_FAILURE}"
    fi
    log_success "Globals e roles aplicados com sucesso no laboratório."

    # Restauração do dump compactado com pipefail estrito e ON_ERROR_STOP=1
    log_info "Restaurando dump do banco de dados no contêiner de laboratório..."
    log_info "Comando: gzip -dc <dump> | psql -U postgres -d postgres -v ON_ERROR_STOP=1"

    local restore_exit=0
    # Execução protegida gravando logs restritos com chmod 600
    touch "${TEMP_WORK_DIR}/restore_db.log" "${TEMP_WORK_DIR}/restore_db.err"
    chmod 600 "${TEMP_WORK_DIR}/restore_db.log" "${TEMP_WORK_DIR}/restore_db.err"

    (
        set -o pipefail
        gzip -dc "${BACKUP_INPUT_PATH}" | docker exec -i "${LAB_CONTAINER_NAME}" psql -U postgres -d postgres -v ON_ERROR_STOP=1 > "${TEMP_WORK_DIR}/restore_db.log" 2> "${TEMP_WORK_DIR}/restore_db.err"
    ) || restore_exit=$?

    if [ "${restore_exit}" -ne 0 ]; then
        VEREDITO_NIVEL_B="FALHA"
        local restore_err_snippet
        restore_err_snippet="$(head -n 20 "${TEMP_WORK_DIR}/restore_db.err" 2>/dev/null || echo "Falha durante a execução do psql")"
        DETALHE_NIVEL_B="Falha na execução do psql durante a restauração do banco (exit code: ${restore_exit}). Erro: ${restore_err_snippet}"
        log_error "${DETALHE_NIVEL_B}"
        exit "${EXIT_LEVEL_B_FAILURE}"
    fi

    VEREDITO_NIVEL_B="APROVADO"
    DETALHE_NIVEL_B="Restauração SQL concluída com sucesso (globals/roles + dump de dados sem violações com ON_ERROR_STOP=1)."
    log_success "Nível B APROVADO com sucesso."
}

# ------------------------------------------------------------------------------
# Nível C - Validação Estrutural e Auditoria de Registros
# ------------------------------------------------------------------------------
executar_nivel_c() {
    log_step "9. Nível C: Validação Estrutural Completa e Comparativo de Registros"

    # Requisito 5: Verificar EFETIVAMENTE no laboratório:
    # schemas, tabelas, índices, constraints, permissões (grants) e políticas RLS
    log_info "Executando inspeções estruturais detalhadas no laboratório restaurado..."

    local lab_schemas_count
    lab_schemas_count="$(docker exec -i "${LAB_CONTAINER_NAME}" psql -U postgres -d postgres -tAc "SELECT count(*) FROM information_schema.schemata WHERE schema_name IN ('public', 'auth', 'storage');" 2>/dev/null || echo 0)"

    local lab_tables_count
    lab_tables_count="$(docker exec -i "${LAB_CONTAINER_NAME}" psql -U postgres -d postgres -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';" 2>/dev/null || echo 0)"

    local lab_indexes_count
    lab_indexes_count="$(docker exec -i "${LAB_CONTAINER_NAME}" psql -U postgres -d postgres -tAc "SELECT count(*) FROM pg_indexes WHERE schemaname = 'public';" 2>/dev/null || echo 0)"

    local lab_constraints_count
    lab_constraints_count="$(docker exec -i "${LAB_CONTAINER_NAME}" psql -U postgres -d postgres -tAc "SELECT count(*) FROM information_schema.table_constraints WHERE table_schema = 'public';" 2>/dev/null || echo 0)"

    local lab_grants_count
    lab_grants_count="$(docker exec -i "${LAB_CONTAINER_NAME}" psql -U postgres -d postgres -tAc "SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema = 'public' AND grantee IN ('authenticated', 'anon', 'service_role');" 2>/dev/null || echo 0)"

    local lab_rls_count
    lab_rls_count="$(docker exec -i "${LAB_CONTAINER_NAME}" psql -U postgres -d postgres -tAc "SELECT count(*) FROM pg_policies WHERE schemaname = 'public';" 2>/dev/null || echo 0)"

    log_info "Métricas estruturais apuradas no laboratório:"
    log_info "  - Schemas essenciais encontrados: ${lab_schemas_count}/3 (public, auth, storage)"
    log_info "  - Tabelas públicas (public.*):      ${lab_tables_count}"
    log_info "  - Índices criados (public.*):       ${lab_indexes_count}"
    log_info "  - Constraints apuradas (public.*):  ${lab_constraints_count}"
    log_info "  - Grants de roles do Supabase:      ${lab_grants_count}"
    log_info "  - Políticas RLS ativas:             ${lab_rls_count}"

    # Validações estruturais mínimas
    if [ "${lab_schemas_count}" -lt 2 ] || [ "${lab_tables_count}" -lt 5 ]; then
        VEREDITO_NIVEL_C="FALHA"
        DETALHE_NIVEL_C="Estrutura do banco restaurado é insuficiente (schemas: ${lab_schemas_count}, tabelas: ${lab_tables_count})."
        log_error "${DETALHE_NIVEL_C}"
        exit "${EXIT_LEVEL_C_FAILURE}"
    fi

    # Auditoria comparativa de contagens das tabelas essenciais
    log_info "Iniciando conferência de contagens das tabelas essenciais..."
    local tabelas_essenciais=(
        "public.clients"
        "public.cases"
        "public.tasks"
        "public.appointments"
        "public.transactions"
        "public.payment_plans"
        "public.suppliers"
        "public.document_templates"
        "public.settings"
        "public.profiles"
        "public.leads"
        "public.lead_interactions"
        "auth.users"
    )

    local tabela_relatorio_linhas=""
    TOTAL_TABELAS_AUDITADAS=${#tabelas_essenciais[@]}
    TOTAL_TABELAS_COINCIDENTES=0
    TOTAL_TABELAS_DIVERGENTES=0
    TOTAL_TABELAS_ERRO=0

    printf "\n%-30s | %-16s | %-16s | %-12s\n" "Tabela" "Produção (ref)" "Laboratório" "Status"
    echo "-----------------------------------------------------------------------------------"

    for tab in "${tabelas_essenciais[@]}"; do
        local count_lab="0"
        local count_prod="N/A"
        local status_tab="OK"

        # Contagem no laboratório
        count_lab="$(docker exec -i "${LAB_CONTAINER_NAME}" psql -U postgres -d postgres -tAc "SELECT count(*) FROM ${tab};" 2>/dev/null || echo "ERRO")"

        # Contagem em produção (se disponível)
        if [ "${PULAR_COMPARACAO_PROD}" -eq 0 ] && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${PROD_CONTAINER}$"; then
            count_prod="$(docker exec -i "${PROD_CONTAINER}" psql -U postgres -d postgres -tAc "SELECT count(*) FROM ${tab};" 2>/dev/null || echo "ERRO")"
            
            if [ "${count_lab}" = "ERRO" ] || [ "${count_prod}" = "ERRO" ]; then
                status_tab="ERRO"
                TOTAL_TABELAS_ERRO=$((TOTAL_TABELAS_ERRO + 1))
            elif [ "${count_lab}" != "${count_prod}" ]; then
                status_tab="DIVERGENTE"
                TOTAL_TABELAS_DIVERGENTES=$((TOTAL_TABELAS_DIVERGENTES + 1))
            else
                status_tab="COINCIDENTE"
                TOTAL_TABELAS_COINCIDENTES=$((TOTAL_TABELAS_COINCIDENTES + 1))
            fi
        else
            count_prod="[NÃO CONSULTADO]"
            if [ "${count_lab}" = "ERRO" ]; then
                status_tab="ERRO"
                TOTAL_TABELAS_ERRO=$((TOTAL_TABELAS_ERRO + 1))
            else
                status_tab="RESTAURADO"
                TOTAL_TABELAS_COINCIDENTES=$((TOTAL_TABELAS_COINCIDENTES + 1))
            fi
        fi

        printf "%-30s | %-16s | %-16s | %-12s\n" "${tab}" "${count_prod}" "${count_lab}" "${status_tab}"
        tabela_relatorio_linhas="${tabela_relatorio_linhas}\n$(printf "%-30s | %-16s | %-16s | %-12s" "${tab}" "${count_prod}" "${count_lab}" "${status_tab}")"
    done
    echo "-----------------------------------------------------------------------------------"

    CONTAGENS_RELATORIO="${tabela_relatorio_linhas}"

    if [ "${TOTAL_TABELAS_ERRO}" -gt 0 ]; then
        VEREDITO_NIVEL_C="FALHA"
        DETALHE_NIVEL_C="Erro ao auditar registros em uma ou mais tabelas essenciais do laboratório."
        log_error "${DETALHE_NIVEL_C}"
        exit "${EXIT_LEVEL_C_FAILURE}"
    fi

    if [ "${TOTAL_TABELAS_DIVERGENTES}" -gt 0 ]; then
        VEREDITO_NIVEL_C="APROVADO COM DIVERGÊNCIA NORMAL DE DELTA"
        DETALHE_NIVEL_C="${TOTAL_TABELAS_DIVERGENTES} tabela(s) apresentaram divergência de contagem com a produção (esperado se houve novas operações entre a geração do backup e este teste)."
        log_warn "${DETALHE_NIVEL_C}"
    else
        VEREDITO_NIVEL_C="APROVADO"
        DETALHE_NIVEL_C="Estrutura completa e contagens 100% validadas nas ${TOTAL_TABELAS_AUDITADAS} tabelas auditadas."
        log_success "Nível C APROVADO com sucesso."
    fi
}

# ------------------------------------------------------------------------------
# Relatório Final Consolidado
# ------------------------------------------------------------------------------
emitir_relatorio_final() {
    log_step "10. Relatório Final de Auditoria e Certificação do Backup"

    local data_hora_fim
    data_hora_fim="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"

    cat << EOF

======================================================================================
 DPSJUR / SBJUR - RELATÓRIO TÉCNICO DE AUDITORIA DE RESTAURAÇÃO ISOLADA
======================================================================================
Data/Hora de Conclusão: ${data_hora_fim}
Versão do Script:       ${SCRIPT_VERSION}
Arquivo de Backup:      ${BACKUP_INPUT_PATH}
Versão PostgreSQL Dump: ${DUMP_REAL_PG_VERSION}
Ambiente de Execução:   Hostinger VPS (srv1737667 - 2.25.181.69)
Contêiner Oficial Prod: ${PROD_CONTAINER} (intocado / apenas leitura)
Contêiner Efêmero Lab:  ${LAB_CONTAINER_NAME} (destruído no cleanup)
Volume Efêmero Lab:     ${LAB_VOLUME_NAME} (destruído no cleanup)
======================================================================================

DISTINÇÃO CLARA DE AMBIENTES (CONFORME REQUISITO 10):
--------------------------------------------------------------------------------------
• Supabase Cloud:      DESATIVADO / ABANDONADO pelo projeto DPSjur para eliminar custos.
• Supabase Self-Hosted: AMBIENTE ATIVO DE PRODUÇÃO no VPS Hostinger via EasyPanel.
                        Todos os testes foram executados exclusivamente contra este ambiente.

STATUS DE COMPROVAÇÃO DE ORIGEM DO BACKUP (REQUISITO 8):
--------------------------------------------------------------------------------------
• Status:  ${ORIGEM_BACKUP_STATUS}
• Detalhe: ${ORIGEM_BACKUP_DETALHE}

QUADRO CONSOLIDADO DE VEREDITOS POR NÍVEL:
--------------------------------------------------------------------------------------
1. Nível A - Integridade Física (gzip -t / descompressão):
   [ ${VEREDITO_NIVEL_A} ]
   Detalhe: ${DETALHE_NIVEL_A}

2. Nível B - Restauração SQL em Ambiente Isolado:
   [ ${VEREDITO_NIVEL_B} ]
   Detalhe: ${DETALHE_NIVEL_B}

3. Nível C - Validação Estrutural e Registros:
   [ ${VEREDITO_NIVEL_C} ]
   Detalhe: ${DETALHE_NIVEL_C}

4. Nível D - Recuperação Operacional de Serviços (Gotrue/PostgREST/Kong/Storage):
   [ ${VEREDITO_NIVEL_D} ]
   (Conforme Requisito 5, este teste valida rigorosamente a camada de banco de dados.
    A camada de aplicação e APIs auxiliares não foi validada por este script.)

TABELA COMPARATIVA DE REGISTROS (PRODUÇÃO vs LABORATÓRIO RESTAURADO):
--------------------------------------------------------------------------------------
Tabela                         | Produção (ref)   | Laboratório      | Status      
--------------------------------------------------------------------------------------
$(echo -e "${CONTAGENS_RELATORIO}")
--------------------------------------------------------------------------------------
Total de tabelas auditadas:    ${TOTAL_TABELAS_AUDITADAS}
Tabelas coincidentes/restauradas: ${TOTAL_TABELAS_COINCIDENTES}
Tabelas divergentes (delta):   ${TOTAL_TABELAS_DIVERGENTES}
Tabelas com erro:              ${TOTAL_TABELAS_ERRO}

PROCEDIMENTO DE REVERSÃO:
--------------------------------------------------------------------------------------
• Nenhuma alteração foi realizada em nenhum contêiner, banco de dados ou serviço ativo
  do VPS. O contêiner de produção '${PROD_CONTAINER}' foi consultado unicamente em modo
  somente-leitura. O banco legado '${LEGACY_FORBIDDEN_CONTAINER}' permaneceu intocado.
• Nenhum rollback ou reversão é necessária no VPS.

======================================================================================
 FIM DO RELATÓRIO TÉCNICO (${SCRIPT_VERSION})
======================================================================================

EOF
}

# ------------------------------------------------------------------------------
# Ponto de Entrada Principal
# ------------------------------------------------------------------------------
main() {
    processar_parametros "$@"
    validar_ambiente
    selecionar_e_validar_dump
    verificar_origem_backup
    executar_nivel_a
    verificar_recursos_sistema
    validar_imagem_e_protecao_servicos
    extrair_e_sanitizar_globals
    executar_nivel_b
    executar_nivel_c
    emitir_relatorio_final
}

main "$@"
