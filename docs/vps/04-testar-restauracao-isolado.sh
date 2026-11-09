#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur — Fase 6: Teste de restauração de backup PostgreSQL em
#                          contêiner Docker EFÊMERO e ISOLADO, 100% local no VPS
# Script:   docs/vps/04-testar-restauracao-isolado.sh
# Versão:   v2.4.0
#
# HISTÓRICO
#   v2.2.0-r1 : proposta inicial (isolamento completo, roles via pg_dumpall -g).
#   v2.3.0    : versão auditada pelo usuário; o trabalho de correção ficou
#               mapeado, porém NÃO consolidado/persistido (commit v0.0.659).
#   v2.4.0    : ESTA versão — consolida as 5 correções exigidas pela auditoria
#               independente (nenhuma outra funcionalidade alterada):
#        (1) FIM do fallback de roles genéricas. Falha na EXTRAÇÃO
#            (pg_dumpall --globals-only) ou na CARGA/verificação das roles
#            reais da produção INTERROMPE o teste imediatamente com exit code
#            próprio (EXIT_ROLES_EXTRACT_FAILED=30 / EXIT_ROLES_RESTORE_
#            FAILED=31). Nenhuma role genérica/sintética é criada em nenhuma
#            hipótese, e o relatório jamais declara "recuperação fiel" nesse
#            cenário. A ÚNICA exceção tolerada na carga é duplicate_object
#            (role já existente na imagem); qualquer outra exceção SQL propaga
#            e aborta o teste.
#        (2) ORIGEM_DO_BACKUP = "NÃO COMPROVADA" por padrão. Checksum (sha256),
#            nome, tamanho, mtime e mera existência de metadados atestam
#            APENAS integridade física do ARQUIVO, não a identidade do banco
#            de origem do dump. O status só muda para "COMPROVADA" se existir
#            um manifesto gerado NO MOMENTO DA CRIAÇÃO do backup (pelo próprio
#            rotineiro de backup, com hash + identidade do banco de origem)
#            e verificável contra o arquivo atual. A rotina de backup atual
#            (docs/backup-fase6/01-instalar-backup.sh) NÃO gera esse manifesto,
#            portanto o status permanece NÃO COMPROVADA em toda execução real.
#        (3) SUPRESSÃO de erro SQL sensível: NENHUM trecho de mensagem de erro
#            SQL (que pode conter dados, nomes de tabelas/colunas, valores)
#            é impresso no terminal stdout/stderr ou incluído no relatório.
#            Todo stderr de psql/pg_dumpall/gunzip/docker vai EXCLUSIVAMENTE ao
#            log técnico restrito (arquivo chmod 600 dentro de diretório
#            chmod 700). Console e relatório exibem apenas: código de erro,
#            etapa da falha e o CAMINHO do log restrito.
#        (4) DELIMITAÇÃO do escopo da validação estrutural: o relatório NÃO
#            declara validação "completa". Diferencia explicitamente o que foi
#            CONFERIDO (contagens) — existência de schemas, tabelas, índices,
#            constraints, políticas RLS, funções e sequências + contagens de
#            registros comparadas com a produção — do que permanece NÃO
#            VALIDADO — integridade profunda/conteúdo linha a linha,
#            constraints de dados reavaliadas, estado de sequências, execução
#            de funções, gatilhos, visões etc.
#        (5) IDENTIDADE dos recursos Docker no cleanup: antes de remover
#            container/volume, o script confere o NOME EXATO desta sessão
#            (^sbjur-restore-lab-<PID>$ / ^sbjur-restore-lab-data-<PID>$) E a
#            label de sessão (sbjur-restore-lab-session=<PID>); divergência de
#            identidade ⇒ o recurso NÃO é tocado. Falhas de limpeza (rm que
#            falhou, arquivo que não sumiu, recurso remanescente) são
#            CAPTURADAS e REPORTADAS no console e no relatório — nunca
#            engolidas por `|| true` silencioso. Nenhum outro container ou
#            volume do VPS é afetado; dpsjur-db não é referenciado.
#
# O QUE O SCRIPT FAZ
#   - Seleciona o arquivo de backup (.sql.gz) a testar (argumento ou menu).
#   - Calcula checksum sha256 (integridade física) e avalia a ORIGEM do backup
#     conforme a correção (2).
#   - Localiza o contêiner de PRODUÇÃO (por padrão sbljur-local_supabase-db-1,
#     com alternativa sbjur-local_supabase-db-1; dpsjur-db está EXCLUÍDO de
#     qualquer detecção) e faz inspeção EXCLUSIVAMENTE só-leitura.
#   - Extrai as roles reais da produção (pg_dumpall --globals-only, só-leitura)
#     e as sanitiza (corr. 1: só duplicate_object tolerado).
#   - Sobe um contêiner PostgreSQL EFÊMERO (--network none, volume dedicado
#     com label de sessão, memória limitada) na mesma versão major da
#     produção, carrega as roles reais e restaura o dump dentro dele.
#   - Valida catálogo + contagens de registros contra a produção, com rótulos
#     "CONFERIDO (contagens)" vs "NÃO VALIDADO" (corr. 4).
#   - Remove os recursos do laboratório conferindo IDENTIDADE (corr. 5) e
#     emite relatório em arquivo restrito (chmod 600) + resumo seguro no console.
#
# COMO EXECUTAR (no VPS; NÃO usar via curl|bash — baixar o arquivo primeiro):
#   bash 04-testar-restauracao-isolado.sh /root/sbjur-backups/diario/sbjur_backup_YYYYMMDD.sql.gz
#   (sem argumento, lista os backups disponíveis e pergunta qual testar)
#
# CÓDIGOS DE SAÍDA
#    0  EXIT_OK                    sucesso (ver observações do relatório)
#   10  EXIT_USAGE                 uso inválido / sem backup selecionado
#   11  EXIT_DOCKER_UNAVAILABLE    docker indisponível ou falha ao criar recursos
#   12  EXIT_LAB_IMAGE_UNAVAILABLE imagem base do laboratório não obtida
#   13  EXIT_LAB_NOT_READY         laboratório não ficou pronto no tempo limite
#   20  EXIT_BACKUP_NOT_FOUND      nenhum backup localizado
#   21  EXIT_BACKUP_INVALID        arquivo de backup inválido/corrompido
#   30  EXIT_ROLES_EXTRACT_FAILED  falha ao EXTRAIR/sanitizar roles da produção (ABORTA)
#   31  EXIT_ROLES_RESTORE_FAILED  falha ao CARREGAR/verificar roles no lab (ABORTA)
#   40  EXIT_RESTORE_FAILED        falha na restauração do dump no laboratório
#   50  EXIT_VALIDATION_FAILED     divergências estruturais de contagem
#   60  EXIT_CLEANUP_FAILED        limpeza não foi 100% (recursos remanescentes)
#  130  interrompido pelo usuário (SIGINT/SIGTERM)
#
# ATENÇÃO: nenhum comando deste script altera a produção. Todas as consultas à
# produção são somente leitura (SELECT/catálogo/pg_dumpall -g). O contêiner
# dpsjur-db NÃO é referenciado em nenhum comando deste script.
# ==============================================================================

