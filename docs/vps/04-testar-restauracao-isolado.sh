#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur — Fase 6: Teste de restauração de backup PostgreSQL em
#                          contêiner Docker EFÊMERO e ISOLADO, 100% local no VPS
# Script:   docs/vps/04-testar-restauracao-isolado.sh
# Versão:   v2.6.1
#
# HISTÓRICO
#   v2.6.1    : correções de segurança solicitadas na auditoria independente:
#        (1) SEGURANÇA REFORÇADA CONTRA FALHAS DE CONSULTA NO CLEANUP:
#            Eliminado todo uso de '|| true' nas verificações de volumes e
#            contêineres (docker ps, docker inspect, docker volume inspect,
#            docker volume ls). Falhas de consulta nunca são tratadas como
#            resultado vazio/seguro: se a verificação de contêineres conectados,
#            a inspeção de label de sessão ou a listagem de recursos falhar, a
#            remoção do volume/contêiner é recusada, o recurso é preservado, a
#            ocorrência é registrada em CLEANUP_OBS e no log restrito com
#            alerta de console, e o cleanup termina classificado como INCOMPLETO.
#        (2) SELEÇÃO MANUAL ESTRITA DO CONTÊINER DE PRODUÇÃO (PROD_CONTAINER):
#            O nome informado manualmente via variável de ambiente PROD_CONTAINER
#            deve pertencer EXCLUSIVAMENTE aos nomes de PROD_CONTAINER_CANDIDATES.
#            Qualquer nome não autorizado (incluindo 'dpsjur-db', que segue
#            explicitamente fora de escopo com mensagem própria) resulta em
#            interrupção imediata (die com exit 30), MESMO que o contêiner
#            exista e esteja em execução no Docker.
#   v2.2.0-r1 : proposta inicial (isolamento completo, roles via pg_dumpall -g).
#   v2.3.0    : versão auditada pelo usuário; o trabalho de correção ficou
#               mapeado, porém NÃO consolidado/persistido (commit v0.0.659).
#   v2.4.0    : consolidação das 5 correções da primeira auditoria (fallback de
#               roles terminativo, origem NÃO COMPROVADA por padrão, supressão
#               de erro SQL, escopo estrutural delimitado, cleanup com
#               identidade nome+label).
#   v2.6.0    : correções de segurança solicitadas na auditoria independente:
#        (1) SEGURANÇA REFORÇADA NA REMOÇÃO DE VOLUMES:
#            O cleanup remove SOMENTE volumes comprovadamente pertencentes a
#            esta sessão de teste. Todo volume avaliado tem obrigatoriamente
#            sua label de identidade (sbjur-restore-lab-session = PID)
#            conferida E passa por verificação de uso compartilhado: se
#            qualquer outro contêiner estiver conectado a ele, ou se a label
#            estiver ausente/divergente, a remoção automática é recusada, a
#            pendência é registrada em log/relatório e o recurso é preservado.
#        (2) IDENTIFICAÇÃO INEQUÍVOCA DO BANCO DE PRODUÇÃO:
#            Eliminada completamente a seleção automática por padrão solto
#            (grep 'supabase-db'). O script aceita exclusivamente nomes exatos
#            previamente autorizados em PROD_CONTAINER_CANDIDATES ou um nome
#            informado explicitamente via variável PROD_CONTAINER validado
#            (deve existir e estar em execução). Se houver ambiguidade ou
#            nenhum candidato inequívoco for localizado, o teste aborta
#            imediatamente com exit 30 (EXIT_ROLES_EXTRACT_FAILED). O contêiner
#            dpsjur-db permanece totalmente fora do escopo.
#        (3) DISTINÇÃO CLARA DA ORIGEM DO BACKUP NO RELATÓRIO:
#            Revisada a classificação de origem. Um manifesto com hash SHA-256
#            e identidade do contêiner atesta correspondência técnica, mas não
#            comprova por si só origem física inquestionável sem evidências
#            adicionais (ex.: assinatura/carimbo confiável). Diferenciação
#            explícita entre: (a) integridade física do arquivo; (b)
#            correspondência com o manifesto; (c) comprovação de origem. A
#            expressão "ORIGEM COMPROVADA" nunca é emitida sem tais evidências
#            adicionais — o status torna-se "CORRESPONDENTE AO MANIFESTO (não
#            comprova origem)" quando hash+identidade batem, mantendo a
#            origem como NÃO COMPROVADA.
#   v2.5.1    : correções pontuais da terceira revisão:
#        (1) VOLUME MONTADO NO CAMINHO DE DADOS DA IMAGEM OFICIAL. Na imagem
#            oficial postgres, majors <= 17 declaram PGDATA/VOLUME em
#            /var/lib/postgresql/data; majors >= 18 mudaram para VOLUME
#            /var/lib/postgresql com PGDATA /var/lib/postgresql/<major>/docker
#            (docker-library/postgres PR #1259). O volume do laboratório passa
#            a ser montado EXATAMENTE no VOLUME declarado pela imagem
#            correspondente à major detectada (e o PGDATA é fixado de forma
#            explícita e coerente), eliminando o VOLUME ANÔNIMO que sobrava
#            com os dados restaurados. O cleanup passou a capturar (docker
#            inspect .Mounts do contêiner do lab, ANTES de removê-lo) e
#            remover QUALQUER volume anônimo eventual — sempre restrito aos
#            recursos desta sessão (nome ^sbjur-restore-lab-<PID>$ + label de
#            sessão; nada fora do laboratório é tocado).
#        (2) RELATÓRIO × CÓDIGO DE SAÍDA CONSISTENTES. O código de saída FINAL
#            passou a ser calculado ANTES da emissão do relatório: quando a
#            restauração termina bem mas a limpeza é incompleta, o relatório é
#            emitido já com o código final (60), registrando ambos — falha
#            principal (MAIN_RC) e status do cleanup — de forma coerente com o
#            exit final. O código da falha principal NUNCA é mascarado (rc != 0
#            permanece rc), e nenhuma falha é ocultada.
#   v2.5.0    : as 5 correções da SEGUNDA auditoria independente
#               (nenhuma outra funcionalidade alterada):
#        (1) TRAP DE LIMPEZA REGISTRADO ANTES DE CRIAR QUALQUER RECURSO Docker.
#            do_cleanup/emit_report/on_exit passam a ser definidos e o
#            `trap on_exit EXIT` registrado logo após os helpers/preparação de
#            arquivos — ANTES da seleção de recursos do laboratório (volume,
#            contêiner). Qualquer falha intermediária (die, exit, sinal) já
#            dispara a limpeza das sessões. Todas as variáveis de estado usadas
#            pelo cleanup (CLEANUP_STATUS, CLEANUP_OBS, LOG_FILE, nomes do
#            laboratório etc.) são inicializadas ANTES do trap ficar ativo.
#        (2) FALHA DE LIMPEZA REFLETIDA EM TODOS OS CAMINHOS DE SAÍDA. O trap
#            on_exit captura o código da falha principal (MAIN_RC), executa o
#            cleanup e emite relatório SEMPRE. O relatório e o console registram
#            AMBOS: o código da falha que abortou E o status do cleanup. O
#            código de saída final é EXIT_CLEANUP_FAILED (60) quando o cleanup
#            foi incompleto e a execução terminaria 0 — e em qualquer outro
#            caminho o código da falha principal é PRESERVADO (nunca mascarado),
#            com o status INCOMPLETO do cleanup sempre visível no relatório.
#            Caminho de interrupção (exit 130) também passa pelo trap.
#        (3) SEM PRESUNÇÃO DE VERSÃO. Se a versão major do PostgreSQL de
#            produção não puder ser detectada, o teste é INTERROMPIDO com
#            EXIT_PROD_VERSION_UNKNOWN (14) — nunca mais se assume major 18.
#            A imagem do laboratório é postgres:<major> (imagem OFICIAL do
#            PostgreSQL) e só é escolhida automaticamente se a major detectada
#            for uma versão publicada da imagem oficial; caso contrário, aborta
#            antes de criar qualquer recurso. Override documentado via variável
#            LAB_IMAGE. NOTA DE COMPATIBILIDADE: a produção roda a imagem
#            supabase/postgres (self-hosted), que pode divergir em extensões e
#            paths; o laboratório com postgres:<major> valida APENAS o DUMP SQL.
#        (4) PRÉ-CHECAGEM DE DISCO E MEMÓRIA antes de criar o laboratório, sem
#            redução automática de limites e sem fallback: tamanho
#            descomprimido estimado (gzip -l; fallback: descompressão de
#            amostra; último recurso: fator conservador 4x), fator de expansão
#            do PostgreSQL (heap+índices+WAL) e reserva de segurança para a
#            produção na mesma máquina. Disco livre no filesystem do Docker
#            menor que o necessário ⇒ EXIT_INSUFFICIENT_DISK (15). MemAvailable
#            menor que LAB_MEMORY_LIMIT × folga ⇒ EXIT_INSUFFICIENT_MEMORY (16).
#            Ou há recurso suficiente ou o teste não começa.
#        (5) SANITIZAÇÃO DE ROLES REESCRITA E ORIGEM MAIS RIGOROSA:
#            (5a) a sanitização é feita por um filtro awk que MONTA a instrução
#            completa (suporta CREATE ROLE multilinha), descarta CREATE/ALTER
#            DATABASE, COMMENT ON DATABASE, ALTER ROLE ... IN DATABASE e
#            meta-comandos psql (\connect, \restrict...) sem remover conteúdo
#            legítimo, e envolve CADA CREATE ROLE em bloco DO tolerando
#            EXCLUSIVAMENTE duplicate_object. APÓS gerar o arquivo sanitizado,
#            uma verificação grep confirma que NÃO sobrou nenhuma linha com
#            CREATE DATABASE / ALTER DATABASE / COMMENT ON DATABASE / \connect —
#            se sobrar, o teste aborta. A verificação pós-carga de que toda role
#            esperada existe no laboratório foi preservada.
#            (5b) ORIGEM do backup continua NÃO COMPROVADA por padrão. O
#            manifesto só valida a origem se contiver, ALÉM do hash sha256
#            (comparado de forma inequívoca: caixa e whitespace normalizados),
#            um campo EXPLÍCITO de identidade do banco/container de origem — e
#            essa identidade é CONFERIDA contra o contêiner de produção
#            detectado. Hash e metadados atestam APENAS integridade física
#            (reforçado no relatório).
#
# O QUE O SCRIPT FAZ
#   - Seleciona o arquivo de backup (.sql.gz) a testar (argumento ou menu).
#   - Calcula checksum sha256 (integridade física) e avalia a ORIGEM do backup
#     conforme a correção (5b).
#   - Localiza o contêiner de PRODUÇÃO (por padrão sbljur-local_supabase-db-1,
#     com alternativa sbjur-local_supabase-db-1; dpsjur-db está EXCLUÍDO de
#     qualquer detecção) e faz inspeção EXCLUSIVAMENTE só-leitura.
#   - Detecta a versão major do PostgreSQL de produção (aborta se não detectar
#     — correção 3) e verifica disco/memória disponíveis (correção 4) ANTES de
#     criar qualquer recurso do laboratório.
#   - Extrai as roles reais da produção (pg_dumpall --globals-only, só-leitura)
#     e as sanitiza com verificação pós-geração (correção 5a).
#   - Sobe um contêiner PostgreSQL EFÊMERO (--network none, volume dedicado
#     com label de sessão, memória limitada) na imagem postgres:<major> da
#     produção, carrega as roles reais e restaura o dump dentro dele.
#   - Valida catálogo + contagens de registros contra a produção, com rótulos
#     "CONFERIDO (contagens)" vs "NÃO VALIDADO".
#   - Remove os recursos do laboratório conferindo IDENTIDADE e emite relatório
#     em arquivo restrito (chmod 600) + resumo seguro no console.
#
# COMPATIBILIDADE DE IMAGEM (correção 3)
#   - Produção: imagem supabase/postgres (self-hosted via EasyPanel).
#   - Laboratório: imagem OFICIAL postgres:<major> do Docker Hub, usada
#     APENAS para validar o DUMP SQL (sintaxe, objetos, contagens). Extensões
#     específicas da imagem Supabase (ex.: pg_cron, pg_net, pgjwt) e paths
#     internos podem divergir — divergências de EXTENSÃO não invalidam o
#     teste de integridade do dump, mas são escopo NÃO VALIDADO deste script.
#   - Override: LAB_IMAGE=postgres:17 bash 04-testar-restauracao-isolado.sh ...
#     (a imagem informada é usada tal qual; a verificação de versão publicada
#     da imagem oficial é dispensada, mas a DETECÇÃO da major da produção
#     continua obrigatória — exit 14 se não detectável). NOTA (v2.5.1): a
#     montagem do volume e o PGDATA do laboratório seguem o layout da imagem
#     OFICIAL postgres correspondente à major detectada; um override deve ser
#     compatível com esse layout.
#
# COMO EXECUTAR (no VPS; NÃO usar via curl|bash — baixar o arquivo primeiro):
#   bash 04-testar-restauracao-isolado.sh /root/sbjur-backups/diario/sbjur_backup_YYYYMMDD.sql.gz
#   (sem argumento, lista os backups disponíveis e pergunta qual testar)
#
# VARIÁVEIS DE AMBIENTE OPCIONAIS
#   LAB_IMAGE                  imagem do laboratório (default: postgres:<major>)
#   LAB_WAIT_SECONDS           timeout de prontidão do lab (default: 300)
#   LAB_MEMORY_LIMIT           limite de memória do lab (default: 2g)
#   LAB_SHM_SIZE               /dev/shm do lab (default: 256m)
#   LAB_MEMORY_HEADROOM_FACTOR folga de memória além do limite do lab, fator
#                              inteiro >= 1 (default: 2 ⇒ MemAvailable precisa
#                              cobrir 2x o limite do lab)
#   LAB_DISK_EXPANSION_FACTOR  fator de expansão PostgreSQL sobre o tamanho
#                              descomprimido, inteiro (default: 2)
#   LAB_DISK_RESERVE           reserva de segurança em disco p/ a produção
#                              (default: 2g)
#   PROD_CONTAINER             nome exato do contêiner de produção (opcional, restrito a PROD_CONTAINER_CANDIDATES)
#
# CÓDIGOS DE SAÍDA
#    0  EXIT_OK                    sucesso (ver observações do relatório)
#   10  EXIT_USAGE                 uso inválido / parâmetro inválido
#   11  EXIT_DOCKER_UNAVAILABLE    docker indisponível ou falha ao criar recursos
#   12  EXIT_LAB_IMAGE_UNAVAILABLE imagem base do laboratório não obtida
#   13  EXIT_LAB_NOT_READY         laboratório não ficou pronto no tempo limite
#   14  EXIT_PROD_VERSION_UNKNOWN  major do PostgreSQL de produção não detectada
#                                  ou sem versão publicada da imagem oficial
#   15  EXIT_INSUFFICIENT_DISK     espaço em disco insuficiente (pré-checagem)
#   16  EXIT_INSUFFICIENT_MEMORY   memória disponível insuficiente (pré-checagem)
#   20  EXIT_BACKUP_NOT_FOUND      nenhum backup localizado
#   21  EXIT_BACKUP_INVALID        arquivo de backup inválido/corrompido
#   30  EXIT_ROLES_EXTRACT_FAILED  falha ao EXTRAIR/sanitizar roles da produção (ABORTA)
#   31  EXIT_ROLES_RESTORE_FAILED  falha ao CARREGAR/verificar roles no lab (ABORTA)
#   40  EXIT_RESTORE_FAILED        falha na restauração do dump no laboratório
#   50  EXIT_VALIDATION_FAILED     divergências estruturais de contagem
#   60  EXIT_CLEANUP_FAILED        limpeza não foi 100% (recursos remanescentes;
#                                  também quando a restauração termina bem mas
#                                  a limpeza falha — relatório registra ambos)
#  130  interrompido pelo usuário (SIGINT/SIGTERM)
#
# ATENÇÃO: nenhum comando deste script altera a produção. Todas as consultas à
# produção são somente leitura (SELECT/catálogo/pg_dumpall -g). O contêiner
# dpsjur-db NÃO é referenciado em nenhum comando deste script.
# ==============================================================================

