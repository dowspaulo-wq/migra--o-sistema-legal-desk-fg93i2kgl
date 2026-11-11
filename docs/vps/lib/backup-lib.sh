#!/usr/bin/env bash
# ==============================================================================
# DPSjur / SBJur — Biblioteca compartilhada das rotinas de backup dos DOIS
# PostgreSQL da VPS Hostinger (EasyPanel/Docker).
# Script: docs/vps/lib/backup-lib.sh
# Versão: v2.1.1
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
# CORREÇÕES DA AUDITORIA INDEPENDENTE (f17a6b4 / v2.0.0 → v2.1.0):
#   H. Lock flock REUTILIZÁVEL: o arquivo de lock deixou de ser critério de
#      exclusão (noclobber puro impedia execuções futuras com o arquivo
#      remanescente no disco). O FD é aberto em MODO APPEND (nunca trunca um
#      lock alheio) e a exclusividade vem do flock; o arquivo que permanece no
#      disco é REUTILIZADO na execução seguinte. Fallback mkdir com recuperação
#      de lock obsoleto (stale) APENAS quando o PID registrado não existe mais
#      (kill -0), com quarentena por mv atômico antes da remoção.
#   I. bk_resolve_swarm_container retorna SOMENTE o ID do contêiner no stdout
#      (logs/diagnósticos vão para stderr); o cruzamento entre
#      `docker service ps` e `docker ps` é feito por ID (o nome de tarefa em
#      service ps inclui sufixo, ex. <servico>.1.<id>) e a resolução é
#      reprovada por docker ps --filter id= — divergência é fatal.
#   J. Credenciais: caminho EXCLUSIVO por execução dentro do contêiner
#      (<prefixo>-<data>-<pid>-<aleatório>), chmod 600 VERIFICADO (não
#      tolerado), recusa de caminho preexistente e limpeza que remove SOMENTE
#      o caminho registrado nesta sessão; falha de preparação/limpeza é
#      comunicada (stderr + log) e sinalizada ao trap do chamador.
#   K. pg_dump: opção -X REMOVIDA (pg_dump -X é mecanismo obsoleto que EXIGE um
#      nome de opção como argumento — "-X -p" consumia o -p e abortaria com
#      "invalid -X option"). psql mantém -X (= --no-psqlrc, válido e igual em
#      PG15 e PG18). Escolha conservadora documentada junto a cada comando.
#   L. bk_publish_dump: mv -n com prova posterior (distingue recusa de corrida
#      TOCTOU de publicação bem-sucedida); chmod 600 do arquivo publicado é
#      VERIFICADO e FATAL em falha — nenhum "chmod ... || true".
#
# CORREÇÕES DA AUDITORIA INDEPENDENTE (1f36a02 / v2.1.0 → v2.1.1):
#   M. bk_verify_container aceita o IDENTIFICADOR propagado pelo chamador (ID
#      OU nome), comprovado por IGUALDADE EXATA contra a coluna ID ou a coluna
#      Names de `docker ps`. O Banco B chega com o ID retornado por
#      bk_resolve_swarm_container (que NUNCA é um nome) — a comparação antiga
#      (ID × nomes) nunca casava e abortaria toda execução do Banco B. Mais de
#      uma correspondência é fatal; sem regex genérica.
#   N. bk_finalize_session NÃO lê mais $? — no trap EXIT, $? já foi poluído
#      pelas operações de limpeza que precedem a chamada (podia registrar
#      SUCESSO com falha anterior). O código original é capturado no INÍCIO do
#      cleanup e transmitido EXPLICITAMENTE por argumentos, com flag dedicada
#      de falha de limpeza; SUCESSO exige código original 0 E limpeza integral;
#      falha de limpeza é comunicada em stderr/log sem ocultar nem substituir
#      o erro original; o script sai com o código ORIGINAL (ou com
#      BK_EXIT_CLEANUP_FAIL quando o backup concluiu mas a limpeza falhou).
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
BK_EXIT_CLEANUP_FAIL=29  # backup concluiu (exit original 0) mas a LIMPEZA da sessão falhou

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
    # O PGPASSFILE interno é registrado por bk_stage_pgpass_into_container
    # (caminho exclusivo desta sessão). Consulta sem ele é recusada — nunca
    # cair num caminho padrão genérico.
    if [ -z "${BK_PGPASS_IN_CONTAINER:-}" ]; then
        bk_die "PGPASSFILE interno não registrado — bk_stage_pgpass_into_container deve executar ANTES de qualquer consulta psql." "${BK_EXIT_CONFIG_FAIL}"
    fi
    # -X do psql = --no-psqlrc (não ler .psqlrc): mesma semântica em PG15 e PG18.
    # Demais opções (-A -t -q -p -U -d -c) são estáveis nas duas versões.
    if ! out="$(docker exec "${container}" env PGPASSFILE="${BK_PGPASS_IN_CONTAINER}" \
            "${bin_prefix}psql" -X -A -t -q -p "${pg_port}" -U "${pg_user}" -d "${pg_db}" -c "${sql}" \
            2>>"${LOG_FILE}")"; then
        return 1
    fi
    printf '%s' "${out}"
    return 0
}