set -u -o pipefail

# ------------------------------------------------------------------ constantes
SCRIPT_VERSION="v2.4.0"
BACKUP_ROOT="/root/sbjur-backups"
DIAG_DIR="${BACKUP_ROOT}/logs/diagnostico-restauracao"   # restrito (chmod 700)
TS_STAMP="$(date +%Y%m%d-%H%M%S)"

LOG_FILE="${DIAG_DIR}/lab-execucao-${TS_STAMP}-$$.log"
REPORT_FILE="${DIAG_DIR}/relatorio-teste-${TS_STAMP}-$$.txt"
GLOBALS_RAW_FILE="${DIAG_DIR}/globals-brutos-${TS_STAMP}-$$.sql"
GLOBALS_SANITIZED_FILE="${DIAG_DIR}/globals-sanitizados-${TS_STAMP}-$$.sql"
EXPECTED_ROLES_FILE="${DIAG_DIR}/roles-esperadas-${TS_STAMP}-$$.txt"
LAB_ROLES_FILE="${DIAG_DIR}/roles-lab-${TS_STAMP}-$$.txt"
DIVERGENCES_FILE="${DIAG_DIR}/divergencias-contagem-${TS_STAMP}-$$.txt"
CONFERIDOS_FILE="${DIAG_DIR}/conferidos-contagem-${TS_STAMP}-$$.txt"

LAB_NAME_PREFIX="sbjur-restore-lab-"
LAB_NAME="${LAB_NAME_PREFIX}$$"                    # nome único desta sessão (PID)
LAB_VOLUME="sbjur-restore-lab-data-$$"             # volume dedicado desta sessão
LAB_LABEL="sbjur-restore-lab-session"              # label de identidade do recurso
LAB_LABEL_VALUE="$$"
PROD_CONTAINER_ENV="${PROD_CONTAINER:-}"
# Candidatos EXATOS de produção (inspeção só-leitura). dpsjur-db está
# deliberadamente EXCLUÍDO de qualquer detecção.
PROD_CONTAINER_CANDIDATES="sbljur-local_supabase-db-1 sbjur-local_supabase-db-1"
PROD_CONTAINER=""
LAB_IMAGE="${LAB_IMAGE:-}"
LAB_WAIT_SECONDS="${LAB_WAIT_SECONDS:-300}"
LAB_MEMORY_LIMIT="${LAB_MEMORY_LIMIT:-2g}"
LAB_SHM_SIZE="${LAB_SHM_SIZE:-256m}"

EXIT_OK=0
EXIT_USAGE=10
EXIT_DOCKER_UNAVAILABLE=11
EXIT_LAB_IMAGE_UNAVAILABLE=12
EXIT_LAB_NOT_READY=13
EXIT_BACKUP_NOT_FOUND=20
EXIT_BACKUP_INVALID=21
EXIT_ROLES_EXTRACT_FAILED=30
EXIT_ROLES_RESTORE_FAILED=31
EXIT_RESTORE_FAILED=40
EXIT_VALIDATION_FAILED=50
EXIT_CLEANUP_FAILED=60

# ------------------------------------------------------------- estado global
RESULT_BACKUP="NÃO EXECUTADO"
RESULT_CHECKSUM="NÃO CALCULADO"
CHECKSUM_SHA256=""
ORIGEM_BACKUP_STATUS="NÃO COMPROVADA"     # (correção 2) padrão seguro
ORIGEM_DETALHE="Nenhum manifesto de criação verificado."
RESULT_ROLES="NÃO EXECUTADO"
RESULT_RESTORE="NÃO EXECUTADO"
ESTRUTURAL_STATUS="NÃO REALIZADA"
ESTRUTURAL_RESUMO=""
CONFERIDOS_COUNT=0
DIVERGENCES_COUNT=0
CLEANUP_OK=1
CLEANUP_STATUS="PENDENTE"
CLEANUP_OBS=""
PROD_CONTAINER="(não localizado)"
PROD_DB_IDENTIDADE="NÃO OBTIDA"

# --------------------------------------------------- preparação de arquivos
mkdir -p "${DIAG_DIR}" 2>/dev/null || true
chmod 700 "${DIAG_DIR}" 2>/dev/null || true
: > "${LOG_FILE}" 2>/dev/null || {
    echo "ERRO FATAL: não foi possível criar o log restrito em ${LOG_FILE}." >&2
    exit "${EXIT_DOCKER_UNAVAILABLE}"
}
chmod 600 "${LOG_FILE}" 2>/dev/null || true
touch "${REPORT_FILE}" "${DIVERGENCES_FILE}" "${CONFERIDOS_FILE}" 2>/dev/null || true
chmod 600 "${REPORT_FILE}" "${DIVERGENCES_FILE}" "${CONFERIDOS_FILE}" 2>/dev/null || true

# ------------------------------------------------------------------- helpers
# log(): registro técnico COMPLETO (pode conter stderr/SQL) — APENAS arquivo
# restrito chmod 600 dentro de diretório chmod 700. Nunca vai ao console.
log() {
    printf '%s %s\n' "$(date '+%F %T')" "$*" >> "${LOG_FILE}"
}

# say(): saída de console — SOMENTE texto seguro, jamais conteúdo de erro SQL.
say() {
    printf '%s\n' "$*"
}

# die(): encerra com mensagem genérica (sem conteúdo de erro) e exit code próprio.
die() {
    local msg="$1" code="$2"
    say "❌ ${msg}"
    say "   Detalhe técnico completo restrito a: ${LOG_FILE}"
    log "ABORTADO (exit ${code}): ${msg}"
    exit "${code}"
}

run_psql_prod() {
    # somente leitura na produção; stderr vai ao log restrito
    if command -v timeout >/dev/null 2>&1; then
        timeout 60 docker exec "${PROD_CONTAINER}" psql -U postgres -d postgres -tAc "$1" 2>>"${LOG_FILE}"
    else
        docker exec "${PROD_CONTAINER}" psql -U postgres -d postgres -tAc "$1" 2>>"${LOG_FILE}"
    fi
}

run_psql_lab() {
    docker exec "${LAB_NAME}" psql -U postgres -d postgres -tAc "$1" 2>>"${LOG_FILE}"
}

on_interrupt() {
    say "⚠️ Execução interrompida pelo usuário (sinal recebido)."
    exit 130
}
trap on_interrupt INT TERM

# --------------------------------------------------- seleção do arquivo alvo
BACKUP_FILE="${1:-}"

