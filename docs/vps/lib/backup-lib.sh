#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur — Biblioteca compartilhada das rotinas de backup dos DOIS
# PostgreSQL da VPS Hostinger (EasyPanel/Docker).
# Script: docs/vps/lib/backup-lib.sh
# Versão: v2.0.0
#
# OBJETIVO:
#   Centralizar as funções comuns usadas por:
#     - docs/vps/22-backup-banco-a-sbjur-local.sh   (Banco A — PostgreSQL 15.8)
#     - docs/vps/23-backup-banco-b-dpsjur.sh        (Banco B — PostgreSQL 18)
#   De forma que cada banco tenha identificação, logs, diretórios e retenção
#   INDEPENDENTES (um script por banco), sem duplicar a mesma lógica duas vezes.
#
# CORREÇÕES DA AUDITORIA INDEPENDENTE (d510fd9 / v1.0.0 → v2.0.0):
#   A. TODAS as consultas psql dentro do contêiner usam conexão EXPLÍCITA
#      (-U <usuário> -d <banco> -p <porta>); o Banco B ainda resolve o
#      contêiner do serviço Swarm DETERMINISTICAMENTE (bk_resolve_swarm_container),
#      recusando resposta ausente ou ambígua (mais de um contêiner de tarefa).
#   B. Credenciais: NÃO se presume que PGPASSFILE do host chega ao docker exec.
#      O script chamador fornece bk_stage_pgpass_into_container / bk_remove_pgpass
#      para instalar o .pgpass DENTRO do contêiner (docker cp, chmod 600,
#      propriedade do usuário da conexão) e removê-lo ao final. Nenhuma senha
#      em argumento, log ou arquivo versionado.
#   C. Captura de código de erro: o padrão correto NÃO usa `!` na condição:
#         if bk_run_dump_pipeline "${OUT_FILE}"; then :; else rc=$?; fi
#      (com `!`, $? dentro do else seria 0 — inversão de status).
#   D. Escrita em arquivo TEMPORÁRIO exclusivo (mktemp no MESMO diretório de
#      destino, chmod 600), validação completa e PUBLICAÇÃO ATÔMICA (mv dentro
#      do mesmo filesystem). Backup existente NUNCA sobrescrito
#      (bk_publish_dump recusa destino já existente). Falha nunca remove
#      backups anteriores; limpeza de temporários é segura (nome próprio).
#   E. Lock: flock prepara o arquivo com noclobber e abre o FD com o arquivo
#      JÁ pronto (sem corrida de truncamento sob lock); fallback mkdir define
#      BK_LOCK_KIND/BK_LOCK_PATH/BK_LOCK_DIR DURANTE a aquisição, e
#      bk_release_lock só remove o diretório de lock QUANDO o PID registrado
#      é o próprio ($$), nunca o de outra execução.
#   F. Retenção: MODO OBSERVAÇÃO por padrão. Com exclusão habilitada: candidatos
#      são APENAS arquivos regulares (-f, sem seguir links simbólicos) com o
#      prefixo do próprio banco, no diretório correspondente; a validação de
#      integridade (gzip -t + tamanho mínimo) é executada AQUI, individualmente,
#      em cada candidato à remoção — arquivo que não valida NÃO é removido e
#      marca a retenção como falha.
#   G. pipefail + PIPESTATUS separados para pg_dump e gzip; bk_finalize_session
#      registra veredito. INTEGRIDADE gzip ≠ CONSISTÊNCIA do dump ≠ SUCESSO de
#      restauração isolada — três verificações NÃO equivalentes (ver doc).
#
# POLÍTICA DE SEGURANÇA:
#   - umask 077 estrito; arquivos com permissão efetiva conferida por stat.
#   - Nenhuma senha em argumento de comando (visível em ps/histórico/logs).
#   - Falha de qualquer etapa essencial é FATAL (exit com código próprio).
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
# bk_setup_dirs — cria a árvore de diretórios do banco:
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
# bk_psql_in_container — executa psql DENTRO do contêiner com conexão
# EXPLÍCITA: usuário, banco e porta informados (nunca inferidos pelo cliente).
# A autenticação usa o PGPASSFILE instalado dentro do contêiner pelo chamador
# (bk_stage_pgpass_into_container) — nenhuma senha em argumento.
#
# Parâmetros: <container> <bin_prefix> <pg_user> <pg_db> <pg_port> <sql>
# Saída no stdout; stderr vai para o log da sessão.
# ------------------------------------------------------------------------------
bk_psql_in_container() {
    local container="$1" bin_prefix="$2" pg_user="$3" pg_db="$4" pg_port="$5" sql="$6"
    local out
    if ! out="$(docker exec "${container}" env PGPASSFILE="${BK_PGPASS_IN_CONTAINER:-/tmp/.pgpass-bk}" \
            "${bin_prefix}psql" -X -A -t -q -p "${pg_port}" -U "${pg_user}" -d "${pg_db}" -c "${sql}" \
            2>>"${LOG_FILE}")"; then
        return 1
    fi
    printf '%s' "${out}"
    return 0
}

