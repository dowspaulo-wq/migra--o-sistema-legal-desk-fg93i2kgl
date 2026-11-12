#!/usr/bin/env bash
# ==============================================================================
# DPSjur — VALIDAÇÃO DE RESTAURAÇÃO · PASSO 3
# Script: docs/vps/restore-validacao/03-validar-restauracao.sh
# Versão: v1.1.0
#
# FINALIDADE: validar o banco recém-restaurado no contêiner do PASSO 02
# (default: dpsjur-restore-final) e gravar log + resumo em ARQUIVO.
#
#   ./03-validar-restauracao.sh dpsjur-restore-final \
#       [--diagnostico caminho/do/diagnostico-backup-*.txt] \
#       [--out DIRETORIO_DE_SAIDA]
#
# O que é verificado (TUDO SOMENTE LEITURA — SELECT e catálogo; nenhum INSERT/
# UPDATE/DELETE/DDL; nenhum backup tocado; nenhuma VPS):
#   - versão do PostgreSQL do DESTINO (comparada com a origem, se o diagnóstico
#     do passo 01 for informado);
#   - lista e contagem de tabelas por schema (excluindo pg_* e
#     information_schema);
#   - contagem de registros por tabela (count(*) exato);
#   - sequências e seus valores atuais (pg_sequences);
#   - funções por schema (pg_proc, mesmo critério de exclusão);
#   - políticas RLS (pg_policies) + tabelas com RLS habilitado;
#   - extensões instaladas (pg_extension);
#   - papéis/roles presentes (pg_roles, com flags superuser/login);
#   - COMPARAÇÃO com o diagnóstico do passo 01 (--diagnostico): tabelas com
#     dados no dump (seção COPY) e extensões exigidas (CREATE EXTENSION)
#     que estejam AUSENTES no destino.
#
# CONEXÃO: docker exec DENTRO do próprio contêiner (psql -U supabase_admin).
# Primeiro tenta socket local (sem senha); se falhar, usa TCP 127.0.0.1 com
# .pgpass gravado dentro do contêiner a partir de SUPABASE_RESTORE_PG_PASSWORD
# (mesmo default do passo 02). Nada sai da máquina local; senha nunca vai ao log.
#
# SAÍDA: relatório completo em arquivo (validacao-restauracao-<container>-
# <data>.txt) + resumo no stdout. COPIAR O ARQUIVO E COLAR DE VOLTA NO CHAT —
# a restauração só sai de "PENDENTE DE VALIDAÇÃO" após a análise deste log.
#
# ⚠ NÃO VALIDADO: este script NÃO foi executado e NÃO passou por `bash -n` nem
# por ShellCheck — esta plataforma não tem Bash/Docker/PostgreSQL. Executar e
# validar no WSL2 de Douglas antes de confiar no resultado. Status permanece
# PENDENTE até o log real de execução ser analisado.
# ==============================================================================

set -o errexit
set -o nounset
set -o pipefail
umask 077

readonly SCRIPT_NAME="03-validar-restauracao.sh"
readonly SCRIPT_VERSION="v1.1.0"
readonly DEFAULT_CONTAINER="dpsjur-restore-final"
readonly PG_USER="supabase_admin"
readonly PG_DB="postgres"
readonly PG_PASSWORD="${SUPABASE_RESTORE_PG_PASSWORD:-restore-local-only-NAO-producao}"

# Schemas internos excluídos de TABELAS e FUNÇÕES (catálogo e infraestrutura
# do PostgreSQL; os schemas do Supabase — auth, storage, extensions — permanecem).
readonly SQL_EXCLUDE_SCHEMA="nspname NOT LIKE 'pg\_%' AND nspname <> 'information_schema'"
readonly SQL_EXCLUDE_TABLESCHEMA="schemaname NOT LIKE 'pg\_%' AND schemaname <> 'information_schema'"