if [ -z "${BACKUP_FILE}" ]; then
    say "Nenhum arquivo de backup informado como argumento."
    say "Buscando candidatos em ${BACKUP_ROOT}/{diario,semanal,mensal} ..."
    CANDIDATES="$(ls -1t \
        "${BACKUP_ROOT}"/diario/sbjur_backup_*.sql.gz \
        "${BACKUP_ROOT}"/semanal/sbjur_backup_*.sql.gz \
        "${BACKUP_ROOT}"/mensal/sbjur_backup_*.sql.gz 2>/dev/null || true)"
    if [ -z "${CANDIDATES}" ]; then
        say "❌ Nenhum backup encontrado. Informe o caminho do arquivo como argumento."
        exit "${EXIT_BACKUP_NOT_FOUND}"
    fi
    if [ ! -t 0 ] && [ ! -r /dev/tty ]; then
        say "❌ Execução não interativa exige o caminho do backup como argumento:"
        say "   bash $0 /root/sbjur-backups/diario/sbjur_backup_AAAAMMDD.sql.gz"
        exit "${EXIT_USAGE}"
    fi
    say ""
    say "Backups disponíveis (mais recente primeiro):"
    n=0
    while IFS= read -r f; do
        n=$((n + 1))
        say "  ${n}. ${f}"
    done <<< "${CANDIDATES}"
    CHOICE=""
    if [ -t 0 ]; then
        printf 'Digite o número do backup a testar: '
        read -r CHOICE
    else
        exec 3</dev/tty
        printf 'Digite o número do backup a testar: ' >&2
        read -r CHOICE <&3
        exec 3<&-
    fi
    case "${CHOICE}" in
        ''|*[!0-9]*)
            say "❌ Escolha inválida."
            exit "${EXIT_USAGE}"
            ;;
    esac
    BACKUP_FILE="$(printf '%s\n' "${CANDIDATES}" | sed -n "${CHOICE}p")"
    if [ -z "${BACKUP_FILE}" ]; then
        say "❌ Escolha inválida."
        exit "${EXIT_USAGE}"
    fi
fi

log "=== SBJur — teste de restauração isolado ${SCRIPT_VERSION} (PID $$) ==="
log "Backup selecionado: ${BACKUP_FILE}"

if [ ! -f "${BACKUP_FILE}" ] || [ ! -r "${BACKUP_FILE}" ]; then
    say "❌ Arquivo de backup não encontrado ou sem permissão de leitura: ${BACKUP_FILE}"
    exit "${EXIT_BACKUP_NOT_FOUND}"
fi

BACKUP_BYTES="$(stat -c%s "${BACKUP_FILE}" 2>>"${LOG_FILE}" || echo 0)"
if [ "${BACKUP_BYTES}" -le 1000 ] 2>/dev/null; then
    say "❌ Arquivo de backup com tamanho insignificante (${BACKUP_BYTES} bytes). Provável dump falho."
    exit "${EXIT_BACKUP_INVALID}"
fi

# Teste de integridade física do gzip (stderr → log restrito)
if ! gzip -t "${BACKUP_FILE}" 2>>"${LOG_FILE}"; then
    say "❌ Arquivo de backup NÃO passa no teste de integridade gzip (corrompido ou truncado)."
    say "   Detalhe técnico completo restrito a: ${LOG_FILE}"
    exit "${EXIT_BACKUP_INVALID}"
fi

BACKUP_SIZE_H="$(du -h "${BACKUP_FILE}" 2>/dev/null | awk '{print $1}' || echo 'N/A')"
RESULT_BACKUP="${BACKUP_FILE} (${BACKUP_SIZE_H}, ${BACKUP_BYTES} bytes)"

# --------------------------- (correção 2) checksum = integridade FÍSICA apenas
if command -v sha256sum >/dev/null 2>&1; then
    CHECKSUM_SHA256="$(sha256sum "${BACKUP_FILE}" 2>>"${LOG_FILE}" | awk '{print $1}')"
    if [ -n "${CHECKSUM_SHA256}" ]; then
        RESULT_CHECKSUM="sha256: ${CHECKSUM_SHA256}"
    else
        RESULT_CHECKSUM="FALHA AO CALCULAR (ver log restrito)"
    fi
else
    CHECKSUM_SHA256=""
    RESULT_CHECKSUM="NÃO CALCULADO (sha256sum indisponível neste sistema)"
fi
log "Checksum calculado (integridade física): ${RESULT_CHECKSUM}"

# Status de ORIGEM (correção 2): muda de NÃO COMPROVADA APENAS se existir
# manifesto gerado NO MOMENTO da criação do backup (hash + identidade do banco
# de origem) e o hash do manifesto conferir com o arquivo atual. Nome do
# arquivo, mtime, tamanho e checksum sozinhos NÃO comprovam origem.
ORIGEM_BACKUP_STATUS="NÃO COMPROVADA"
ORIGEM_DETALHE="Checksum e metadados de arquivo atestam apenas integridade física; não comprovam a identidade do banco de origem."
BASE_NAME="$(basename "${BACKUP_FILE}")"
for MF in \
    "${BACKUP_FILE}.manifesto" \
    "${BACKUP_FILE}.manifest" \
    "${BACKUP_FILE}.sha256" \
    "${BACKUP_ROOT}/manifestos/${BASE_NAME}.manifesto"; do
    if [ -f "${MF}" ]; then
        MF_SHA="$(awk 'NR==1 {print tolower($1); exit}' "${MF}" 2>>"${LOG_FILE}")"
        if [ -n "${MF_SHA}" ] && [ -n "${CHECKSUM_SHA256}" ] && [ "${MF_SHA}" = "${CHECKSUM_SHA256}" ]; then
            if grep -qiE 'banco[_ ]origem|database|origem|container' "${MF}" 2>>"${LOG_FILE}"; then
                ORIGEM_BACKUP_STATUS="COMPROVADA (manifesto gerado na criação do backup; hash e identidade do banco de origem conferidos)"
                ORIGEM_DETALHE="Manifesto de criação: ${MF}"
            else
                ORIGEM_BACKUP_STATUS="NÃO COMPROVADA (manifesto presente, porém sem registro de identidade do banco de origem)"
                ORIGEM_DETALHE="Manifesto presente (${MF}) com hash conferido, porém sem identidade do banco de origem."
            fi
        else
            ORIGEM_BACKUP_STATUS="NÃO COMPROVADA (manifesto presente, porém hash DIVERGENTE do arquivo atual)"
            ORIGEM_DETALHE="Manifesto: ${MF}. O arquivo atual não corresponde ao registrado na criação."
        fi
        break
    fi
done
log "ORIGEM_BACKUP_STATUS: ${ORIGEM_BACKUP_STATUS}"

# --------------------------------------------------------- preflight docker
if ! command -v docker >/dev/null 2>&1; then
    say "❌ Docker não está instalado ou não está no PATH. Teste não pode ser executado."
    exit "${EXIT_DOCKER_UNAVAILABLE}"
