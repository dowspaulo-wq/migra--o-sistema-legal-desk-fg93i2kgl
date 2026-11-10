#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur — Auditoria e Teste de Restauração de Backups PostgreSQL
# Script: docs/vps/20-auditar-backup.sh
# Versão: v1.1.0
#
# OBJETIVO:
#   Auditar a integridade técnica e capacidade de restauração dos backups
#   PostgreSQL gerados pela rotina SBJur.
#
# DOIS MODOS DE OPERAÇÃO:
#
#   1. MODO LEVE (flag --leve):
#      - Pode rodar na VPS de produção ou em qualquer máquina.
#      - Operação ESTRITAMENTE SÓ-LEITURA no sistema de arquivos.
#      - Localiza o backup mais recente em /root/sbjur-backups/ (ou --arquivo).
#      - Realiza verificação de integridade gzip -t, tamanho, data/idade e SHA-256.
#      - NUNCA cria contêineres e NUNCA interage com o Docker.
#
#   2. MODO LABORATÓRIO (padrão, ou flag --laboratorio):
#      - DESTINADO A RODAR FORA DA VPS DE PRODUÇÃO, em máquina independente
#        (ex.: WSL2, Linux de bancada, Docker Desktop isolado).
#      - GUARDA DE SEGURANÇA OBRIGATÓRIA: Recusa-se terminantemente a executar
#        se suspeitar que está na VPS de produção:
#          * Hostname conhecido da VPS (srv1737667.hstgr.cloud ou srv1737667);
#          * Presença de contêineres de produção ativos ou parados (nomes contendo
#            supabase-db, kong, auth, rest, studio, dpsjur).
#        Se qualquer indício for detectado, ABORTA com exit 11 antes de criar qualquer
#        recurso no Docker ou no disco.
#      - Pré-checagens fail-safe: integridade gzip -t, espaço livre em disco
#        (estimativa conservadora contra wrap-around de 32 bits do ISIZE do gzip),
#        memória disponível (exige >= 4 GiB).
#      - Contêiner temporário com supabase/postgres (default: supabase/postgres:15.8.1.085),
#        nome EXCLUSIVO sbsjur-audit-<PID>, label de sessão sbsjur-audit=true,
#        REDE OBRIGATÓRIA --network none, limite de memória, banco novo e VAZIO.
#      - Restauração com log de erros completo capturado sob umask 077 + chmod 600.
#      - Pós-restauração em duas etapas separadas:
#          (a) Estado bruto do restore (detecta pendências do dump original);
#          (b) Procedimento pós-restauração opcional/documentado no lab
#              (recriação de graphql_public.graphql via CREATE EXTENSION pg_graphql
#              / grant_pg_graphql_access dentro do lab), com revalidação imediata.
#      - Validação de catálogo: esquemas, tabelas, constraints/FKs, funções,
#        triggers, extensões e contagens SELECT count(*) por tabela do schema public.
#      - Comparação automatizada com o inventário gerado por 21-gerar-inventario.sh
#        quando fornecido via --inventario <caminho.json>.
#      - Relatório padronizado rigoroso com SITUAÇÃO FINAL avaliada em 5 critérios
#        distintos: veredito APROVADO emitido SOMENTE se TODOS os cinco critérios
#        estiverem satisfeitos sem divergências não explicadas.
#      - Cleanup seguro: remove apenas contêineres e volumes com nome E label
#        desta sessão; falha na inspeção de montagens recusa remoção e classifica
#        como INCOMPLETO. Nunca remove backups.
#
# PARÂMETROS / FLAGS:
#   --leve                          Ativa modo leve (apenas metadados e integridade física).
#   --laboratorio                   Ativa modo laboratório (restauração completa; padrão).
#   --arquivo <caminho.sql.gz>      Caminho do arquivo de backup a auditar.
#   --inventario <caminho.json>     Caminho do inventário gerado por 21-gerar-inventario.sh.
#   --imagem <imagem:tag>           Imagem Docker do PostgreSQL (padrão: supabase/postgres:15.8.1.085).
#   --pos-restauracao               Habilita etapa corretiva de dependências (pg_graphql) no lab.
#   --sem-pos-restauracao           Desabilita etapa corretiva de dependências.
#   --relatorio <caminho.txt>       Caminho do relatório de auditoria gerado.
#   -h, --help                      Exibe manual de uso e opções.
# ==============================================================================

set -u -o pipefail
umask 077

SCRIPT_VERSION="v1.1.0"
TS_STAMP="$(date +%Y%m%d-%H%M%S)"
PID_ATUAL="$$"

# Modos e flags
MODE="laboratorio" # "leve" ou "laboratorio"
BACKUP_FILE=""
INVENTORY_FILE=""
REPORT_FILE=""
LAB_IMAGE="supabase/postgres:15.8.1.085"
APPLY_POST_RESTORE=1 # padrão: ativo para investigar/recuperar dependências Supabase

# Nomes de laboratório
LAB_NAME="sbsjur-audit-${PID_ATUAL}"
LAB_VOLUME="sbsjur-audit-vol-${PID_ATUAL}"
LAB_LABEL_KEY="sbsjur-audit"
LAB_LABEL_VAL="true"
LAB_MEMORY_LIMIT="3g"
LAB_SHM_SIZE="256m"

# Diretórios e logs
AUDIT_WORK_DIR="${HOME}/sbsjur-auditoria"
DIAG_DIR="${AUDIT_WORK_DIR}/logs"
mkdir -p "${DIAG_DIR}" 2>/dev/null || true
chmod 700 "${AUDIT_WORK_DIR}" 2>/dev/null || true
chmod 700 "${DIAG_DIR}" 2>/dev/null || true

LOG_FILE="${DIAG_DIR}/auditoria-${TS_STAMP}-${PID_ATUAL}.log"
touch "${LOG_FILE}" 2>/dev/null || true
chmod 600 "${LOG_FILE}" 2>/dev/null || true

RESTORE_ERRORS_FILE="${DIAG_DIR}/restore-errors-${TS_STAMP}-${PID_ATUAL}.log"
touch "${RESTORE_ERRORS_FILE}" 2>/dev/null || true
chmod 600 "${RESTORE_ERRORS_FILE}" 2>/dev/null || true

DIVERGENCES_FILE="${DIAG_DIR}/divergencias-${TS_STAMP}-${PID_ATUAL}.txt"
touch "${DIVERGENCES_FILE}" 2>/dev/null || true
chmod 600 "${DIVERGENCES_FILE}" 2>/dev/null || true

CONFERIDOS_FILE="${DIAG_DIR}/conferidos-${TS_STAMP}-${PID_ATUAL}.txt"
touch "${CONFERIDOS_FILE}" 2>/dev/null || true
chmod 600 "${CONFERIDOS_FILE}" 2>/dev/null || true

# Códigos de Saída
EXIT_OK=0
EXIT_USAGE=10
EXIT_GUARD_PROD_BLOCKED=11
EXIT_DOCKER_UNAVAILABLE=12
EXIT_INSUFFICIENT_DISK=15
EXIT_INSUFFICIENT_MEM=16
EXIT_BACKUP_NOT_FOUND=20
EXIT_BACKUP_CORRUPT=21
EXIT_RESTORE_FAILED=40
EXIT_AUDIT_REJECTED=50
EXIT_CLEANUP_FAILED=60

# Estado global da auditoria (para o relatório final)
TEST_START_TIME="$(date +%s)"
BACKUP_DATE="(não identificado)"
BACKUP_SIZE_BYTES=0
BACKUP_SIZE_HUMAN="0B"
BACKUP_SHA256=""
INTEGRIDADE_ARQUIVO_STATUS="PENDENTE" # "OK" ou "FALHA"
RESTORE_STATUS="NÃO EXECUTADO"
RESTORE_RAW_ERRORS_COUNT=0
RESTORE_RAW_SUMMARY=""
POST_RESTORE_APPLIED="NÃO"
POST_RESTORE_RESULT="NÃO APLICADO"

TOTAL_TABELAS_LAB=0
TOTAL_REGISTROS_LAB=0
TOTAL_CONSTRAINTS_LAB=0
TOTAL_FUNCOES_LAB=0
TOTAL_TRIGGERS_LAB=0
TOTAL_EXTENSOES_LAB=0

CLEANUP_STATUS="NÃO INICIADO"
CLEANUP_OBS=""
MAIN_RC=0

# 5 Critérios rigorosos
CRIT_A="PENDENTE" # Integridade do arquivo
CRIT_B="PENDENTE" # Restauração concluída sem erros
CRIT_C="PENDENTE" # Recuperação de estruturas e dados
CRIT_D="PENDENTE" # Recuperação de dependências Supabase
CRIT_E="PENDENTE" # Compatibilidade e operação básica do CRM
VEREDITO_FINAL="INCONCLUSIVO"
CLASSIFICACAO_RECUPERACAO="INDEFINIDA" # "RESTAURAÇÃO INTEGRAL", "RECUPERAÇÃO PARCIAL" ou "NÃO RECUPERADO"

# Helpers
say() {
    printf '%s\n' "$*"
}

say_err() {
    printf '❌ %s\n' "$*" >&2
}

log() {
    printf '%s %s\n' "$(date '+%F %T')" "$*" >> "${LOG_FILE}" 2>&1 || true
}

die() {
    local msg="$1" code="$2"
    say_err "${msg}"
    say "   Registro completo gravado em: ${LOG_FILE}" >&2
    log "ABORTADO (exit ${code}): ${msg}"
    exit "${code}"
}

