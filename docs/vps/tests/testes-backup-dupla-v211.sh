#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur — Testes com MOCKS para os scripts de backup dupla (v2.1.2)
# ==============================================================================
# Cobre os cenários obrigatórios da auditoria do commit 1f36a02:
#   T1. contêiner do serviço dpsjur_dpsjur-db identificado por ID é ACEITO por
#       bk_verify_container (versão 18 / usuário Doug / banco dpsjur confirmados);
#   T2. contêiner INCORRETO é REJEITADO (exit 13);
#   T3. contêiner AMBÍGUO (mesmo ID com dois nomes) é REJEITADO (exit 13);
#   T4. serviço/tarefas Swarm ausentes são REJEITADOS (exit 13);
#   T5. pg_dump falhando → bk_run_dump_pipeline retorna BK_EXIT_DUMP_FAIL (20);
#   T6. publicação falhando (destino existente) → bk_publish_dump falha (25);
#   T7. bk_finalize_session registra SUCESSO somente com código 0 + limpeza ok;
#   T8. bk_finalize_session registra FALHA PRESERVANDO o código original;
#   T9. bk_finalize_session registra FALHA DE LIMPEZA quando só a limpeza falha;
#   T10. código de saída ORIGINAL preservado após a limpeza (trap EXIT —
#        exit 20 sobrevive a limpeza que falha; exit 0 + limpeza falha → 29;
#        exit 0 + limpeza ok → 0).
#
# NADA é executado de verdade: `docker` é um MOCK colocado à frente do PATH;
# nenhum contêiner, banco, VPS ou arquivo real é tocado. Rodar em máquina com
# Bash (WSL2 de Douglas):
#   bash docs/vps/tests/testes-backup-dupla-v211.sh
# Exit 0 = todos os testes passaram; exit 1 = alguma divergência (listada).
#
# v2.1.2 — correção da auditoria do harness:
#   A. MOCK_CASE EXPORTADA: o mock de docker é um SCRIPT FILHO (executável no
#      PATH) e só enxerga variáveis exportadas. Sem `export MOCK_CASE`, todo
#      cenário caía no default "ok" e os testes T2/T3/T4a/T4b não exercitavam
#      o comportamento pretendido. A exportação passa a valer também dentro de
#      subshells $() e pipelines (contexto onde atribuição simples não propaga
#      para subprocessos). MOCK_DUMP_FAIL já era exportada — mantido.
#   B. T7: o assert antigo (`expect_exit 0 ... true`) testava o comando `true`,
#      não a função — passava sem testar nada. Substituído por captura real do
#      código de bk_finalize_session (chamada em subshell; a função não faz
#      exit, apenas registra no log — o veredito passou a ser provado também
#      pelo código retornado, sem flexibilizar nenhum assert).
#
# STATUS: NÃO EXECUTADO nesta rodada (plataforma de desenvolvimento SEM Bash):
#   bash -n NÃO VALIDADO, ShellCheck NÃO VALIDADO, execução do harness NÃO
#   VALIDADO. Validar no WSL2 de Douglas antes de qualquer uso.
# ==============================================================================

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${HERE}/../lib/backup-lib.sh"
if [ ! -f "${LIB}" ]; then
    printf 'ERRO: lib não encontrada em %s\n' "${LIB}" >&2
    exit 1
fi

WORK="$(mktemp -d /tmp/bk-dupla-tests-XXXXXX)"
trap 'rm -rf "${WORK}"' EXIT

export LOG_FILE="${WORK}/harness.log"
: > "${LOG_FILE}"
export BK_PGPASS_IN_CONTAINER="/tmp/.pgpass-mock-sessao-apenas-teste"
export BK_TMP_FILE=""
# Cenário do mock de docker — EXPORTADA: o mock roda como subprocesso e só vê
# o ambiente exportado (v2.1.2, correção A). Renomeado de MOCK_CASE para
# BK_MOCK_CASE para eliminar a colisão com qualquer uso futuro do nome dentro
# dos scripts testados.
export BK_MOCK_CASE="ok"
# shellcheck source=../lib/backup-lib.sh
source "${LIB}"

# ------------------------------------------------------------------------------
# Mock de docker (comportamento por BK_MOCK_CASE / MOCK_DUMP_FAIL)
# ------------------------------------------------------------------------------
MOCK_BIN="${WORK}/bin"
mkdir -p "${MOCK_BIN}"
cat > "${MOCK_BIN}/docker" <<'EOF_MOCK'
#!/usr/bin/env bash
case "${BK_MOCK_CASE:-ok}" in
    daemon-morto) exit 1 ;;
