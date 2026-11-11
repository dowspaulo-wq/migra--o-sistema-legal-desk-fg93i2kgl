#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur — Biblioteca compartilhada das rotinas de backup dos DOIS
# PostgreSQL da VPS Hostinger (EasyPanel/Docker).
# Script: docs/vps/lib/backup-lib.sh
# Versão: v1.0.0
#
# OBJETIVO:
#   Centralizar as funções comuns usadas por:
#     - docs/vps/22-backup-banco-a-sbjur-local.sh   (Banco A — PostgreSQL 15.8)
#     - docs/vps/23-backup-banco-b-dpsjur.sh        (Banco B — PostgreSQL 18)
#   De forma que cada banco tenha identificação, logs, diretórios e retenção
#   INDEPENDENTES (um script por banco), sem duplicar a mesma lógica duas vezes.
#
# REQUISITOS ATENDIDOS POR ESTA BIBLIOTECA (do pedido de Douglas):
#   - Senhas NUNCA na linha de comando nem em logs: pg_dump/psql autenticam via
#     PGPASSFILE (formato .pgpass, chmod 600 obrigatório) — Requisito 3.
#   - set -o pipefail + verificação SEPARADA dos códigos de saída do pg_dump e
#     da compactação via PIPESTATUS — Requisito 4.
#   - Validação de integridade (gzip -t) e tamanho mínimo do dump — Requisito 5.
#   - Logs independentes por banco, com SUCESSO/FALHA explícitos, sem /dev/null
#     para as saídas dos comandos — Requisito 7.
#   - Retenção controlada: por padrão APENAS INFORMA (modo observação) e só
#     apaga com --aplicar-retencao, nunca durante a migração — Requisito 8.
#   - Lock anti-simultâneo (flock, com fallback mkdir atômico) e proteção contra
#     sobrescrita (noclobber + nome de arquivo com timestamp; colisão = aborto) —
#     Requisito 9.
#
# POLÍTICA DE SEGURANÇA:
#   - umask 077 estrito; arquivos de log e dumps criados com permissão efetiva
#     conferida por stat (padrão dos demais scripts da sessão).
#   - Nenhuma senha em argumento de comando (visível em ps/ histórico/ logs).
#   - Falha de qualquer etapa essencial é FATAL (exit imediato com código
#     próprio), nunca silenciada.
# ==============================================================================

# ------------------------------------------------------------------------------
# Constantes de códigos de saída (compartilhadas pelos dois scripts)
# ------------------------------------------------------------------------------
BK_EXIT_OK=0
BK_EXIT_USAGE=10
BK_EXIT_LOCK=11          # outra execução em andamento
BK_EXIT_DEP_MISSING=12   # dependência ausente
BK_EXIT_GUARD=13         # identificação do contêiner não comprovada
BK_EXIT_DUMP_FAIL=20     # pg_dump falhou
BK_EXIT_COMPRESS_FAIL=21 # compactação falhou
BK_EXIT_INTEGRITY_FAIL=22 # gzip -t / tamanho mínimo falhou
BK_EXIT_FS_FAIL=25       # falha de filesystem (mkdir, touch, chmod, stat)
BK_EXIT_RETENTION_FAIL=27 # retenção apontou erro
BK_EXIT_CONFIG_FAIL=28   # configuração ausente/inválida (ex.: .pgpass)

# ------------------------------------------------------------------------------
# bk_log — grava uma linha no log da sessão e espelha em stdout/stderr.
# Uso: bk_log "mensagem"   (stdout) | bk_log_err "mensagem"  (stderr)
# O LOG_FILE precisa estar definido pelo script chamador.
# ------------------------------------------------------------------------------
bk_log() {
    printf '%s %s\n' "$(date '+%F %T')" "$*" >> "${LOG_FILE}"
    printf '%s\n' "$*"
}

bk_log_err() {
    printf '%s %s\n' "$(date '+%F %T')" "ERRO: $*" >> "${LOG_FILE}"
    printf '❌ %s\n' "$*" >&2
}