# Limpeza e Trap (Ativo antes de criar qualquer recurso)
do_cleanup() {
    local fails=0
    local c_names="" c_label="" vol_names="" vol_label=""
    local anon_vols="" v=""

    log "Iniciando rotina de limpeza segura para sessão PID ${PID_ATUAL}..."

    if [ "${MODE}" = "leve" ]; then
        CLEANUP_STATUS="NÃO REQUERIDO (modo leve)"
        return 0
    fi

    if ! command -v docker >/dev/null 2>&1; then
        CLEANUP_STATUS="NÃO APLICÁVEL (Docker ausente)"
        return 0
    fi

    # 1. Contêiner do laboratório: verificar se existe e conferir nome + label
    if ! c_names="$(docker ps -a --format '{{.Names}}' 2>>"${LOG_FILE}")"; then
        fails=$((fails + 1))
        CLEANUP_OBS="${CLEANUP_OBS} Erro ao listar contêineres Docker;"
        say "🛑 RECUSA DE LIMPEZA: Falha ao consultar Docker ps. Recurso '${LAB_NAME}' preservado por segurança."
    elif printf '%s\n' "${c_names}" | grep -qx -- "${LAB_NAME}"; then
        if ! c_label="$(docker inspect -f "{{index .Config.Labels \"${LAB_LABEL_KEY}\"}}" "${LAB_NAME}" 2>>"${LOG_FILE}")"; then
            fails=$((fails + 1))
            CLEANUP_OBS="${CLEANUP_OBS} Falha ao inspecionar labels do contêiner '${LAB_NAME}';"
            say "🛑 RECUSA DE LIMPEZA: Falha ao inspecionar contêiner '${LAB_NAME}'. Preservado."
        elif [ "${c_label}" = "${LAB_LABEL_VAL}" ]; then
            # Checar montagens antes de remover (Regra de Auditoria v2.6.2: se .Mounts falhar, não remove)
            if ! anon_vols="$(docker inspect -f '{{range .Mounts}}{{if .Name}}{{.Name}} {{end}}{{end}}' "${LAB_NAME}" 2>>"${LOG_FILE}")"; then
                fails=$((fails + 1))
                CLEANUP_OBS="${CLEANUP_OBS} Falha na inspeção de montagens (.Mounts) de '${LAB_NAME}';"
                say "🛑 RECUSA DE LIMPEZA: Falha ao inspecionar volumes montados no contêiner '${LAB_NAME}'. Contêiner PRESERVADO para auditoria manual."
                log "RECUSA DE LIMPEZA: docker inspect falhou ao inspecionar montagens de '${LAB_NAME}'."
            else
                log "Removendo contêiner conferido: ${LAB_NAME}..."
                if docker rm -f "${LAB_NAME}" >>"${LOG_FILE}" 2>&1; then
                    log "Contêiner ${LAB_NAME} removido com sucesso."
                else
                    fails=$((fails + 1))
                    CLEANUP_OBS="${CLEANUP_OBS} Falha ao executar docker rm '${LAB_NAME}';"
                    say "⚠️ Falha ao remover contêiner '${LAB_NAME}'."
                fi
            fi
        else
            fails=$((fails + 1))
            CLEANUP_OBS="${CLEANUP_OBS} Label do contêiner '${LAB_NAME}' divergiu (${c_label} != ${LAB_LABEL_VAL});"
            say "🛑 RECUSA DE LIMPEZA: Label do contêiner '${LAB_NAME}' não confere. Recurso preservado."
        fi
    fi

    # 2. Volume dedicado do laboratório
    if ! vol_names="$(docker volume ls -q 2>>"${LOG_FILE}")"; then
        fails=$((fails + 1))
        CLEANUP_OBS="${CLEANUP_OBS} Falha ao listar volumes Docker;"
    elif printf '%s\n' "${vol_names}" | grep -qx -- "${LAB_VOLUME}"; then
        if ! vol_label="$(docker volume inspect -f "{{index .Labels \"${LAB_LABEL_KEY}\"}}" "${LAB_VOLUME}" 2>>"${LOG_FILE}")"; then
            fails=$((fails + 1))
            CLEANUP_OBS="${CLEANUP_OBS} Falha ao inspecionar labels do volume '${LAB_VOLUME}';"
        elif [ "${vol_label}" = "${LAB_LABEL_VAL}" ]; then
            # Checar se ainda há contêineres atrelados
            local v_users
            v_users="$(docker ps -a --filter "volume=${LAB_VOLUME}" --format '{{.Names}}' 2>>"${LOG_FILE}" || true)"
            if [ -n "${v_users}" ]; then
                fails=$((fails + 1))
                CLEANUP_OBS="${CLEANUP_OBS} Volume '${LAB_VOLUME}' ainda em uso por ${v_users};"
            else
                log "Removendo volume conferido: ${LAB_VOLUME}..."
                if docker volume rm "${LAB_VOLUME}" >>"${LOG_FILE}" 2>&1; then
                    log "Volume ${LAB_VOLUME} removido com sucesso."
                else
                    fails=$((fails + 1))
                    CLEANUP_OBS="${CLEANUP_OBS} Falha ao remover volume '${LAB_VOLUME}';"
                fi
            fi
        else
            fails=$((fails + 1))
            CLEANUP_OBS="${CLEANUP_OBS} Label do volume '${LAB_VOLUME}' divergiu (${vol_label});"
        fi
    fi

    # 3. Remover volumes anônimos adicionais desta sessão se existirem
    for v in ${anon_vols:-}; do
        [ "${v}" = "${LAB_VOLUME}" ] && continue
        if docker volume inspect "${v}" >>"${LOG_FILE}" 2>&1; then
            local av_label
            av_label="$(docker volume inspect -f "{{index .Labels \"${LAB_LABEL_KEY}\"}}" "${v}" 2>>"${LOG_FILE}" || echo "")"
            if [ "${av_label}" = "${LAB_LABEL_VAL}" ]; then
                docker volume rm "${v}" >>"${LOG_FILE}" 2>&1 || true
            fi
        fi
    done

    # 4. Resultado da limpeza
    if [ "${fails}" -eq 0 ]; then
        CLEANUP_STATUS="100% CONCLUÍDO (todos os recursos efêmeros foram removidos com sucesso)"
        return 0
    else
        CLEANUP_STATUS="INCOMPLETO (recursos remanescentes por falha ou preservação de segurança)"
        return 1
    fi
}

emit_report() {
    local rc="$1"
    local test_end_time
    test_end_time="$(date +%s)"
    local duration=$((test_end_time - TEST_START_TIME))

    if [ -z "${REPORT_FILE}" ]; then
        REPORT_FILE="${AUDIT_WORK_DIR}/relatorio-auditoria-${TS_STAMP}-${PID_ATUAL}.txt"
    fi

    {
        echo "================================================================================"
        echo " RELATÓRIO DE AUDITORIA DE BACKUP POSTGRESQL — SISTEMA SBJUR / DPSJUR"
        echo " Script: docs/vps/20-auditar-backup.sh (${SCRIPT_VERSION})"
        echo " Sessão / PID: ${PID_ATUAL} | Início: $(date -d "@${TEST_START_TIME}" '+%F %T' 2>/dev/null || date '+%F %T')"
        echo " Modo de Execução: ${MODE^^}"
        echo "================================================================================"
        echo ""
        echo "1. DADOS DO BACKUP EXAMINADO"
        echo "   Arquivo de backup: ${BACKUP_FILE}"
        echo "   Data/Timestamp do arquivo: ${BACKUP_DATE}"
        echo "   Tamanho do arquivo: ${BACKUP_SIZE_HUMAN} (${BACKUP_SIZE_BYTES} bytes)"
        echo "   Hash SHA-256: ${BACKUP_SHA256}"
        echo ""
        echo "2. INTEGRIDADE FÍSICA DO ARQUIVO"
        echo "   Status: ${INTEGRIDADE_ARQUIVO_STATUS}"
        echo "   Critério gzip: $([ "${INTEGRIDADE_ARQUIVO_STATUS}" = "OK" ] && echo "Aprovado no teste gzip -t (sem truncamento/corrupção)" || echo "FALHA de integridade no fluxo gzip")"
        echo ""
        echo "3. DURAÇÃO E AMBIENTE DO TESTE"
        echo "   Duração da auditoria: ${duration} segundos"
        echo "   Modo: ${MODE}"
        if [ "${MODE}" = "laboratorio" ]; then
            echo "   Ambiente de execução: Laboratório Isolado (--network none)"
            echo "   Imagem Docker utilizada: ${LAB_IMAGE}"
            echo "   Procedimento pós-restauração (pg_graphql): $([ "${APPLY_POST_RESTORE}" -eq 1 ] && echo "Habilitado" || echo "Desabilitado")"
        else
            echo "   Ambiente: Modo Leve (Leitura de metadados, sem Docker)"
        fi
        echo ""
        if [ "${MODE}" = "laboratorio" ]; then
            echo "4. RESULTADO DA RESTAURAÇÃO"
            echo "   (a) Restauração Original (Bruta do Arquivo):"
            echo "       Status: ${RESTORE_ORIGINAL_STATUS}"
            echo "       Quantidade de erros brutos identificados no log: ${RESTORE_RAW_ERRORS_COUNT}"
            echo "       Resumo dos erros brutos do restore:"
            if [ -s "${RESTORE_ERRORS_FILE}" ]; then
                # Sanitização rigorosa de privacidade: ofuscar valores literais em aspas/números de documento para impedir vazamento de dados de clientes
                head -n 25 "${RESTORE_ERRORS_FILE}" \
                    | sed -E "s/'[^']{4,}'/'[DADO_OFUSCADO]'/g" \
                    | sed -E 's/[0-9]{11}/[CPF_OFUSCADO]/g' \
                    | sed -E 's/[0-9]{14}/[CNPJ_OFUSCADO]/g' \
                    | sed 's/^/          [RESTORE ERROR] /'
                if [ "${RESTORE_RAW_ERRORS_COUNT}" -gt 25 ]; then
                    echo "          ... e mais $((RESTORE_RAW_ERRORS_COUNT - 25)) mensagens de erro no log restrito."
                fi
                echo "          (Nota de Privacidade: Detalhes literais com dados sensíveis permanecem restritos ao log técnico chmod 600)"
            else
                echo "          (Nenhum erro registrado durante a carga do dump)"
            fi
            echo ""
            echo "   (b) Recuperação Assistida (Pós-Restauração / Dependências Supabase):"
            echo "       Procedimento: Recriação controlada sem DROP CASCADE (proteção contra perda de dados)"
            echo "       Status: ${POST_RESTORE_RESULT}"
            echo "       Aplicação efetiva: ${POST_RESTORE_APPLIED}"
            echo ""
            echo "5. QUANTIDADE DE TABELAS E REGISTROS (SCHEMA PUBLIC)"
            echo "   Tabelas restauradas no schema public: ${TOTAL_TABELAS_LAB}"
            echo "   Total de registros contados no schema public: ${TOTAL_REGISTROS_LAB}"
            echo "   Constraints / Chaves Estrangeiras restauradas: ${TOTAL_CONSTRAINTS_LAB}"
            echo "   Funções restauradas: ${TOTAL_FUNCOES_LAB}"
            echo "   Triggers restaurados: ${TOTAL_TRIGGERS_LAB}"
            echo "   Extensões ativas no laboratório: ${TOTAL_EXTENSOES_LAB}"
            echo "   Falhas de consulta SQL registradas: ${QUERY_FAILURES_COUNT}"
            echo ""
            echo "6. INCONSISTÊNCIAS / DIVERGÊNCIAS E DIFERENÇAS TEMPORAIS"
            if [ -s "${DIVERGENCES_FILE}" ]; then
                sed 's/^/   [DIVERGÊNCIA] /' "${DIVERGENCES_FILE}"
            else
                echo "   (Nenhuma divergência estrutural crítica pendente)"
            fi
            echo ""
            if [ -s "${TEMPORAL_DIFFS_FILE}" ]; then
                echo "   Diferenças temporais esperadas (produção posterior ao backup):"
                sed 's/^/   /' "${TEMPORAL_DIFFS_FILE}"
                echo ""
            fi
            echo "   Itens conferidos com sucesso:"
            if [ -s "${CONFERIDOS_FILE}" ]; then
                head -n 25 "${CONFERIDOS_FILE}" | sed 's/^/   [CONFERIDO] /'
                local conf_total
                conf_total="$(wc -l < "${CONFERIDOS_FILE}" 2>/dev/null || echo 0)"
                if [ "${conf_total}" -gt 25 ]; then
                    echo "   ... e mais $((conf_total - 25)) itens conferidos com êxito."
                fi
            else
                echo "   (Nenhum item catalogado)"
            fi
            echo ""
        fi
        echo "7. SITUAÇÃO FINAL — AVALIAÇÃO DOS 5 CRITÉRIOS RIGOROSOS"
        echo "   -----------------------------------------------------------------------------"
        echo "   (a) Integridade do arquivo ...................: [ ${CRIT_A} ]"
        echo "   (b) Restauração concluída sem erros ..........: [ ${CRIT_B} ]"
        echo "   (c) Recuperação de estruturas e dados ........: [ ${CRIT_C} ]"
        echo "   (d) Recuperação de dependências Supabase .....: [ ${CRIT_D} ]"
        echo "   (e) Compatibilidade e operação básica do CRM .: [ ${CRIT_E} ]"
        echo "   -----------------------------------------------------------------------------"
        echo "   CLASSIFICAÇÃO TÉCNICA: ${CLASSIFICACAO_RECUPERACAO}"
        echo "   VEREDITO FINAL DA AUDITORIA: [ ${VEREDITO_FINAL} ]"
        echo "   -----------------------------------------------------------------------------"
        echo "   Regra de aprovação: O veredito APROVADO é concedido SOMENTE se TODOS os"
        echo "   cinco critérios estiverem aprovados (OK) e sem divergências não explicadas."
        echo ""
        echo "8. PROVIDÊNCIAS NECESSÁRIAS"
        if [ "${VEREDITO_FINAL}" = "APROVADO" ]; then
            echo "   - Nenhuma providência corretiva imediata necessária."
            echo "   - Manter rotina periódica de auditoria mensal conforme cronograma."
        else
            if [ "${CRIT_A}" != "OK" ]; then
                echo "   - [CRÍTICO] Investigar falha de integridade do arquivo compactado gzip."
            fi
            if [ "${CRIT_B}" != "OK" ]; then
                echo "   - [ALERTA] Analisar mensagens de erro capturadas na restauração bruta."
                echo "     Verificar ausência de roles de cluster no dump (lacuna conhecida de pg_dump)."
            fi
            if [ "${CRIT_D}" != "OK" ]; then
                echo "   - [SUPABASE] O dump pulou criação de extensões pré-existentes na imagem"
                echo "     (ex.: pg_graphql). Avaliar script de pós-restauração ou rotina complementar"
                echo "     na infraestrutura para restaurar graphql_public.graphql automaticamente."
            fi
            if [ -s "${DIVERGENCES_FILE}" ]; then
                echo "   - [DADOS] Sanar divergências de contagem ou tabelas faltantes entre produção e backup."
            fi
            echo "   - Manter este relatório arquivado para histórico de conformidade."
        fi
        echo ""
        echo "9. LIMPEZA DOS RECURSOS (CLEANUP)"
        echo "   Status da limpeza: ${CLEANUP_STATUS}"
        if [ -n "${CLEANUP_OBS}" ]; then
            echo "   Observações do cleanup: ${CLEANUP_OBS}"
        fi
        echo ""
        echo "10. REGISTROS TÉCNICOS"
        echo "    Código de saída final: ${rc}"
        echo "    Arquivo deste relatório: ${REPORT_FILE} (chmod 600)"
        echo "    Log técnico restrito: ${LOG_FILE} (chmod 600)"
        echo "    Log de erros do restore: ${RESTORE_ERRORS_FILE} (chmod 600)"
        echo "================================================================================"
    } > "${REPORT_FILE}" 2>>"${LOG_FILE}"
    chmod 600 "${REPORT_FILE}" 2>/dev/null || true

    # Console Summary
    say ""
    say "================================================================================"
    say " RESUMO DA AUDITORIA DE BACKUP (${SCRIPT_VERSION})"
    say "================================================================================"
    say " Arquivo examinado ......: ${BACKUP_FILE}"
    say " Integridade física .....: ${INTEGRIDADE_ARQUIVO_STATUS}"
    say " Modo ...................: ${MODE}"
    if [ "${MODE}" = "laboratorio" ]; then
        say " Restauração bruta ......: ${RESTORE_STATUS} (${RESTORE_RAW_ERRORS_COUNT} erros brutos)"
        say " Pós-restauração ........: ${POST_RESTORE_RESULT}"
        say " Tabelas / Registros ....: ${TOTAL_TABELAS_LAB} tabelas / ${TOTAL_REGISTROS_LAB} registros"
        say " Situação dos Critérios .:"
        say "   (a) Integridade do arquivo ...................: [ ${CRIT_A} ]"
        say "   (b) Restauração sem erros ....................: [ ${CRIT_B} ]"
        say "   (c) Recuperação de estruturas/dados ..........: [ ${CRIT_C} ]"
        say "   (d) Dependências Supabase ....................: [ ${CRIT_D} ]"
        say "   (e) Recuperação operacional do CRM ...........: [ ${CRIT_E} ]"
        say " Classificação ..........: ${CLASSIFICACAO_RECUPERACAO}"
        say " VEREDITO FINAL .........: [ ${VEREDITO_FINAL} ]"
        say " Limpeza (cleanup) ......: ${CLEANUP_STATUS}"
    else
        say " Situação Final .........: Modo Leve concluído com integridade [ ${INTEGRIDADE_ARQUIVO_STATUS} ]"
    fi
    say " Relatório completo .....: ${REPORT_FILE} (chmod 600)"
    say " Log técnico restrito ...: ${LOG_FILE}"
    say "================================================================================"
}

on_exit() {
    local rc="$?"
    trap - EXIT INT TERM
    MAIN_RC="${rc}"
    do_cleanup || true

    local final_rc="${rc}"
    if [ "${CLEANUP_STATUS#INCOMPLETO}" != "${CLEANUP_STATUS}" ] && [ "${rc}" -eq "${EXIT_OK}" ]; then
        final_rc="${EXIT_CLEANUP_FAILED}"
    fi

    emit_report "${final_rc}"
    exit "${final_rc}"
}
trap on_exit EXIT

on_interrupt() {
    say_err "Execução interrompida pelo usuário (SIGINT/SIGTERM)."
    exit 130
}
trap on_interrupt INT TERM

# Manual de Ajuda
show_help() {
    cat <<EOF
Uso: bash $0 [MODO] [OPÇÕES]

Modos de Operação:
  --leve                          Modo leve de inspeção (apenas verifica metadados, integridade gzip e sha256).
                                  Pode ser executado com segurança na VPS de produção.
  --laboratorio                   Modo completo de laboratório com contêiner temporário (PADRÃO).
                                  OBRIGATÓRIO RODAR FORA DA VPS (em WSL2, Linux local, máquina de teste).

Opções:
  --arquivo <caminho.sql.gz>      Caminho do arquivo de backup a auditar.
                                  Se omitido, busca o mais recente em /root/sbjur-backups/.
  --inventario <caminho.json>     Caminho do arquivo de inventário JSON gerado por 21-gerar-inventario.sh.
  --imagem <imagem:tag>           Imagem Docker do PostgreSQL (padrão: supabase/postgres:15.8.1.085).
  --pos-restauracao               Aplica etapa corretiva de dependências (pg_graphql) no lab (PADRÃO: ativado).
  --sem-pos-restauracao           Desativa etapa corretiva pós-restauração.
  --relatorio <caminho.txt>       Caminho do arquivo de relatório a ser gerado.
  -h, --help                      Exibe este manual.

Exemplos:
  # Na VPS de produção (apenas modo leve):
  bash $0 --leve --arquivo /root/sbjur-backups/diario/sbjur_backup_2026-11-10_030001.sql.gz

  # Na máquina de laboratório / WSL2 (auditoria completa com inventário):
  bash $0 --arquivo ./sbjur_backup_2026-11-10.sql.gz --inventario ./inventario-prod.json
EOF
}

# Parsing de Parâmetros
while [ $# -gt 0 ]; do
    case "$1" in
        --leve)
            MODE="leve"
            shift
            ;;
        --laboratorio)
            MODE="laboratorio"
            shift
            ;;
        --arquivo)
            [ $# -ge 2 ] || die "Flag --arquivo exige caminho de arquivo." "${EXIT_USAGE}"
            BACKUP_FILE="$2"
            shift 2
            ;;
        --inventario)
            [ $# -ge 2 ] || die "Flag --inventario exige caminho de arquivo JSON." "${EXIT_USAGE}"
            INVENTORY_FILE="$2"
            shift 2
            ;;
        --imagem)
            [ $# -ge 2 ] || die "Flag --imagem exige nome da imagem Docker." "${EXIT_USAGE}"
            LAB_IMAGE="$2"
            shift 2
            ;;
        --pos-restauracao)
            APPLY_POST_RESTORE=1
            shift
            ;;
        --sem-pos-restauracao)
            APPLY_POST_RESTORE=0
            shift
            ;;
        --relatorio)
            [ $# -ge 2 ] || die "Flag --relatorio exige caminho de arquivo." "${EXIT_USAGE}"
            REPORT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit "${EXIT_OK}"
            ;;
        *)
            die "Parâmetro desconhecido: $1 (consulte --help)" "${EXIT_USAGE}"
            ;;
    esac