esac

if [ "${1:-}" = "info" ]; then
    exit 0
fi

if [ "${1:-}" = "service" ] && [ "${2:-}" = "ls" ]; then
    case "${BK_MOCK_CASE:-ok}" in
        servico-ausente) exit 1 ;;
        *) printf '%s\n' "dpsjur_dpsjur-db" ;;
    esac
    exit 0
fi

if [ "${1:-}" = "service" ] && [ "${2:-}" = "ps" ]; then
    case "${BK_MOCK_CASE:-ok}" in
        sem-tarefa) : ;;
        *) printf '%s\n' "dpsjur_dpsjur-db.1.abcdef1234567890" ;;
    esac
    exit 0
fi

if [ "${1:-}" = "ps" ]; then
    if printf '%s\n' "$@" | grep -q -- '--filter'; then
        case "${BK_MOCK_CASE:-ok}" in
            ok|dump-fail|publish-fail) printf '%s\n' "abcdef1234567890" ;;
        esac
        exit 0
    fi
    case "${BK_MOCK_CASE:-ok}" in
        ok|dump-fail|publish-fail)
            printf '%s\t%s\n' "abcdef1234567890" "dpsjur_dpsjur-db.1.abcdef1234567890" ;;
        incorreto)
            printf '%s\t%s\n' "9999999999999999" "outro-container" ;;
        ambiguo)
            printf '%s\t%s\n' "abcdef1234567890" "dpsjur_dpsjur-db.1.abcdef1234567890"
            printf '%s\t%s\n' "abcdef1234567890" "dpsjur_dpsjur-db.2.abcdef1234567890" ;;
    esac
    exit 0
fi

if [ "${1:-}" = "cp" ]; then
    exit 0
fi

if [ "${1:-}" = "exec" ]; then
    shift 2   # descarta 'exec' e o identificador do contêiner
    is_psql=0; is_pgdump=0; is_sh=0
    payload=""; prev=""
    for a in "$@"; do
        case "${a}" in
            psql) is_psql=1 ;;
            *pg_dump) is_pgdump=1 ;;
            sh) is_sh=1 ;;
        esac
        if [ "${prev}" = "-c" ]; then payload="${a}"; fi
        prev="${a}"
    done
    if [ "${is_sh}" -eq 1 ]; then
        case "${payload}" in
            *"test -e"*) exit 1 ;;   # arquivo já removido (prova pós-rm)
            *) exit 0 ;;             # command -v pg_dump etc.
        esac
    fi
    if [ "${is_psql}" -eq 1 ]; then
        case "${payload}" in
            *server_version*) printf '18.2 (Debian 18.2-1.pgdg120+1)\n' ;;
            *pg_database*)    printf 'dpsjur\n' ;;
            *pg_roles*)       printf 'Doug\n' ;;
            *)                printf '\n' ;;
        esac
        exit 0
    fi
    if [ "${is_pgdump}" -eq 1 ]; then
        if [ "${MOCK_DUMP_FAIL:-0}" = "1" ]; then
            printf 'pg_dump: erro simulado pelo mock\n' >&2
            exit 1
        fi
        printf -- '-- PostgreSQL database dump simulada\n'
        exit 0
    fi
    exit 0
fi

printf 'docker mock: chamada não tratada: %s\n' "$*" >&2
exit 1
EOF_MOCK
chmod 700 "${MOCK_BIN}/docker"
PATH="${MOCK_BIN}:${PATH}"
export PATH

# ------------------------------------------------------------------------------
# Ferramental do harness
# ------------------------------------------------------------------------------
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  ✅ PASSOU: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  ❌ FALHOU: %s\n' "$1" >&2; }

# expect_exit <código_esperado> <nome> <comando...> — roda em SUBSHELL e
# compara o código de saída (bk_die/exit da função não mata o harness).
expect_exit() {
    local want="$1" nome="$2"
    shift 2
    local got=0
    ( "$@" ) || got=$?
    if [ "${got}" = "${want}" ]; then
        ok "${nome} (exit ${got} como esperado)"
    else
        fail "${nome} — esperado exit ${want}, obtido exit ${got}"
    fi
}

log_contains() {
    if grep -q -- "$2" "${LOG_FILE}" 2>/dev/null; then
        ok "$1"
    else
        fail "$1 — log não contém: $2"
    fi
}

CONTAINER_ID="abcdef1234567890"
EXPECTED_SERVICE="dpsjur_dpsjur-db"