# ------------------------------------------------------------------------------
# bk_die — registra falha no log e encerra com o código indicado.
# ------------------------------------------------------------------------------
bk_die() {
    local msg="$1" code="$2"
    bk_log_err "${msg}"
    bk_log "FALHA (exit ${code}): ${msg}"
    printf 'FALHA (exit %s): %s\n' "${code}" "${msg}" >> "${LOG_FILE}"
    exit "${code}"
}

# ------------------------------------------------------------------------------
# bk_require_deps — valida dependências obrigatórias antes de qualquer trabalho.
# Uso: bk_require_deps docker gzip stat flock
# ------------------------------------------------------------------------------
bk_require_deps() {
    local dep
    for dep in "$@"; do
        if ! command -v "${dep}" >/dev/null 2>&1; then
            bk_die "Dependência obrigatória não encontrada no PATH: ${dep}" "${BK_EXIT_DEP_MISSING}"
        fi
    done
}

# ------------------------------------------------------------------------------
# bk_setup_dirs — cria a árvore de diretórios do banco (Requisito 6):
#   <base>/diario  <base>/semanal  <base>/mensal  <base>/logs  <base>/tmp
# Sempre com mkdir -p idempotente; falha é fatal.
# ------------------------------------------------------------------------------
bk_setup_dirs() {
    local base="$1"
    local d
    for d in diario semanal mensal logs tmp; do
        if [ ! -d "${base}/${d}" ]; then
            mkdir -p "${base}/${d}" || bk_die "Falha ao criar diretório: ${base}/${d}" "${BK_EXIT_FS_FAIL}"
            chmod 700 "${base}/${d}" || bk_die "Falha no chmod 700 de: ${base}/${d}" "${BK_EXIT_FS_FAIL}"
        fi
    done
    chmod 700 "${base}" 2>/dev/null || true
    return 0
}

# ------------------------------------------------------------------------------
# bk_verify_fs_file — verifica que o arquivo existe, não é vazio e tem permissão
# efetiva 600 (padrão da sessão). Uso: bk_verify_fs_file <caminho> <rotulo>
# ------------------------------------------------------------------------------
bk_verify_fs_file() {
    local path="$1" rotulo="$2" perm
    if [ ! -s "${path}" ]; then
        bk_die "Arquivo ${rotulo} inexistente ou vazio: ${path}" "${BK_EXIT_FS_FAIL}"
    fi
    perm="$(stat -c '%a' "${path}" 2>/dev/null || stat -f '%Lp' "${path}" 2>/dev/null || echo "")"
    if [ -z "${perm}" ]; then
        bk_die "Falha ao obter permissão de ${rotulo} via stat: ${path}" "${BK_EXIT_FS_FAIL}"
    fi
    if [ "${perm}" != "600" ]; then
        bk_die "Permissão efetiva de ${rotulo} inválida (${perm}); esperado 600: ${path}" "${BK_EXIT_FS_FAIL}"
    fi
    return 0
}