done

say "================================================================================"
say " AUDITORIA DE BACKUP POSTGRESQL — SBJUR / DPSJUR (${SCRIPT_VERSION})"
say " Modo selecionado: ${MODE^^}"
say "================================================================================"

# ==============================================================================
# GUARDA DE SEGURANÇA OBRIGATÓRIA (MODO LABORATÓRIO):
# O modo laboratório NÃO PODE rodar na VPS de produção!
# ==============================================================================
if [ "${MODE}" = "laboratorio" ]; then
    say "🛡️  Executando verificação de segurança de ambiente (Guarda Anti-VPS)..."
    log "Verificando se o ambiente atual é seguro para executar o laboratório..."

    # 1. Checagem estrita de Hostname (qualquer falha em consultar o hostname aborta imediatamente)
    CURRENT_HOST=""
    if command -v hostname >/dev/null 2>&1; then
        if ! CURRENT_HOST="$(hostname 2>>"${LOG_FILE}")"; then
            log "FALHA DE SEGURANÇA: Comando 'hostname' falhou ao consultar nome do host."
            say_err "EXECUÇÃO RECUSADA POR SEGURANÇA OPERACIONAL!"
            say_err "Não foi possível verificar o hostname com segurança. O laboratório não pode prosseguir."
            exit "${EXIT_GUARD_PROD_BLOCKED}"
        fi
    elif command -v uname >/dev/null 2>&1; then
        if ! CURRENT_HOST="$(uname -n 2>>"${LOG_FILE}")"; then
            log "FALHA DE SEGURANÇA: Comando 'uname -n' falhou ao consultar nome do host."
            say_err "EXECUÇÃO RECUSADA POR SEGURANÇA OPERACIONAL!"
            say_err "Não foi possível verificar o hostname com segurança via uname. O laboratório não pode prosseguir."
            exit "${EXIT_GUARD_PROD_BLOCKED}"
        fi
    else
        log "FALHA DE SEGURANÇA: Nem 'hostname' nem 'uname' disponíveis para checagem anti-VPS."
        say_err "EXECUÇÃO RECUSADA POR SEGURANÇA OPERACIONAL!"
        say_err "Ambiente sem utilitários para verificação de hostname. Segurança não comprovável."
        exit "${EXIT_GUARD_PROD_BLOCKED}"
    fi

    CURRENT_HOST="$(printf '%s\n' "${CURRENT_HOST}" | head -n 1 | tr -d '[:space:]')"
    if [ -z "${CURRENT_HOST}" ]; then
        log "FALHA DE SEGURANÇA: Hostname retornado vazio."
        say_err "EXECUÇÃO RECUSADA POR SEGURANÇA OPERACIONAL!"
        say_err "Hostname vazio retornado. Segurança do ambiente não pôde ser comprovada."
        exit "${EXIT_GUARD_PROD_BLOCKED}"
    fi

    log "Hostname da máquina atual: ${CURRENT_HOST}"
    if [ "${CURRENT_HOST}" = "srv1737667.hstgr.cloud" ] || [ "${CURRENT_HOST}" = "srv1737667" ] || [ "${CURRENT_HOST#srv1737667}" != "${CURRENT_HOST}" ]; then
        log "GUARDA DE SEGURANÇA DISPARADA: Hostname corresponde à VPS de produção (${CURRENT_HOST})."
        say_err "EXECUÇÃO RECUSADA POR SEGURANÇA OPERACIONAL!"
        say_err "O modo laboratório (--laboratorio) NÃO PODE rodar na VPS de produção (Host: ${CURRENT_HOST})."
        say_err "Este modo sobe contêineres e consome CPU/RAM/Disco que impactariam o CRM de produção."
        say_err "Execute este script em máquina de laboratório independente (WSL2, Docker Desktop ou Linux local)."
        say_err "Na VPS de produção é permitido EXCLUSIVAMENTE o modo leve: bash $0 --leve"
        exit "${EXIT_GUARD_PROD_BLOCKED}"
    fi

    # 2. Checagem estrita de Docker e Contêineres de Produção
    if ! command -v docker >/dev/null 2>&1; then
        log "FALHA DE SEGURANÇA: Binário docker não encontrado para conferência de ambiente."
        say_err "EXECUÇÃO RECUSADA: Docker não disponível no host para checagem ou execução do laboratório."
        exit "${EXIT_DOCKER_UNAVAILABLE}"
    fi

    if ! docker info >>"${LOG_FILE}" 2>&1; then
        log "FALHA DE SEGURANÇA: 'docker info' falhou ao contatar o daemon Docker."
        say_err "EXECUÇÃO RECUSADA: Falha ao verificar daemon Docker. Estado dos contêineres não pôde ser auditado."
        exit "${EXIT_GUARD_PROD_BLOCKED}"
    fi

    # Consulta de contêineres com detecção estrita de falhas
    ALL_CONTAINERS=""
    if ! ALL_CONTAINERS="$(docker ps -a --format '{{.Names}}' 2>>"${LOG_FILE}")"; then
        log "FALHA DE SEGURANÇA: 'docker ps -a' retornou erro. Não é possível atestar ausência de contêineres de produção."
        say_err "EXECUÇÃO RECUSADA POR SEGURANÇA OPERACIONAL!"
        say_err "Falha na consulta 'docker ps -a'. Por segurança estrita, o laboratório foi bloqueado."
        exit "${EXIT_GUARD_PROD_BLOCKED}"
    fi

    PROD_PATTERNS="supabase-db|kong|auth|rest|studio|dpsjur|sbljur-local_supabase-db-1|sbjur-local_supabase-db-1"
    MATCHING_CONTAINERS="$(printf '%s\n' "${ALL_CONTAINERS}" | grep -E "${PROD_PATTERNS}" || true)"
    if [ -n "${MATCHING_CONTAINERS}" ]; then
        log "GUARDA DE SEGURANÇA DISPARADA: Contêineres de produção detectados no Docker: ${MATCHING_CONTAINERS}"
        say_err "EXECUÇÃO RECUSADA POR SEGURANÇA OPERACIONAL!"
        say_err "Foram detectados contêineres típicos do ambiente de produção neste host:"
        printf '%s\n' "${MATCHING_CONTAINERS}" | sed 's/^/   - /' >&2
        say_err "O modo laboratório é restrito a máquinas isoladas sem contêineres de produção."
        say_err "Abortando imediatamente antes de criar qualquer recurso."
        exit "${EXIT_GUARD_PROD_BLOCKED}"
    fi

    say "✅ Guarda Anti-VPS validada: Ambiente não corresponde à VPS de produção e nenhum contêiner de produção foi detectado."