# ------------------------------------------------------------------------------
# bk_resolve_swarm_container — identificação DETERMINÍSTICA do contêiner que
# executa o serviço Docker Swarm esperado. NÃO usa o nome do contêiner nem
# regex genérica sobre nomes: usa `docker service ps` e filtra por igualdade
# exata do serviço + estado Running, deduplicando réplicas.
#
# Parâmetros: <servico_swarm>   ex.: dpsjur_dpsjur-db
# Saída: nome do contêiner no stdout.
# Ambiguidade (mais de um contêiner Running da mesma tarefa em nós distintos
# com nomes diferentes) ou ausência de contêiner Running é FATAL (exit 13):
# o script NÃO adivinha qual réplica usar.
# ------------------------------------------------------------------------------
bk_resolve_swarm_container() {
    local service="$1"
    local names filtered unique count

    # (1) comando docker + nó manager do Swarm acessível (prova real de acesso)
    if ! docker info >/dev/null 2>&1; then
        bk_die "Docker daemon inacessível — impossível resolver serviço Swarm '${service}'." "${BK_EXIT_GUARD}"
    fi
    if ! docker service ls --format '{{.Name}}' 2>/dev/null | grep -Fx -- "${service}" >/dev/null; then
        bk_die "Serviço Swarm NÃO encontrado por igualdade exata: '${service}'. O nó pode não ser manager (docker service exige), o serviço pode ter mudado de nome ou o Swarm está indisponível — CONFIRMAR com Douglas antes de qualquer alteração." "${BK_EXIT_GUARD}"
    fi

    # (2) nomes de tarefa do serviço, APENAS as com contêiner Running atual
    #     (formato oficial de tarefa do Swarm: <servico>.<slot>.<id-tarefa>).
    #     Docker service ps só roda em manager; aqui o manager é obrigatório.
    names="$(docker service ps --format '{{.Name}}' --filter "desired-state=running" -- "${service}" 2>>"${LOG_FILE}")" || {
        bk_die "Falha ao listar tarefas do serviço Swarm '${service}'." "${BK_EXIT_GUARD}"
    }
    if [ -z "${names//[$'\t\r ']/}" ]; then
        bk_die "Nenhuma tarefa Running para o serviço '${service}' — recusando (sem adivinhação)." "${BK_EXIT_GUARD}"
    fi

    # (3) apenas tarefas cujo contêiner EFETIVAMENTE existe neste nó (docker ps
    #     conhece o nome EXATAMENTE — `docker service ps` lista tarefas de todos
    #     os nós; só o contêiner local é utilizável para docker exec aqui).
    filtered=""
    local n
    while IFS= read -r n; do
        [ -n "${n}" ] || continue
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -Fx -- "${n}" >/dev/null; then
            filtered="${filtered}${n}"$'\n'
        fi
    done <<EOF_TAREFAS
${names}
EOF_TAREFAS

    # (4) deduplica (tarefa pode aparecer duplicada em estados transitórios) e
    #     EXIGE exatamente UM contêiner local do serviço — ambiguidade é fatal.
    unique="$(printf '%s' "${filtered}" | sed '/^$/d' | sort -u)"
    if [ -z "${unique}" ]; then
        bk_die "Nenhum contêiner local elegível para o serviço '${service}' (nenhuma tarefa Running neste nó). Recusando prosseguir — sem adivinhação e sem regex genérica." "${BK_EXIT_GUARD}"
    fi
    count="$(printf '%s\n' "${unique}" | grep -c . || true)"
    if [ "${count}" -ne 1 ]; then
        bk_die "Identificação do contêiner do serviço '${service}' AMBÍGUA neste nó (${count} contêineres Running elegíveis). Recusando prosseguir — sem adivinhação e sem regex genérica." "${BK_EXIT_GUARD}"
    fi

    local container="${unique}"
    bk_log "Contêiner do serviço Swarm '${service}' resolvido deterministicamente: ${container}"
    printf '%s\n' "${container}"
    return 0
}