# ------------------------------------------------------------------------------
# bk_resolve_swarm_container — identificação DETERMINÍSTICA do contêiner que
# executa o serviço Docker Swarm esperado. Resolve EXCLUSIVAMENTE o serviço
# informado (igualdade exata, sem nome literal de contêiner e sem regex
# genérica) e cruza `docker service ps` × `docker ps`:
#   - o nome de tarefa em `docker service ps` inclui sufixo de tarefa
#     (<servico>.<slot>.<id-tarefa>, ex. dpsjur_dpsjur-db.1.abc123...);
#   - o contêiner local correspondente é encontrado pelo ID (o ID da tarefa
#     Swarm é o mesmo do contêiner — o ID curto do docker ps é prefixo dele)
#     ou, alternativamente, pelo nome EXATO do contêiner;
#   - o resultado é REPROVADO com `docker ps --filter id=<id>` (igualdade
#     exata) antes de ser retornado.
#
# Parâmetros: <servico_swarm>   ex.: dpsjur_dpsjur-db
# Saída (stdout): SOMENTE o ID do contêiner (uma linha). Logs e diagnósticos
# vão para STDERR — nada além do identificador é escrito no stdout.
# Ausência, ambiguidade (mais de um contêiner Running elegível no nó) ou
# divergência entre service ps e docker ps é FATAL (exit 13): o script NÃO
# adivinha qual réplica usar e NUNCA seleciona outro PostgreSQL.
# ------------------------------------------------------------------------------
bk_resolve_swarm_container() {
    local service="$1"
    local task_names local_list filtered unique count container_id confirmed

    # (1) comando docker + nó manager do Swarm acessível (prova real de acesso)
    if ! docker info >/dev/null 2>&1; then
        bk_die "Docker daemon inacessível — impossível resolver serviço Swarm '${service}'." "${BK_EXIT_GUARD}"
    fi
    if ! docker service ls --format '{{.Name}}' 2>/dev/null | grep -Fx -- "${service}" >/dev/null; then
        bk_die "Serviço Swarm NÃO encontrado por igualdade exata: '${service}'. O nó pode não ser manager (docker service exige), o serviço pode ter mudado de nome ou o Swarm está indisponível — CONFIRMAR com Douglas antes de qualquer alteração." "${BK_EXIT_GUARD}"
    fi
    printf 'bk_resolve_swarm_container: serviço Swarm confirmado por igualdade exata: %s\n' "${service}" >&2

    # (2) nomes de tarefa do serviço, APENAS as com contêiner Running atual
    #     (formato oficial de tarefa do Swarm: <servico>.<slot>.<id-tarefa>).
    #     Docker service ps só roda em manager; aqui o manager é obrigatório.
    if ! task_names="$(docker service ps --format '{{.Name}}' --filter "desired-state=running" -- "${service}" 2>/dev/null)"; then
        bk_die "Falha ao listar tarefas do serviço Swarm '${service}'." "${BK_EXIT_GUARD}"
    fi
    if [ -z "${task_names//[$'\t\r ']/}" ]; then
        bk_die "Nenhuma tarefa Running para o serviço '${service}' — recusando (sem adivinhação)." "${BK_EXIT_GUARD}"
    fi
    printf 'bk_resolve_swarm_container: tarefas Running do serviço: %s\n' "$(printf '%s' "${task_names}" | sed '/^$/d' | tr '\n' ' ')" >&2

    # (3) inventário dos contêineres locais em execução (ID + nome) — UMA
    #     chamada a docker ps, avaliada contra cada tarefa Running.
    if ! local_list="$(docker ps --format '{{.ID}}\t{{.Names}}' 2>/dev/null)"; then
        bk_die "Falha ao listar contêineres locais em execução (docker ps)." "${BK_EXIT_GUARD}"
    fi

    # (4) cruzamento service ps × docker ps, POR CONTÊINER: para cada tarefa
    #     Running, o contêiner local correspondente é
    #       (4a) o contêiner cujo NOME é exatamente o nome da tarefa, ou
    #       (4b) o contêiner cujo ID curto é PREFIXO do ID de tarefa no
    #            sufixo do nome (tarefa <servico>.<slot>.<id> — o ID do
    #            contêiner Swarm é o mesmo ID da tarefa).
    #     Só contêineres DESTE nó são elegíveis (service ps lista todos os nós).
    filtered=""
    local n cid task_id
    while IFS= read -r n; do
        [ -n "${n}" ] || continue
        cid="$(printf '%s\n' "${local_list}" | awk -F'\t' -v t="${n}" '$2 == t {print $1; exit}')"
        if [ -z "${cid}" ]; then
            task_id="${n##*.}"
            case "${task_id}" in
                ''|*[!0-9a-f]*) task_id="" ;;   # sufixo não é ID hexadecimal plausível
            esac
            if [ -n "${task_id}" ]; then
                cid="$(printf '%s\n' "${local_list}" | awk -F'\t' -v i="${task_id}" 'index(i, $1) == 1 {print $1; exit}')"
            fi
        fi
        if [ -n "${cid}" ]; then
            filtered="${filtered}${cid}"$'\n'
            printf 'bk_resolve_swarm_container: tarefa %s → contêiner local %s\n' "${n}" "${cid}" >&2
        else
            printf 'bk_resolve_swarm_container: tarefa %s sem contêiner correspondente NESTE nó (ignorada)\n' "${n}" >&2
        fi
    done <<EOF_TAREFAS