set -u -o pipefail

# ------------------------------------------------------------------ constantes
SCRIPT_VERSION="v2.6.1"
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
LAB_ANON_VOLUMES=""                                # volumes anônimos eventuais do lab (v2.5.1)
LAB_LABEL="sbjur-restore-lab-session"              # label de identidade do recurso
LAB_LABEL_VALUE="$$"
PROD_CONTAINER_ENV="${PROD_CONTAINER:-}"
# Candidatos EXATOS de produção (inspeção só-leitura). dpsjur-db está
# deliberadamente EXCLUÍDO de qualquer detecção.
PROD_CONTAINER_CANDIDATES="sbljur-local_supabase-db-1 sbjur-local_supabase-db-1"
PROD_CONTAINER=""
LAB_IMAGE="${LAB_IMAGE:-}"                         # override opcional (documentado)
LAB_IMAGE_FINAL=""                                 # imagem efetivamente usada
LAB_VOLUME_MOUNT=""                                # caminho de dados da imagem (v2.5.1)
LAB_PGDATA=""                                      # PGDATA fixado no lab (v2.5.1)
LAB_IMAGE_OVERRIDDEN=0
LAB_WAIT_SECONDS="${LAB_WAIT_SECONDS:-300}"
LAB_MEMORY_LIMIT="${LAB_MEMORY_LIMIT:-2g}"
LAB_SHM_SIZE="${LAB_SHM_SIZE:-256m}"
LAB_MEMORY_HEADROOM_FACTOR="${LAB_MEMORY_HEADROOM_FACTOR:-2}"
LAB_DISK_EXPANSION_FACTOR="${LAB_DISK_EXPANSION_FACTOR:-2}"
LAB_DISK_RESERVE="${LAB_DISK_RESERVE:-2g}"
DOCKER_ROOT=""                                     # aferido na pré-checagem