# ------------------------------------------------------------------------------
# bk_verify_container — Requisito 2: identificação EXPLÍCITA e PROVA de que o
# contêiner é o certo. NÃO usa regex genérica. Exige TODOS:
#   (a) o contêiner EXATO está em execução (docker ps --format '{{.Names}}');
#   (b) a versão major do PostgreSQL CONFERE com a esperada (SHOW server_version);
#   (c) o banco esperado EXISTE dentro dele (pg_database);
#   (d) o usuário esperado EXISTE dentro dele (pg_roles);
#   (e) o comando pg_dump existe dentro do contêiner.
# Qualquer divergência é fatal com exit ${BK_EXIT_GUARD}.
# Parâmetros: <container> <pg_major_esperado> <db_esperado> <user_esperado> <pg_bin_prefix>
#   pg_bin_prefix: "" (binário no PATH do contêiner) ou ex. "/usr/lib/postgresql/15/bin"
# ------------------------------------------------------------------------------
bk_verify_container() {
    local container="$1" pg_major_wanted="$2" db_wanted="$3" user_wanted="$4" pg_bin="$5"
    local running major db_list user_list

    # (a) contêiner EXATO em execução (busca por igualdade exata, não regex)
    running="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -Fx -- "${container}")" || running=""
    if [ "${running}" != "${container}" ]; then
        bk_die "Contêiner EXATO não está em execução: '${container}' (prova exigida por igualdade, sem regex genérica)." "${BK_EXIT_GUARD}"
    fi
    bk_log "Contêiner comprovado em execução: ${container}"

    # (b) versão major CONFERE
    major="$(docker exec "${container}" ${pg_bin}psql -X -A -t -c "SHOW server_version;" 2>>"${LOG_FILE}" | head -n 1 | awk -F. '{print $1}' | tr -d '[:space:]')" || {
        bk_die "Falha ao consultar server_version no contêiner ${container}." "${BK_EXIT_GUARD}"
    }
    if [ -z "${major}" ]; then
        bk_die "Versão do PostgreSQL vazia ou indeterminada no contêiner ${container}." "${BK_EXIT_GUARD}"
    fi
    if [ "${major}" != "${pg_major_wanted}" ]; then
        bk_die "Versão do PostgreSQL DIVERGENTE no contêiner ${container}: esperada ${pg_major_wanted}, obtida ${major}. Este script é exclusivo do banco ${pg_major_wanted}." "${BK_EXIT_GUARD}"
    fi
    bk_log "Versão PostgreSQL comprovada: ${major} (esperada ${pg_major_wanted})"

    # (c) banco esperado existe
    db_list="$(docker exec "${container}" ${pg_bin}psql -X -A -t -c "SELECT datname FROM pg_database WHERE datname = '${db_wanted}';" 2>>"${LOG_FILE}" | tr -d '[:space:]')" || {
        bk_die "Falha ao consultar pg_database no contêiner ${container}." "${BK_EXIT_GUARD}"
    }
    if [ "${db_list}" != "${db_wanted}" ]; then
        bk_die "Banco esperado NÃO encontrado no contêiner ${container}: '${db_wanted}'. Este script é exclusivo deste banco." "${BK_EXIT_GUARD}"
    fi
    bk_log "Banco comprovado no contêiner: ${db_wanted}"

    # (d) usuário esperado existe
    user_list="$(docker exec "${container}" ${pg_bin}psql -X -A -t -c "SELECT rolname FROM pg_roles WHERE rolname = '${user_wanted}';" 2>>"${LOG_FILE}" | tr -d '[:space:]')" || {
        bk_die "Falha ao consultar pg_roles no contêiner ${container}." "${BK_EXIT_GUARD}"
    }
    if [ "${user_list}" != "${user_wanted}" ]; then
        bk_die "Usuário esperado NÃO encontrado no contêiner ${container}: '${user_wanted}'." "${BK_EXIT_GUARD}"
    fi
    bk_log "Usuário comprovado no contêiner: ${user_wanted}"

    # (e) pg_dump existe no contêiner
    if ! docker exec "${container}" sh -c "command -v ${pg_bin}pg_dump >/dev/null 2>&1" >>"${LOG_FILE}" 2>&1; then
        bk_die "pg_dump não disponível dentro do contêiner ${container}." "${BK_EXIT_GUARD}"
    fi
    bk_log "pg_dump disponível no contêiner: ${container}"

    return 0
}