${task_names}
EOF_TAREFAS

    # (5) deduplica (tarefa pode aparecer duplicada em estados transitórios) e
    #     EXIGE exatamente UM contêiner local do serviço — ambiguidade é fatal.
    unique="$(printf '%s' "${filtered}" | sed '/^$/d' | sort -u)"
    if [ -z "${unique}" ]; then
        bk_die "Nenhum contêiner local elegível para o serviço '${service}' (nenhuma tarefa Running neste nó ou divergência service ps × docker ps). Recusando prosseguir — sem adivinhação e sem regex genérica." "${BK_EXIT_GUARD}"
    fi
    count="$(printf '%s\n' "${unique}" | grep -c . || true)"
    if [ "${count}" -ne 1 ]; then
        bk_die "Identificação do contêiner do serviço '${service}' AMBÍGUA neste nó (${count} contêineres Running elegíveis). Recusando prosseguir — sem adivinhação e sem regex genérica." "${BK_EXIT_GUARD}"
    fi
    container_id="${unique}"

    # (6) prova FINAL: o ID resolvido existe como contêiner local em execução
    #     (docker ps --filter id=, igualdade exata, UMA linha). Divergência
    #     entre docker service ps e docker ps aqui é fatal.
    confirmed="$(docker ps --format '{{.ID}}' --filter "id=${container_id}" 2>/dev/null | grep -Fx -- "${container_id}" || true)"
    if [ "${confirmed}" != "${container_id}" ]; then
        bk_die "Divergência entre 'docker service ps' e 'docker ps': contêiner resolvido (${container_id}) do serviço '${service}' NÃO confirmado em execução neste nó. Recusando." "${BK_EXIT_GUARD}"
    fi

    printf 'bk_resolve_swarm_container: %s → exatamente 1 contêiner elegível neste nó: %s\n' "${service}" "${container_id}" >&2
    printf '%s\n' "${container_id}"
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
#   container: IDENTIFICADOR do contêiner propagado pelo chamador — ID (Banco B,
#     saída de bk_resolve_swarm_container) OU nome exato (Banco A, contêiner
#     fixo); é comprovado por igualdade exata em `docker ps` (correção M);
#   pg_bin_prefix: "" (binário no PATH do contêiner) ou ex. "/usr/lib/postgresql/15/bin"
# ------------------------------------------------------------------------------
bk_verify_container() {
    local container="$1" pg_major_wanted="$2" db_wanted="$3" user_wanted="$4" pg_port="$5" pg_bin="$6"
   local ps_list matches match_count matched_id matched_name
   local major db_found user_found
 
   # (a) o IDENTIFICADOR recebido (ID ou nome — o chamador propaga SEMPRE a
   #     mesma forma que resolveu) casa com EXATAMENTE UM contêiner em
   #     execução: igualdade exata na coluna ID OU na coluna Names de
   #     `docker ps` — sem regex genérica, sem casamento parcial, sem
   #     adivinhação. Nenhuma correspondência é fatal; mais de uma também
   #     (correção M: o Banco B chega aqui com ID, não com nome).
   if ! ps_list="$(docker ps --format '{{.ID}}\t{{.Names}}' 2>/dev/null)"; then
       bk_die "Falha ao listar contêineres em execução (docker ps)." "${BK_EXIT_GUARD}"
   fi
   matches="$(printf '%s\n' "${ps_list}" | awk -F'\t' -v c="${container}" '$1 == c || $2 == c {print $1 "\t" $2}')"
   if [ -z "${matches}" ]; then
       bk_die "Contêiner NÃO encontrado em execução pelo identificador exato '${container}' (ID ou nome; igualdade exata, sem regex genérica)." "${BK_EXIT_GUARD}"
   fi
   match_count="$(printf '%s\n' "${matches}" | grep -c . || true)"
   if [ "${match_count}" -ne 1 ]; then
       bk_die "Identificador do contêiner AMBÍGUA: '${container}' casa com ${match_count} contêineres em execução (ID ou nome exato). Recusando prosseguir — sem adivinhação." "${BK_EXIT_GUARD}"
    fi
   matched_id="$(printf '%s\n' "${matches}" | awk -F'\t' '{print $1}')"
   matched_name="$(printf '%s\n' "${matches}" | awk -F'\t' '{print $2}')"
   bk_log "Contêiner comprovado em execução (igualdade exata): id=${matched_id} nome=${matched_name} (identificador recebido: ${container})"

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
#   2. gera um CAMINHO EXCLUSIVO desta execução dentro do contêiner
#      (<prefixo>-<data>-<pid>-<aleatório>) e RECUSA se ele já existir
#      (nenhum arquivo de credenciais preexistente é sobrescrito);
#   3. copia o arquivo para dentro do contêiner via `docker cp` (a senha não
#      aparece na linha de comando — só caminhos);
#   4. chmod 600 e chown do usuário da conexão DENTRO do contêiner, com o
#      chmod 600 VERIFICADO por stat (permissão errada é FATAL, não tolerada).
# Em caso de qualquer falha, remove o resíduo desta execução e aborta (exit 28).
#
# Parâmetros: <container> <host_pgpass> <container_pgpass_prefix> <container_user_owner>
#   container_pgpass_prefix: base do caminho interno (ex.: /tmp/.pgpass-bk-banco-b);
#   o sufixo exclusivo da sessão é acrescentado AQUI (nunca reutilizar o mesmo
#   caminho entre execuções).
# Define: BK_PGPASS_IN_CONTAINER (caminho interno desta sessão, usado por
# bk_psql_in_container, por bk_remove_pgpass e pelo comando pg_dump do chamador
# via `docker exec ... env PGPASSFILE=...`).
# NOTA (requisito B): docker exec NÃO herda PGPASSFILE do host; a instalação
# dentro do contêiner é obrigatória e o caminho interno deve ter chmod 600 e
# ser propriedade do usuário da conexão.
# ------------------------------------------------------------------------------
bk_stage_pgpass_into_container() {
    local container="$1" host_pgpass="$2" container_pgpass_prefix="$3" owner_user="$4"
    local container_pgpass unique_suffix nfields exists_rc perm_check

    # (1) validação estrutural do .pgpass do host (sem ecoar conteúdo)
    if [ ! -f "${host_pgpass}" ]; then
        bk_die "Arquivo .pgpass não encontrado no host: ${host_pgpass}. Crie-o com chmod 600 antes de rodar o backup (veja --help)." "${BK_EXIT_CONFIG_FAIL}"
    fi
    bk_verify_fs_file "${host_pgpass}" "PGPASSFILE do host"
    nfields="$(awk -F'[:\\\\]' '{print NF}' "${host_pgpass}" 2>>"${LOG_FILE}" | grep -vx '5' | head -n 1)"
    if [ -n "${nfields}" ]; then
        bk_die "${host_pgpass}: linha(s) sem exatamente 5 campos .pgpass (senha com ':' não escapada?). Corrigir ANTES de prosseguir." "${BK_EXIT_CONFIG_FAIL}"
    fi
    if grep -q ':$' "${host_pgpass}" 2>>"${LOG_FILE}"; then
        bk_die "${host_pgpass}: senha VAZIA encontrada — recusando (autenticação falharia). Corrigir antes de prosseguir." "${BK_EXIT_CONFIG_FAIL}"
    fi

    # (2) caminho EXCLUSIVO desta execução (data + PID + aleatório) — cada
    #     sessão usa seu próprio arquivo; nada de caminho compartilhado.
    unique_suffix="$(date +%Y%m%d-%H%M%S)-$$-${RANDOM}-${RANDOM}"
    container_pgpass="${container_pgpass_prefix}-${unique_suffix}"

    # (3) recusa caminho preexistente (nenhum arquivo alheio é sobrescrito).
    #     Código distinguido: 1 = não existe (segue); 0 = existe (fatal);
    #     outro = falha de verificação (fatal — sem tolerância silenciosa).
    exists_rc=0
    docker exec "${container}" sh -c "test -e '${container_pgpass}'" >/dev/null 2>&1 || exists_rc=$?
    case "${exists_rc}" in
        1) : ;;
        0) bk_die "Arquivo de credenciais JÁ EXISTE no contêiner ${container}: ${container_pgpass} — recusando sobrescrita (colisão de sufixo exclusivo não é tolerada)." "${BK_EXIT_CONFIG_FAIL}" ;;
        *) bk_die "Falha ao verificar preexistência do caminho de credenciais no contêiner ${container} (código ${exists_rc}): ${container_pgpass}." "${BK_EXIT_CONFIG_FAIL}" ;;
    esac

    # (4) copiar para dentro do contêiner via docker cp (só caminhos na argv)
    if ! docker cp "${host_pgpass}" "${container}:${container_pgpass}" >>"${LOG_FILE}" 2>&1; then
        bk_die "Falha ao copiar o .pgpass para dentro do contêiner ${container} (docker cp): ${container_pgpass}." "${BK_EXIT_CONFIG_FAIL}"
    fi
    if ! docker exec "${container}" sh -c "chmod 600 '${container_pgpass}' && chown '${owner_user}' '${container_pgpass}'" >>"${LOG_FILE}" 2>&1; then
        docker exec "${container}" sh -c "rm -f -- '${container_pgpass}'" >/dev/null 2>&1 || true
        bk_die "Falha ao ajustar chmod 600/chown do .pgpass interno em ${container} (dono: ${owner_user}): ${container_pgpass}." "${BK_EXIT_CONFIG_FAIL}"
    fi
    # (5) chmod 600 VERIFICADO dentro do contêiner — permissão diferente é
    #     FATAL (credencial exposta não é tolerada); resíduo é removido.
    perm_check="$(docker exec "${container}" sh -c "stat -c '%a' '${container_pgpass}'" 2>/dev/null || echo '')"
    if [ "${perm_check}" != "600" ]; then
        docker exec "${container}" sh -c "rm -f -- '${container_pgpass}'" >/dev/null 2>&1 || true
        bk_die "Permissão efetiva do .pgpass interno NÃO confirmada (obtida '${perm_check:-indeterminada}'; esperado 600) — resíduo removido: ${container}:${container_pgpass}." "${BK_EXIT_CONFIG_FAIL}"
    fi

    # (6) registrar o caminho desta sessão (bk_psql_in_container, pg_dump do
    #     chamador e bk_remove_pgpass usam EXATAMENTE este caminho)
    BK_PGPASS_IN_CONTAINER="${container_pgpass}"
    export BK_PGPASS_IN_CONTAINER
    bk_log "PGPASSFILE instalado dentro do contêiner ${container} em ${container_pgpass} (chmod 600 verificado, dono ${owner_user}); senha fora de argumento/log."
    return 0
}