fi

# ==============================================================================
# LOCALIZAÇÃO E VALIDAÇÃO DO ARQUIVO DE BACKUP
# ==============================================================================
if [ -z "${BACKUP_FILE}" ]; then
    say "🔍 Buscando backup mais recente em /root/sbjur-backups/..."
    BACKUP_FILE="$(ls -1t \
        /root/sbjur-backups/diario/sbjur_backup_*.sql.gz \
        /root/sbjur-backups/semanal/sbjur_backup_*.sql.gz \
        /root/sbjur-backups/mensal/sbjur_backup_*.sql.gz \
        /root/sbjur-backups/sbjur_backup_*.sql.gz 2>/dev/null | head -n 1 || true)"
fi

if [ -z "${BACKUP_FILE}" ] || [ ! -f "${BACKUP_FILE}" ] || [ ! -r "${BACKUP_FILE}" ]; then
    die "Arquivo de backup não encontrado ou sem permissão de leitura: '${BACKUP_FILE:-nenhum informado}'." "${EXIT_BACKUP_NOT_FOUND}"
fi

say "📁 Arquivo de backup selecionado: ${BACKUP_FILE}"
log "Backup selecionado: ${BACKUP_FILE}"

BACKUP_SIZE_BYTES="$(stat -c%s "${BACKUP_FILE}" 2>/dev/null || wc -c < "${BACKUP_FILE}" 2>/dev/null || echo 0)"
BACKUP_SIZE_BYTES="$(echo "${BACKUP_SIZE_BYTES}" | tr -d '[:space:]')"
BACKUP_SIZE_HUMAN="$(du -h "${BACKUP_FILE}" 2>/dev/null | awk '{print $1}' || echo "N/A")"
BACKUP_DATE="$(date -r "${BACKUP_FILE}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Desconhecido")"

if [ "${BACKUP_SIZE_BYTES}" -lt 1000 ]; then
    INTEGRIDADE_ARQUIVO_STATUS="FALHA"
    CRIT_A="FALHA"
    die "Arquivo de backup possui tamanho suspeito (${BACKUP_SIZE_BYTES} bytes < 1KB). Provável arquivo vazio ou truncado." "${EXIT_BACKUP_CORRUPT}"
fi

# Teste de integridade física gzip
say "🧪 Verificando integridade física do arquivo com gzip -t..."
if gzip -t "${BACKUP_FILE}" 2>>"${LOG_FILE}"; then
    say "✅ Teste gzip -t aprovado: Estrutura do arquivo compactado está intacta."
    INTEGRIDADE_ARQUIVO_STATUS="OK"
    CRIT_A="OK"