# ------------------------------------------------------------------------------
# bk_run_dump_pipeline — Requisitos 3 e 4: executa pg_dump | gzip com
#   - autenticação por PGPASSFILE (senha JAMAIS em argumento de comando);
#   - pipefail ativo e códigos de saída SEPARADOS de pg_dump e gzip (PIPESTATUS);
#   - destino gravado com noclobber (nunca sobrescreve arquivo preexistente).
# Retorna 0 em sucesso. Em falha, registra qual dos dois estágios falhou e
# retorna o código correspondente ao chamador (que decide o exit).
#
# Variáveis de ambiente esperadas (definidas pelo chamador):
#   BK_PGPASSFILE   caminho do arquivo .pgpass (chmod 600 validado antes)
#   BK_DUMP_CMD     array com o comando pg_dump base (sem -f/sem stdout duplo)
#   BK_DUMP_OUT     caminho do arquivo .sql.gz destino
#   LOG_FILE        log da sessão
#
# Uso típico no script chamador:
#   BK_DUMP_CMD=(pg_dump -U "${PG_USER}" -d "${PG_DB}" -Fc ...)
#   bk_run_dump_pipeline || rc=$?
# ------------------------------------------------------------------------------
bk_run_dump_pipeline() {
    local out="$1"
    local dump_rc gzip_rc
    local pipe_status

    # noclobber: a criação falha se o arquivo já existir (nunca sobrescrever).
    ( set -o noclobber; : > "${out}" ) 2>>"${LOG_FILE}" || {
        bk_log_err "Arquivo destino já existe (noclobber recusou sobrescrita): ${out}"
        return "${BK_EXIT_FS_FAIL}"
    }
    chmod 600 "${out}" 2>>"${LOG_FILE}" || {
        bk_log_err "Falha no chmod 600 do arquivo destino: ${out}"
        rm -f "${out}" 2>/dev/null || true
        return "${BK_EXIT_FS_FAIL}"
    }

    # Executa o pipeline com pipefail e captura de PIPESTATUS.
    set -o pipefail
    # shellcheck disable=SC2097,SC2098
    ( "${BK_DUMP_CMD[@]}" 2>>"${LOG_FILE}" ) | gzip -c 2>>"${LOG_FILE}" >> "${out}"
    pipe_status=("${PIPESTATUS[@]}")
    dump_rc="${pipe_status[0]:-1}"
    gzip_rc="${pipe_status[1]:-1}"
    if [ "${dump_rc}" -ne 0 ] || [ "${gzip_rc}" -ne 0 ]; then
        bk_log "FALHA no pipeline de dump: pg_dump exit ${dump_rc}, gzip exit ${gzip_rc}"
        return "${BK_EXIT_DUMP_FAIL}"
    fi
    bk_log "Pipeline de dump concluído: pg_dump exit 0, gzip exit 0"
    return 0
}

# ------------------------------------------------------------------------------
# bk_validate_dump — Requisito 5: integridade (gzip -t) e tamanho mínimo.
# Parâmetros: <arquivo.sql.gz> <tamanho_min_bytes>
# ------------------------------------------------------------------------------
bk_validate_dump() {
    local file="$1" min_bytes="$2"
    local size

    if [ ! -f "${file}" ]; then
        bk_die "Arquivo de dump não encontrado para validação: ${file}" "${BK_EXIT_INTEGRITY_FAIL}"
    fi

    # Integridade gzip
    if ! gzip -t "${file}" 2>>"${LOG_FILE}"; then
        bk_die "VALIDAÇÃO DE INTEGRIDADE FALHOU (gzip -t retornou erro): ${file}" "${BK_EXIT_INTEGRITY_FAIL}"
    fi
    bk_log "Integridade gzip confirmada (gzip -t exit 0): ${file}"

    # Tamanho mínimo
    size="$(stat -c '%s' "${file}" 2>/dev/null || stat -f '%z' "${file}" 2>/dev/null || echo "")"
    if [ -z "${size}" ]; then
        bk_die "Falha ao obter tamanho do dump via stat: ${file}" "${BK_EXIT_FS_FAIL}"
    fi
    if [ "${size}" -lt "${min_bytes}" ]; then
        bk_die "Tamanho do dump (${size} bytes) ABAIXO do mínimo exigido (${min_bytes} bytes): ${file}" "${BK_EXIT_INTEGRITY_FAIL}"
    fi
    bk_log "Tamanho do dump dentro do mínimo: ${size} bytes (mínimo ${min_bytes})."
    return 0
}