# Majors publicadas da imagem OFICIAL postgres (Docker Hub). Se a major
# detectada da produção não estiver aqui, a imagem postgres:<major> não pode
# ser presumida e o teste aborta (correção 3) — salvo override LAB_IMAGE.
POSTGRES_OFFICIAL_MAJORS="10 11 12 13 14 15 16 17 18"

EXIT_OK=0
EXIT_USAGE=10
EXIT_DOCKER_UNAVAILABLE=11
EXIT_LAB_IMAGE_UNAVAILABLE=12
EXIT_LAB_NOT_READY=13
EXIT_PROD_VERSION_UNKNOWN=14
EXIT_INSUFFICIENT_DISK=15
EXIT_INSUFFICIENT_MEMORY=16
EXIT_BACKUP_NOT_FOUND=20
EXIT_BACKUP_INVALID=21
EXIT_ROLES_EXTRACT_FAILED=30
EXIT_ROLES_RESTORE_FAILED=31
EXIT_RESTORE_FAILED=40
EXIT_VALIDATION_FAILED=50
EXIT_CLEANUP_FAILED=60

# ------------------------------------------------------------- estado global
# (tudo inicializado ANTES do trap EXIT ficar ativo — correção 1)
RESULT_BACKUP="NÃO EXECUTADO"
RESULT_CHECKSUM="NÃO CALCULADO"
CHECKSUM_SHA256=""
ORIGEM_BACKUP_STATUS="NÃO COMPROVADA"     # (correção 5b / v2.6.0) padrão seguro
MANIFESTO_STATUS="NÃO EXECUTADO"
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
MAIN_RC="(não registrado)"                # código da falha principal (correção 2)
PROD_CONTAINER="(não localizado)"
PROD_DB_IDENTIDADE="NÃO OBTIDA"
PROD_MAJOR="(não detectada)"
PRECHECK_DISK="NÃO VERIFICADO"
PRECHECK_MEM="NÃO VERIFICADO"

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

# norm_hash(): normaliza caixa e whitespace para comparações inequívocas
# (correção 5b).
norm_hash() {
    printf '%s' "$1" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]'
}

# mem_to_bytes(): converte 2g/512m/1024k/bytes em bytes (vazio = inválido).
mem_to_bytes() {
    local v
    v="$(printf '%s' "$1" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    case "${v}" in
        ''|*[!0-9kmg]*) printf ''; return 1 ;;
        *g) printf '%s' $(( ${v%g} * 1073741824 )) ;;
        *m) printf '%s' $(( ${v%m} * 1048576 )) ;;
        *k) printf '%s' $(( ${v%k} * 1024 )) ;;
        *)  printf '%s' "${v}" ;;
    esac
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

# ==============================================================================
# (correção 1) ROTINA DE LIMPEZA + TRAP DE SAÍDA — definidos e REGISTRADOS
# ANTES de criar qualquer recurso Docker (volume/contêiner do laboratório).
# Todas as variáveis de estado usadas aqui já foram inicializadas acima.
# ==============================================================================