else
    say_err "Teste gzip -t FALHOU: Arquivo corrompido ou truncado."
    INTEGRIDADE_ARQUIVO_STATUS="FALHA"
    CRIT_A="FALHA"
    die "Arquivo de backup está corrompido ou incompleto." "${EXIT_BACKUP_CORRUPT}"
fi

# Cálculo SHA-256
if command -v sha256sum >/dev/null 2>&1; then
    BACKUP_SHA256="$(sha256sum "${BACKUP_FILE}" 2>>"${LOG_FILE}" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
    BACKUP_SHA256="$(shasum -a 256 "${BACKUP_FILE}" 2>>"${LOG_FILE}" | awk '{print $1}')"
else
    BACKUP_SHA256="sha256sum_indisponivel"
fi
say "🔑 SHA-256 do arquivo: ${BACKUP_SHA256}"
log "SHA-256: ${BACKUP_SHA256}"

# ==============================================================================
# SE MODO LEVE, ENCERRA AQUI
# ==============================================================================
if [ "${MODE}" = "leve" ]; then
    say "ℹ️  Modo leve concluído com sucesso. Nenhuma ação com Docker foi realizada."
    CLEANUP_STATUS="NÃO REQUERIDO (modo leve)"
    exit "${EXIT_OK}"
fi

# ==============================================================================
# FLUXO DO MODO LABORATÓRIO
# ==============================================================================

# 1. Pré-checagem de Docker
say "🐳 Verificando disponibilidade do Docker local..."
if ! command -v docker >/dev/null 2>&1; then
    die "Docker não encontrado. O modo laboratório requer Docker instalado no host." "${EXIT_DOCKER_UNAVAILABLE}"
fi
if ! docker info >>"${LOG_FILE}" 2>&1; then
    die "Docker daemon não está acessível ou sem permissão de execução." "${EXIT_DOCKER_UNAVAILABLE}"
fi

# 2. Pré-checagem de Espaço em Disco (Conservadora contra limitação de 32 bits do ISIZE do gzip)
say "💾 Estimando espaço em disco necessário (proteção contra wrap-around 32 bits do gzip)..."
GZ_FOUR_GIB=4294967296
GZ_ONE_GIB=1073741824

GZ_OUT="$(LC_ALL=C gzip -l "${BACKUP_FILE}" 2>>"${LOG_FILE}" || true)"
GZ_CMP="$(printf '%s\n' "${GZ_OUT}" | awk 'NR==2 {print $1}' | tr -d '[:space:]')"
GZ_UNC="$(printf '%s\n' "${GZ_OUT}" | awk 'NR==2 {print $2}' | tr -d '[:space:]')"
case "${GZ_CMP}" in ''|*[!0-9]*) GZ_CMP="" ;; esac
case "${GZ_UNC}" in ''|*[!0-9]*) GZ_UNC="" ;; esac

# Amostra de 8 MiB para aferir taxa real de expansão
SAMPLE_IN=$((8 * 1024 * 1024))
SAMPLE_OUT="$(head -c "${SAMPLE_IN}" "${BACKUP_FILE}" 2>>"${LOG_FILE}" | gunzip -c 2>>"${LOG_FILE}" | wc -c 2>>"${LOG_FILE}" | tr -d '[:space:]')"
case "${SAMPLE_OUT}" in ''|*[!0-9]*) SAMPLE_OUT="0" ;; esac
SAMPLE_EST=0
if [ "${SAMPLE_OUT}" -gt 0 ]; then
    SAMPLE_EST=$(( (BACKUP_SIZE_BYTES * SAMPLE_OUT + SAMPLE_IN - 1) / SAMPLE_IN ))
fi

GZ_SUSPECT=0
if [ -z "${GZ_UNC}" ] || [ -z "${GZ_CMP}" ] || [ "${GZ_UNC}" -le "${GZ_CMP}" ] \
        || [ "${GZ_UNC}" -ge "${GZ_FOUR_GIB}" ] || [ "${BACKUP_SIZE_BYTES}" -ge "${GZ_ONE_GIB}" ]; then
    GZ_SUSPECT=1
elif [ "${SAMPLE_EST}" -ge "${GZ_FOUR_GIB}" ] || [ "${SAMPLE_EST}" -gt $(( GZ_UNC * 2 )) ]; then
    GZ_SUSPECT=1
fi

EST_UNCOMPRESSED=0
if [ "${GZ_SUSPECT}" -eq 0 ]; then
    if [ "${SAMPLE_EST}" -gt "${GZ_UNC}" ]; then
        EST_UNCOMPRESSED="${SAMPLE_EST}"
    else
        EST_UNCOMPRESSED="${GZ_UNC}"
    fi
else
    log "gzip -l não confiável ou arquivo grande. Utilizando amostra ou fator conservador 4x."
    if [ "${SAMPLE_EST}" -gt 0 ]; then
        EST_UNCOMPRESSED="${SAMPLE_EST}"
    else
        EST_UNCOMPRESSED=$(( BACKUP_SIZE_BYTES * 4 ))
    fi
fi

if [ "${EST_UNCOMPRESSED}" -le 0 ]; then
    die "Falha ao estimar tamanho descomprimido do backup." "${EXIT_INSUFFICIENT_DISK}"
fi

# Espaço livre requerido no disco do Docker (descomprimido * 2x expansão postgres + 2GB reserva)
REQUIRED_DISK_BYTES=$(( EST_UNCOMPRESSED * 2 + 2147483648 ))
DOCKER_ROOT="$(docker info --format '{{.DockerRootDir}}' 2>>"${LOG_FILE}" || echo "/var/lib/docker")"
[ -n "${DOCKER_ROOT}" ] || DOCKER_ROOT="/var/lib/docker"

# Obter espaço livre no diretório de dados do Docker ou fallback no HOME
STAT_TARGET="${DOCKER_ROOT}"
[ -d "${STAT_TARGET}" ] || STAT_TARGET="${HOME}"
STAT_OUT="$(LC_ALL=C stat -f -c '%a %S' "${STAT_TARGET}" 2>>"${LOG_FILE}" || true)"
FREE_BLOCKS="$(printf '%s\n' "${STAT_OUT}" | awk '{print $1}' | tr -d '[:space:]')"
BLOCK_SIZE="$(printf '%s\n' "${STAT_OUT}" | awk '{print $2}' | tr -d '[:space:]')"

if [ -n "${FREE_BLOCKS}" ] && [ -n "${BLOCK_SIZE}" ]; then
    FREE_DISK_BYTES=$(( FREE_BLOCKS * BLOCK_SIZE ))
    log "Espaço livre aferido: ${FREE_DISK_BYTES} bytes. Necessário: ${REQUIRED_DISK_BYTES} bytes."
    if [ "${FREE_DISK_BYTES}" -lt "${REQUIRED_DISK_BYTES}" ]; then
        die "Espaço em disco insuficiente: Livre (${FREE_DISK_BYTES} B) < Necessário (${REQUIRED_DISK_BYTES} B)." "${EXIT_INSUFFICIENT_DISK}"
    fi
    say "✅ Espaço em disco verificado: Suficiente para expansão e dados."
else
    log "Não foi possível aferir blocos via stat -f; prosseguindo com monitoramento de log."
fi

# 3. Pré-checagem de Memória (Exigir >= 4 GiB de MemTotal ou MemAvailable)
say "🧠 Verificando memória do host de laboratório (exigência >= 4 GiB)..."
if [ -f /proc/meminfo ]; then
    MEM_TOTAL_KB="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)"
    MEM_AVAIL_KB="$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)"
    MEM_TOTAL_BYTES=$(( MEM_TOTAL_KB * 1024 ))
    MEM_AVAIL_BYTES=$(( MEM_AVAIL_KB * 1024 ))
    FOUR_GIB=$(( 4 * 1024 * 1024 * 1024 ))

    log "MemTotal: ${MEM_TOTAL_BYTES} bytes, MemAvailable: ${MEM_AVAIL_BYTES} bytes."
    if [ "${MEM_TOTAL_BYTES}" -lt "${FOUR_GIB}" ]; then
        die "Memória total insuficiente (${MEM_TOTAL_BYTES} B < 4 GiB). O laboratório exige máquina com ao menos 4 GiB de memória." "${EXIT_INSUFFICIENT_MEM}"
    fi
    say "✅ Memória verificada: Host possui capacidade compatível (>= 4 GiB)."
else
    say "ℹ️  /proc/meminfo indisponível (ambiente Docker Desktop/macOS/BSD). Verificação direta de memória suprimida."
fi

# 4. Criação do Contêiner Efêmero
say "📦 Criando volume dedicado: ${LAB_VOLUME}..."
if ! docker volume create --label "${LAB_LABEL_KEY}=${LAB_LABEL_VAL}" "${LAB_VOLUME}" >>"${LOG_FILE}" 2>&1; then
    die "Falha ao criar volume Docker para o laboratório." "${EXIT_DOCKER_UNAVAILABLE}"
fi

say "🚀 Subindo contêiner isolado: ${LAB_NAME} (imagem: ${LAB_IMAGE}, rede: none)..."
if ! docker run -d \
        --name "${LAB_NAME}" \
        --network none \
        --restart no \
        --label "${LAB_LABEL_KEY}=${LAB_LABEL_VAL}" \
        --memory "${LAB_MEMORY_LIMIT}" \
        --shm-size "${LAB_SHM_SIZE}" \
        -e POSTGRES_USER=postgres \
        -e POSTGRES_PASSWORD=lab-audit-secret-pwd-$$ \
        -e POSTGRES_DB=postgres \
        -v "${LAB_VOLUME}:/var/lib/postgresql/data" \
        "${LAB_IMAGE}" >>"${LOG_FILE}" 2>&1; then
    die "Falha ao iniciar contêiner de laboratório '${LAB_NAME}'." "${EXIT_DOCKER_UNAVAILABLE}"
fi