usage() {
    printf 'Uso: %s NOME_DO_CONTAINER [--diagnostico ARQUIVO] [--out DIRETORIO]\n' "${SCRIPT_NAME}"
    printf '\nValidação SOMENTE LEITURA do banco restaurado (passo 02). Grava log + resumo em arquivo.\n'
    printf '  NOME_DO_CONTAINER  contêiner criado pelo passo 02 (default: %s)\n' "${DEFAULT_CONTAINER}"
    printf '  --diagnostico      relatório do passo 01 (diagnostico-backup-*.txt) — habilita comparação\n'
    printf '  --out DIRETORIO    onde gravar o relatório (padrão: mesmo diretório do diagnóstico, se informado)\n'
}

CONTAINER=""
DIAGNOSTICO=""
OUT_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --diagnostico) shift; DIAGNOSTICO="${1:?--diagnostico requer um arquivo}" ;;
        --out)         shift; OUT_DIR="${1:?--out requer um diretório}" ;;
        --help|-h)     usage; exit 0 ;;
        -*)            printf 'Argumento desconhecido: %s\n' "$1" >&2; usage >&2; exit 64 ;;
        *)
            if [ -z "${CONTAINER}" ]; then
                CONTAINER="$1"
            else
                printf 'Argumento inesperado: %s\n' "$1" >&2; usage >&2; exit 64
            fi
            ;;
    esac
    shift
done

if [ -z "${CONTAINER}" ]; then
    CONTAINER="${DEFAULT_CONTAINER}"
fi
if [ -z "${OUT_DIR}" ] && [ -n "${DIAGNOSTICO}" ]; then
    OUT_DIR="$(dirname "${DIAGNOSTICO}")"
fi
if [ -z "${OUT_DIR}" ]; then
    OUT_DIR="${TMPDIR:-/tmp}/dpsjur-restore-validacao"
fi
mkdir -p "${OUT_DIR}"

STAMP="$(date +%Y-%m-%d_%H%M%S)"
REPORT="${OUT_DIR}/validacao-restauracao-${CONTAINER}-${STAMP}.txt"
TLIST="${OUT_DIR}/.tabelas-${CONTAINER}-${STAMP}.tmp"

# ------------------------------------------------------------------------------
# Pré-requisitos
# ------------------------------------------------------------------------------

command -v docker >/dev/null 2>&1 || { printf 'ERRO: comando obrigatório ausente: docker\n' >&2; exit 69; }

if ! docker ps --format '{{.Names}}' | grep -Fxq "${CONTAINER}"; then
    if docker ps -a --format '{{.Names}}' | grep -Fxq "${CONTAINER}"; then
        printf 'ERRO: o contêiner "%s" existe mas NÃO está em execução.\n' "${CONTAINER}" >&2
        printf 'Inicie-o primeiro (docker start %s) e rode novamente.\n' "${CONTAINER}" >&2
    else
        printf 'ERRO: contêiner não encontrado: "%s".\n' "${CONTAINER}" >&2
        printf 'O passo 02 (02-restaurar-limpo.sh) cria o contêiner; default dele: %s.\n' "${DEFAULT_CONTAINER}" >&2
    fi
    exit 66
fi

if [ -n "${DIAGNOSTICO}" ] && [ ! -f "${DIAGNOSTICO}" ]; then
    printf 'ERRO: arquivo de diagnóstico não encontrado: %s\n' "${DIAGNOSTICO}" >&2
    exit 66
fi

# ------------------------------------------------------------------------------
# Conexão — apenas DENTRO do contêiner. Socket primeiro; TCP+pgpass como plano B.
# ------------------------------------------------------------------------------

printf 'Testando conexão ao PostgreSQL do contêiner "%s"...\n' "${CONTAINER}"

CONN_MODE=""
if docker exec "${CONTAINER}" psql -U "${PG_USER}" -d "${PG_DB}" -tAc 'SELECT 1' >/dev/null 2>&1; then
    CONN_MODE="socket"