# ------------------------------------------------------------------------------
# bk_verify_container — identificação EXPLÍCITA e PROVA de que o contêiner é o
# certo. NÃO usa regex genérica. Exige TODOS:
#   (a) o contêiner EXATO está em execução (igualdade exata, não regex);
#   (b) TODAS as consultas psql usam conexão EXPLÍCITA: -U <usuário> -d <banco>
#       -p <porta> (o PGPASSFILE interno precisa já estar instalado —
#       bk_stage_pgpass_into_container ANTES desta função);
#   (c) a versão major do PostgreSQL CONFERE com a esperada (SHOW server_version);
#   (d) o banco esperado EXISTE dentro dele (pg_database — no banco conectado);
#   (e) o usuário esperado EXISTE dentro dele (pg_roles — no banco conectado);
#   (f) o comando pg_dump existe dentro do contêiner.
# Qualquer divergência é fatal com exit ${BK_EXIT_GUARD}.
# Parâmetros: <container> <pg_major_esperado> <db_esperado> <user_esperado>
#             <pg_port> <pg_bin_prefix>
#   pg_bin_prefix: "" (binário no PATH do contêiner) ou ex. "/usr/lib/postgresql/15/bin"
# ------------------------------------------------------------------------------
bk_verify_container() {
    local container="$1" pg_major_wanted="$2" db_wanted="$3" user_wanted="$4" pg_port="$5" pg_bin="$6"
    local running major db_found user_found

    # (a) contêiner EXATO em execução (busca por igualdade exata, não regex)
    running="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -Fx -- "${container}")" || running=""
    if [ "${running}" != "${container}" ]; then
        bk_die "Contêiner EXATO não está em execução: '${container}' (prova exigida por igualdade, sem regex genérica)." "${BK_EXIT_GUARD}"
    fi
    bk_log "Contêiner comprovado em execução: ${container}"

    # (b+e) conexão EXPLÍCITA: usuário e banco do PRÓPRIO banco em todas as
    # consultas; autenticação via PGPASSFILE interno (bk_stage_pgpass_into_container).
    if ! major="$(bk_psql_in_container "${container}" "${pg_bin}" "${user_wanted}" "${db_wanted}" "${pg_port}" "SHOW server_version;")"; then
        bk_die "Falha ao consultar server_version no contêiner ${container} (conexão explícita -U ${user_wanted} -d ${db_wanted} -p ${pg_port}). Verificar credenciais internas (seção 3 do RUN-BACKUP-DUPLA-POSTGRES.md)." "${BK_EXIT_GUARD}"
    fi
    major="$(printf '%s' "${major}" | head -n 1 | awk -F. '{print $1}' | tr -d '[:space:]')"
    if [ -z "${major}" ]; then
        bk_die "Versão do PostgreSQL vazia ou indeterminada no contêiner ${container}." "${BK_EXIT_GUARD}"
    fi
    if [ "${major}" != "${pg_major_wanted}" ]; then
        bk_die "Versão do PostgreSQL DIVERGENTE no contêiner ${container}: esperada ${pg_major_wanted}, obtida ${major}. Este script é exclusivo do banco ${pg_major_wanted}." "${BK_EXIT_GUARD}"
    fi
    bk_log "Versão PostgreSQL comprovada: ${major} (esperada ${pg_major_wanted})"

    # (d) banco esperado existe (consulta rodando DENTRO do banco conectado)
    if ! db_found="$(bk_psql_in_container "${container}" "${pg_bin}" "${user_wanted}" "${db_wanted}" "${pg_port}" "SELECT datname FROM pg_database WHERE datname = '${db_wanted}';")"; then
        bk_die "Falha ao consultar pg_database no contêiner ${container} (conexão explícita -U ${user_wanted} -d ${db_wanted})." "${BK_EXIT_GUARD}"
    fi
    db_found="$(printf '%s' "${db_found}" | tr -d '[:space:]')"
    if [ "${db_found}" != "${db_wanted}" ]; then
        bk_die "Banco esperado NÃO encontrado no contêiner ${container}: '${db_wanted}'. Este script é exclusivo deste banco." "${BK_EXIT_GUARD}"
    fi
    bk_log "Banco comprovado no contêiner: ${db_wanted}"

    # (e) usuário esperado existe (consulta rodando DENTRO do banco conectado)
    if ! user_found="$(bk_psql_in_container "${container}" "${pg_bin}" "${user_wanted}" "${db_wanted}" "${pg_port}" "SELECT rolname FROM pg_roles WHERE rolname = '${user_wanted}';")"; then
        bk_die "Falha ao consultar pg_roles no contêiner ${container} (conexão explícita -U ${user_wanted} -d ${db_wanted})." "${BK_EXIT_GUARD}"
    fi
    user_found="$(printf '%s' "${user_found}" | tr -d '[:space:]')"
    if [ "${user_found}" != "${user_wanted}" ]; then
        bk_die "Usuário esperado NÃO encontrado no contêiner ${container}: '${user_wanted}'." "${BK_EXIT_GUARD}"
    fi
    bk_log "Usuário comprovado no contêiner: ${user_wanted}"

    # (f) pg_dump existe no contêiner
    if ! docker exec "${container}" sh -c "command -v ${pg_bin}pg_dump >/dev/null 2>&1" >>"${LOG_FILE}" 2>&1; then
        bk_die "pg_dump não disponível dentro do contêiner ${container}." "${BK_EXIT_GUARD}"
    fi
    bk_log "pg_dump disponível no contêiner: ${container}"

    return 0
}