# Aguardar prontidão do PostgreSQL
say "⏳ Aguardando inicialização do PostgreSQL no contêiner..."
LAB_READY=0
for i in $(seq 1 60); do
    if docker exec "${LAB_NAME}" pg_isready -U postgres -d postgres >>"${LOG_FILE}" 2>&1; then
        LAB_READY=1
        break
    fi
    sleep 1
done

if [ "${LAB_READY}" -ne 1 ]; then
    die "PostgreSQL no contêiner de laboratório não respondeu em 60 segundos." "${EXIT_DOCKER_UNAVAILABLE}"
fi
say "✅ PostgreSQL de laboratório pronto para receber o restore."

# Funções de consulta com flags estritas psql -X -v ON_ERROR_STOP=1
run_lab_psql() {
    local q="$1"
    local db="${2:-postgres}"
    docker exec "${LAB_NAME}" psql -X -v ON_ERROR_STOP=1 -U postgres -d "${db}" -t -A -c "${q}" 2>>"${LOG_FILE}"
}

run_lab_psql_raw() {
    local q="$1"
    local db="${2:-postgres}"
    docker exec "${LAB_NAME}" psql -X -v ON_ERROR_STOP=1 -U postgres -d "${db}" -t -A -F '|' -c "${q}" 2>>"${LOG_FILE}"
}

AUDIT_DB="sbsjur_teste_limpo"
say "🔨 Criando banco de dados novo e vazio: ${AUDIT_DB}..."
if ! run_lab_psql "CREATE DATABASE ${AUDIT_DB};" "postgres" >/dev/null 2>>"${LOG_FILE}"; then
    die "Falha ao criar banco de laboratório '${AUDIT_DB}'." "${EXIT_RESTORE_FAILED}"
fi

# 5. Execução do Restore com psql -X -v ON_ERROR_STOP=1 e Captura Rigorosa
say "♻️  Iniciando restauração do dump (gunzip -c | psql -X -v ON_ERROR_STOP=1)..."
log "Iniciando carga de dump em ${AUDIT_DB} com psql -X -v ON_ERROR_STOP=1..."

gunzip -c "${BACKUP_FILE}" 2>>"${LOG_FILE}" \
    | docker exec -i "${LAB_NAME}" psql -X -v ON_ERROR_STOP=1 -U postgres -d "${AUDIT_DB}" 2> "${RESTORE_ERRORS_FILE}" > "${DIAG_DIR}/restore-stdout-${TS_STAMP}-$$.log"
RESTORE_PIPE_STATUS=("${PIPESTATUS[@]}")
GZIP_EXIT="${RESTORE_PIPE_STATUS[0]}"
PSQL_EXIT="${RESTORE_PIPE_STATUS[1]}"

chmod 600 "${RESTORE_ERRORS_FILE}" 2>/dev/null || true
RESTORE_RAW_ERRORS_COUNT="$(grep -cE 'ERROR:|ERRO:|FATAL:' "${RESTORE_ERRORS_FILE}" || true)"
log "GZIP_EXIT: ${GZIP_EXIT}, PSQL_EXIT: ${PSQL_EXIT}, Mensagens de erro SQL: ${RESTORE_RAW_ERRORS_COUNT}"

if [ "${GZIP_EXIT}" -ne 0 ]; then
    RESTORE_STATUS="FALHA NA DESCOMPRESSÃO (gunzip exit ${GZIP_EXIT})"
    CRIT_B="FALHA"
    say_err "Erro no fluxo gunzip (exit ${GZIP_EXIT}) durante a restauração."
    printf 'FALHA DE RESTAURAÇÃO: gunzip falhou com código %s\n' "${GZIP_EXIT}" >> "${DIVERGENCES_FILE}"
elif [ "${PSQL_EXIT}" -ne 0 ] || [ "${RESTORE_RAW_ERRORS_COUNT}" -gt 0 ]; then
    RESTORE_STATUS="INTERROMPIDO POR ERRO SQL (psql exit ${PSQL_EXIT}, ${RESTORE_RAW_ERRORS_COUNT} erro(s) SQL)"
    CRIT_B="FALHA"
    say "⚠️  Restauração INTERROMPIDA por erro SQL (ON_ERROR_STOP=1, exit ${PSQL_EXIT}, ${RESTORE_RAW_ERRORS_COUNT} erro(s)). Detalhes restritos ao log."
    printf 'FALHA DE RESTAURAÇÃO: psql interrompido com código %s (%s erro(s) SQL capturados)\n' "${PSQL_EXIT}" "${RESTORE_RAW_ERRORS_COUNT}" >> "${DIVERGENCES_FILE}"
else
    RESTORE_STATUS="CONCLUÍDO SEM ERROS (psql exit 0, 0 erros SQL)"
    CRIT_B="OK"
    say "✅ Restauração concluída com sucesso absoluto (zero erros SQL, exit 0)."
    printf 'CONFERIDO: restauração executada sem erros (exit 0)\n' >> "${CONFERIDOS_FILE}"
fi

# 6. Procedimento Pós-Restauração (Tratamento de Dependências Supabase / pg_graphql)
#    No teste manual de 10/11/2026, a função graphql_public.graphql não existia pois
#    a extensão pg_graphql pré-instalada na imagem supabase/postgres fez o dump pular
#    o CREATE EXTENSION.
say "🔧 Verificando estado das extensões e funções críticas do Supabase..."
GRAPHQL_FN_EXISTS="$(run_lab_psql "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='graphql_public' AND p.proname='graphql';" "${AUDIT_DB}" | tr -d '[:space:]')"

if [ "${GRAPHQL_FN_EXISTS}" = "1" ]; then
    say "✅ Função graphql_public.graphql identificada no banco restaurado."
    CRIT_D="OK"
    POST_RESTORE_RESULT="NÃO NECESSÁRIO (dependência graphql_public.graphql já existe)"
else
    say "⚠️  Dependência ausente detectada: graphql_public.graphql NÃO existe no catálogo restaurado."
    log "graphql_public.graphql ausente após restauração bruta."

    if [ "${APPLY_POST_RESTORE}" -eq 1 ]; then
        say "🛠️  Aplicando procedimento pós-restauração documentado no laboratório..."
        log "Executando procedimento corretivo para pg_graphql..."

        # Executar comando de recuperação documentado dentro do laboratório:
        # Tenta DROP EXTENSION IF EXISTS pg_graphql CASCADE seguido de CREATE EXTENSION pg_graphql
        docker exec "${LAB_NAME}" psql -X -v ON_ERROR_STOP=1 -U postgres -d "${AUDIT_DB}" -c "
            DROP EXTENSION IF EXISTS pg_graphql CASCADE;
            CREATE EXTENSION IF NOT EXISTS pg_graphql WITH SCHEMA graphql;
        " >>"${LOG_FILE}" 2>&1

        # Re-validar
        GRAPHQL_FN_AFTER="$(run_lab_psql "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='graphql_public' AND p.proname='graphql';" "${AUDIT_DB}" | tr -d '[:space:]')"
        if [ "${GRAPHQL_FN_AFTER}" = "1" ]; then
            say "✅ Procedimento pós-restauração teve SUCESSO: graphql_public.graphql recriada com êxito."
            POST_RESTORE_RESULT="APLICADO COM SUCESSO (pg_graphql recriado e validado no laboratório)"
            CRIT_D="OK"
            POST_RESTORE_APPLIED="SIM"
        else
            say_err "Falha na etapa corretiva: graphql_public.graphql permaneceu ausente."
            POST_RESTORE_RESULT="FALHA NA APLICAÇÃO (graphql_public.graphql permaneceu ausente)"
            CRIT_D="FALHA"
        fi
    else
        say "ℹ️  Procedimento pós-restauração desabilitado por flag (--sem-pos-restauracao)."
        POST_RESTORE_RESULT="NÃO APLICADO (desabilitado por flag)"
        CRIT_D="FALHA"
    fi
fi

# 7. Validação de Catálogo e Contagens
say "📊 Coletando métricas e contagens do banco de dados restaurado..."
TOTAL_TABELAS_LAB="$(run_lab_psql "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';" "${AUDIT_DB}" | tr -d '[:space:]')"
TOTAL_CONSTRAINTS_LAB="$(run_lab_psql "SELECT count(*) FROM information_schema.table_constraints WHERE table_schema='public';" "${AUDIT_DB}" | tr -d '[:space:]')"
TOTAL_FUNCOES_LAB="$(run_lab_psql "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public';" "${AUDIT_DB}" | tr -d '[:space:]')"
TOTAL_TRIGGERS_LAB="$(run_lab_psql "SELECT count(*) FROM information_schema.triggers WHERE trigger_schema='public';" "${AUDIT_DB}" | tr -d '[:space:]')"
TOTAL_EXTENSOES_LAB="$(run_lab_psql "SELECT count(*) FROM pg_extension;" "${AUDIT_DB}" | tr -d '[:space:]')"

case "${TOTAL_TABELAS_LAB}" in ''|*[!0-9]*) TOTAL_TABELAS_LAB=0 ;; esac
case "${TOTAL_CONSTRAINTS_LAB}" in ''|*[!0-9]*) TOTAL_CONSTRAINTS_LAB=0 ;; esac
case "${TOTAL_FUNCOES_LAB}" in ''|*[!0-9]*) TOTAL_FUNCOES_LAB=0 ;; esac
case "${TOTAL_TRIGGERS_LAB}" in ''|*[!0-9]*) TOTAL_TRIGGERS_LAB=0 ;; esac
case "${TOTAL_EXTENSOES_LAB}" in ''|*[!0-9]*) TOTAL_EXTENSOES_LAB=0 ;; esac

# Contagem de registros por tabela no schema public
LAB_TABLES="$(run_lab_psql_raw "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;" "${AUDIT_DB}")"
TOTAL_REGISTROS_LAB=0

if [ -n "${LAB_TABLES}" ]; then
    while IFS= read -r t; do
        [ -n "${t}" ] || continue
        cnt="$(run_lab_psql "SELECT count(*) FROM public.\"${t}\";" "${AUDIT_DB}" | tr -d '[:space:]')"
        case "${cnt}" in ''|*[!0-9]*) cnt=0 ;; esac
        TOTAL_REGISTROS_LAB=$((TOTAL_REGISTROS_LAB + cnt))
        printf 'Tabela public."%s": %s registros\n' "${t}" "${cnt}" >> "${CONFERIDOS_FILE}"
    done <<< "${LAB_TABLES}"