else
    # Plano B: TCP 127.0.0.1 interno com .pgpass gravado por stdin (sem eco no log)
    docker exec -i "${CONTAINER}" bash -c 'cat > /tmp/.pgpass-validacao && chmod 600 /tmp/.pgpass-validacao' <<PGPASS
127.0.0.1:5432:*:${PG_USER}:${PG_PASSWORD}
PGPASS
    if docker exec "${CONTAINER}" bash -c \
        'PGPASSFILE=/tmp/.pgpass-validacao psql -h 127.0.0.1 -p 5432 -U '"${PG_USER}"' -d '"${PG_DB}"' -tAc "SELECT 1"' \
        >/dev/null 2>&1; then
        CONN_MODE="tcp"
    else
        printf 'ERRO: não foi possível conectar como %s ao banco %s no contêiner "%s"\n' "${PG_USER}" "${PG_DB}" "${CONTAINER}" >&2
        printf '(nem via socket, nem via TCP). Confirme que o passo 02 criou este contêiner\n' >&2
        printf 'e que a senha coincide (variável SUPABASE_RESTORE_PG_PASSWORD).\n' >&2
        docker exec "${CONTAINER}" rm -f /tmp/.pgpass-validacao >/dev/null 2>&1 || true
        exit 70
    fi
fi
printf 'Conexão OK (modo: %s).\n' "${CONN_MODE}"

psql_dest() {
    # $1 = SQL. Executa SOMENTE LEITURA no destino, saída em linhas -At.
    if [ "${CONN_MODE}" = "socket" ]; then
        docker exec "${CONTAINER}" psql -U "${PG_USER}" -d "${PG_DB}" -At -v ON_ERROR_STOP=1 -c "$1"
    else
        docker exec "${CONTAINER}" bash -c \
            "PGPASSFILE=/tmp/.pgpass-validacao psql -h 127.0.0.1 -p 5432 -U ${PG_USER} -d ${PG_DB} -At -v ON_ERROR_STOP=1 -c \"\$0\"" "$1"
    fi
}

psql_dest_multiline() {
    # SQL via stdin (para queries longas/legíveis). Saída -At.
    if [ "${CONN_MODE}" = "socket" ]; then
        docker exec -i "${CONTAINER}" psql -U "${PG_USER}" -d "${PG_DB}" -At -v ON_ERROR_STOP=1
    else
        docker exec -i "${CONTAINER}" bash -c \
            "PGPASSFILE=/tmp/.pgpass-validacao psql -h 127.0.0.1 -p 5432 -U ${PG_USER} -d ${PG_DB} -At -v ON_ERROR_STOP=1"
    fi
}

# ------------------------------------------------------------------------------
# Coleta — TODO acesso abaixo é SELECT/catálogo (somente leitura).
# ------------------------------------------------------------------------------

# Falha de conexão no meio da coleta deve abortar com código claro (70).
guard_rc() {
    rc=$?
    if [ "${rc}" -ne 0 ]; then
        printf '\n[FALHA] consulta somente-leitura falhou (código %s) — relatório parcial em: %s\n' "${rc}" "${REPORT}" >&2
        exit 70
    fi
}
trap guard_rc EXIT

ORIGEM_DUMP=""
if [ -n "${DIAGNOSTICO}" ]; then
    ORIGEM_DUMP="$(grep -E '^-- Dumped from database version' "${DIAGNOSTICO}" | head -1 || true)"
fi

# Lista de tabelas do destino (usada na listagem e na contagem de registros).
psql_dest_multiline > "${TLIST}" <<SQL
SELECT schemaname || '.' || tablename
FROM pg_tables
WHERE ${SQL_EXCLUDE_TABLESCHEMA}
ORDER BY schemaname, tablename;
SQL

TOTAL_TABELAS="$(wc -l < "${TLIST}" | tr -d ' ')"
DEST_VERSION="$(psql_dest 'SHOW server_version;')"