# ------------------------------------------------------------------------------
# bk_stage_pgpass_into_container — instala o .pgpass DENTRO do contêiner para o
# processo que executará pg_dump/psql (docker exec NÃO herda PGPASSFILE do host).
#
# O que esta função faz (NADA de senha em argumento, log ou arquivo versionado):
#   1. valida o .pgpass do HOST (chmod 600, 5 campos, sem senha vazia);
#   2. copia o arquivo para dentro do contêiner via `docker cp` (a senha não
#      aparece na linha de comando — só caminhos);
#   3. chmod 600 e chown do usuário da conexão DENTRO do contêiner.
# Em caso de qualquer falha, remove o resíduo e aborta (exit 28).
#
# Parâmetros: <container> <host_pgpass> <container_pgpass> <container_user_owner>
# Define: BK_PGPASS_IN_CONTAINER (caminho interno, usado por bk_psql_in_container
# e por bk_run_dump_pipeline via `docker exec ... env PGPASSFILE=...`).
# NOTA (requisito B): docker exec NÃO herda PGPASSFILE do host; a instalação
# dentro do contêiner é obrigatória e o caminho interno deve ter chmod 600 e
# ser propriedade do usuário da conexão.
# ------------------------------------------------------------------------------
bk_stage_pgpass_into_container() {
    local container="$1" host_pgpass="$2" container_pgpass="$3" owner_user="$4"

    # (1) validação estrutural do .pgpass do host (sem ecoar conteúdo)
    if [ ! -f "${host_pgpass}" ]; then
        bk_die "Arquivo .pgpass não encontrado no host: ${host_pgpass}. Crie-o com chmod 600 antes de rodar o backup (veja --help)." "${BK_EXIT_CONFIG_FAIL}"
    fi
    bk_verify_fs_file "${host_pgpass}" "PGPASSFILE do host"
    local nfields
    nfields="$(awk -F'[:\\\\]' '{print NF}' "${host_pgpass}" 2>>"${LOG_FILE}" | grep -vx '5' | head -n 1)"
    if [ -n "${nfields}" ]; then
        bk_die "${host_pgpass}: linha(s) sem exatamente 5 campos .pgpass (senha com ':' não escapada?). Corrigir ANTES de prosseguir." "${BK_EXIT_CONFIG_FAIL}"
    fi
    if grep -q ':$' "${host_pgpass}" 2>>"${LOG_FILE}"; then
        bk_die "${host_pgpass}: senha VAZIA encontrada — recusando (autenticação falharia). Corrigir antes de prosseguir." "${BK_EXIT_CONFIG_FAIL}"
    fi

    # (2) copiar para dentro do contêiner via docker cp (só caminhos na argv)
    if ! docker cp "${host_pgpass}" "${container}:${container_pgpass}" >>"${LOG_FILE}" 2>&1; then
        bk_die "Falha ao copiar o .pgpass para dentro do contêiner ${container} (docker cp)." "${BK_EXIT_CONFIG_FAIL}"
    fi
    if ! docker exec "${container}" sh -c "chmod 600 '${container_pgpass}' && chown '${owner_user}' '${container_pgpass}'" >>"${LOG_FILE}" 2>&1; then
        docker exec "${container}" sh -c "rm -f '${container_pgpass}'" >/dev/null 2>&1 || true
        bk_die "Falha ao ajustar chmod 600/chown do .pgpass interno em ${container} (dono: ${owner_user})." "${BK_EXIT_CONFIG_FAIL}"
    fi

    # (3) exportar o caminho interno para bk_psql_in_container e para o dump
    BK_PGPASS_IN_CONTAINER="${container_pgpass}"
    export BK_PGPASS_IN_CONTAINER
    bk_log "PGPASSFILE instalado dentro do contêiner ${container} em ${container_pgpass} (chmod 600, dono ${owner_user}); senha fora de argumento/log."
    return 0
}