fi
if ! docker info >>"${LOG_FILE}" 2>&1; then
    say "❌ Docker indisponível (sem permissão ou daemon parado). Teste não pode ser executado."
    say "   Detalhe técnico completo restrito a: ${LOG_FILE}"
    exit "${EXIT_DOCKER_UNAVAILABLE}"
fi

# --------------------------- localização do contêiner de produção (só-leitura)
find_prod_container() {
    local c
    if [ -n "${PROD_CONTAINER_ENV}" ]; then
        if docker ps --format '{{.Names}}' 2>>"${LOG_FILE}" | grep -qx -- "${PROD_CONTAINER_ENV}"; then
            PROD_CONTAINER="${PROD_CONTAINER_ENV}"
        fi
        return
    fi
    for c in ${PROD_CONTAINER_CANDIDATES}; do
        if docker ps --format '{{.Names}}' 2>>"${LOG_FILE}" | grep -qx -- "${c}"; then
            PROD_CONTAINER="${c}"
            return
        fi
    done
    # Fallback por padrão de nome, SEMPRE excluindo dpsjur-db (intocado) e o
    # próprio laboratório desta ou de outras sessões.
    PROD_CONTAINER="$(docker ps --format '{{.Names}}' 2>>"${LOG_FILE}" \
        | grep -E 'supabase-db' \
        | grep -v -E "^dpsjur-db$|^${LAB_NAME_PREFIX}" \
        | head -n 1 || true)"
}

find_prod_container
if [ -z "${PROD_CONTAINER}" ]; then
    # (correção 1) sem produção acessível não há como extrair roles reais:
    # ABORTA — sem fallback para roles genéricas.
    die "Contêiner de produção de banco não localizado (padrões: ${PROD_CONTAINER_CANDIDATES}). Sem acesso às roles reais da produção o teste NÃO prossegue — nenhuma role genérica/sintética é utilizada." "${EXIT_ROLES_EXTRACT_FAILED}"
fi
log "Contêiner de produção (inspeção só-leitura): ${PROD_CONTAINER}"

PROD_DB_IDENTIDADE="$(run_psql_prod "SELECT current_database() || ' @ ' || COALESCE(inet_server_addr()::text,'socket-local')" | head -n 1 || true)"
[ -n "${PROD_DB_IDENTIDADE}" ] || PROD_DB_IDENTIDADE="NÃO OBTIDA (ver log restrito)"
log "Identidade do banco de produção: ${PROD_DB_IDENTIDADE}"

# ======================= (correção 1) EXTRAÇÃO DAS ROLES REAIS DA PRODUÇÃO ===
# Sem isso o teste é abortado. Nenhuma role genérica/de fallback é criada.
say "🔑 Extraindo roles reais da produção (pg_dumpall --globals-only, só-leitura)..."
if ! docker exec "${PROD_CONTAINER}" pg_dumpall -U postgres --globals-only \
        > "${GLOBALS_RAW_FILE}" 2>>"${LOG_FILE}"; then
    RESULT_ROLES="FALHA NA EXTRAÇÃO (pg_dumpall --globals-only) — teste interrompido"
    die "Falha ao EXTRAIR as roles reais da produção. O teste foi INTERROMPIDO (exit ${EXIT_ROLES_EXTRACT_FAILED}). Nenhuma role de fallback foi utilizada e nenhuma restauração foi declarada fiel." "${EXIT_ROLES_EXTRACT_FAILED}"
fi
chmod 600 "${GLOBALS_RAW_FILE}" 2>/dev/null || true

if [ ! -s "${GLOBALS_RAW_FILE}" ]; then
    RESULT_ROLES="FALHA NA EXTRAÇÃO (arquivo de globals vazio) — teste interrompido"
    die "A extração das roles da produção retornou conteúdo vazio. O teste foi INTERROMPIDO (exit ${EXIT_ROLES_EXTRACT_FAILED})." "${EXIT_ROLES_EXTRACT_FAILED}"
fi

# Sanitização (arquivo restrito):
#   - remove CREATE/ALTER DATABASE, COMMENT ON DATABASE, ALTER ROLE ... IN
#     DATABASE (referenciam bancos inexistentes no laboratório) e linhas
#     psql iniciadas por '\' (\connect, \restrict, \unrestrict, \password);
#   - envolve CREATE ROLE em bloco DO que tolera EXCLUSIVAMENTE a exceção
#     duplicate_object (role já existente na imagem). Qualquer OUTRA exceção
#     propaga e interrompe o teste (correção 1).
if ! grep -vE '^[[:space:]]*(CREATE DATABASE|ALTER DATABASE|COMMENT ON DATABASE|ALTER ROLE[^;]*IN DATABASE|\\)' \
            "${GLOBALS_RAW_FILE}" 2>>"${LOG_FILE}" \
    | sed -E 's|^([[:space:]]*CREATE ROLE[^;]+);[[:space:]]*$|DO $$BEGIN \1; EXCEPTION WHEN duplicate_object THEN NULL; END$$;|' \
    > "${GLOBALS_SANITIZED_FILE}" 2>>"${LOG_FILE}"; then
    RESULT_ROLES="FALHA NA SANITIZAÇÃO DOS GLOBALS — teste interrompido"
    die "Falha ao sanitizar o arquivo de globals. O teste foi INTERROMPIDO (exit ${EXIT_ROLES_EXTRACT_FAILED})." "${EXIT_ROLES_EXTRACT_FAILED}"
fi
chmod 600 "${GLOBALS_SANITIZED_FILE}" 2>/dev/null || true

if [ ! -s "${GLOBALS_SANITIZED_FILE}" ]; then
    RESULT_ROLES="FALHA NA SANITIZAÇÃO DOS GLOBALS (resultado vazio) — teste interrompido"
    die "A sanitização das roles resultou em arquivo vazio. O teste foi INTERROMPIDO (exit ${EXIT_ROLES_EXTRACT_FAILED})." "${EXIT_ROLES_EXTRACT_FAILED}"
fi

# ================================================================ LABORATÓRIO
# Mesma versão major da produção; isolamento total: --network none, volume
# dedicado desta sessão, contêiner com label de identidade.
say "🔎 Detectando versão major do PostgreSQL de produção..."
PROD_MAJOR="$(run_psql_prod 'SHOW server_version' | head -n 1 | awk -F. '{print $1}' | tr -d '[:space:]')"
if [ -z "${PROD_MAJOR}" ]; then
    PROD_MAJOR="18"
    log "Versão de produção não detectável; assumindo major ${PROD_MAJOR} (ver log)."
fi
if [ -z "${LAB_IMAGE}" ]; then
    LAB_IMAGE="postgres:${PROD_MAJOR}"
fi
say "🐳 Imagem do laboratório: ${LAB_IMAGE} (rede: nenhuma — isolamento total)"