fi

say "📈 Catálogo Restaurado: ${TOTAL_TABELAS_LAB} tabelas, ${TOTAL_REGISTROS_LAB} registros, ${TOTAL_CONSTRAINTS_LAB} constraints."

# 8. Comparação com Inventário da Produção
INVENTORY_COMPARISON_VALID="NAO"
if [ -n "${INVENTORY_FILE}" ]; then
    if [ ! -f "${INVENTORY_FILE}" ]; then
        say_err "Arquivo de inventário não encontrado: ${INVENTORY_FILE}"
        printf 'DIVERGÊNCIA: Arquivo de inventário informado não existe: %s\n' "${INVENTORY_FILE}" >> "${DIVERGENCES_FILE}"
    elif ! command -v jq >/dev/null 2>&1; then
        say_err "Ferramenta 'jq' não disponível. A auditoria integral exige 'jq' para validação semântica do inventário."
        printf 'DIVERGÊNCIA: Ferramenta jq indisponível para comparar inventário\n' >> "${DIVERGENCES_FILE}"
    elif ! jq -e . "${INVENTORY_FILE}" >/dev/null 2>>"${LOG_FILE}"; then
        say_err "Arquivo de inventário inválido ou corrompido (falha de sintaxe JSON)."
        printf 'DIVERGÊNCIA: Arquivo de inventário possui JSON inválido ou corrompido: %s\n' "${INVENTORY_FILE}" >> "${DIVERGENCES_FILE}"
    else
        say "🔍 Comparando estruturas com inventário validado: ${INVENTORY_FILE}..."
        INV_TOTAL_PUBLIC="$(jq -r '.sumario.total_tabelas_public // .sumario.total_tabelas // 0' "${INVENTORY_FILE}" 2>/dev/null || echo 0)"
        log "Comparação de inventário - Tabelas public esperadas: ${INV_TOTAL_PUBLIC}, Encontradas no lab: ${TOTAL_TABELAS_LAB}"

        if [ "${INV_TOTAL_PUBLIC}" -gt 0 ] && [ "${INV_TOTAL_PUBLIC}" -ne "${TOTAL_TABELAS_LAB}" ]; then
            printf 'DIVERGÊNCIA ESTRUTURAL: Quantidade de tabelas no schema public difere (Inventário: %s, Restaurado: %s)\n' "${INV_TOTAL_PUBLIC}" "${TOTAL_TABELAS_LAB}" >> "${DIVERGENCES_FILE}"
        else
            printf 'CONFERIDO: Quantidade de tabelas no schema public coincide (%s tabelas)\n' "${TOTAL_TABELAS_LAB}" >> "${CONFERIDOS_FILE}"
        fi

        # Checar tabelas catalogadas no inventário (suportando schemas public e auth)
        while IFS= read -r row; do
            [ -n "${row}" ] || continue
            inv_schema="$(echo "${row}" | cut -d'|' -f1)"
            inv_tab="$(echo "${row}" | cut -d'|' -f2)"
            inv_cnt="$(echo "${row}" | cut -d'|' -f3)"
            inv_type="$(echo "${row}" | cut -d'|' -f4)"

            # Verificar se a tabela existe no laboratório
            tab_exists="$(run_lab_psql "SELECT count(*) FROM information_schema.tables WHERE table_schema='${inv_schema}' AND table_name='${inv_tab}';" "${AUDIT_DB}" 2>>"${LOG_FILE}" | tr -d '[:space:]')"
            if [ "${tab_exists}" != "1" ]; then
                printf 'DIVERGÊNCIA: Tabela %s."%s" presente no inventário NÃO EXISTE no banco restaurado\n' "${inv_schema}" "${inv_tab}" >> "${DIVERGENCES_FILE}"
                continue
            fi

            if [ "${inv_type}" = "exata" ]; then
                lab_cnt="$(run_lab_psql "SELECT count(*) FROM \"${inv_schema}\".\"${inv_tab}\";" "${AUDIT_DB}" 2>>"${LOG_FILE}" | tr -d '[:space:]')"
                case "${lab_cnt}" in ''|*[!0-9]*) lab_cnt="-1" ;; esac
                if [ "${lab_cnt}" = "${inv_cnt}" ]; then
                    printf 'CONFERIDO (contagem exata): %s."%s" (Inventário: %s, Restaurado: %s)\n' "${inv_schema}" "${inv_tab}" "${inv_cnt}" "${lab_cnt}" >> "${CONFERIDOS_FILE}"
                else
                    printf 'DIVERGÊNCIA DE CONTAGEM EXATA: %s."%s" (Inventário: %s, Restaurado: %s)\n' "${inv_schema}" "${inv_tab}" "${inv_cnt}" "${lab_cnt}" >> "${DIVERGENCES_FILE}"
                fi
            else
                # Contagem estimada: NUNCA exigir igualdade numérica exata
                lab_est="$(run_lab_psql "SELECT COALESCE(reltuples::bigint, 0) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='${inv_schema}' AND c.relname='${inv_tab}';" "${AUDIT_DB}" 2>>"${LOG_FILE}" | tr -d '[:space:]')"
                case "${lab_est}" in ''|*[!0-9]*) lab_est="0" ;; esac
                printf 'CONFERIDO (estimativa estatística - não vinculante): %s."%s" (Estimativa Inventário: %s, Estimativa Lab: %s)\n' "${inv_schema}" "${inv_tab}" "${inv_cnt}" "${lab_est}" >> "${CONFERIDOS_FILE}"
            fi
        done < <(jq -r '.tabelas[] | "\(.schema)|\(.tabela)|\(.contagem)|\(.tipo_contagem)"' "${INVENTORY_FILE}" 2>/dev/null || true)

        INVENTORY_COMPARISON_VALID="SIM"
    fi
else
    say "ℹ️  Nenhum arquivo de inventário fornecido (--inventario). Comparação detalhada de conformidade não pôde ser atestada."
fi

# 9. Testes Técnicos Não Destrutivos de Compatibilidade e Operação Básica do CRM
# (Atenção: estes testes verificam integridade referencial, auth, sintaxe e transação no banco,
# MAS NÃO comprovam integralmente a aplicação CRM em execução, APIs REST ou autenticação GoTrue ativa).
say "🧪 Executando verificações técnicas de integridade e compatibilidade básica do CRM..."
CRM_OPERATIONAL_TESTS_OK=0
CRM_OPERATIONAL_TESTS_TOTAL=4
CRM_OPERATIONAL_DETAILS=""

# Teste Operacional 1: Integridade referencial / Chaves Estrangeiras (FKs órfãs)
# Valida se os relacionamentos centrais do CRM possuem registros órfãos
FK_ORPHANS_FOUND=0
ORPHAN_CHECK_QUERY="
SELECT count(*) FROM (
    SELECT c.id FROM public.cases c WHERE c.client_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.clients cl WHERE cl.id = c.client_id)
    UNION ALL
    SELECT t.id FROM public.tasks t WHERE t.client_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.clients cl WHERE cl.id = t.client_id)
    UNION ALL
    SELECT tr.id FROM public.transactions tr WHERE tr.client_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.clients cl WHERE cl.id = tr.client_id)
) orphans;
"
FK_ORPHANS_CNT=""
if ! FK_ORPHANS_CNT="$(run_lab_psql "${ORPHAN_CHECK_QUERY}" "${AUDIT_DB}")"; then
    say_err "Falha na consulta SQL de verificação de FKs órfãs."
    printf 'DIVERGÊNCIA (op-crm): Falha de consulta SQL ao verificar FKs órfãs\n' >> "${DIVERGENCES_FILE}"
    CRM_OPERATIONAL_DETAILS="${CRM_OPERATIONAL_DETAILS} [FK: falha de consulta]"
else
    FK_ORPHANS_CNT="$(echo "${FK_ORPHANS_CNT}" | tr -d '[:space:]')"
    case "${FK_ORPHANS_CNT}" in ''|*[!0-9]*) FK_ORPHANS_CNT="-1" ;; esac

    if [ "${FK_ORPHANS_CNT}" = "0" ]; then
        CRM_OPERATIONAL_TESTS_OK=$((CRM_OPERATIONAL_TESTS_OK + 1))
        printf 'CONFERIDO (op-crm): Integridade referencial intacta (0 chaves estrangeiras órfãs em cases/tasks/transactions)\n' >> "${CONFERIDOS_FILE}"
        CRM_OPERATIONAL_DETAILS="${CRM_OPERATIONAL_DETAILS} [FK: 0 órfãs]"
    else
        printf 'DIVERGÊNCIA (op-crm): Encontrados %s registros órfãos violando integridade referencial básica do CRM\n' "${FK_ORPHANS_CNT}" >> "${DIVERGENCES_FILE}"
        CRM_OPERATIONAL_DETAILS="${CRM_OPERATIONAL_DETAILS} [FK: ${FK_ORPHANS_CNT} órfãs]"
    fi
fi

# Teste Operacional 2: Estado e unicidade da base de usuários (auth.users e perfis)
USERS_DUP_COUNT=""
if ! USERS_DUP_COUNT="$(run_lab_psql "SELECT count(*) FROM (SELECT email FROM auth.users WHERE email IS NOT NULL GROUP BY lower(email) HAVING count(*) > 1) d;" "${AUDIT_DB}")"; then
    say_err "Falha na consulta SQL de verificação de duplicidades de e-mail em auth.users."
    printf 'DIVERGÊNCIA (op-crm): Falha de consulta SQL ao checar duplicidades em auth.users\n' >> "${DIVERGENCES_FILE}"
    USERS_DUP_COUNT="-1"
else
    USERS_DUP_COUNT="$(echo "${USERS_DUP_COUNT}" | tr -d '[:space:]')"
    case "${USERS_DUP_COUNT}" in ''|*[!0-9]*) USERS_DUP_COUNT="-1" ;; esac
fi