# ------------------------------------------------------------------------------
# bk_remove_pgpass — remove o .pgpass interno do contêiner (sempre ao final da
# sessão, inclusive em falha — trap do chamador). Sem echo de conteúdo.
# ------------------------------------------------------------------------------
bk_remove_pgpass() {
    local container="$1" container_pgpass="$2"
    if [ -n "${container}" ] && [ -n "${container_pgpass}" ]; then
        docker exec "${container}" sh -c "rm -f '${container_pgpass}'" >>"${LOG_FILE}" 2>&1 || true
        bk_log "PGPASSFILE interno removido do contêiner ${container}: ${container_pgpass}"
    fi
    return 0
}

# ------------------------------------------------------------------------------
# bk_run_dump_pipeline — executa pg_dump | gzip em arquivo TEMPORÁRIO exclusivo
# (mktemp no MESMO diretório do destino: mv de publicação atômica no mesmo
# filesystem), com:
#   - autenticação por PGPASSFILE DENTRO do contêiner (docker exec env
#     PGPASSFILE=...) — senha JAMAIS em argumento de comando;
#   - pipefail ativo e códigos de saída SEPARADOS de pg_dump e gzip (PIPESTATUS);
#   - NENHUMA escrita direta no destino final: bk_publish_dump publica com mv
#     atômico e recusa destino existente.
# Em falha, o temporário é removido e o código de falha correspondente é
# retornado ao chamador (que decide o exit).
#
# Variáveis de ambiente esperadas (definidas pelo chamador):
#   BK_DUMP_CMD     array com o comando pg_dump (sem -f)
#   LOG_FILE        log da sessão
#
# Parâmetros: <destino_final.sql.gz>
# Saída: define a variável global BK_TMP_FILE com o caminho do temporário
# criado (o chamador passa adiante para bk_validate_dump e bk_publish_dump).
# bk_tmp_cleanup é a limpeza segura (só o nome criado aqui, nunca de outro).
# ------------------------------------------------------------------------------
bk_run_dump_pipeline() {
    local final_out="$1"
    local dump_rc gzip_rc tmp
    local pipe_status

    # (1) temporário exclusivo no MESMO diretório do destino (mesmo filesystem
    # → publicação via mv é atômica); chmod 600 explícito; umask 077 reforça.
    mkdir -p -- "$(dirname -- "${final_out}")" || {
        bk_log_err "Falha ao preparar diretório de destino: $(dirname -- "${final_out}")"
        return "${BK_EXIT_FS_FAIL}"
    }
    tmp="$(mktemp -- "${final_out}.tmp-XXXXXX" 2>>"${LOG_FILE}")" || {
        bk_log_err "Falha ao criar arquivo temporário exclusivo junto a ${final_out}."
        return "${BK_EXIT_FS_FAIL}"
    }
    chmod 600 "${tmp}" 2>>"${LOG_FILE}" || {
        bk_log_err "Falha no chmod 600 do temporário: ${tmp}"
        rm -f -- "${tmp}" 2>/dev/null || true
        return "${BK_EXIT_FS_FAIL}"
    }
    BK_TMP_FILE="${tmp}"
    export BK_TMP_FILE
    bk_log "Temporário exclusivo criado: ${tmp}"

    # (2) pipeline: pg_dump → gzip → temporário. PIPESTATUS captura o código de
    # cada estágio SEPARADAMENTE (pipefail no shell principal, herdado pelo
    # pg_dump via docker exec). Saída apenas para o TEMPORÁRIO: o destino final
    # só é criado por bk_publish_dump (mv atômico), nunca por >> direto.
    "${BK_DUMP_CMD[@]}" 2>>"${LOG_FILE}" | gzip -c 2>>"${LOG_FILE}" >> "${tmp}"
    pipe_status=("${PIPESTATUS[@]}")
    dump_rc="${pipe_status[0]:-1}"
    gzip_rc="${pipe_status[1]:-1}"
    if [ "${dump_rc}" -ne 0 ] || [ "${gzip_rc}" -ne 0 ]; then
        bk_log "FALHA no pipeline de dump: pg_dump exit ${dump_rc}, gzip exit ${gzip_rc}"
        bk_tmp_cleanup
        if [ "${dump_rc}" -ne 0 ]; then
            return "${BK_EXIT_DUMP_FAIL}"
        fi
        return "${BK_EXIT_COMPRESS_FAIL}"
    fi
    bk_log "Pipeline de dump concluído: pg_dump exit 0, gzip exit 0 → temporário ${tmp}"
    return 0
}

# ------------------------------------------------------------------------------
# bk_tmp_cleanup — limpeza SEGURA do temporário desta execução:
# só remove o caminho registrado em BK_TMP_FILE (nome exclusivo desta sessão),
# nunca glob, nunca arquivo de outra execução. Idempotente.
# ------------------------------------------------------------------------------
bk_tmp_cleanup() {
    if [ -n "${BK_TMP_FILE:-}" ] && [ -f "${BK_TMP_FILE}" ] && [ ! -L "${BK_TMP_FILE}" ]; then
        rm -f -- "${BK_TMP_FILE}" 2>>"${LOG_FILE}" || true
        bk_log "Temporário desta sessão removido: ${BK_TMP_FILE}"
    fi
    return 0
}