if ! docker image inspect "${LAB_IMAGE}" >>"${LOG_FILE}" 2>&1; then
    say "ℹ️ Imagem ${LAB_IMAGE} ausente localmente; efetuando docker pull..."
    if ! docker pull "${LAB_IMAGE}" >>"${LOG_FILE}" 2>&1; then
        die "Não foi possível obter a imagem base do laboratório (${LAB_IMAGE}). O teste foi INTERROMPIDO (exit ${EXIT_LAB_IMAGE_UNAVAILABLE})." "${EXIT_LAB_IMAGE_UNAVAILABLE}"
    fi
fi

say "📦 Criando volume dedicado do laboratório: ${LAB_VOLUME}"
if ! docker volume create --label "${LAB_LABEL}=${LAB_LABEL_VALUE}" "${LAB_VOLUME}" >>"${LOG_FILE}" 2>&1; then
    die "Falha ao criar o volume do laboratório. O teste foi INTERROMPIDO (exit ${EXIT_DOCKER_UNAVAILABLE})." "${EXIT_DOCKER_UNAVAILABLE}"
fi

say "🚀 Subindo contêiner efêmero do laboratório: ${LAB_NAME}"
if ! docker run -d \
        --name "${LAB_NAME}" \
        --network none \
        --restart no \
        --label "${LAB_LABEL}=${LAB_LABEL_VALUE}" \
        --memory "${LAB_MEMORY_LIMIT}" \
        --shm-size "${LAB_SHM_SIZE}" \
        -e POSTGRES_USER=postgres \
        -e POSTGRES_PASSWORD=lab-sbjur-recovery-unico-$$ \
        -e POSTGRES_DB=postgres \
        -v "${LAB_VOLUME}:/var/lib/postgresql" \
        "${LAB_IMAGE}" >>"${LOG_FILE}" 2>&1; then
    die "Falha ao iniciar o contêiner do laboratório. O teste foi INTERROMPIDO (exit ${EXIT_DOCKER_UNAVAILABLE})." "${EXIT_DOCKER_UNAVAILABLE}"
fi

say "⏳ Aguardando o PostgreSQL do laboratório ficar pronto (até ${LAB_WAIT_SECONDS}s)..."
LAB_READY=0
LAB_WAITED=0
while [ "${LAB_WAITED}" -lt "${LAB_WAIT_SECONDS}" ]; do
    if docker exec "${LAB_NAME}" pg_isready -U postgres -d postgres >>"${LOG_FILE}" 2>&1; then
        LAB_READY=1
        break
    fi
    sleep 2
    LAB_WAITED=$((LAB_WAITED + 2))
done
if [ "${LAB_READY}" -ne 1 ]; then
    die "Laboratório não ficou pronto em ${LAB_WAIT_SECONDS}s. O teste foi INTERROMPIDO (exit ${EXIT_LAB_NOT_READY})." "${EXIT_LAB_NOT_READY}"
fi
say "✅ Laboratório pronto (${LAB_WAITED}s)."

# ------------------------------------------------- carga das roles no lab
say "📥 Carregando roles reais da produção no laboratório..."
if ! docker exec -i "${LAB_NAME}" psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
        < "${GLOBALS_SANITIZED_FILE}" >>"${LOG_FILE}" 2>&1; then
    RESULT_ROLES="FALHA NA CARGA DAS ROLES no laboratório — teste interrompido"
    die "Falha ao CARREGAR as roles reais da produção no laboratório (erro registrado apenas no log restrito). O teste foi INTERROMPIDO (exit ${EXIT_ROLES_RESTORE_FAILED}). Nenhuma role de fallback foi utilizada." "${EXIT_ROLES_RESTORE_FAILED}"
fi

# Verificação de fidelidade das roles: toda role extraída da produção deve
# existir no laboratório. Faltando qualquer uma → aborta (correção 1).
sed -nE 's/^[[:space:]]*CREATE ROLE "?([A-Za-z_][A-Za-z0-9_$]*)"?.*$/\1/p' \
    "${GLOBALS_SANITIZED_FILE}" 2>>"${LOG_FILE}" | sort -u > "${EXPECTED_ROLES_FILE}" 2>>"${LOG_FILE}"
chmod 600 "${EXPECTED_ROLES_FILE}" 2>/dev/null || true
run_psql_lab "SELECT rolname FROM pg_roles WHERE rolname NOT LIKE 'pg\_%' ORDER BY 1" \
    | sort -u > "${LAB_ROLES_FILE}" 2>>"${LOG_FILE}"
chmod 600 "${LAB_ROLES_FILE}" 2>/dev/null || true

EXPECTED_ROLES_COUNT="$(wc -l < "${EXPECTED_ROLES_FILE}" 2>/dev/null | tr -d '[:space:]')"
MISSING_ROLES_COUNT="$(comm -23 "${EXPECTED_ROLES_FILE}" "${LAB_ROLES_FILE}" 2>>"${LOG_FILE}" | wc -l | tr -d '[:space:]')"
if [ -z "${EXPECTED_ROLES_COUNT}" ] || [ "${EXPECTED_ROLES_COUNT}" -eq 0 ]; then
    RESULT_ROLES="FALHA NA VERIFICAÇÃO (nenhuma role esperada foi identificada na extração) — teste interrompido"
    die "A lista de roles esperadas saiu vazia após a extração/sanitização. O teste foi INTERROMPIDO (exit ${EXIT_ROLES_RESTORE_FAILED})." "${EXIT_ROLES_RESTORE_FAILED}"
fi
if [ "${MISSING_ROLES_COUNT}" -ne 0 ]; then
    RESULT_ROLES="FALHA NA VERIFICAÇÃO (${MISSING_ROLES_COUNT} roles da produção ausentes no laboratório) — teste interrompido"
    die "${MISSING_ROLES_COUNT} roles extraídas da produção NÃO foram criadas no laboratório (nomes apenas no log/relatório restritos). O teste foi INTERROMPIDO (exit ${EXIT_ROLES_RESTORE_FAILED})." "${EXIT_ROLES_RESTORE_FAILED}"
fi
RESULT_ROLES="COMPROVADA — roles reais da produção (pg_dumpall --globals-only) carregadas no laboratório; roles esperadas: ${EXPECTED_ROLES_COUNT}; ausentes: 0; exceção tolerada: apenas duplicate_object; nenhuma role genérica/de fallback utilizada."
say "✅ Roles reais carregadas e conferidas (${EXPECTED_ROLES_COUNT} roles esperadas, 0 ausentes)."

# ======================================================= RESTAURAÇÃO DO DUMP
say "♻️  Restaurando o backup dentro do laboratório (isto NÃO afeta a produção)..."
gunzip -c "${BACKUP_FILE}" 2>>"${LOG_FILE}" \
    | docker exec -i "${LAB_NAME}" psql -U postgres -d postgres -v ON_ERROR_STOP=1 >>"${LOG_FILE}" 2>&1
RESTORE_RC=$?
if [ "${RESTORE_RC}" -ne 0 ]; then
    RESULT_RESTORE="FALHA (código ${RESTORE_RC}) — detalhe do erro SQL restrito ao log"
    die "A restauração do dump FALHOU no laboratório (código ${RESTORE_RC}). A mensagem de erro SQL NÃO é exibida aqui; consulte o log restrito. (exit ${EXIT_RESTORE_FAILED})" "${EXIT_RESTORE_FAILED}"