# ------------------------------------------------------------------------------
# bk_finalize_session — fecha a sessão com veredito explícito de SUCESSO/FALHA
# no log (Requisito 7). Sempre chamado no trap de EXIT.
# ------------------------------------------------------------------------------
bk_finalize_session() {
    local exit_code=$?
    if [ "${exit_code}" -eq 0 ]; then
        printf '%s VEREDITO: SUCESSO — backup concluído e validado (%s)\n' "$(date '+%F %T')" "$*" >> "${LOG_FILE}"
    else
        printf '%s VEREDITO: FALHA — backup NÃO concluído (exit %s) (%s)\n' "$(date '+%F %T')" "${exit_code}" "$*" >> "${LOG_FILE}"
    fi
    # Libera o lock se ainda estiver detido por este processo.
    if [ -n "${BK_LOCK_FD:-}" ]; then
        eval "exec ${BK_LOCK_FD}>&-" 2>/dev/null || true
    fi
    return "${exit_code}"
}

# ------------------------------------------------------------------------------
# bk_acquire_lock — Requisito 9: impede execução simultânea.
#   - Preferência: flock sobre descritor de arquivo (liberação automática no
#     fim do processo, inclusive em kill -9);
#   - Fallback: mkdir atômico com PID gravado (mkdir é atômico por construção).
# Em caso de lock existente: exit ${BK_EXIT_LOCK} SEM remover o lock alheio.
# ------------------------------------------------------------------------------
bk_acquire_lock() {
    local lock_path="$1"
    local pid_atual=$$

    if command -v flock >/dev/null 2>&1; then
        # abre o descritor 200 no arquivo de lock
        ( : > "${lock_path}" ) 2>>"${LOG_FILE}" || bk_die "Falha ao criar lock: ${lock_path}" "${BK_EXIT_LOCK}"
        chmod 600 "${lock_path}" 2>>"${LOG_FILE}" || bk_die "Falha no chmod 600 do lock: ${lock_path}" "${BK_EXIT_LOCK}"
        eval "exec 200>\"${lock_path}\"" || bk_die "Falha ao abrir lock para flock: ${lock_path}" "${BK_EXIT_LOCK}"
        BK_LOCK_FD=200
        if ! flock -n 200; then
            bk_die "OUTRA execução em andamento (lock ativo): ${lock_path}. Abortando sem interferir." "${BK_EXIT_LOCK}"
        fi
        printf '%s\n' "${pid_atual}" >&200
        bk_log "Lock adquirido via flock (${lock_path}, PID ${pid_atual})"
    else
        # Fallback: mkdir atômico (prova de ausência de lock preexistente).
        if ! mkdir "${lock_path}.d" 2>>"${LOG_FILE}"; then
            if [ -f "${lock_path}.d/pid" ]; then
                local other_pid
                other_pid="$(cat "${lock_path}.d/pid" 2>/dev/null || echo '?')"
                bk_die "OUTRA execução possivelmente em andamento (lock mkdir ativo, PID registrado: ${other_pid}): ${lock_path}.d" "${BK_EXIT_LOCK}"
            fi
            bk_die "Lock mkdir já existe e sem PID registrado (execução anterior pode ter morrido): ${lock_path}.d — resolver manualmente." "${BK_EXIT_LOCK}"
        fi
        printf '%s\n' "${pid_atual}" > "${lock_path}.d/pid" 2>>"${LOG_FILE}" || true
        chmod 700 "${lock_path}.d" 2>>"${LOG_FILE}" || true
        bk_log "Lock adquirido via mkdir atômico (${lock_path}.d, PID ${pid_atual})"
    fi
    return 0
}

# ------------------------------------------------------------------------------
# bk_release_lock — libera o lock mkdir (flock é liberado ao fechar o FD).
# ------------------------------------------------------------------------------
bk_release_lock() {
    if [ "${BK_LOCK_KIND:-}" = "mkdir" ] && [ -n "${BK_LOCK_PATH:-}" ]; then
        rm -rf "${BK_LOCK_PATH}.d" 2>/dev/null || true
        bk_log "Lock mkdir liberado."
    fi
    return 0
}