# ==============================================================================
# T1+T4 — bk_resolve_swarm_container (FALHA 1, lado da resolução)
# ==============================================================================
printf '\n== T4a: serviço Swarm ausente é rejeitado ==\n'
export BK_MOCK_CASE="servico-ausente"
expect_exit 13 "serviço inexistente rejeitado" bk_resolve_swarm_container "${EXPECTED_SERVICE}"

printf '\n== T4b: nenhuma tarefa Running é rejeitada ==\n'
export BK_MOCK_CASE="sem-tarefa"
expect_exit 13 "nenhuma tarefa Running rejeitada" bk_resolve_swarm_container "${EXPECTED_SERVICE}"

printf '\n== T1a: resolução retorna EXATAMENTE o ID do contêiner ==\n'
export BK_MOCK_CASE="ok"
resolved="$(bk_resolve_swarm_container "${EXPECTED_SERVICE}" 2>/dev/null)"
rc=$?
if [ "${rc}" -eq 0 ] && [ "${resolved}" = "${CONTAINER_ID}" ]; then
    ok "resolve retornou exatamente o ID (${resolved})"
else
    fail "resolve — esperado stdout '${CONTAINER_ID}' com exit 0; obtido '${resolved:-vazio}' com exit ${rc}"
fi

# ==============================================================================
# T1–T3 — bk_verify_container (FALHA 1, lado da verificação)
# ==============================================================================
printf '\n== T1b: contêiner identificado por ID é ACEITO (18/Doug/dpsjur) ==\n'
export BK_MOCK_CASE="ok"
expect_exit 0 "ID do serviço Swarm aceito por bk_verify_container" \
    bk_verify_container "${CONTAINER_ID}" "18" "dpsjur" "Doug" "5432" ""

printf '\n== T2: contêiner INCORRETO é rejeitado ==\n'
export BK_MOCK_CASE="incorreto"
expect_exit 13 "contêiner incorreto rejeitado" \
    bk_verify_container "${CONTAINER_ID}" "18" "dpsjur" "Doug" "5432" ""

printf '\n== T3: contêiner AMBÍGUO (mesmo ID, dois nomes) é rejeitado ==\n'
export BK_MOCK_CASE="ambiguo"
expect_exit 13 "contêiner ambíguo rejeitado" \
    bk_verify_container "${CONTAINER_ID}" "18" "dpsjur" "Doug" "5432" ""

# ==============================================================================
# T5 — pg_dump falhando → FALHA com código próprio
# ==============================================================================
printf '\n== T5: pg_dump falhando → veredito FALHA (exit 20) ==\n'
export BK_MOCK_CASE="dump-fail"
export MOCK_DUMP_FAIL="1"
BK_DUMP_CMD=(docker exec "${CONTAINER_ID}" env PGPASSFILE="${BK_PGPASS_IN_CONTAINER}" \
    pg_dump -p "5432" -U "Doug" -d "dpsjur")
expect_exit "${BK_EXIT_DUMP_FAIL}" "bk_run_dump_pipeline retorna ${BK_EXIT_DUMP_FAIL} em falha de pg_dump" \
    bk_run_dump_pipeline "${WORK}/dump-falha/dump.sql.gz"

# ==============================================================================
# T6 — publicação falhando (destino existente) → FALHA, nada sobrescrito
# ==============================================================================
printf '\n== T6: publicação com destino existente → FALHA (exit 25) ==\n'
export BK_MOCK_CASE="publish-fail"
export MOCK_DUMP_FAIL="0"
mkdir -p "${WORK}/publish"
: > "${WORK}/publish/destino-existente.sql.gz"
: > "${WORK}/publish/tmp-simulado.sql.gz"
expect_exit "${BK_EXIT_FS_FAIL}" "bk_publish_dump recusa destino existente" \
    bk_publish_dump "${WORK}/publish/tmp-simulado.sql.gz" "${WORK}/publish/destino-existente.sql.gz"
if [ -f "${WORK}/publish/destino-existente.sql.gz" ] && [ ! -s "${WORK}/publish/destino-existente.sql.gz" ]; then
    ok "destino preexistente NÃO foi sobrescrito (intacto e vazio como antes)"
else
    fail "destino preexistente foi alterado — NUNCA deveria"
fi