# ------------------------------------ cleanup com conferência de identidade
do_cleanup() {
    local fails=0
    local label="" vlabel="" f="" v=""
    local ps_names="" vol_list="" v_users=""
    local anon_vol_list="" anon_vlabel="" anon_users=""
    local final_ps="" final_vols=""

    log "Iniciando cleanup com verificação de identidade..."

    # --- contêiner do laboratório: remover SOMENTE se nome + label conferem
    if ! ps_names="$(docker ps -a --format '{{.Names}}' 2>>"${LOG_FILE}")"; then
        fails=$((fails + 1))
        CLEANUP_OBS="${CLEANUP_OBS} falha ao listar containers para verificar '${LAB_NAME}';"
        say "🛑 RECUSA DE LIMPEZA: falha ao listar containers no Docker. Não foi possível verificar o container '${LAB_NAME}'. Preservando o recurso por segurança."
        log "RECUSA DE LIMPEZA: docker ps falhou ao consultar container '${LAB_NAME}'."
    elif printf '%s\n' "${ps_names}" | grep -qx -- "${LAB_NAME}"; then
        if ! label="$(docker inspect -f "{{index .Config.Labels \"${LAB_LABEL}\"}}" "${LAB_NAME}" 2>>"${LOG_FILE}")"; then
            fails=$((fails + 1))
            CLEANUP_OBS="${CLEANUP_OBS} falha ao inspecionar label do container '${LAB_NAME}';"
            say "🛑 RECUSA DE LIMPEZA: falha ao inspecionar label do container '${LAB_NAME}'. Preservando o recurso por segurança."
            log "RECUSA DE LIMPEZA: docker inspect falhou ao consultar label do container '${LAB_NAME}'."
        elif [ "${label}" = "${LAB_LABEL_VALUE}" ]; then
            # (v2.5.1) captura de volumes ANÔNIMOS eventuais ANTES de remover o
            # contêiner: todo .Name de .Mounts deste contêiner (exceto o volume
            # nomeado desta sessão) pertence a ESTE laboratório e será removido
            # abaixo, após o contêiner. Se a label divergir, nada é capturado
            # nem removido (recusa de escopo preservada).
            if ! LAB_ANON_VOLUMES="$(docker inspect -f '{{range .Mounts}}{{if .Name}}{{.Name}} {{end}}{{end}}' "${LAB_NAME}" 2>>"${LOG_FILE}")"; then
                fails=$((fails + 1))
                CLEANUP_OBS="${CLEANUP_OBS} falha ao inspecionar montagens do container '${LAB_NAME}';"
                say "🛑 RECUSA DE LIMPEZA: falha ao inspecionar montagens do container '${LAB_NAME}'. Preservando recursos por segurança."
                log "RECUSA DE LIMPEZA: falha ao inspecionar montagens do container '${LAB_NAME}'."
                LAB_ANON_VOLUMES=""
            fi
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
            log "RECUSA DE LIMPEZA: container '${LAB_NAME}' label '${label}' != '${LAB_LABEL_VALUE}'."
        fi
    fi

    # --- volume dedicado do laboratório: remover SOMENTE se nome + label conferem E sem uso externo
    # (v2.6.1 — Correção 1) Erro de listagem ou de inspeção nunca é tratado como resultado vazio:
    # se a consulta falhar, a remoção é RECUSADA, o recurso é PRESERVADO e fails é incrementado.
    if ! vol_list="$(docker volume ls -q 2>>"${LOG_FILE}")"; then
        fails=$((fails + 1))
        CLEANUP_OBS="${CLEANUP_OBS} falha ao listar volumes para verificar '${LAB_VOLUME}';"
        say "🛑 RECUSA DE LIMPEZA: falha ao listar volumes no Docker. Não foi possível verificar o volume '${LAB_VOLUME}'. Preservando o recurso por segurança."
        log "RECUSA DE LIMPEZA: docker volume ls falhou ao consultar volume '${LAB_VOLUME}'."
    elif printf '%s\n' "${vol_list}" | grep -qx -- "${LAB_VOLUME}"; then
        if ! vlabel="$(docker volume inspect -f "{{index .Labels \"${LAB_LABEL}\"}}" "${LAB_VOLUME}" 2>>"${LOG_FILE}")"; then
            fails=$((fails + 1))
            CLEANUP_OBS="${CLEANUP_OBS} falha ao inspecionar label do volume '${LAB_VOLUME}';"
            say "🛑 RECUSA DE LIMPEZA: falha ao inspecionar label do volume '${LAB_VOLUME}'. Limpeza automática recusada por segurança para preservar o recurso."
            log "RECUSA DE LIMPEZA: docker volume inspect falhou ao consultar label do volume '${LAB_VOLUME}'."
        elif [ "${vlabel}" = "${LAB_LABEL_VALUE}" ]; then
            # Checagem de uso compartilhado/externo: nenhum contêiner remanescente pode estar conectado
            if ! v_users="$(docker ps -a --filter "volume=${LAB_VOLUME}" --format '{{.Names}}' 2>>"${LOG_FILE}")"; then
                fails=$((fails + 1))
                CLEANUP_OBS="${CLEANUP_OBS} falha ao verificar containers associados ao volume '${LAB_VOLUME}';"
                say "🛑 RECUSA DE LIMPEZA: falha ao verificar containers associados ao volume '${LAB_VOLUME}'. Limpeza automática recusada por segurança para preservar o recurso."
                log "Falha ao consultar containers associados ao volume '${LAB_VOLUME}'. Remoção recusada por segurança."
            elif [ -n "${v_users}" ]; then
                fails=$((fails + 1))
                CLEANUP_OBS="${CLEANUP_OBS} volume '${LAB_VOLUME}' NÃO removido por estar associado a outro(s) container(s): ${v_users};"
                say "🛑 RECUSA DE LIMPEZA: volume '${LAB_VOLUME}' está associado a outro(s) container(s) (${v_users}). Limpeza automática recusada por segurança para preservar o recurso."
                log "Volume '${LAB_VOLUME}' compartilhado/em uso por: ${v_users}. Remoção recusada."
            elif docker volume rm "${LAB_VOLUME}" >>"${LOG_FILE}" 2>&1; then
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
            log "RECUSA DE LIMPEZA: volume '${LAB_VOLUME}' label '${vlabel}' != '${LAB_LABEL_VALUE}'."
        fi
    fi

    # --- (v2.5.1 / v2.6.0 / v2.6.1 — Correção 1) volumes adicionais/anônimos capturados:
    # SOMENTE volumes comprovadamente pertencentes a esta sessão de teste podem
    # ser removidos. Regras estritas:
    #   1. Volume deve possuir comprovadamente a label da sessão (LAB_LABEL=LAB_LABEL_VALUE);
    #   2. Volume não pode estar em uso por nenhum contêiner externo ou compartilhado;
    #   3. Na dúvida (label ausente, divergente, em uso, erro de inspeção/listagem), a limpeza é
    #      recusada, a pendência registrada em log/observações e o recurso preservado.
    for v in ${LAB_ANON_VOLUMES}; do
        [ "${v}" = "${LAB_VOLUME}" ] && continue
        if ! anon_vol_list="$(docker volume ls -q 2>>"${LOG_FILE}")"; then
            fails=$((fails + 1))
            CLEANUP_OBS="${CLEANUP_OBS} falha ao listar volumes para verificar volume adicional '${v}';"
            say "🛑 RECUSA DE LIMPEZA: falha ao listar volumes no Docker para volume adicional '${v}'. Preservando o recurso por segurança."
            log "RECUSA DE LIMPEZA: docker volume ls falhou ao consultar volume adicional '${v}'."
            continue
        fi
        if printf '%s\n' "${anon_vol_list}" | grep -qx -- "${v}"; then
            if ! anon_vlabel="$(docker volume inspect -f "{{index .Labels \"${LAB_LABEL}\"}}" "${v}" 2>>"${LOG_FILE}")"; then
                fails=$((fails + 1))
                CLEANUP_OBS="${CLEANUP_OBS} falha ao inspecionar label do volume adicional '${v}';"
                say "🛑 RECUSA DE LIMPEZA: falha ao inspecionar label do volume adicional '${v}'. Preservando o recurso por segurança."
                log "RECUSA DE LIMPEZA: docker volume inspect falhou ao consultar label do volume adicional '${v}'."
            elif [ "${anon_vlabel}" != "${LAB_LABEL_VALUE}" ]; then
                fails=$((fails + 1))
                CLEANUP_OBS="${CLEANUP_OBS} volume adicional '${v}' NÃO removido por ausência/divergência de label da sessão;"
                say "🛑 RECUSA DE LIMPEZA: volume adicional '${v}' não possui label desta sessão de teste. Preservando o recurso por segurança."
                log "Volume adicional '${v}' recusado no cleanup: label '${anon_vlabel}' diverge de '${LAB_LABEL_VALUE}'."
            elif ! anon_users="$(docker ps -a --filter "volume=${v}" --format '{{.Names}}' 2>>"${LOG_FILE}")"; then
                fails=$((fails + 1))
                CLEANUP_OBS="${CLEANUP_OBS} falha ao verificar containers associados ao volume adicional '${v}';"
                say "🛑 RECUSA DE LIMPEZA: falha ao verificar containers associados ao volume adicional '${v}'. Preservando o recurso por segurança."
                log "Falha ao consultar containers associados ao volume adicional '${v}'. Remoção recusada por segurança."
            elif [ -n "${anon_users}" ]; then
                fails=$((fails + 1))
                CLEANUP_OBS="${CLEANUP_OBS} volume adicional '${v}' NÃO removido por estar associado a container(s): ${anon_users};"
                say "🛑 RECUSA DE LIMPEZA: volume adicional '${v}' está conectado a container(s) (${anon_users}). Preservando o recurso."
                log "Volume adicional '${v}' recusado no cleanup: em uso por contêineres: ${anon_users}."
            else
                if docker volume rm "${v}" >>"${LOG_FILE}" 2>&1; then
                    log "Volume adicional/anônimo do laboratório '${v}' conferido e removido."
                else
                    fails=$((fails + 1))
                    CLEANUP_OBS="${CLEANUP_OBS} falha ao remover o volume adicional '${v}';"
                    say "⚠️ FALHA DE LIMPEZA: o volume adicional '${v}' não pôde ser removido. Remova manualmente. Detalhes: ${LOG_FILE}"
                fi
            fi
        fi
    done

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
    if ! final_ps="$(docker ps -a --format '{{.Names}}' 2>>"${LOG_FILE}")"; then
        fails=$((fails + 1))
        CLEANUP_OBS="${CLEANUP_OBS} falha ao listar containers na conferência final;"
        log "Aviso de cleanup: falha ao rodar docker ps na conferência final."
    elif printf '%s\n' "${final_ps}" | grep -qx -- "${LAB_NAME}"; then
        fails=$((fails + 1))
        CLEANUP_OBS="${CLEANUP_OBS} container do laboratório '${LAB_NAME}' ainda presente após a limpeza;"
    fi

    if ! final_vols="$(docker volume ls -q 2>>"${LOG_FILE}")"; then
        fails=$((fails + 1))
        CLEANUP_OBS="${CLEANUP_OBS} falha ao listar volumes na conferência final;"
        log "Aviso de cleanup: falha ao rodar docker volume ls na conferência final."
    elif printf '%s\n' "${final_vols}" | grep -qx -- "${LAB_VOLUME}"; then
        fails=$((fails + 1))
        CLEANUP_OBS="${CLEANUP_OBS} volume do laboratório '${LAB_VOLUME}' ainda presente após a limpeza;"
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

# ------------------------------------------------ (relatório) emite relatório
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
        echo "3. COMPROVAÇÃO DE ORIGEM E MANIFESTO"
        echo "   a) Integridade Física: ${RESULT_CHECKSUM}"
        echo "   b) Correspondência com Manifesto: ${MANIFESTO_STATUS}"
        echo "   c) Origem Efetiva: ${ORIGEM_BACKUP_STATUS}"
        echo "   Detalhe: ${ORIGEM_DETALHE}"
        echo "   NOTA EXPRESSA (v2.6.0): O checksum SHA-256 e os metadados do"
        echo "   arquivo (nome, data, tamanho) comprovam EXCLUSIVAMENTE a"
        echo "   integridade física. Um arquivo de manifesto contendo hash e nome"
        echo "   de contêiner comprova correspondência entre arquivo e manifesto,"
        echo "   mas isoladamente NÃO comprova que o dump foi produzido na criação"
        echo "   pelo banco de produção. A designação 'ORIGEM COMPROVADA' é"
        echo "   estritamente reservada a procedimentos com evidência criptográfica"
        echo "   ou assinatura indelével; sem tais garantias, a origem permanece"
        echo "   formalmente classificada como NÃO COMPROVADA."
        echo "   Status desta execução: ${ORIGEM_BACKUP_STATUS}"
        echo ""
        echo "4. PRODUÇÃO (inspeção só-leitura) E PRÉ-REQUISITOS DO LABORATÓRIO"
        echo "   Contêiner de produção: ${PROD_CONTAINER}"
        echo "   Identidade do banco:   ${PROD_DB_IDENTIDADE}"
        echo "   Versão major do PostgreSQL de produção: ${PROD_MAJOR}"
        echo "   Imagem do laboratório: ${LAB_IMAGE_FINAL}"
        echo "   NOTA DE COMPATIBILIDADE: a produção roda a imagem supabase/"
        echo "   postgres (self-hosted); o laboratório usa a imagem OFICIAL"
        echo "   postgres:<major> APENAS para validar o DUMP SQL — extensões e"
        echo "   paths internos podem divergir entre as imagens."
        echo "   Disco (filesystem de ${DOCKER_ROOT:-não aferido}): ${PRECHECK_DISK}"
        echo "   Memória (MemAvailable): ${PRECHECK_MEM}"
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
        echo "     - equivalência de EXTENSÕES entre a imagem supabase/postgres (produção) e a imagem oficial postgres:<major> (laboratório);"
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
        echo "    Código da falha principal (antes do cleanup): ${MAIN_RC}"
        echo "    Status da limpeza (cleanup): ${CLEANUP_STATUS}"
        if [ -n "${CLEANUP_OBS}" ]; then
            echo "    Observações do cleanup:${CLEANUP_OBS}"
        fi
        echo "    Código de saída final: ${rc}"
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
    say " Falha principal (código): ${MAIN_RC}"
    say " Limpeza (cleanup) ....: ${CLEANUP_STATUS}"
    if [ -n "${CLEANUP_OBS}" ]; then
        say " Observações do cleanup:${CLEANUP_OBS}"
    fi
    say " Código de saída ......: ${rc}"
    say ""
    say " Relatório completo (restrito, chmod 600): ${REPORT_FILE}"
    say " Log técnico completo (restrito, chmod 600): ${LOG_FILE}"
    say " Nenhuma mensagem de erro SQL é exibida no console nem no relatório:"
    say " detalhes exclusivamente no log restrito acima."
    say "============================================================================"
}

# ------------------------------------------------------------- trap de saída
# (correção 1 e 2; v2.5.1 — Pendência 2) ativo ANTES de qualquer recurso Docker;
# emite relatório em TODOS os caminhos (die/exit/sinal) e reflete falha de
# limpeza no exit code sem nunca mascarar o código da falha principal. O
# código de saída FINAL é calculado ANTES do relatório: o relatório registra
# exatamente o código com que o script termina (coerência relatório × exit).
on_exit() {
    local rc="$?"
    local final_rc
    trap - EXIT INT TERM
    MAIN_RC="${rc}"
    do_cleanup || true
    final_rc="${rc}"
    if [ "${CLEANUP_STATUS#INCOMPLETO}" != "${CLEANUP_STATUS}" ] \
            && [ "${rc}" -eq "${EXIT_OK}" ]; then
        # Sucesso aparente, mas a limpeza falhou: o exit code DEVE refletir.
        final_rc="${EXIT_CLEANUP_FAILED}"
    fi
    emit_report "${final_rc}"
    if [ "${final_rc}" -ne "${rc}" ]; then
        say "⚠️ Falha de limpeza registrada: código de saída ajustado de 0 para ${EXIT_CLEANUP_FAILED} (relatório registra ambos)."
    elif [ "${CLEANUP_STATUS#INCOMPLETO}" != "${CLEANUP_STATUS}" ]; then
        # rc != 0: o código da falha principal é PRESERVADO (nunca mascarado);
        # o relatório e o console acima registram AMBOS — falha principal e
        # status INCOMPLETO do cleanup — em TODOS os caminhos de saída.
        say "⚠️ ATENÇÃO: falha principal (código ${rc}) E limpeza INCOMPLETA — ambos registrados no relatório."
    fi
    exit "${final_rc}"
}
trap on_exit EXIT

on_interrupt() {
    say "⚠️ Execução interrompida pelo usuário (sinal recebido)."
    exit 130
}
trap on_interrupt INT TERM

# ======================================================== FLUXO — BACKUP ALVO
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

# ----------------------- (correção 5b) checksum = integridade FÍSICA apenas
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
# (v2.6.0 / v2.6.1 — Correção 2) Identificação INEQUÍVOCA do contêiner de produção:
#  - Eliminada qualquer seleção automática por padrão solto (grep 'supabase-db').
#  - Aceita EXCLUSIVAMENTE o nome informado via PROD_CONTAINER (que deve pertencer
#    obrigatoriamente a PROD_CONTAINER_CANDIDATES E estar em execução) ou os
#    nomes exatos de PROD_CONTAINER_CANDIDATES.
#  - O contêiner 'dpsjur-db' permanece expressamente fora de escopo (rejeição imediata).
#  - Se o nome informado via PROD_CONTAINER não pertencer a PROD_CONTAINER_CANDIDATES,
#    o teste aborta imediatamente (die com exit 30), MESMO que o contêiner
#    exista e esteja em execução no Docker.
#  - Se nenhum candidato exato ou mais de um candidato concorrente for
#    identificado (ambiguidade), o procedimento aborta imediatamente com exit 30.
find_prod_container() {
    local c found_candidates="" count_found=0 valid_env=0

    # 1. Variável de ambiente informada explicitamente
    if [ -n "${PROD_CONTAINER_ENV}" ]; then
        if [ "${PROD_CONTAINER_ENV}" = "dpsjur-db" ]; then
            log "PROD_CONTAINER='dpsjur-db' rejeitado por segurança (contêiner fora de escopo)."
            die "O contêiner 'dpsjur-db' está explicitamente fora do escopo deste procedimento. Operação cancelada." "${EXIT_ROLES_EXTRACT_FAILED}"
        fi

        # Validação estrita: PROD_CONTAINER deve ser EXCLUSIVAMENTE um dos candidatos autorizados
        for c in ${PROD_CONTAINER_CANDIDATES}; do
            if [ "${c}" = "${PROD_CONTAINER_ENV}" ]; then
                valid_env=1
                break
            fi
        done

        if [ "${valid_env}" -ne 1 ]; then
            log "PROD_CONTAINER='${PROD_CONTAINER_ENV}' rejeitado: nome não autorizado (candidatos permitidos: ${PROD_CONTAINER_CANDIDATES})."
            die "O contêiner informado em PROD_CONTAINER ('${PROD_CONTAINER_ENV}') NÃO é um candidato autorizado (candidatos permitidos: ${PROD_CONTAINER_CANDIDATES}). Operação cancelada por segurança." "${EXIT_ROLES_EXTRACT_FAILED}"
        fi

        if docker ps --format '{{.Names}}' 2>>"${LOG_FILE}" | grep -qx -- "${PROD_CONTAINER_ENV}"; then
            PROD_CONTAINER="${PROD_CONTAINER_ENV}"
            log "Contêiner de produção definido via PROD_CONTAINER informado e validado em execução: ${PROD_CONTAINER}"
            return
        else
            log "PROD_CONTAINER='${PROD_CONTAINER_ENV}' informado não está em execução no Docker."
            die "O contêiner de produção informado em PROD_CONTAINER ('${PROD_CONTAINER_ENV}') não foi localizado em execução. Sem contêiner de produção inequívoco o teste não prossegue." "${EXIT_ROLES_EXTRACT_FAILED}"
        fi
    fi

    # 2. Busca estrita por correspondência EXATA na lista autorizada
    for c in ${PROD_CONTAINER_CANDIDATES}; do
        if [ "${c}" = "dpsjur-db" ]; then
            continue
        fi
        if docker ps --format '{{.Names}}' 2>>"${LOG_FILE}" | grep -qx -- "${c}"; then
            found_candidates="${found_candidates} ${c}"
            count_found=$((count_found + 1))
        fi
    done

    # 3. Validação de unicidade e ausência de dúvida
    if [ "${count_found}" -eq 1 ]; then
        PROD_CONTAINER="$(echo "${found_candidates}" | awk '{print $1}')"
        log "Contêiner de produção localizado de forma unívoca na lista autorizada: ${PROD_CONTAINER}"
        return
    elif [ "${count_found}" -gt 1 ]; then
        log "Ambiguidade detectada: múltiplos contêineres candidatos autorizados em execução:${found_candidates}"
        die "Múltiplos contêineres candidatos autorizados foram encontrados em execução (${found_candidates# }). Por segurança, havendo dúvida sobre qual contêiner corresponde à produção, o teste foi interrompido (defina PROD_CONTAINER=<nome_exato> para desambiguar)." "${EXIT_ROLES_EXTRACT_FAILED}"
    fi

    # Sem correspondência exata autorizada: NENHUM fallback por regex solto é tolerado
    PROD_CONTAINER=""
}

find_prod_container
if [ -z "${PROD_CONTAINER}" ]; then
    # sem produção acessível de forma inequívoca não há como extrair roles reais: ABORTA
    die "Contêiner de produção de banco não localizado (candidatos autorizados: ${PROD_CONTAINER_CANDIDATES}). Sem contêiner inequívoco e sem acesso às roles reais da produção o teste NÃO prossegue — nenhuma role genérica/sintética é utilizada e nenhum padrão solto é aceito." "${EXIT_ROLES_EXTRACT_FAILED}"
fi
log "Contêiner de produção (inspeção só-leitura): ${PROD_CONTAINER}"

PROD_DB_IDENTIDADE="$(run_psql_prod "SELECT current_database() || ' @ ' || COALESCE(inet_server_addr()::text,'socket-local')" | head -n 1 || true)"
[ -n "${PROD_DB_IDENTIDADE}" ] || PROD_DB_IDENTIDADE="NÃO OBTIDA (ver log restrito)"
log "Identidade do banco de produção: ${PROD_DB_IDENTIDADE}"

# ============ (correção 3) VERSÃO MAJOR DA PRODUÇÃO — SEM PRESUNÇÃO ==========
say "🔎 Detectando versão major do PostgreSQL de produção..."
PROD_MAJOR="$(run_psql_prod 'SHOW server_version' | head -n 1 | awk -F. '{print $1}' | tr -d '[:space:]')"
case "${PROD_MAJOR}" in
    ''|*[!0-9]*)
        PROD_MAJOR="(não detectada)"
        log "Versão major da produção NÃO detectável (SHOW server_version vazio ou inválido)."
        die "NÃO foi possível detectar a versão major do PostgreSQL de produção. Nenhuma presunção de versão é feita (não se assume major 18). O teste foi INTERROMPIDO antes de criar qualquer recurso do laboratório (exit ${EXIT_PROD_VERSION_UNKNOWN})." "${EXIT_PROD_VERSION_UNKNOWN}"
        ;;
esac
log "Versão major detectada da produção: ${PROD_MAJOR}"

# ---------------------- (correção 4) pré-checagem de DISCO E MEMÓRIA ---------
# Sem redução automática de limites e sem fallback: ou há recurso suficiente
# ou o teste não começa (aborta ANTES de criar qualquer recurso).
say "💾 Verificando recursos disponíveis (disco e memória) — sem redução automática de limites..."

MEM_LIMIT_BYTES="$(mem_to_bytes "${LAB_MEMORY_LIMIT}" 2>>"${LOG_FILE}" || true)"
if [ -z "${MEM_LIMIT_BYTES}" ]; then
    die "LAB_MEMORY_LIMIT inválido ('${LAB_MEMORY_LIMIT}'). Use formato como 2g, 512m, 1024k ou bytes puros." "${EXIT_USAGE}"
fi
DISK_RESERVE_BYTES="$(mem_to_bytes "${LAB_DISK_RESERVE}" 2>>"${LOG_FILE}" || true)"
if [ -z "${DISK_RESERVE_BYTES}" ]; then
    die "LAB_DISK_RESERVE inválido ('${LAB_DISK_RESERVE}'). Use formato como 2g, 512m, 1024k ou bytes puros." "${EXIT_USAGE}"
fi
case "${LAB_DISK_EXPANSION_FACTOR}" in
    ''|*[!0-9]*)
        die "LAB_DISK_EXPANSION_FACTOR inválido ('${LAB_DISK_EXPANSION_FACTOR}'): use um inteiro >= 1." "${EXIT_USAGE}"
        ;;
esac
case "${LAB_MEMORY_HEADROOM_FACTOR}" in
    ''|*[!0-9]*)
        die "LAB_MEMORY_HEADROOM_FACTOR inválido ('${LAB_MEMORY_HEADROOM_FACTOR}'): use um inteiro >= 1." "${EXIT_USAGE}"
        ;;