# ------------------------------------------------------------------------------
# bk_validate_dump — integridade (gzip -t) e tamanho mínimo.
# Parâmetros: <arquivo.sql.gz> <tamanho_min_bytes>
# IMPORTANTE: gzip -t prova INTEGRIDADE do arquivo — NÃO prova CONSISTÊNCIA do
# dump nem SUCESSO de restauração isolada (três verificações não equivalentes).
# ------------------------------------------------------------------------------
bk_validate_dump() {
    local file="$1" min_bytes="$2"
    local size

    if [ ! -f "${file}" ] || [ -L "${file}" ]; then
        bk_die "Arquivo de dump não encontrado ou não é arquivo regular: ${file}" "${BK_EXIT_INTEGRITY_FAIL}"
    fi

    # Integridade gzip (verificação de INTEGRIDADE do arquivo — não de conteúdo)
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
# bk_publish_dump — PUBLICAÇÃO ATÔMICA do backup validado:
#   - recusa destino existente (nunca sobrescreve backup preexistente);
#   - publica com mv DENTRO do MESMO filesystem (mv é atômico neste caso);
#   - falha na publicação NUNCA remove backups anteriores nem outros arquivos.
# Parâmetros: <temporário> <destino_final.sql.gz>
# ------------------------------------------------------------------------------
bk_publish_dump() {
    local tmp="$1" final="$2"

    if [ -e "${final}" ] || [ -L "${final}" ]; then
        bk_die "Destino JÁ EXISTE — recusando sobrescrita (backup preexistente preservado): ${final}. Remoção manual decidida por Douglas, se necessário." "${BK_EXIT_FS_FAIL}"
    fi
    if [ ! -f "${tmp}" ] || [ -L "${tmp}" ]; then
        bk_die "Temporário não encontrado para publicação (não é arquivo regular): ${tmp}" "${BK_EXIT_FS_FAIL}"
    fi

    # mv no MESMO filesystem: renomeação atômica. -n recusa sobrescrever caso
    # algo apareça na janela entre a prova acima e o mv (falha → abort; NUNCA
    # trunca o destino que surgiu). Se o mv falhar, o temporário é preservado
    # para análise (limpeza é responsabilidade de bk_tmp_cleanup do chamador).
    if ! mv -n -- "${tmp}" "${final}" 2>>"${LOG_FILE}"; then
        bk_die "Falha na publicação atômica (mv) de ${tmp} → ${final}." "${BK_EXIT_FS_FAIL}"
    fi
    if [ ! -f "${final}" ] || [ -f "${tmp}" ]; then
        bk_die "Publicação NÃO confirmada (destino ausente ou temporário ainda presente): ${final}." "${BK_EXIT_FS_FAIL}"
    fi
    chmod 600 "${final}" 2>>"${LOG_FILE}" || true
    bk_log "Backup publicado ATOMICAMENTE: ${final}"
    bk_log "ATENÇÃO: integridade gzip ≠ consistência do dump ≠ restauração isolada validada — três verificações NÃO equivalentes (ver RUN-BACKUP-DUPLA-POSTGRES.md)."
    return 0
}

# ------------------------------------------------------------------------------
# bk_finalize_session — fecha a sessão com veredito explícito de SUCESSO/FALHA
# no log (Requisito 7). Sempre chamado no trap de EXIT.
# ------------------------------------------------------------------------------
bk_finalize_session() {
    # Chamado DENTRO do trap EXIT (cleanup $?): $? é o código real da sessão.
    local exit_code=$?
    if [ "${exit_code}" -eq 0 ]; then
        printf '%s VEREDITO: SUCESSO — backup concluído, validado e publicado (%s)\n' "$(date '+%F %T')" "$*" >> "${LOG_FILE}"
    else
        printf '%s VEREDITO: FALHA — backup NÃO concluído, nenhum backup anterior afetado (exit %s) (%s)\n' "$(date '+%F %T')" "${exit_code}" "$*" >> "${LOG_FILE}"
    fi
    # Libera o FD do flock se ainda estiver detido por este processo (o lock
    # mkdir é liberado por bk_release_lock acima, com prova de identidade).
    if [ -n "${BK_LOCK_FD:-}" ]; then
        eval "exec ${BK_LOCK_FD}>&-" 2>/dev/null || true
    fi
    # Preserva o código da sessão: um comando dentro do trap EXIT não altera
    # o exit original do script (o trap termina com este return).
    return "${exit_code}"
}

# ------------------------------------------------------------------------------
# bk_acquire_lock — impede execução simultânea.
#   - Preferência: flock sobre descritor de arquivo (liberação automática no
#     fim do processo, inclusive em kill -9). O arquivo de lock é criado com
#     noclobber (nunca trunca arquivo alheio) e o FD é aberto APÓS a criação
#     (sem corrida de preparação sob lock — sem `: > file` destrutivo);
#   - Fallback: mkdir atômico com PID gravado. As variáveis BK_LOCK_KIND,
#     BK_LOCK_PATH e BK_LOCK_DIR são definidas DURANTE a aquisição (bk_release_lock
#     só age quando elas existem e quando o PID registrado é o próprio $$).
# Em caso de lock existente: exit ${BK_EXIT_LOCK} SEM remover o lock alheio.
# ------------------------------------------------------------------------------
bk_acquire_lock() {
    local lock_path="$1"
    local pid_atual=$$

    if command -v flock >/dev/null 2>&1; then
        # (1) cria o arquivo SEM truncar nada preexistente (noclobber atômico)
        if ! ( set -o noclobber; : > "${lock_path}" ) 2>>"${LOG_FILE}"; then
            bk_die "Lock já existe e não pôde ser criado com noclobber (execução em andamento?): ${lock_path}." "${BK_EXIT_LOCK}"
        fi
        chmod 600 "${lock_path}" 2>>"${LOG_FILE}" || bk_die "Falha no chmod 600 do lock: ${lock_path}" "${BK_EXIT_LOCK}"
        # (2) abre o FD só DEPOIS do arquivo pronto (sem corrida de preparação)
        eval "exec 200>\"${lock_path}\"" || bk_die "Falha ao abrir lock para flock: ${lock_path}" "${BK_EXIT_LOCK}"
        BK_LOCK_FD=200
        # (3) tenta o lock exclusivo; falha = outra execução detém o lock
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
        # Define as variáveis de estado DURANTE a aquisição (antes de escrever
        # o PID), garantindo que bk_release_lock só age se a aquisição foi SÓ.
        BK_LOCK_KIND="mkdir"
        BK_LOCK_PATH="${lock_path}"
        BK_LOCK_DIR="${lock_path}.d"
        BK_LOCK_PID="${pid_atual}"
        printf '%s\n' "${pid_atual}" > "${lock_path}.d/pid" 2>>"${LOG_FILE}" || bk_die "Lock adquirido mas falha ao registrar PID — resolvendo manualmente (nenhuma alteração automática)." "${BK_EXIT_LOCK}"
        chmod 700 "${lock_path}.d" 2>>"${LOG_FILE}" || true
        bk_log "Lock adquirido via mkdir atômico (${lock_path}.d, PID ${pid_atual})"
    fi
    return 0
}

# ------------------------------------------------------------------------------
# bk_release_lock — libera o lock mkdir (flock é liberado ao fechar o FD).
# NUNCA remove o lock de OUTRA execução: só age quando
#   - o lock desta sessão é mkdir;
#   - o diretório de lock é exatamente o desta sessão;
#   - o PID registrado DENTRO do lock é o próprio $$.
# Se o PID divergir, o lock é de outra execução — NÃO tocar (só registrar).
# ------------------------------------------------------------------------------
bk_release_lock() {
    [ "${BK_LOCK_KIND:-}" = "mkdir" ] || return 0
    [ -n "${BK_LOCK_DIR:-}" ] || return 0
    local lock_pid
    lock_pid="$(cat "${BK_LOCK_DIR}/pid" 2>/dev/null || echo '')"
    if [ "${lock_pid}" != "${BK_LOCK_PID:-}" ] || [ "${lock_pid}" != "$$" ]; then
        bk_log "Lock mkdir NÃO liberado: PID registrado (${lock_pid:-vazio}) não é desta execução ($$) — lock de outra execução NÃO foi tocado."
        return 0
    fi
    rm -rf -- "${BK_LOCK_DIR}" 2>/dev/null || true
    bk_log "Lock mkdir liberado (PID próprio confirmado: ${lock_pid})."
    return 0
}

# ------------------------------------------------------------------------------
# bk_apply_retention — retenção CONTROLADA por diretório (diario/semanal/mensal)
# com política CONSERVADORA e PROVA REAL:
#   - MODO PADRÃO (sem --aplicar-retencao): APENAS INFORMA o que seria removido;
#     NADA é apagado (período de sobreposição com a rotina atual preservada);
#   - COM --aplicar-retencao: candidatos são APENAS arquivos REGULARES com o
#     prefixo exato do PRÓPRIO banco, no DIRETÓRIO correspondente (não segue
#     links simbólicos — glob não-resolver + [ -f ] sem -L recusa symlink);
#     cada candidato à remoção é VALIDADO individualmente (gzip -t + tamanho
#     mínimo) antes da exclusão — arquivo que não valida NÃO é removido e
#     marca a retenção como FALHA (exit 27); erro de exclusão idem.
#   - A rotina antiga (outros prefixos, ex. backup-*) NUNCA é tocada.
# Parâmetros: <dir> <prefixo_banco> <manter_n> <aplicar: 0|1> <tamanho_min_bytes>
# ------------------------------------------------------------------------------
bk_apply_retention() {
    local dir="$1" prefix="$2" keep="$3" apply="$4" min_bytes="$5"
    local f total=0 removed=0
    local validated_ok=1

    if [ ! -d "${dir}" ]; then
        bk_log "Retenção: diretório inexistente, nada a fazer: ${dir}"
        return 0
    fi

    # Lista apenas arquivos REGULARES do próprio banco (prefixo exato), sem
    # seguir links simbólicos (glob que não casa é vazio; -f sem -L recusa
    # symlink). Os nomes são gerados por ESTES scripts com carimbo
    # YYYYmmdd-HHMMSS, portanto a ordenação LEXICOGRÁFICA é cronológica
    # (antigos primeiro) — sem depender de mtime nem de subshell.
    local ordered
    ordered="$(mktemp -- "${LOG_FILE}-retencao-list-XXXXXX" 2>>"${LOG_FILE}")" || \
        bk_die "Falha ao criar lista ordenada de retenção." "${BK_EXIT_FS_FAIL}"
    chmod 600 "${ordered}" 2>>"${LOG_FILE}" || true
    for f in "${dir}"/"${prefix}"*.sql.gz; do
        [ -e "${f}" ] || continue            # glob não casou
        [ -f "${f}" ] || continue            # não é arquivo regular (ex.: diretório)
        [ -L "${f}" ] && continue            # link simbólico: NUNCA candidato
        printf '%s\n' "${f}" >> "${ordered}" 2>>"${LOG_FILE}"
    done
    sort -o "${ordered}" "${ordered}" 2>>"${LOG_FILE}" || bk_die "Falha ao ordenar lista de retenção." "${BK_EXIT_FS_FAIL}"

    total=0
    while IFS= read -r f; do
        [ -n "${f}" ] || continue
        total=$((total + 1))
    done < "${ordered}"

    if [ "${total}" -le "${keep}" ]; then
        bk_log "Retenção (${dir}): ${total} arquivo(s) do banco (<= ${keep} a manter); nada a remover."
        rm -f "${ordered}" 2>/dev/null || true
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
        done < "${ordered}"
        rm -f "${ordered}" 2>/dev/null || true
        return 0
    fi

    # Modo aplicação: remove apenas os mais antigos, até o limite, com
    # validação individual OBRIGATÓRIA antes da exclusão.
    local count=0 vsize vfile
    while IFS= read -r vfile; do
        [ -n "${vfile}" ] || continue
        count=$((count + 1))
        if [ "${count}" -gt "${to_remove}" ]; then
            break
        fi
        if ! gzip -t "${vfile}" 2>>"${LOG_FILE}"; then
            bk_log_err "Retenção: candidato ${vfile} FALHOU em gzip -t — NÃO será removido; retenção marcada como FALHA."
            validated_ok=0
            continue
        fi
        vsize="$(stat -c '%s' "${vfile}" 2>/dev/null || stat -f '%z' "${vfile}" 2>/dev/null || echo '')"
        if [ -z "${vsize}" ] || [ "${vsize}" -lt "${min_bytes}" ]; then
            bk_log_err "Retenção: candidato ${vfile} abaixo do mínimo (${vsize:-?} < ${min_bytes}) — NÃO será removido; retenção marcada como FALHA."
            validated_ok=0
            continue
        fi
        if ! rm -f -- "${vfile}" 2>>"${LOG_FILE}"; then
            bk_log_err "Falha ao remover backup antigo VALIDADO: ${vfile}"
            validated_ok=0
            continue
        fi
        removed=$((removed + 1))
    done < "${ordered}"
    bk_log "Retenção aplicada: ${removed} backup(s) antigo(s) removido(s) de ${dir}."

    rm -f "${ordered}" 2>/dev/null || true
    if [ "${validated_ok}" -ne 1 ]; then
        bk_log_err "Retenção concluída COM FALHAS em ${dir} (nenhum arquivo inválido foi removido; nenhum backup válido foi afetado)."
        return "${BK_EXIT_RETENTION_FAIL}"
    fi
    return 0
}