{
    printf '=================================================================\n'
    printf 'RELATÓRIO DE VALIDAÇÃO DA RESTAURAÇÃO (somente leitura)\n'
    printf 'Script     : %s %s\n' "${SCRIPT_NAME}" "${SCRIPT_VERSION}"
    printf 'Gerado em  : %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'Contêiner  : %s (imagem do passo 02)\n' "${CONTAINER}"
    printf 'Conexão    : %s (dentro do contêiner, usuário %s, banco %s)\n' "${CONN_MODE}" "${PG_USER}" "${PG_DB}"
    printf 'Diagnóstico: %s\n' "${DIAGNOSTICO:-não informado (comparação pulada)}"
    printf '=================================================================\n'
    printf '\n'

    # -- Versão do PostgreSQL do destino -----------------------------------------
    printf -- '--- Versão do PostgreSQL (destino) ----------------------------------\n'
    printf 'server_version : %s\n' "${DEST_VERSION}"
    printf 'full version   : %s\n' "$(psql_dest 'SELECT version();')"
    if [ -n "${ORIGEM_DUMP}" ]; then
        printf 'origem (dump)  : %s\n' "${ORIGEM_DUMP#-- Dumped from database version }"
        printf '>> Compare as versões: destino %s vs origem acima.\n' "${DEST_VERSION}"
    fi
    printf '\n'

    # -- Schemas ------------------------------------------------------------------
    printf -- '--- Schemas (exceto pg_* e information_schema) ----------------------\n'
    psql_dest_multiline <<'SQL'
SELECT nspname || ' | ' || pg_get_userbyid(nspowner)
FROM pg_namespace
WHERE nspname NOT LIKE 'pg\_%' AND nspname <> 'information_schema'
ORDER BY nspname;
SQL
    printf '\n'

    # -- Tabelas por schema ---------------------------------------------------------
    printf -- '--- Tabelas por schema (contagem) -----------------------------------\n'
    psql_dest_multiline <<SQL
SELECT schemaname || ' | ' || count(*)
FROM pg_tables
WHERE ${SQL_EXCLUDE_TABLESCHEMA}
GROUP BY schemaname
ORDER BY schemaname;
SQL
    printf 'TOTAL de tabelas (exceto schemas internos): %s\n' "${TOTAL_TABELAS}"
    printf '\n'

    # -- Lista de tabelas -----------------------------------------------------------
    printf -- '--- Lista de tabelas (schema.tabela) --------------------------------\n'
    cat "${TLIST}"
    printf '\n'

    # -- Contagem de registros por tabela (count(*) exato) ---------------------------
    printf -- '--- Registros por tabela (count(*) exato) ---------------------------\n'
    printf 'schema.tabela | registros\n'
    # Loop SEM pipeline (o pipe criaria subshell); leitura do arquivo temporário.
    while IFS= read -r QUALIFIED_NAME; do
        [ -z "${QUALIFIED_NAME}" ] && continue
        ROWS="$(psql_dest "SELECT count(*) FROM ${QUALIFIED_NAME};")"
        printf '%s | %s\n' "${QUALIFIED_NAME}" "${ROWS}"
    done < "${TLIST}"
    printf '\n'

    # -- Sequências e valores --------------------------------------------------------
    printf -- '--- Sequências e valores atuais (pg_sequences) ----------------------\n'
    printf 'schema.sequência | último valor\n'
    psql_dest_multiline <<SQL
SELECT schemaname || '.' || sequencename || ' | ' || COALESCE(last_value::text, '(sem valor)')
FROM pg_sequences
WHERE ${SQL_EXCLUDE_TABLESCHEMA}
ORDER BY schemaname, sequencename;
SQL
    printf '\n'

    # -- Funções por schema ------------------------------------------------------------
    printf -- '--- Funções por schema (contagem) -----------------------------------\n'
    psql_dest_multiline <<SQL
SELECT n.nspname || ' | ' || count(*)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE ${SQL_EXCLUDE_SCHEMA}
GROUP BY n.nspname
ORDER BY n.nspname;
SQL
    printf 'TOTAL de funções: %s\n' "$(psql_dest "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE ${SQL_EXCLUDE_SCHEMA};")"
    printf '\n'
    printf '--- Lista de funções (schema.função) ---------------------------------\n'
    psql_dest_multiline <<SQL
SELECT n.nspname || '.' || p.proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE ${SQL_EXCLUDE_SCHEMA}
ORDER BY n.nspname, p.proname;
SQL
    printf '\n'

    # -- RLS: políticas e tabelas com RLS habilitado --------------------------------------
    printf -- '--- Políticas RLS (pg_policies) --------------------------------------\n'
    printf 'schema.tabela | política | comando | papéis\n'
    psql_dest_multiline <<'SQL'
SELECT schemaname || '.' || tablename || ' | ' || policyname || ' | ' || cmd || ' | ' || COALESCE(roles::text, '-')
FROM pg_policies
ORDER BY schemaname, tablename, policyname;
SQL
    printf 'TOTAL de políticas: %s\n' "$(psql_dest 'SELECT count(*) FROM pg_policies;')"
    printf '\n'
    printf '--- Tabelas com RLS HABILITADO (relrowsecurity) ----------------------\n'
    psql_dest_multiline <<SQL
SELECT n.nspname || '.' || c.relname || ' | forçado=' || c.relforcerowsecurity::text
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relrowsecurity = true AND ${SQL_EXCLUDE_SCHEMA} AND c.relkind IN ('r','p')
ORDER BY n.nspname, c.relname;
SQL
    printf '\n'

    # -- Extensões ------------------------------------------------------------------------
    printf -- '--- Extensões instaladas (pg_extension) ------------------------------\n'
    printf 'extensão | versão | schema\n'
    psql_dest_multiline <<'SQL'
SELECT extname || ' | ' || extversion || ' | ' || n.nspname
FROM pg_extension e
JOIN pg_namespace n ON n.oid = e.extnamespace
ORDER BY extname;
SQL
    printf '\n'

    # -- Papéis / roles -----------------------------------------------------------------------
    printf -- '--- Papéis (pg_roles) -------------------------------------------------\n'
    printf 'papel | superuser | login | replicação\n'
    psql_dest_multiline <<'SQL'
SELECT rolname || ' | ' || rolsuper::text || ' | ' || rolcanlogin::text || ' | ' || rolreplication::text
FROM pg_roles
ORDER BY rolname;
SQL
    printf '\n'

    # -- Comparação com o diagnóstico do passo 01 ------------------------------------------------
    if [ -n "${DIAGNOSTICO}" ]; then
        printf -- '--- Comparação com o diagnóstico do passo 01 -------------------------\n'
        printf 'Arquivo: %s\n\n' "${DIAGNOSTICO}"

        # Tabelas com dados no dump: seção "--- COPY (tabelas com dados) ---" do
        # relatório do 01 (linhas no formato "N schema.tabela" do uniq -c).
        DUMP_TABLES="$(grep -hE '^[[:space:]]*[0-9]+ [A-Za-z_"][^ ]*[A-Za-z0-9_]$' "${DIAGNOSTICO}" \
            | sed -E 's/^[[:space:]]*[0-9]+[[:space:]]+//; s/"//g' \
            | sort -u || true)"

        if [ -z "${DUMP_TABLES}" ]; then
            printf 'ATENÇÃO: nenhuma tabela extraída da seção COPY do diagnóstico\n'
            printf '(formato inesperado do relatório do passo 01?). Comparação de tabelas pulada.\n'
        else
            MISSING=0
            while IFS= read -r OBJ; do
                [ -z "${OBJ}" ] && continue
                # Consulta assepticamente: identificador via to_regclass('...') com
                # aspas simples do literal preservadas (objeto só tem [A-Za-z0-9_."]).
                EXISTS="$(psql_dest "SELECT to_regclass('${OBJ}') IS NOT NULL;" || true)"
                if [ "${EXISTS}" != "t" ]; then
                    printf 'AUSENTE NO DESTINO: %s\n' "${OBJ}"
                    MISSING=$((MISSING + 1))
                fi
            done <<EOF