# ------------------------------------------------------------------------------
# bk_remove_pgpass — remove o .pgpass interno do contêiner (sempre ao final da
# sessão, inclusive em falha — trap do chamador). Remove SOMENTE o caminho
# registrado nesta sessão (BK_PGPASS_IN_CONTAINER): caminho divergente é
# recusado (proteção contra apagar credenciais de outra execução). A verificação
# pós-remoção (test -e) prova que o arquivo saiu; falha é retornada ao chamador
# e comunicada em stderr+log — limpeza NUNCA é silenciosa.
# ------------------------------------------------------------------------------
bk_remove_pgpass() {
    local container="$1" container_pgpass="$2"
    if [ -z "${container}" ] || [ -z "${container_pgpass}" ]; then
        return 0   # nada foi instalado nesta sessão
    fi
    if [ "${container_pgpass}" != "${BK_PGPASS_IN_CONTAINER:-}" ]; then
        bk_log_err "bk_remove_pgpass: caminho solicitado (${container_pgpass}) NÃO é o registrado desta sessão (${BK_PGPASS_IN_CONTAINER:-vazio}) — NADA foi removido."
        return 1
    fi
    docker exec "${container}" sh -c "rm -f -- '${container_pgpass}'" >>"${LOG_FILE}" 2>&1 || true
    if docker exec "${container}" sh -c "test -e '${container_pgpass}'" >/dev/null 2>&1; then
        bk_log_err "bk_remove_pgpass: arquivo de credenciais AINDA PRESENTE após remoção no contêiner ${container}: ${container_pgpass} — remoção manual decidida por Douglas."
        return 1
    fi
    bk_log "PGPASSFILE interno removido do contêiner ${container}: ${container_pgpass}"
    BK_PGPASS_IN_CONTAINER=""
    export BK_PGPASS_IN_CONTAINER
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
        bk_die "Falha na publicação (mv -n) de ${tmp} → ${final}." "${BK_EXIT_FS_FAIL}"
    fi
    # Prova posterior OBRIGATÓRIA: GNU mv -n devolve 0 mesmo quando RECUSA
    # mover. Os dois casos são distinguidos AQUI (sem dependência de código de
    # retorno):
    #   - destino existe E temporário ainda existe → o mv -n recusou
    #     sobrescrever na corrida TOCTOU: backup preexistente PRESERVADO, erro;
    #   - destino existe e temporário sumiu → o destino é o próprio arquivo
    #     desta execução: publicação confirmada;
    #   - destino ausente → mv não publicou: erro.
    if [ -e "${final}" ] && [ -e "${tmp}" ]; then
        bk_die "Destino ${final} JÁ EXISTIA e o mv -n RECUSOU sobrescrever (corrida com outra publicação — condição TOCTOU). Backup preexistente PRESERVADO; o temporário desta sessão será removido pelo trap." "${BK_EXIT_FS_FAIL}"
    fi
    if [ ! -f "${final}" ] || [ -L "${final}" ] || [ -e "${tmp}" ]; then
        bk_die "Publicação NÃO confirmada (destino ausente, não é arquivo regular, ou temporário ainda presente): ${final}." "${BK_EXIT_FS_FAIL}"
    fi
    # Permissão do arquivo publicado é GARANTIA DE SEGURANÇA: falha de chmod é
    # FATAL (nada de "|| true") e a permissão efetiva é verificada por stat.
    if ! chmod 600 "${final}" 2>>"${LOG_FILE}"; then
        bk_die "Falha no chmod 600 do backup publicado — publicação ABORTADA: ${final}" "${BK_EXIT_FS_FAIL}"
    fi
    local perm
    perm="$(stat -c '%a' "${final}" 2>/dev/null || stat -f '%Lp' "${final}" 2>/dev/null || echo "")"
    if [ "${perm}" != "600" ]; then
        bk_die "Permissão efetiva do backup publicado inválida (obtida '${perm:-indeterminada}'; esperado 600): ${final}" "${BK_EXIT_FS_FAIL}"
    fi
    bk_log "Backup publicado ATOMICAMENTE (mv -n no mesmo filesystem; destino preexistente NUNCA sobrescrito): ${final}"
    bk_log "ATENÇÃO: integridade gzip ≠ consistência do dump ≠ restauração isolada validada — três verificações NÃO equivalentes (ver RUN-BACKUP-DUPLA-POSTGRES.md)."
    return 0
}