# ==============================================================================
# T7–T9 — bk_finalize_session (FALHA 2, veredito por argumentos explícitos)
# ==============================================================================
printf '\n== T7: código 0 + limpeza ok → VEREDITO: SUCESSO ==\n'
: > "${LOG_FILE}"
# v2.1.2 (correção B): antes era `expect_exit 0 ... true`, que testava o
# comando `true` e não a função — passava sem testar nada. bk_finalize_session
# RETORNA 0 (não faz exit), então o código de retorno real é capturado aqui.
got=0
( bk_finalize_session 0 0 "Teste T7" ) || got=$?
if [ "${got}" -eq 0 ]; then
    ok "bk_finalize_session(0,0) retorna 0 (código real da função)"
else
    fail "bk_finalize_session(0,0) — esperado retorno 0, obtido ${got}"
fi
log_contains "veredito SUCESSO registrado" "VEREDITO: SUCESSO"

printf '\n== T8: código 20 + limpeza ok → FALHA com código original PRESERVADO ==\n'
: > "${LOG_FILE}"
got=0
( bk_finalize_session 20 0 "Teste T8" ) || got=$?
if [ "${got}" -eq 0 ]; then
    ok "bk_finalize_session(20,0) retorna 0 (falha registrada, exit decidido pelo chamador)"
else
    fail "bk_finalize_session(20,0) — esperado retorno 0, obtido ${got}"
fi
log_contains "veredito FALHA registrado" "VEREDITO: FALHA"
log_contains "código original 20 preservado no veredito" "exit original 20 PRESERVADO"

printf '\n== T9: código 0 + limpeza FALHA → FALHA DE LIMPEZA (não SUCESSO) ==\n'
: > "${LOG_FILE}"
got=0
( bk_finalize_session 0 1 "Teste T9" ) || got=$?
if [ "${got}" -eq 0 ]; then
    ok "bk_finalize_session(0,1) retorna 0 (veredito FALHA DE LIMPEZA no log, exit decidido pelo chamador)"
else
    fail "bk_finalize_session(0,1) — esperado retorno 0, obtido ${got}"
fi
if grep -q "VEREDITO: SUCESSO" "${LOG_FILE}"; then
    fail "T9 — SUCESSO registrado mesmo com limpeza falha"
else
    ok "SUCESSO NÃO registrado quando a limpeza falha"
fi
log_contains "FALHA DE LIMPEZA comunicada" "FALHA DE LIMPEZA"

# ==============================================================================
# T10 — código original preservado APÓS a limpeza (mecânica do trap EXIT)
# Réplica exata da mecânica dos scripts 22/23: captura no início, flag de
# limpeza, exit explícito dentro do trap.
# ==============================================================================
run_session_mechanics() {
    local simulated_exit="$1" cleanup_ok="$2"
    (
        cleanup() {
            local original_exit="$1"
            local cleanup_failed=0
            if [ "${cleanup_ok}" -ne 1 ]; then
                cleanup_failed=1   # limpeza simulada como falha
            fi
            if [ "${original_exit}" -eq 0 ] && [ "${cleanup_failed}" -ne 0 ]; then
                original_exit="${BK_EXIT_CLEANUP_FAIL}"
            fi
            # (log simulado omitido — sem LOG_FILE neste subshell de prova)
            exit "${original_exit}"
        }
        trap 'cleanup $?' EXIT
        exit "${simulated_exit}"
    )
}

printf '\n== T10a: falha original 20 SOBREVIVE à limpeza que falha ==\n'
got=0
run_session_mechanics 20 0 || got=$?
if [ "${got}" -eq 20 ]; then ok "exit 20 preservado após limpeza falha"; else fail "esperado 20, obtido ${got}"; fi

printf '\n== T10b: sucesso com limpeza falha → BK_EXIT_CLEANUP_FAIL (29) ==\n'
got=0
run_session_mechanics 0 0 || got=$?
if [ "${got}" -eq "${BK_EXIT_CLEANUP_FAIL}" ]; then ok "exit 29 quando só a limpeza falha"; else fail "esperado ${BK_EXIT_CLEANUP_FAIL}, obtido ${got}"; fi

printf '\n== T10c: sucesso com limpeza integral → 0 ==\n'
got=0
run_session_mechanics 0 1 || got=$?
if [ "${got}" -eq 0 ]; then ok "exit 0 quando tudo conclui"; else fail "esperado 0, obtido ${got}"; fi

# ==============================================================================
# Resumo
# ==============================================================================
printf '\n================================================================================\n'
printf 'RESUMO: %s passaram, %s falharam (mocks de docker/psql — NADA real executado)\n' "${PASS}" "${FAIL}"
printf 'Log completo do harness: %s\n' "${LOG_FILE}"
printf '================================================================================\n'
if [ "${FAIL}" -ne 0 ]; then
    exit 1
fi
exit 0