# ------------------------------------------------------------------------------
# bk_apply_retention — Requisito 8: retenção CONTROLADA por diretório
#   (diario/semanal/mensal) com política conservadora:
#   - MODO PADRÃO (sem --aplicar-retencao): APENAS INFORMA o que seria removido;
#     NADA é apagado (período de sobreposição com a rotina atual preservada);
#   - COM --aplicar-retencao: apaga SOMENTE arquivos com o prefixo do próprio
#     banco, SOMENTE no diretório correspondente e SOMENTE após a validação de
#     integridade deste dump ter passado; erro de exclusão é registrado e torna
#     a retenção "falha" (chamador decide exit).
# Parâmetros: <dir> <prefixo_banco> <manter_n> <aplicar: 0|1>
# ------------------------------------------------------------------------------
bk_apply_retention() {
    local dir="$1" prefix="$2" keep="$3" apply="$4"
    local f total=0 removed=0
    local list_file="${LOG_FILE%.log}-retencao-$(date +%Y%m%d-%H%M%S).list"

    if [ ! -d "${dir}" ]; then
        bk_log "Retenção: diretório inexistente, nada a fazer: ${dir}"
        return 0
    fi

    # Lista os arquivos do próprio banco (prefixo exato), mais antigos primeiro.
    : > "${list_file}" 2>>"${LOG_FILE}" || bk_die "Falha ao criar lista de retenção: ${list_file}" "${BK_EXIT_FS_FAIL}"
    chmod 600 "${list_file}" 2>>"${LOG_FILE}" || bk_die "Falha no chmod 600 da lista de retenção." "${BK_EXIT_FS_FAIL}"
    ls -1t "${dir}"/"${prefix}"*.sql.gz 2>>"${LOG_FILE}" | tac > "${list_file}" 2>>"${LOG_FILE}"

    total=0
    while IFS= read -r f; do
        [ -n "${f}" ] || continue
        total=$((total + 1))
    done < "${list_file}"

    if [ "${total}" -le "${keep}" ]; then
        bk_log "Retenção (${dir}): ${total} arquivo(s) do banco (<= ${keep} a manter); nada a remover."
        rm -f "${list_file}" 2>/dev/null || true
        return 0
    fi

    local to_remove=$((total - keep))
    bk_log "Retenção (${dir}): ${total} arquivo(s) do banco; manter os ${keep} mais recentes; candidatos a remover: ${to_remove}."

    if [ "${apply}" -ne 1 ]; then
        bk_log "Retenção em MODO OBSERVAÇÃO (sem --aplicar-retencao): NADA será excluído. Seriam removidos:"
        local shown=0
        while IFS= read -r f; do
            [ -n "${f}" ] || continue
            shown=$((shown + 1))
            if [ "${shown}" -le "${to_remove}" ]; then
                bk_log "  [seria removido] ${f}"
            fi
        done < "${list_file}"
        rm -f "${list_file}" 2>/dev/null || true
        return 0
    fi

    # Modo aplicação: remove apenas os mais antigos, até o limite.
    local count=0
    while IFS= read -r f; do
        [ -n "${f}" ] || continue
        count=$((count + 1))
        if [ "${count}" -gt "${to_remove}" ]; then
            break
        fi
        bk_log "Retenção: removendo backup antigo VALIDADO anteriormente: ${f}"
        if ! rm -f -- "${f}" 2>>"${LOG_FILE}"; then
            bk_log_err "Falha ao remover backup antigo: ${f}"
            return "${BK_EXIT_RETENTION_FAIL}"
        fi
        removed=$((removed + 1))
    done < "${list_file}"
    bk_log "Retenção aplicada: ${removed} backup(s) antigo(s) removido(s) de ${dir}."
    rm -f "${list_file}" 2>/dev/null || true
    return 0
}