# ------------------------------------------------------------------------------
# bk_finalize_session — fecha a sessão com veredito explícito de SUCESSO/FALHA
# no log (Requisito 7). Sempre chamado no trap de EXIT.
#
# Parâmetros POSICIONAIS (correção N — NUNCA deduzir de $?; no trap EXIT o $?
# já foi poluído pelas operações de limpeza que precedem esta chamada):
#   $1 = código de saída ORIGINAL da sessão, capturado NO INÍCIO do cleanup
#        (antes de qualquer operação de limpeza);
#   $2 = 0 se TODA a limpeza concluiu; 1 se QUALQUER passo de limpeza falhou;
#   $3 = rótulo da sessão (ex.: "Banco A").
# Regras:
#   - SUCESSO só é registrado quando o código original é 0 E a limpeza inteira
#     concluiu (todas as etapas obrigatórias);
#   - falha de limpeza é comunicada em stderr+log SEM ocultar nem substituir o
#     erro original;
#   - o chamador decide o exit: código ORIGINAL preservado (ou
#     BK_EXIT_CLEANUP_FAIL quando o backup concluiu e só a limpeza falhou).
# ------------------------------------------------------------------------------
bk_finalize_session() {
   local exit_code="${1:-1}" cleanup_failed="${2:-1}" label="${3:-sessão}"
   # Defesa contra chamada SEM argumentos (correção N): sem código original
   # propagado, NUNCA presumir sucesso — trata como falha.
   if [ "$#" -lt 3 ]; then
       bk_log_err "bk_finalize_session chamado SEM os 3 argumentos obrigatórios (código original, flag de limpeza, rótulo) — tratado como FALHA (nada presumido)."
       exit_code=1
       cleanup_failed=1
   fi
   if [ "${exit_code}" -eq 0 ] && [ "${cleanup_failed}" -eq 0 ]; then
       printf '%s VEREDITO: SUCESSO — backup concluído, validado, publicado e limpeza integral (%s)\n' "$(date '+%F %T')" "${label}" >> "${LOG_FILE}"
   elif [ "${exit_code}" -ne 0 ]; then
       printf '%s VEREDITO: FALHA — backup NÃO concluído, nenhum backup anterior afetado (exit original %s PRESERVADO) (%s)\n' "$(date '+%F %T')" "${exit_code}" "${label}" >> "${LOG_FILE}"
       if [ "${cleanup_failed}" -ne 0 ]; then
           bk_log_err "bk_finalize_session: além do erro original (exit ${exit_code}), a LIMPEZA da sessão TAMBÉM falhou — ver linhas de limpeza acima (erro original NÃO é substituído)."
       fi
   else
       printf '%s VEREDITO: FALHA DE LIMPEZA — backup concluído e publicado, mas a limpeza da sessão falhou (exit %s); nenhuma etapa obrigatória omitida do veredito (%s)\n' "$(date '+%F %T')" "${BK_EXIT_CLEANUP_FAIL}" "${label}" >> "${LOG_FILE}"
       bk_log_err "bk_finalize_session: backup concluído, porém a limpeza falhou — veredito NÃO é SUCESSO (exit ${BK_EXIT_CLEANUP_FAIL})."
   fi
    # Libera o FD do flock se ainda estiver detido por este processo (o lock
    # mkdir é liberado por bk_release_lock acima, com prova de identidade).
    if [ -n "${BK_LOCK_FD:-}" ]; then
        eval "exec ${BK_LOCK_FD}>&-" 2>/dev/null || true
    fi
   return 0
}