fi
RESULT_RESTORE="CONCLUÍDA (psql ON_ERROR_STOP=1, código 0) — dump integral aplicado ao laboratório"
say "✅ Restauração concluída no laboratório."

# ================================================ VALIDAÇÃO ESTRUTURAL (corr.4)
# Rótulos obrigatórios do relatório:
#   CONFERIDO (contagens)   — catálogo + contagens comparadas com a produção
#   NÃO VALIDADO            — integridade profunda/conteúdo, sequências,
#                             execução de funções etc.
say "📊 Comparando catálogo e contagens de registros com a produção (só-leitura)..."
: > "${CONFERIDOS_FILE}"
: > "${DIVERGENCES_FILE}"

# --- listas de schemas
PROD_SCHEMAS="$(run_psql_prod "SELECT nspname FROM pg_namespace WHERE nspname NOT LIKE 'pg\_%' AND nspname <> 'information_schema' ORDER BY 1" | sort -u)"
LAB_SCHEMAS="$(run_psql_lab "SELECT nspname FROM pg_namespace WHERE nspname NOT LIKE 'pg\_%' AND nspname <> 'information_schema' ORDER BY 1" | sort -u)"
if [ -n "${PROD_SCHEMAS}" ] && [ "${PROD_SCHEMAS}" = "${LAB_SCHEMAS}" ]; then
    printf 'CONFERIDO (contagens): lista de schemas idêntica entre produção e laboratório\n' >> "${CONFERIDOS_FILE}"
else
    printf 'DIVERGENTE: lista de schemas difere entre produção e laboratório (nomes restritos ao relatório/log)\n' >> "${DIVERGENCES_FILE}"
fi

# --- contagens de objetos de catálogo (público)
compare_catalog_count() {
    local label="$1" prod_q="$2" lab_q="$3"
    local p l
    p="$(run_psql_prod "${prod_q}" | head -n 1 | tr -d '[:space:]')"
    l="$(run_psql_lab "${lab_q}" | head -n 1 | tr -d '[:space:]')"
    if [ -z "${p}" ] || [ -z "${l}" ]; then
        printf 'NÃO CONFERIDO (erro de consulta; ver log restrito): %s\n' "${label}" >> "${DIVERGENCES_FILE}"
    elif [ "${p}" = "${l}" ]; then
        printf 'CONFERIDO (contagens): %s — produção=%s, laboratório=%s\n' "${label}" "${p}" "${l}" >> "${CONFERIDOS_FILE}"
    else
        printf 'DIVERGENTE: %s — produção=%s, laboratório=%s\n' "${label}" "${p}" "${l}" >> "${DIVERGENCES_FILE}"
    fi
}

compare_catalog_count "tabelas no schema público" \
    "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'" \
    "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'"
compare_catalog_count "índices no schema público" \
    "SELECT count(*) FROM pg_indexes WHERE schemaname='public'" \
    "SELECT count(*) FROM pg_indexes WHERE schemaname='public'"
compare_catalog_count "constraints (PK/FK/UNIQUE/CHECK) no schema público" \
    "SELECT count(*) FROM information_schema.table_constraints WHERE table_schema='public' AND constraint_type IN ('PRIMARY KEY','FOREIGN KEY','UNIQUE','CHECK')" \
    "SELECT count(*) FROM information_schema.table_constraints WHERE table_schema='public' AND constraint_type IN ('PRIMARY KEY','FOREIGN KEY','UNIQUE','CHECK')"
compare_catalog_count "políticas RLS no schema público" \
    "SELECT count(*) FROM pg_policies WHERE schemaname='public'" \
    "SELECT count(*) FROM pg_policies WHERE schemaname='public'"
compare_catalog_count "funções no schema público (existência)" \
    "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'" \
    "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'"
compare_catalog_count "sequências (existência)" \
    "SELECT count(*) FROM information_schema.sequences WHERE sequence_schema='public'" \
    "SELECT count(*) FROM information_schema.sequences WHERE sequence_schema='public'"

# --- contagens de registros por tabela (público + auth.users)
PROD_TABLES="$(run_psql_prod "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename")"
TABLES_OK=0
TABLES_DIFF=0
TABLES_ERR=0
if [ -n "${PROD_TABLES}" ]; then
    while IFS= read -r t; do
        [ -n "${t}" ] || continue
        p="$(run_psql_prod "SELECT count(*) FROM public.\"${t}\"" | head -n 1 | tr -d '[:space:]')"
        l="$(run_psql_lab "SELECT count(*) FROM public.\"${t}\"" | head -n 1 | tr -d '[:space:]')"
        if [ -z "${p}" ] || [ -z "${l}" ]; then
            TABLES_ERR=$((TABLES_ERR + 1))
            printf 'NÃO CONFERIDO (erro de consulta; ver log restrito): contagem da tabela %s\n' "${t}" >> "${DIVERGENCES_FILE}"
        elif [ "${p}" = "${l}" ]; then
            TABLES_OK=$((TABLES_OK + 1))
            printf 'CONFERIDO (contagens): tabela %s — produção=%s, laboratório=%s\n' "${t}" "${p}" "${l}" >> "${CONFERIDOS_FILE}"
        else
            TABLES_DIFF=$((TABLES_DIFF + 1))
            printf 'DIVERGENTE: contagem da tabela %s — produção=%s, laboratório=%s\n' "${t}" "${p}" "${l}" >> "${DIVERGENCES_FILE}"
        fi
    done <<< "${PROD_TABLES}"
else
    TABLES_ERR=$((TABLES_ERR + 1))
    printf 'NÃO CONFERIDO: lista de tabelas públicas indisponível na produção (ver log restrito)\n' >> "${DIVERGENCES_FILE}"
fi

# auth.users (referência do rotineiro de backup)
p="$(run_psql_prod 'SELECT count(*) FROM auth.users' | head -n 1 | tr -d '[:space:]')"
l="$(run_psql_lab  'SELECT count(*) FROM auth.users' | head -n 1 | tr -d '[:space:]')"
if [ -n "${p}" ] && [ -n "${l}" ] && [ "${p}" = "${l}" ]; then
    printf 'CONFERIDO (contagens): auth.users — produção=%s, laboratório=%s\n' "${p}" "${l}" >> "${CONFERIDOS_FILE}"
else
    printf 'DIVERGENTE/NÃO CONFERIDO: contagem de auth.users — produção=%s, laboratório=%s\n' "${p:-erro}" "${l:-erro}" >> "${DIVERGENCES_FILE}"
fi