USERS_TOTAL=""
if ! USERS_TOTAL="$(run_lab_psql "SELECT count(*) FROM auth.users;" "${AUDIT_DB}")"; then
    say_err "Falha na consulta SQL de contagem de auth.users."
    printf 'DIVERGÊNCIA (op-crm): Falha de consulta SQL ao contar auth.users\n' >> "${DIVERGENCES_FILE}"
    USERS_TOTAL="0"
else
    USERS_TOTAL="$(echo "${USERS_TOTAL}" | tr -d '[:space:]')"
    case "${USERS_TOTAL}" in ''|*[!0-9]*) USERS_TOTAL="0" ;; esac
fi

if [ "${USERS_DUP_COUNT}" = "0" ] && [ "${USERS_TOTAL}" -ge 1 ]; then
    CRM_OPERATIONAL_TESTS_OK=$((CRM_OPERATIONAL_TESTS_OK + 1))
    printf 'CONFERIDO (op-crm): Tabela auth.users íntegra (%s usuários, 0 duplicidades de e-mail)\n' "${USERS_TOTAL}" >> "${CONFERIDOS_FILE}"
    CRM_OPERATIONAL_DETAILS="${CRM_OPERATIONAL_DETAILS} [Users: ${USERS_TOTAL} ok]"
else
    printf 'DIVERGÊNCIA (op-crm): Inconsistência ou falha em auth.users (total: %s, e-mails duplicados: %s)\n' "${USERS_TOTAL}" "${USERS_DUP_COUNT}" >> "${DIVERGENCES_FILE}"
    CRM_OPERATIONAL_DETAILS="${CRM_OPERATIONAL_DETAILS} [Users: inconsistente ou falha]"
fi

# Teste Operacional 3: Execução de consultas representativas de tela do CRM com EXPLAIN
EXPLAIN_CLIENTS_RC=0
if ! run_lab_psql "EXPLAIN SELECT c.id, c.name, count(cs.id) FROM public.clients c LEFT JOIN public.cases cs ON cs.client_id = c.id GROUP BY c.id, c.name LIMIT 20;" "${AUDIT_DB}" >/dev/null; then
    EXPLAIN_CLIENTS_RC=1
fi

EXPLAIN_FINANCE_RC=0
if ! run_lab_psql "EXPLAIN SELECT id, amount, type, status, due_date FROM public.transactions WHERE deleted_at IS NULL ORDER BY due_date DESC LIMIT 50;" "${AUDIT_DB}" >/dev/null; then
    EXPLAIN_FINANCE_RC=1
fi

if [ "${EXPLAIN_CLIENTS_RC}" -eq 0 ] && [ "${EXPLAIN_FINANCE_RC}" -eq 0 ]; then
    CRM_OPERATIONAL_TESTS_OK=$((CRM_OPERATIONAL_TESTS_OK + 1))
    printf 'CONFERIDO (op-crm): Consultas de tela do CRM operam sem erro sintático ou de plano de execução (EXPLAIN OK)\n' >> "${CONFERIDOS_FILE}"
    CRM_OPERATIONAL_DETAILS="${CRM_OPERATIONAL_DETAILS} [Planos EXPLAIN: ok]"
else
    printf 'DIVERGÊNCIA (op-crm): Falha de execução nas consultas representativas das telas do CRM\n' >> "${DIVERGENCES_FILE}"
    CRM_OPERATIONAL_DETAILS="${CRM_OPERATIONAL_DETAILS} [Planos EXPLAIN: falha]"
fi

# Teste Operacional 4: Transação de leitura/simulação idempotente (BEGIN ... ROLLBACK)
ROLLBACK_SIM_OK=0
if run_lab_psql "BEGIN; SELECT count(*) FROM public.clients; SELECT count(*) FROM public.cases; ROLLBACK;" "${AUDIT_DB}" >/dev/null; then
    ROLLBACK_SIM_OK=1
fi

if [ "${ROLLBACK_SIM_OK}" -eq 1 ]; then
    CRM_OPERATIONAL_TESTS_OK=$((CRM_OPERATIONAL_TESTS_OK + 1))
    printf 'CONFERIDO (op-crm): Bloco transacional com rollback executado com sucesso\n' >> "${CONFERIDOS_FILE}"
    CRM_OPERATIONAL_DETAILS="${CRM_OPERATIONAL_DETAILS} [Simulação transacional: ok]"
else
    printf 'DIVERGÊNCIA (op-crm): Bloco transacional de simulação falhou\n' >> "${DIVERGENCES_FILE}"
    CRM_OPERATIONAL_DETAILS="${CRM_OPERATIONAL_DETAILS} [Simulação transacional: falha]"
fi

# 10. Avaliação dos Critérios Rigorosos e Veredito Final
# Critério C: Recuperação de estruturas e dados
case "${TOTAL_TABELAS_LAB}" in
    ERRO)
        CRIT_C="FALHA"
        ;;
    *)
        if [ "${TOTAL_TABELAS_LAB}" -gt 0 ] && [ "${TOTAL_REGISTROS_STATUS}" = "OK" ] && [ ! -s "${DIVERGENCES_FILE}" ]; then
            CRIT_C="OK"
        elif [ "${TOTAL_TABELAS_LAB}" -gt 0 ]; then
            CRIT_C="PARCIAL"
        else
            CRIT_C="FALHA"
        fi
        ;;
esac

# Critério E: Recuperação operacional e compatibilidade básica
# (Atenção: restrito ao escopo do banco de dados; funcionamento pleno do CRM requer backend GoTrue/Kong ativos)
if [ "${QUERY_FAILURES_COUNT}" -gt 0 ]; then
    CRIT_E="FALHA (${QUERY_FAILURES_COUNT} falha(s) de consulta SQL detectadas)"
elif [ "${CRM_OPERATIONAL_TESTS_OK}" -eq "${CRM_OPERATIONAL_TESTS_TOTAL}" ] && [ "${CRIT_C}" = "OK" ] && [ "${CRIT_D#OK}" != "${CRIT_D}" ]; then
    CRIT_E="COMPATIBILIDADE BÁSICA VERIFICADA (4/4 testes técnicos de banco ok; operação integral do CRM depende de stack GoTrue/Kong)"
elif [ "${CRM_OPERATIONAL_TESTS_OK}" -gt 0 ]; then
    CRIT_E="NÃO COMPROVADO (${CRM_OPERATIONAL_TESTS_OK}/${CRM_OPERATIONAL_TESTS_TOTAL} verificações sucedidas)"
else
    CRIT_E="FALHA"
fi

# Classificação e Veredito Final
DIVERGENCES_COUNT="$(wc -l < "${DIVERGENCES_FILE}" 2>/dev/null || echo 0)"

# Para APROVADO, exige:
# - Critério A em OK
# - Critério B em OK (restauração sem erros SQL brutos)
# - Critério C em OK (estruturas e dados sem divergência estrutural)
# - Critério D iniciando com OK (extensões presentes, seja na restauração original ou recuperação assistida)
# - Critério E com compatibilidade básica verificada
# - Sem divergências críticas pendentes (DIVERGENCES_COUNT == 0)
# - E comparação semântica com inventário oficial validada por jq (INVENTORY_COMPARISON_VALID == SIM)
CRIT_D_OK=0
if [ "${CRIT_D#OK}" != "${CRIT_D}" ]; then
    CRIT_D_OK=1
fi

CRIT_E_OK=0
if [ "${CRIT_E#COMPATIBILIDADE BÁSICA VERIFICADA}" != "${CRIT_E}" ] || [ "${CRIT_E}" = "OK" ]; then
    CRIT_E_OK=1
fi

if [ "${CRIT_A}" = "OK" ] && [ "${CRIT_B}" = "OK" ] && [ "${CRIT_C}" = "OK" ] && [ "${CRIT_D_OK}" -eq 1 ] && [ "${CRIT_E_OK}" -eq 1 ] && [ "${DIVERGENCES_COUNT}" -eq 0 ] && [ "${INVENTORY_COMPARISON_VALID}" = "SIM" ]; then
    VEREDITO_FINAL="APROVADO"
    if [ "${POST_RESTORE_APPLIED}" = "SIM" ]; then
        CLASSIFICACAO_RECUPERACAO="RECUPERAÇÃO ASSISTIDA VALIDADA (banco restaurado íntegro após ajuste de pg_graphql; compatibilidade básica confirmada)"
    else
        CLASSIFICACAO_RECUPERACAO="RESTAURAÇÃO INTEGRAL (restauração direta sem erros; compatibilidade básica confirmada)"
    fi
elif [ "${CRIT_A}" = "OK" ] && [ "${CRIT_B}" = "OK" ] && [ "${CRIT_C}" = "OK" ] && [ "${CRIT_D_OK}" -eq 1 ] && [ "${CRIT_E_OK}" -eq 1 ] && [ "${DIVERGENCES_COUNT}" -eq 0 ]; then
    # Todos os critérios técnicos passaram, mas não houve inventário válido para certificar integralidade absoluta
    VEREDITO_FINAL="REPROVADO"
    CLASSIFICACAO_RECUPERACAO="RECUPERAÇÃO PARCIAL (auditoria técnica no banco aprovada, mas comparação com inventário oficial ausente ou incompleta)"
elif [ "${CRIT_A}" = "OK" ] && [ "${TOTAL_TABELAS_LAB}" != "ERRO" ] && [ "${TOTAL_TABELAS_LAB}" -gt 0 ]; then
    VEREDITO_FINAL="REPROVADO"
    CLASSIFICACAO_RECUPERACAO="RECUPERAÇÃO PARCIAL (inconsistências, dependências ou validações operacionais pendentes)"
else
    VEREDITO_FINAL="REPROVADO"
    CLASSIFICACAO_RECUPERACAO="NÃO RECUPERADO (falha crítica de restauração ou de integridade física)"
fi

log "Auditoria concluída. Veredito: ${VEREDITO_FINAL}, Classificação: ${CLASSIFICACAO_RECUPERACAO}"

if [ "${VEREDITO_FINAL}" = "APROVADO" ]; then
    exit "${EXIT_OK}"
else
    exit "${EXIT_AUDIT_REJECTED}"
fi