# ------------------------------------------------------------------------------
# bk_acquire_lock — impede execução simultânea.
#   - Preferência: flock sobre descritor de arquivo (liberação automática no
#     fim do processo, inclusive em kill -9). O ARQUIVO de lock NÃO é critério
#     de exclusão — ele permanece no disco entre execuções e é REUTILIZADO
#     (aberto em modo APPEND: nunca trunca, mesmo que pertença a outra
#     execução). A exclusividade vem EXCLUSIVAMENTE do flock: duas execuções
#     simultâneas não conseguem o lock; após a liberação, a próxima execução
#     adquire normalmente, sem dependecer de remover o arquivo.
#   - Fallback: mkdir atômico com PID gravado. As variáveis BK_LOCK_KIND,
#     BK_LOCK_PATH, BK_LOCK_DIR e BK_LOCK_PID são definidas DURANTE a
#      aquisição (bk_release_lock só age quando elas existem e quando o PID
#     registrado é o próprio $$). Lock preexistente é considerado obsoleto
#     (stale) APENAS quando o PID registrado NÃO existe mais (kill -0); a
#     recuperação é feita com quarentena por mv atômico (nunca rm direto do
#     lock que pode ter sido re-adquirido) e nova tentativa de mkdir — se a
#     re-aquisição falhar, outra execução ganhou a corrida e este processo
#     recusa. NOTA: kill -0 prova existência do PID para processos do MESMO
#     usuário (as sessões de cron destes scripts são root) — checagem
#     documentada e validada neste ponto.
# Em caso de lock de outra execução VIVA: exit ${BK_EXIT_LOCK} SEM tocar nele.
# ------------------------------------------------------------------------------
bk_acquire_lock() {
    local lock_path="$1"
    local pid_atual=$$
    local lock_dir="${lock_path}.d"

    if command -v flock >/dev/null 2>&1; then
        # (1) garante o arquivo SEM truncar nada preexistente: cria com
        #     noclobber APENAS se não existir; se já existir (execução
        #     anterior), REUTILIZA o mesmo arquivo (nunca remove, nunca trunca).
        if [ ! -f "${lock_path}" ]; then
            if ! ( set -o noclobber; : > "${lock_path}" ) 2>>"${LOG_FILE}"; then
                # perdeu corrida de criação — o arquivo de outra execução
                # serve ao flock; NUNCA truncar nem recriar.
                bk_log "Lock já foi criado em corrida por outro processo: ${lock_path} — arquivo reutilizado (nada truncado)."
            fi
            chmod 600 "${lock_path}" 2>>"${LOG_FILE}" || bk_die "Falha no chmod 600 do lock: ${lock_path}" "${BK_EXIT_LOCK}"
        fi
        # (2) abre o FD em modo APPEND (`>>`): NUNCA trunca o conteúdo
        #     preexistente (prova de que lock alheio não é destruído).
        eval "exec 200>>\"${lock_path}\"" || bk_die "Falha ao abrir lock para flock (modo append, sem truncar): ${lock_path}" "${BK_EXIT_LOCK}"
        BK_LOCK_FD=200
        BK_LOCK_KIND="flock"
        BK_LOCK_PATH="${lock_path}"
        # (3) tenta o lock exclusivo; falha = outra execução DETÉM o lock.
        #     Arquivo remanescente no disco não é lock ativo — só o flock é.
        if ! flock -n 200; then
            bk_die "OUTRA execução em andamento (lock ativo): ${lock_path}. Abortando sem interferir." "${BK_EXIT_LOCK}"
        fi
        printf '%s\n' "${pid_atual}" >&200
        bk_log "Lock adquirido via flock (${lock_path}, PID ${pid_atual}; arquivo reutilizável, exclusividade garantida pelo flock)"
    else
        # Fallback: mkdir atômico (prova de ausência de lock preexistente).
        if ! mkdir "${lock_dir}" 2>>"${LOG_FILE}"; then
            # Lock existente: obsoleto (stale) SÓ se o PID registrado não
            # existe mais (kill -0). PID ausente/ilegível também é tratado
            # como stale (mkdir sem pid não protege ninguém), com quarentena.
            local other_pid=""
            if [ -f "${lock_dir}/pid" ]; then
                other_pid="$(cat "${lock_dir}/pid" 2>/dev/null | tr -d '[:space:]')"
            fi
            case "${other_pid}" in
                ''|*[!0-9]*) other_pid="" ;;
            esac
            if [ -n "${other_pid}" ] && kill -0 "${other_pid}" 2>/dev/null; then
                bk_die "OUTRA execução em andamento (lock mkdir ativo, PID registrado ${other_pid} VIVO): ${lock_dir}" "${BK_EXIT_LOCK}"
            fi
            # Recuperação segura de stale: o diretório de lock é movido para
            # quarentena EXCLUSIVA desta sessão (mv é atômico — não há janela
            # de diretório parcial) e removido DE LÁ; depois o lock é
            # re-adquirido por mkdir. Se o mkdir falhar, outra execução
            # recuperou/ganhou primeiro: recusar sem tocar no lock dela.
            local stale_dir="${lock_dir}.stale-$$-${RANDOM}"
            if ! mv -- "${lock_dir}" "${stale_dir}" 2>>"${LOG_FILE}"; then
                bk_die "Lock mkdir existe e NÃO pôde ser posto em quarentena (recuperação simultânea de stale em andamento?): ${lock_dir} — resolver manualmente." "${BK_EXIT_LOCK}"
            fi
            rm -rf -- "${stale_dir}" 2>>"${LOG_FILE}" || bk_log_err "Falha ao remover lock obsoleto em quarentena: ${stale_dir} (nenhum backup afetado)."
            if ! mkdir "${lock_dir}" 2>>"${LOG_FILE}"; then
                bk_die "Lock mkdir re-adquirido por outra execução durante a recuperação de stale: ${lock_dir}" "${BK_EXIT_LOCK}"
            fi
            bk_log "Lock mkdir obsoleto recuperado com segurança (PID registrado ${other_pid:-vazio} não existe mais): ${lock_dir}"
        fi
        # Define as variáveis de estado DURANTE a aquisição (antes de escrever
        # o PID), garantindo que bk_release_lock só age se a aquisição foi SÓ.
        BK_LOCK_KIND="mkdir"
        BK_LOCK_PATH="${lock_path}"
        BK_LOCK_DIR="${lock_dir}"
        BK_LOCK_PID="${pid_atual}"
        printf '%s\n' "${pid_atual}" > "${lock_dir}/pid" 2>>"${LOG_FILE}" || bk_die "Lock adquirido mas falha ao registrar PID — resolvendo manualmente (nenhuma alteração automática)." "${BK_EXIT_LOCK}"
        chmod 700 "${lock_dir}" 2>>"${LOG_FILE}" || bk_die "Falha no chmod 700 do diretório de lock: ${lock_dir}" "${BK_EXIT_LOCK}"
        bk_log "Lock adquirido via mkdir atômico (${lock_dir}, PID ${pid_atual})"
    fi
    return 0
}

# ------------------------------------------------------------------------------
# bk_release_lock — libera o lock desta execução.
#   - flock: o lock é liberado ao fechar o FD (bk_finalize_session no trap
#     EXIT; e o kernel libera também em kill -9). O ARQUIVO permanece no disco
#     de propósito: a próxima execução o reutiliza — removê-lo não é preciso
#     e seria a fonte do bug de reuso.
#   - mkdir: removido APENAS quando o lock desta sessão é mkdir, o diretório
#     é exatamente o desta sessão e o PID registrado DENTRO do lock é o
#     próprio $$. Se o PID divergir, o lock é de outra execução — NÃO tocar.
# Retorna 1 em falha de remoção (chamador/trap sinalizam).
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
    if ! rm -rf -- "${BK_LOCK_DIR}" 2>>"${LOG_FILE}"; then
        bk_log_err "Falha ao remover o diretório de lock desta execução: ${BK_LOCK_DIR} — resolver manualmente."
        return 1
    fi
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