CONFERIDOS_COUNT="$(grep -c 'CONFERIDO' "${CONFERIDOS_FILE}" 2>/dev/null || true)"
DIVERGENCES_COUNT="$(grep -c 'DIVERGENTE\|NÃO CONFERIDO' "${DIVERGENCES_FILE}" 2>/dev/null || true)"
[ -n "${CONFERIDOS_COUNT}" ] || CONFERIDOS_COUNT=0
[ -n "${DIVERGENCES_COUNT}" ] || DIVERGENCES_COUNT=0

if [ "${DIVERGENCES_COUNT}" -gt 0 ]; then
    ESTRUTURAL_STATUS="FALHA PARCIAL (divergências/erros de contagem — ver relatório restrito)"
elif [ "${CONFERIDOS_COUNT}" -gt 0 ]; then
    ESTRUTURAL_STATUS="CONFERIDA APENAS EM CONTAGENS/CATÁLOGO (isto NÃO é uma validação estrutural completa)"
else
    ESTRUTURAL_STATUS="NÃO REALIZADA (nenhuma comparação pôde ser efetuada — ver log restrito)"
fi
ESTRUTURAL_RESUMO="Itens CONFERIDOS (contagens/catálogo): ${CONFERIDOS_COUNT}; itens DIVERGENTES/NÃO CONFERIDOS: ${DIVERGENCES_COUNT}; tabelas com contagem idêntica: ${TABLES_OK}; tabelas divergentes: ${TABLES_DIFF}; tabelas com erro de consulta: ${TABLES_ERR}."
log "Validação estrutural: ${ESTRUTURAL_STATUS} — ${ESTRUTURAL_RESUMO}"