${DUMP_TABLES}
EOF
            if [ "${MISSING}" -eq 0 ]; then
                printf 'OK: TODAS as tabelas com dados (COPY) no dump existem no destino.\n'
            else
                printf '>> %s tabela(s) do dump NÃO existem no destino — investigar antes de validar.\n' "${MISSING}"
            fi
        fi
        printf '\n'

        # Extensões exigidas pelo dump (linhas CREATE EXTENSION do relatório do 01)
        # conferidas contra pg_extension do destino.
        printf -- '--- Extensões exigidas pelo dump vs instaladas -----------------------\n'
        DUMP_EXTENSIONS="$(grep -hE '^CREATE EXTENSION' "${DIAGNOSTICO}" \
            | sed -E 's/^CREATE EXTENSION (IF NOT EXISTS )?[\"'"'"']?//; s/[\"'"'"'].*$//; s/;.*$//' \
            | awk '{print $1}' | sort -u || true)"
        if [ -z "${DUMP_EXTENSIONS}" ]; then
            printf '(nenhuma extensão listada no diagnóstico)\n'
        else
            while IFS= read -r EXT; do
                [ -z "${EXT}" ] && continue
                INSTALLED="$(psql_dest "SELECT count(*) FROM pg_extension WHERE extname = '${EXT}';")"
                if [ "${INSTALLED}" = "0" ]; then
                    printf 'AUSENTE NO DESTINO: extensão %s (exigida pelo dump)\n' "${EXT}"
                else
                    printf 'OK: extensão %s instalada no destino.\n' "${EXT}"
                fi
            done <<EOF