esac
if [ "${LAB_DISK_EXPANSION_FACTOR}" -lt 1 ] || [ "${LAB_MEMORY_HEADROOM_FACTOR}" -lt 1 ]; then
    die "LAB_DISK_EXPANSION_FACTOR e LAB_MEMORY_HEADROOM_FACTOR devem ser inteiros >= 1." "${EXIT_USAGE}"
fi

# --- estimativa do tamanho DESCOMPRIMIDO do backup
#     1) gzip -l (rodapé do gzip; não é confiável acima de ~4 GiB);
#     2) fallback: descompressão de AMOSTRA (8 MiB) e extrapolação;
#     3) último recurso: fator conservador 4x sobre o tamanho comprimido.
EST_UNCOMPRESSED=""
EST_METHOD=""
GZ_OUT="$(LC_ALL=C gzip -l "${BACKUP_FILE}" 2>>"${LOG_FILE}" || true)"
GZ_CMP="$(printf '%s\n' "${GZ_OUT}" | awk 'NR==2 {print $1}' | tr -d '[:space:]')"
GZ_UNC="$(printf '%s\n' "${GZ_OUT}" | awk 'NR==2 {print $2}' | tr -d '[:space:]')"
case "${GZ_CMP}" in ''|*[!0-9]*) GZ_CMP="" ;; esac
case "${GZ_UNC}" in ''|*[!0-9]*) GZ_UNC="" ;; esac
if [ -n "${GZ_UNC}" ] && [ -n "${GZ_CMP}" ] && [ "${GZ_UNC}" -gt "${GZ_CMP}" ] \
        && [ "${BACKUP_BYTES}" -lt 4294967296 ]; then
    # gzip -l lê o ISIZE do rodapé (tamanho módulo 2^32): acima de 4 GiB o valor
    # é inválido — nesse caso cai na descompressão de amostra abaixo.
     EST_UNCOMPRESSED="${GZ_UNC}"
     EST_METHOD="gzip -l (rodapé do gzip)"
 fi
 if [ -z "${EST_UNCOMPRESSED}" ]; then
     SAMPLE_IN=$((8 * 1024 * 1024))
     SAMPLE_OUT="$(head -c "${SAMPLE_IN}" "${BACKUP_FILE}" 2>>"${LOG_FILE}" \
         | gunzip -c 2>>"${LOG_FILE}" | wc -c 2>>"${LOG_FILE}" | tr -d '[:space:]')"
     case "${SAMPLE_OUT}" in ''|*[!0-9]*) SAMPLE_OUT="0" ;; esac
     if [ "${SAMPLE_OUT}" -gt 0 ]; then
        EST_UNCOMPRESSED=$(( (BACKUP_BYTES * SAMPLE_OUT + SAMPLE_IN - 1) / SAMPLE_IN ))
         EST_METHOD="descompressão de amostra (${SAMPLE_IN} bytes → ${SAMPLE_OUT} bytes, extrapolado)"
     else
         EST_UNCOMPRESSED=$(( BACKUP_BYTES * 4 ))
        EST_METHOD="fallback conservador (4x o tamanho comprimido)"
    fi