# ================================================================ ENCERRAMENTO
# ------------------------------------ (correção 5) cleanup com identidade
do_cleanup() {
    local fails=0
    local label vlabel f

    log "Iniciando cleanup com verificação de identidade..."

    # --- contêiner do laboratório: remover SOMENTE se nome + label conferem
    if docker ps -a --format '{{.Names}}' 2>>"${LOG_FILE}" | grep -qx -- "${LAB_NAME}"; then
        label="$(docker inspect -f "{{index .Config.Labels \"${LAB_LABEL}\"}}" "${LAB_NAME}" 2>>"${LOG_FILE}" || true)"
        if [ "${label}" = "${LAB_LABEL_VALUE}" ]; then
            if docker rm -f "${LAB_NAME}" >>"${LOG_FILE}" 2>&1; then
                log "Container do laboratório '${LAB_NAME}' removido."
            else
                fails=$((fails + 1))
                CLEANUP_OBS="${CLEANUP_OBS} falha ao remover o container '${LAB_NAME}';"
                say "⚠️ FALHA DE LIMPEZA: o container do laboratório '${LAB_NAME}' não pôde ser removido. Remova manualmente. Detalhes: ${LOG_FILE}"
            fi
        else
            fails=$((fails + 1))
            CLEANUP_OBS="${CLEANUP_OBS} container '${LAB_NAME}' NÃO removido por divergência de identidade (label);"
            say "🛑 RECUSA DE LIMPEZA: container '${LAB_NAME}' existe, porém a label de identidade do laboratório NÃO confere. Nada foi removido — verificar manualmente."
        fi
    fi

    # --- volume do laboratório: remover SOMENTE se nome + label conferem
    if docker volume ls -q 2>>"${LOG_FILE}" | grep -qx -- "${LAB_VOLUME}"; then
        vlabel="$(docker volume inspect -f "{{index .Labels \"${LAB_LABEL}\"}}" "${LAB_VOLUME}" 2>>"${LOG_FILE}" || true)"
        if [ "${vlabel}" = "${LAB_LABEL_VALUE}" ]; then
            if docker volume rm "${LAB_VOLUME}" >>"${LOG_FILE}" 2>&1; then
                log "Volume do laboratório '${LAB_VOLUME}' removido."
            else
                fails=$((fails + 1))
                CLEANUP_OBS="${CLEANUP_OBS} falha ao remover o volume '${LAB_VOLUME}';"
                say "⚠️ FALHA DE LIMPEZA: o volume do laboratório '${LAB_VOLUME}' não pôde ser removido. Remova manualmente. Detalhes: ${LOG_FILE}"
            fi
        else
            fails=$((fails + 1))
            CLEANUP_OBS="${CLEANUP_OBS} volume '${LAB_VOLUME}' NÃO removido por divergência de identidade (label);"
            say "🛑 RECUSA DE LIMPEZA: volume '${LAB_VOLUME}' existe, porém a label de identidade do laboratório NÃO confere. Nada foi removido — verificar manualmente."
        fi
    fi

    # --- arquivos temporários restritos desta sessão
    for f in "${GLOBALS_RAW_FILE}" "${GLOBALS_SANITIZED_FILE}" \
             "${EXPECTED_ROLES_FILE}" "${LAB_ROLES_FILE}"; do
        if [ -f "${f}" ]; then
            rm -f "${f}" 2>>"${LOG_FILE}"
            if [ -f "${f}" ]; then
                fails=$((fails + 1))
                CLEANUP_OBS="${CLEANUP_OBS} arquivo temporário restrito '${f}' não removido;"
                say "⚠️ FALHA DE LIMPEZA: arquivo temporário restrito '${f}' não foi removido. Remova manualmente."
            fi
        fi
    done

    # --- conferência final: sobrou recurso do laboratório?
    if docker ps -a --format '{{.Names}}' 2>>"${LOG_FILE}" | grep -qx -- "${LAB_NAME}" \
        || docker volume ls -q 2>>"${LOG_FILE}" | grep -qx -- "${LAB_VOLUME}"; then
        fails=$((fails + 1))
        CLEANUP_OBS="${CLEANUP_OBS} recurso do laboratório ainda presente após a limpeza;"
    fi

    if [ "${fails}" -eq 0 ]; then
        CLEANUP_STATUS="100% — nenhum recurso desta sessão permaneceu (container, volume e arquivos temporários removidos)"
        log "Cleanup 100% concluído."
        return 0
    fi
    CLEANUP_STATUS="INCOMPLETO — sobraram recursos desta sessão (ver observações e log restrito)"
    log "Cleanup INCOMPLETO (${fails} falhas). Observações:${CLEANUP_OBS}"
    return 1
}

# ------------------------------------------------ (corr. 2/3/4) relatório
emit_report() {
    local rc="$1"

    {
        echo "==============================================================="
        echo " RELATÓRIO DE TESTE DE RESTAURAÇÃO ISOLADO — SBJur/DPSjur"
        echo " Script: docs/vps/04-testar-restauracao-isolado.sh (${SCRIPT_VERSION})"
        echo " Sessão: PID $$ — $(date '+%F %T')"
        echo "==============================================================="
        echo ""
        echo "1. ARQUIVO DE BACKUP TESTADO"
        echo "   ${RESULT_BACKUP}"
        echo ""
        echo "2. INTEGRIDADE FÍSICA DO ARQUIVO"
        echo "   ${RESULT_CHECKSUM}"
        echo ""
        echo "3. ORIGEM DO BACKUP: ${ORIGEM_BACKUP_STATUS}"
        echo "   ${ORIGEM_DETALHE}"
        echo "   NOTA EXPRESSA: o checksum (sha256) e os metadados do arquivo"
        echo "   (nome, tamanho, data) atestam APENAS a integridade física do"
        echo "   arquivo. Eles NÃO comprovam a identidade do banco de origem do"
        echo "   dump. A origem só seria considerada comprovada se existisse um"
        echo "   manifesto gerado NO MOMENTO da criação do backup (pelo próprio"
        echo "   rotineiro de backup), contendo hash + identidade do banco de"
        echo "   origem, e verificável contra o arquivo atual. A rotina atual de"
        echo "   backup não gera tal manifesto, portanto o status permanece:"
        echo "   ${ORIGEM_BACKUP_STATUS}"
        echo ""
        echo "4. IDENTIDADE DO BANCO DE PRODUÇÃO (inspeção só-leitura)"
        echo "   Contêiner: ${PROD_CONTAINER}"
        echo "   Banco:     ${PROD_DB_IDENTIDADE}"
        echo ""
        echo "5. ROLES"
        echo "   ${RESULT_ROLES}"
        echo ""
        echo "6. RESTAURAÇÃO DO DUMP"
        echo "   ${RESULT_RESTORE}"
        echo ""
        echo "7. VALIDAÇÃO ESTRUTURAL — ${ESTRUTURAL_STATUS}"
        echo "   ${ESTRUTURAL_RESUMO}"
        echo ""
        echo "   7.a) CONFERIDO (contagens/catálogo) — o que FOI efetivamente conferido:"
        if [ -s "${CONFERIDOS_FILE}" ]; then
            sed 's/^/     /' "${CONFERIDOS_FILE}"
        else
            echo "     (nenhum item pôde ser conferido — ver log restrito)"
        fi
        echo ""
        echo "   7.b) NÃO VALIDADO — o que este teste NÃO valida (escopo delimitado):"
        echo "     - integridade profunda / conteúdo linha a linha dos dados;"
        echo "     - constraints de DADOS aplicadas a valores (CHECK/FK reavaliadas por rotinas de manutenção não foram executadas);"
        echo "     - valores e estado atual das SEQUÊNCIAS (apenas existência conferida);"
        echo "     - execução de FUNÇÕES/procedimentos (apenas existência no catálogo);"
        echo "     - visões materializadas, gatilhos em execução e regras;"
        echo "     - desempenho de consultas e uso efetivo de índices;"
        echo "     - objetos fora dos schemas comparados, se houver."
        echo ""
        echo "   7.c) Itens divergentes/não conferidos:"
        if [ -s "${DIVERGENCES_FILE}" ]; then
            sed 's/^/     /' "${DIVERGENCES_FILE}"
        else
            echo "     (nenhum — todas as comparações de contagem conferiram)"
        fi
        echo ""
        echo "8. LIMPEZA (CLEANUP) DOS RECURSOS DO LABORATÓRIO"
        echo "   ${CLEANUP_STATUS}"
        if [ -n "${CLEANUP_OBS}" ]; then
            echo "   Observações:${CLEANUP_OBS}"
            echo "   → Verifique manualmente: docker ps -a | grep ${LAB_NAME_PREFIX}; docker volume ls | grep sbjur-restore-lab-data"
        fi
        echo ""
        echo "9. FIDELIDADE DA RECUPERAÇÃO — DECLARAÇÃO EXPRESSA"
        if [ "${RESULT_ROLES#COMPROVADA}" != "${RESULT_ROLES}" ] \
            && [ "${RESULT_RESTORE#CONCLUÍDA}" != "${RESULT_RESTORE}" ] \
            && [ "${DIVERGENCES_COUNT}" -eq 0 ]; then
            echo "   ATESTADA APENAS QUANTO A: roles reais, catálogo (schemas/tabelas/"
            echo "   índices/constraints/RLS) e CONTAGENS de registros comparadas com a"
            echo "   produção. ISTO NÃO EQUIVALE a uma validação estrutural completa:"
            echo "   integridade profunda de dados permanece NÃO VALIDADA (item 7.b)."
        else
            echo "   NÃO COMPROVADA nesta execução (código de saída ${rc}). O teste NÃO"
            echo "   utilizou roles genéricas nem declarou recuperação fiel sem as"
            echo "   roles reais da produção."
        fi
        echo ""
        echo "10. RESULTADO DA EXECUÇÃO"
        echo "    Código de saída: ${rc}"
        echo "    Log técnico completo (restrito, chmod 600): ${LOG_FILE}"
        echo "    Divergências de contagem (restrito): ${DIVERGENCES_FILE}"
        echo "    Conferências de contagem (restrito): ${CONFERIDOS_FILE}"
        echo "==============================================================="
    } > "${REPORT_FILE}" 2>>"${LOG_FILE}"
    chmod 600 "${REPORT_FILE}" 2>/dev/null || true

    # ---------------------- resumo de console (sem nenhum conteúdo de erro SQL)
    say ""
    say "==================== RESUMO DO TESTE (${SCRIPT_VERSION}) ===================="
    say " Backup testado .......: ${RESULT_BACKUP}"
    say " Integridade física ...: ${RESULT_CHECKSUM}"
    say " ORIGEM do backup .....: ${ORIGEM_BACKUP_STATUS}"
    say " Roles da produção ....: ${RESULT_ROLES#COMPROVADA — }"
    say " Restauração ..........: ${RESULT_RESTORE}"
    say " Validação estrutural .: ${ESTRUTURAL_STATUS}"
    say "     ${ESTRUTURAL_RESUMO}"
    say " Limpeza (cleanup) ....: ${CLEANUP_STATUS}"
    say " Código de saída ......: ${rc}"
    say ""
    say " Relatório completo (restrito, chmod 600): ${REPORT_FILE}"
    say " Log técnico completo (restrito, chmod 600): ${LOG_FILE}"
    say " Nenhuma mensagem de erro SQL é exibida no console nem no relatório:"
    say " detalhes exclusivamente no log restrito acima."
    say "============================================================================"
}

# ------------------------------------------------------------- trap de saída
on_exit() {
    local rc="$?"
    trap - EXIT INT TERM
    do_cleanup || true
    emit_report "${rc}"
    if [ "${CLEANUP_STATUS#INCOMPLETO}" != "${CLEANUP_STATUS}" ] && [ "${rc}" -eq "${EXIT_OK}" ]; then
        rc="${EXIT_CLEANUP_FAILED}"
    fi
    exit "${rc}"
}
trap on_exit EXIT

# ================================================================ FLUXO FINAL
if [ "${DIVERGENCES_COUNT}" -gt 0 ]; then
    log "Fim da execução: divergências estruturais detectadas."
    exit "${EXIT_VALIDATION_FAILED}"
fi
log "Fim da execução sem divergências de contagem."
exit "${EXIT_OK}"