${DUMP_EXTENSIONS}
EOF
        fi
        printf '\n'

        DUMP_CREATE_TABLES_PRESENT="$(grep -E '^CREATE TABLE ' "${DIAGNOSTICO}" | head -1 || true)"
        if [ -n "${DUMP_CREATE_TABLES_PRESENT}" ]; then
            printf 'Resumo: CREATE TABLE no dump (aprox.): %s | tabelas no destino: %s\n' \
                "$(grep -cE '^CREATE TABLE ' "${DIAGNOSTICO}" || true)" "${TOTAL_TABELAS}"
            printf '>> Diferença esperada: o destino inclui tabelas dos schemas internos do\n'
            printf '>> Supabase que o dump não recria. O que importa é a lista AUSENTE acima.\n'
        fi
    else
        printf -- '--- Comparação com o diagnóstico do passo 01 -------------------------\n'
        printf 'PULADA: nenhum arquivo de diagnóstico informado (--diagnostico).\n'
    fi

    printf '\n'
    printf '=================================================================\n'
    printf 'Fim do relatório. Status da restauração: CONTINUA "PENDENTE DE\n'
    printf 'VALIDAÇÃO" até este log ser analisado na conversa.\n'
    printf '=================================================================\n'
} > "${REPORT}"

trap - EXIT

# Higiene: arquivo temporário de tabelas e .pgpass de validação dentro do contêiner
rm -f "${TLIST}"
if [ "${CONN_MODE}" = "tcp" ]; then
    docker exec "${CONTAINER}" rm -f /tmp/.pgpass-validacao >/dev/null 2>&1 || true
fi

printf '\nRelatório gravado em: %s\n' "${REPORT}"
printf 'COPIE O CONTEÚDO DESTE ARQUIVO E COLE DE VOLTA NO CHAT para análise.\n'
printf 'Nada foi modificado no banco (somente leitura) e nenhum backup foi tocado.\n'