fi
REQUIRED_DISK=$(( EST_UNCOMPRESSED * LAB_DISK_EXPANSION_FACTOR + DISK_RESERVE_BYTES ))
log "Estimativa de tamanho descomprimido: ${EST_UNCOMPRESSED} bytes (${EST_METHOD})"
log "Disco necessário (fator ${LAB_DISK_EXPANSION_FACTOR}x + reserva ${LAB_DISK_RESERVE}): ${REQUIRED_DISK} bytes"

# --- espaço livre no filesystem que hospeda os dados do Docker
DOCKER_ROOT="$(docker info --format '{{.DockerRootDir}}' 2>>"${LOG_FILE}" || true)"
[ -n "${DOCKER_ROOT}" ] || DOCKER_ROOT="/var/lib/docker"
STAT_OUT="$(LC_ALL=C stat -f -c '%a %S' "${DOCKER_ROOT}" 2>>"${LOG_FILE}" || true)"
FREE_BLOCKS="$(printf '%s\n' "${STAT_OUT}" | awk '{print $1}' | tr -d '[:space:]')"
BLOCK_SIZE="$(printf '%s\n' "${STAT_OUT}" | awk '{print $2}' | tr -d '[:space:]')"
case "${FREE_BLOCKS}" in ''|*[!0-9]*) FREE_BLOCKS="" ;; esac
case "${BLOCK_SIZE}" in ''|*[!0-9]*) BLOCK_SIZE="" ;; esac
if [ -z "${FREE_BLOCKS}" ] || [ -z "${BLOCK_SIZE}" ]; then
    PRECHECK_DISK="NÃO FOI POSSÍVEL AFERIR (stat -f em ${DOCKER_ROOT} falhou)"
    die "Não foi possível aferir o espaço livre no filesystem do Docker (${DOCKER_ROOT}). Sem essa medição o teste NÃO começa — nada foi criado (exit ${EXIT_INSUFFICIENT_DISK})." "${EXIT_INSUFFICIENT_DISK}"
fi
FREE_DISK_BYTES=$(( FREE_BLOCKS * BLOCK_SIZE ))
if [ "${FREE_DISK_BYTES}" -lt "${REQUIRED_DISK}" ]; then
    PRECHECK_DISK="INSUFICIENTE — livre: ${FREE_DISK_BYTES} bytes; necessário (estimado): ${REQUIRED_DISK} bytes"
    log "DISCO INSUFICIENTE: ${PRECHECK_DISK}"
    die "Espaço em disco INSUFICIENTE no filesystem do Docker (${DOCKER_ROOT}): livre ${FREE_DISK_BYTES} bytes; necessário ${REQUIRED_DISK} bytes (descomprimido estimado ${EST_UNCOMPRESSED} × fator ${LAB_DISK_EXPANSION_FACTOR} + reserva ${LAB_DISK_RESERVE}). NÃO há redução automática de limites — o teste NÃO começa e nenhum recurso foi criado (exit ${EXIT_INSUFFICIENT_DISK})." "${EXIT_INSUFFICIENT_DISK}"
fi
PRECHECK_DISK="OK — livre: ${FREE_DISK_BYTES} bytes; necessário (estimado): ${REQUIRED_DISK} bytes (${EST_METHOD}; fator ${LAB_DISK_EXPANSION_FACTOR}x + reserva ${LAB_DISK_RESERVE})"
log "Pré-checagem de disco: ${PRECHECK_DISK}"

# --- memória disponível (MemAvailable de /proc/meminfo)
MEM_AVAIL_KB="$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo 2>>"${LOG_FILE}" || true)"
case "${MEM_AVAIL_KB}" in ''|*[!0-9]*) MEM_AVAIL_KB="" ;; esac
if [ -z "${MEM_AVAIL_KB}" ]; then
    PRECHECK_MEM="NÃO FOI POSSÍVEL AFERIR (/proc/meminfo sem MemAvailable legível)"
    die "Não foi possível ler a memória disponível (/proc/meminfo). Sem essa medição o teste NÃO começa — nada foi criado (exit ${EXIT_INSUFFICIENT_MEMORY})." "${EXIT_INSUFFICIENT_MEMORY}"
fi
MEM_AVAIL_BYTES=$(( MEM_AVAIL_KB * 1024 ))
REQUIRED_MEM=$(( MEM_LIMIT_BYTES * LAB_MEMORY_HEADROOM_FACTOR ))
if [ "${MEM_AVAIL_BYTES}" -lt "${REQUIRED_MEM}" ]; then
    PRECHECK_MEM="INSUFICIENTE — MemAvailable: ${MEM_AVAIL_BYTES} bytes; necessário: ${REQUIRED_MEM} bytes"
    log "MEMÓRIA INSUFICIENTE: ${PRECHECK_MEM}"
    die "Memória disponível INSUFICIENTE: MemAvailable ${MEM_AVAIL_BYTES} bytes; necessário ${REQUIRED_MEM} bytes (limite do laboratório ${LAB_MEMORY_LIMIT} × folga ${LAB_MEMORY_HEADROOM_FACTOR} para o resto do sistema, incluindo a produção que segue no ar). NÃO há redução automática de limites — o teste NÃO começa e nenhum recurso foi criado (exit ${EXIT_INSUFFICIENT_MEMORY})." "${EXIT_INSUFFICIENT_MEMORY}"
fi
PRECHECK_MEM="OK — MemAvailable: ${MEM_AVAIL_BYTES} bytes; necessário: ${REQUIRED_MEM} bytes (limite do lab ${LAB_MEMORY_LIMIT} × folga ${LAB_MEMORY_HEADROOM_FACTOR})"
log "Pré-checagem de memória: ${PRECHECK_MEM}"

# --------------------------- imagem do laboratório (correção 3)
if [ -n "${LAB_IMAGE}" ]; then
    LAB_IMAGE_OVERRIDDEN=1
    LAB_IMAGE_FINAL="${LAB_IMAGE}"
    log "LAB_IMAGE informado por variável de ambiente: ${LAB_IMAGE_FINAL} (override documentado; verificação de versão publicada da imagem oficial dispensada; detecção da major da produção permaneceu obrigatória)."
else
    case " ${POSTGRES_OFFICIAL_MAJORS} " in
        *" ${PROD_MAJOR} "*)
            LAB_IMAGE_FINAL="postgres:${PROD_MAJOR}"
            ;;
        *)
            LAB_IMAGE_FINAL="(não determinada)"
            die "A versão major detectada da produção (${PROD_MAJOR}) NÃO corresponde a uma versão publicada da imagem oficial postgres do Docker Hub. Sem imagem oficial correspondente, o laboratório não é criado — nenhum recurso foi criado (exit ${EXIT_PROD_VERSION_UNKNOWN}). Para usar outra imagem explicitamente: LAB_IMAGE=<imagem> bash $0 <backup>." "${EXIT_PROD_VERSION_UNKNOWN}"
            ;;
    esac
fi

# ============ (v2.6.0 — Correção 3) COMPROVAÇÃO DE ORIGEM DO BACKUP ==========
# Diferenciação inequívoca:
#   (a) Integridade física do arquivo: conferida via gzip -t + sha256 calculado;
#   (b) Correspondência com manifesto: hash bate com arquivo .manifesto/.sha256;
#   (c) Comprovação de origem: requer evidência adicional confiável e verificável
#       (ex.: carimbo/assinatura criptográfica imutável). Sem isso, um manifesto
#       com hash e nome de contêiner comprova apenas CORRESPONDÊNCIA, não origem.
# Expressão "ORIGEM COMPROVADA" NUNCA é emitida sem tais evidências suficientes.
ORIGEM_BACKUP_STATUS="NÃO COMPROVADA"
ORIGEM_DETALHE="Checksum e metadados de arquivo atestam apenas integridade física; não comprovam a identidade do banco de origem."
MANIFESTO_STATUS="NENHUM MANIFESTO ENCONTRADO"
BASE_NAME="$(basename "${BACKUP_FILE}")"
CHECKSUM_NORM="$(norm_hash "${CHECKSUM_SHA256}")"
for MF in \
    "${BACKUP_FILE}.manifesto" \
    "${BACKUP_FILE}.manifest" \
    "${BACKUP_FILE}.sha256" \
    "${BACKUP_ROOT}/manifestos/${BASE_NAME}.manifesto"; do
    if [ -f "${MF}" ]; then
        MF_SHA_NORM="$(norm_hash "$(awk 'NR==1 {print $1; exit}' "${MF}" 2>>"${LOG_FILE}")")"
        if [ -n "${MF_SHA_NORM}" ] && [ -n "${CHECKSUM_NORM}" ] && [ "${MF_SHA_NORM}" = "${CHECKSUM_NORM}" ]; then
            # Campo EXPLÍCITO de identidade do banco/container de origem
            MF_IDENT_LINE="$(grep -iE 'container[_ -]?origem|banco[_ -]?origem|db[_ -]?origem|database[_ -]?origem|identidade[_ -]?(do[_ -])?(banco|container)|^[[:space:]]*container[[:space:]]*[=:]|^[[:space:]]*banco[[:space:]]*[=:]|^[[:space:]]*database[[:space:]]*[=:]' "${MF}" 2>>"${LOG_FILE}" | head -n 1 || true)"
            if [ -z "${MF_IDENT_LINE}" ]; then
                MF_IDENT_LINE="$(grep -iE 'container|banco|database|origem' "${MF}" 2>>"${LOG_FILE}" | head -n 1 || true)"
            fi
            MF_IDENT_VALUE=""
            if [ -n "${MF_IDENT_LINE}" ]; then
                MF_IDENT_VALUE="$(printf '%s\n' "${MF_IDENT_LINE}" \
                    | sed -E 's/^[^=:]+[=:][[:space:]]*//' \
                    | tr -d "\"'" \
                    | awk '{print $1}' || true)"
            fi
            MF_IDENT_NORM="$(norm_hash "${MF_IDENT_VALUE:-}")"
            PROD_IDENT_NORM="$(norm_hash "${PROD_CONTAINER}")"
            log "Manifesto ${MF}: hash conferido; linha de identidade e valor registrados apenas neste log restrito; identidade normalizada: ${MF_IDENT_NORM:-vazia} vs produção: ${PROD_IDENT_NORM}"
            if [ -z "${MF_IDENT_NORM}" ]; then
                ORIGEM_BACKUP_STATUS="NÃO COMPROVADA (correspondência parcial com manifesto: hash conferido, porém SEM identificador do banco/container de origem)"
                MANIFESTO_STATUS="CORRESPONDÊNCIA DE HASH (sem identificador de contêiner)"
                ORIGEM_DETALHE="Manifesto: ${MF}. O hash confere (comparação normalizada), mas falta campo de identidade de contêiner. Checksum isolado não comprova origem."
            elif [ "${MF_IDENT_NORM}" != "${PROD_IDENT_NORM}" ]; then
                ORIGEM_BACKUP_STATUS="NÃO COMPROVADA (divergência de identidade: contêiner declarado difere da produção detectada)"
                MANIFESTO_STATUS="DIVERGÊNCIA DE IDENTIDADE NO MANIFESTO"
                ORIGEM_DETALHE="Manifesto: ${MF}. A identidade de origem declarada diverge da produção detectada (valores registrados apenas no log restrito)."
            else
                # Hash confere e identidade bate com a produção, mas isoladamente isso comprova CORRESPONDÊNCIA, não origem indelével.
                ORIGEM_BACKUP_STATUS="NÃO COMPROVADA (correspondente ao manifesto: hash sha256 e contêiner conferem, porém sem assinatura/carimbo indelével na criação)"
                MANIFESTO_STATUS="CORRESPONDENTE AO MANIFESTO (hash sha256 e identidade do contêiner conferidos)"
                ORIGEM_DETALHE="Manifesto: ${MF}. Hash e contêiner conferem com o arquivo e com a produção. A correspondência técnica está verificada, mas a origem efetiva permanece formalmente classificada como NÃO COMPROVADA por ausência de evidência criptográfica/assinada produzida na criação."
            fi
        else
            ORIGEM_BACKUP_STATUS="NÃO COMPROVADA (manifesto presente, porém hash DIVERGENTE do arquivo atual)"
            MANIFESTO_STATUS="HASH DIVERGENTE DO MANIFESTO"
            ORIGEM_DETALHE="Manifesto: ${MF}. O hash registrado no manifesto diverge do hash calculado do arquivo de backup."
        fi
        break
    fi
done
log "ORIGEM_BACKUP_STATUS: ${ORIGEM_BACKUP_STATUS}"
log "MANIFESTO_STATUS: ${MANIFESTO_STATUS}"

# ================ EXTRAÇÃO DAS ROLES REAIS DA PRODUÇÃO (obrigatória) =========
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

# ============ (correção 5a) SANITIZAÇÃO ROBUSTA DAS ROLES (awk) ==============
# Antes: pipeline grep -vE/sed OPERADO POR LINHA — falhava em CREATE ROLE
# multilinha e podia remover conteúdo legítimo. Agora um filtro awk MONTA a
# instrução completa (bufferizando linhas até o ';' terminal), de modo que
# CREATE ROLE multilinha é suportado, e:
#   - descarta CREATE DATABASE / ALTER DATABASE / COMMENT ON DATABASE /
#     ALTER ROLE ... IN DATABASE e meta-comandos psql iniciados por '\'
#     (\connect, \restrict, \unrestrict, \password...);
#   - PRESERVA todo o restante (ALTER ROLE simples, GRANT/REVOKE, comentários);
#   - envolve CADA CREATE ROLE em bloco DO que tolera EXCLUSIVAMENTE a exceção
#     duplicate_object (role já existente na imagem); qualquer OUTRA exceção
#     propaga e interrompe o teste.
# Observação: a fronteira de instrução é ';' no fim da linha — formato sempre
# emitido pelo pg_dumpall. Um ';' dentro de literal (não ocorre em roles/
# hashes emitidos pelo pg_dumpall) quebraria a montagem — nesse caso a carga
# no laboratório falha e o teste aborta (comportamento seguro, nunca silencioso).
if ! awk '
    BEGIN { buf = ""; role = 0 }
    {
        if (buf != "") {
            buf = buf "\n" $0
        } else {
            line = $0
            if (line ~ /^[[:space:]]*$/) { print; next }
            if (line ~ /^[[:space:]]*\\/)                                   { buf = line }
            else if (line ~ /^[[:space:]]*CREATE[[:space:]]+DATABASE/)      { buf = line }
            else if (line ~ /^[[:space:]]*ALTER[[:space:]]+DATABASE/)       { buf = line }
            else if (line ~ /^[[:space:]]*COMMENT[[:space:]]+ON[[:space:]]+DATABASE/) { buf = line }
            else if (line ~ /^[[:space:]]*ALTER[[:space:]]+ROLE[^;]*IN[[:space:]]+DATABASE/) { buf = line }
            else if (line ~ /^[[:space:]]*CREATE[[:space:]]+ROLE/)          { buf = line; role = 1 }
            else { print; next }
        }
        if (buf ~ /;[[:space:]]*$/) {
            if (role) {
                sub(/;[[:space:]]*$/, "", buf)
                print "DO $$BEGIN " buf "; EXCEPTION WHEN duplicate_object THEN NULL; END$$;"
                role = 0
            }
            buf = ""
        }
    }
    END {
        if (buf != "" && role) {
            sub(/;[[:space:]]*$/, "", buf)
            print "DO $$BEGIN " buf "; EXCEPTION WHEN duplicate_object THEN NULL; END$$;"
        }
    }
' "${GLOBALS_RAW_FILE}" > "${GLOBALS_SANITIZED_FILE}" 2>>"${LOG_FILE}"; then
    RESULT_ROLES="FALHA NA SANITIZAÇÃO DOS GLOBALS — teste interrompido"
    die "Falha ao sanitizar o arquivo de globals. O teste foi INTERROMPIDO (exit ${EXIT_ROLES_EXTRACT_FAILED})." "${EXIT_ROLES_EXTRACT_FAILED}"
fi
chmod 600 "${GLOBALS_SANITIZED_FILE}" 2>/dev/null || true

if [ ! -s "${GLOBALS_SANITIZED_FILE}" ]; then
    RESULT_ROLES="FALHA NA SANITIZAÇÃO DOS GLOBALS (resultado vazio) — teste interrompido"
    die "A sanitização das roles resultou em arquivo vazio. O teste foi INTERROMPIDO (exit ${EXIT_ROLES_EXTRACT_FAILED})." "${EXIT_ROLES_EXTRACT_FAILED}"
fi

# --- (correção 5a) VERIFICAÇÃO PÓS-GERAÇÃO: nada de CREATE/ALTER DATABASE,
#     COMMENT ON DATABASE ou \connect pode ter sobrado no arquivo sanitizado.
if grep -nE '^[[:space:]]*(CREATE[[:space:]]+DATABASE|ALTER[[:space:]]+DATABASE|COMMENT[[:space:]]+ON[[:space:]]+DATABASE|\\connect)' \
        "${GLOBALS_SANITIZED_FILE}" >>"${LOG_FILE}" 2>&1; then
    RESULT_ROLES="FALHA NA SANITIZAÇÃO (resíduo de CREATE/ALTER DATABASE ou \\connect no arquivo sanitizado) — teste interrompido"
    log "VERIFICAÇÃO PÓS-GERAÇÃO FALHOU: resíduos listados acima (apenas neste log restrito)."
    die "A verificação pós-geração da sanitização encontrou RESÍDUOS de CREATE/ALTER DATABASE, COMMENT ON DATABASE ou \\connect no arquivo sanitizado. O teste foi INTERROMPIDO antes de qualquer carga (exit ${EXIT_ROLES_EXTRACT_FAILED})." "${EXIT_ROLES_EXTRACT_FAILED}"
fi
log "Verificação pós-geração da sanitização: OK (nenhum resíduo de CREATE/ALTER DATABASE / COMMENT ON DATABASE / \\connect)."

# ================================================================ LABORATÓRIO
# Imagem postgres:<major> da produção (imagem OFICIAL — ver nota de
# compatibilidade no cabeçalho); isolamento total: --network none, volume
# dedicado desta sessão, contêiner com label de identidade.
say "🐳 Imagem do laboratório: ${LAB_IMAGE_FINAL} (rede: nenhuma — isolamento total)"

# ---- (v2.5.1 — Pendência 1) caminho de dados da imagem oficial postgres ----
# Majors <= 17: PGDATA/VOLUME da imagem = /var/lib/postgresql/data.
# Majors >= 18: VOLUME = /var/lib/postgresql e PGDATA =
#               /var/lib/postgresql/<major>/docker (docker-library/postgres
#               PR #1259). Montar o volume EXATAMENTE no VOLUME declarado
#               pela imagem correspondente à major detectada evita que o
#               Docker crie um VOLUME ANÔNIMO para o subcaminho de dados —
#               resíduo com os dados restaurados que o cleanup não alcançava.
if [ "${PROD_MAJOR}" -ge 18 ]; then
    LAB_VOLUME_MOUNT="/var/lib/postgresql"
    LAB_PGDATA="/var/lib/postgresql/${PROD_MAJOR}/docker"
else
    LAB_VOLUME_MOUNT="/var/lib/postgresql/data"
    LAB_PGDATA="/var/lib/postgresql/data"
fi
log "Montagem do volume do lab: ${LAB_VOLUME} -> ${LAB_VOLUME_MOUNT} (PGDATA: ${LAB_PGDATA})"

if ! docker image inspect "${LAB_IMAGE_FINAL}" >>"${LOG_FILE}" 2>&1; then
    say "ℹ️ Imagem ${LAB_IMAGE_FINAL} ausente localmente; efetuando docker pull..."
    if ! docker pull "${LAB_IMAGE_FINAL}" >>"${LOG_FILE}" 2>&1; then
        die "Não foi possível obter a imagem base do laboratório (${LAB_IMAGE_FINAL}). O teste foi INTERROMPIDO (exit ${EXIT_LAB_IMAGE_UNAVAILABLE})." "${EXIT_LAB_IMAGE_UNAVAILABLE}"
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
        -e PGDATA="${LAB_PGDATA}" \
        -v "${LAB_VOLUME}:${LAB_VOLUME_MOUNT}" \
        "${LAB_IMAGE_FINAL}" >>"${LOG_FILE}" 2>&1; then
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
# existir no laboratório. Faltando qualquer uma → aborta. (preservada — corr. 5a)
# NOTA: no arquivo sanitizado cada CREATE ROLE está dentro de um bloco
# "DO $$BEGIN CREATE ROLE ...", por isso o casamento NÃO está ancorado no
# início da linha.
sed -nE 's/^.*CREATE[[:space:]]+ROLE "?([A-Za-z_][A-Za-z0-9_$]*)"?.*$/\1/p' \
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
RESULT_ROLES="COMPROVADA — roles reais da produção (pg_dumpall --globals-only) carregadas no laboratório; roles esperadas: ${EXPECTED_ROLES_COUNT}; ausentes: 0; exceção tolerada: apenas duplicate_object; sanitização verificada pós-geração (sem resíduos de CREATE/ALTER DATABASE ou \\connect); nenhuma role genérica/de fallback utilizada."
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

CONFERIDOS_COUNT="$(grep -c '^CONFERIDO' "${CONFERIDOS_FILE}" 2>/dev/null || true)"
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

# ================================================================ FLUXO FINAL
if [ "${DIVERGENCES_COUNT}" -gt 0 ]; then
    log "Fim da execução: divergências estruturais detectadas."
    exit "${EXIT_VALIDATION_FAILED}"
fi
log "Fim da execução sem divergências de contagem."
exit "${EXIT_OK}"
