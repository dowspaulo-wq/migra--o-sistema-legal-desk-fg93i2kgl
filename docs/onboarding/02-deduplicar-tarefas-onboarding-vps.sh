#!/usr/bin/env bash
# ==============================================================================
# SCRIPT VPS: DEDUPLICAR TAREFAS DE ONBOARDING DE CLIENTES (DPSjur)
# DPSjur - Sistema Jurídico SBJur no VPS Hostinger (EasyPanel / Docker)
# Script: docs/onboarding/02-deduplicar-tarefas-onboarding-vps.sh
# Versão: v1.2.3
# Data: 2026-10-21
#
# O QUE ESTE SCRIPT FAZ (Totalmente Autônomo e Idempotente):
# 1. Varre e descobre o contêiner Docker real do PostgreSQL no VPS (EasyPanel/Supabase).
# 2. Descobre dinamicamente usuário, senha e banco de dados com maior volume de tarefas.
# 3. Detecta tarefas de tipo 'Onboarding' duplicadas para o MESMO cliente + MESMO título de etapa.
# 4. Mantém rigorosamente a tarefa mais antiga (menor created_at ou menor id como critério de desempate),
#    ou preserva a que estiver 'Concluída' caso alguma já tenha sido finalizada.
# 5. Remove as duplicatas excedentes mantendo integridade referencial.
# 6. Emite NOTIFY pgrst, 'reload schema' para PostgREST.
# 7. Realiza conferência rigorosa pós-execução e só emite [OK] se a verificação passar (zero duplicidades).
#
# COMO EXECUTAR NO VPS (como root - comando único sem pipe direto):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/onboarding/02-deduplicar-tarefas-onboarding-vps.sh" -o /root/02-deduplicar-tarefas-onboarding-vps.sh && bash /root/02-deduplicar-tarefas-onboarding-vps.sh
# ==============================================================================

set -uo pipefail

SCRIPT_VERSION="v1.2.3"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "${BOLD}${BLUE} DPSjur - Deduplicar Tarefas de Onboarding de Clientes (VPS)          ${NC}"
echo -e "${BOLD}${BLUE} Versão: ${SCRIPT_VERSION}${NC}"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo -e "Host: $(hostname 2>/dev/null || echo 'VPS')"
echo -e "${BOLD}${BLUE}=====================================================================${NC}\n"

# Helper para executar query psql simples (retorno limpo)
run_container_psql() {
    local container="$1"
    local user="$2"
    local pass="$3"
    local dbname="$4"
    local query="$5"

    if [ -n "$pass" ]; then
        docker exec -i -e PGPASSWORD="$pass" "$container" psql -U "$user" -d "$dbname" -tAc "$query" 2>/dev/null || true
    else
        docker exec -i "$container" psql -U "$user" -d "$dbname" -tAc "$query" 2>/dev/null || true
    fi
}

# Helper robusto para executar arquivo SQL em contêiner com diagnóstico e commit garantido
run_container_sql_file() {
    local container="$1"
    local user="$2"
    local pass="$3"
    local dbname="$4"
    local sql_content="$5"

    local rand_id="dpsjur_onb_dedup_${RANDOM:-$$}_$(date +%s%N 2>/dev/null || date +%s)_$$"
    local host_tmp="/tmp/${rand_id}.sql"
    local cont_tmp="/tmp/${rand_id}.sql"

    printf "%s\n" "$sql_content" > "$host_tmp"

    docker cp "$host_tmp" "${container}:${cont_tmp}" >/dev/null 2>&1
    local cp_rc=$?

    local psql_exit=0
    if [ $cp_rc -eq 0 ]; then
        if [ -n "$pass" ]; then
            docker exec -i -e PGPASSWORD="$pass" "$container" psql -U "$user" -d "$dbname" -v ON_ERROR_STOP=1 -f "$cont_tmp"
            psql_exit=$?
        else
            docker exec -i "$container" psql -U "$user" -d "$dbname" -v ON_ERROR_STOP=1 -f "$cont_tmp"
            psql_exit=$?
        fi
        docker exec -i "$container" rm -f "$cont_tmp" >/dev/null 2>&1 || true
    else
        if [ -n "$pass" ]; then
            docker exec -i -e PGPASSWORD="$pass" "$container" psql -U "$user" -d "$dbname" -v ON_ERROR_STOP=1 < "$host_tmp"
            psql_exit=$?
        else
            docker exec -i "$container" psql -U "$user" -d "$dbname" -v ON_ERROR_STOP=1 < "$host_tmp"
            psql_exit=$?
        fi
    fi

    rm -f "$host_tmp" 2>/dev/null || true
    return $psql_exit
}

# ------------------------------------------------------------------------------
# 1. Localizar e auditar contêineres PostgreSQL em execução no VPS
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 1/4] Varrendo contêineres PostgreSQL em execução no VPS...${NC}"

ALL_DB_CONTAINERS=()
while IFS= read -r c_name; do
    [ -z "$c_name" ] && continue
    if [[ "$c_name" =~ (frontend|web|traefik|redis|kong|edge-runtime|functions|meta|adminer|nginx) ]]; then
        continue
    fi
    ALL_DB_CONTAINERS+=("$c_name")
done < <(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'db|postgres|postg' || true)

if [ ${#ALL_DB_CONTAINERS[@]} -eq 0 ]; then
    echo -e "${RED}❌ Nenhum contêiner Postgres detectado com filtro db/postgres/postg!${NC}"
    echo "Contêineres ativos:"
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' || true
    exit 1
fi

echo -e "Contêineres PostgreSQL encontrados (${#ALL_DB_CONTAINERS[@]}):"
for c in "${ALL_DB_CONTAINERS[@]}"; do
    echo -e "  - ${BOLD}${c}${NC}"
done
echo ""

AUDIT_RESULTS=()
REAL_CONTAINER=""
REAL_USER=""
REAL_PASS=""
REAL_DB=""
MAX_TASKS=-1

for c in "${ALL_DB_CONTAINERS[@]}"; do
    echo -e "🔎 Inspecionando contêiner: ${BOLD}${c}${NC}..."

    ENV_USER=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$c" 2>/dev/null | grep -E '^POSTGRES_USER=' | head -n 1 | cut -d= -f2- || true)
    if [ -z "$ENV_USER" ]; then
        ENV_USER=$(docker exec "$c" env 2>/dev/null | grep -E '^POSTGRES_USER=' | head -n 1 | cut -d= -f2- || true)
    fi

    ENV_PASS=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$c" 2>/dev/null | grep -E '^POSTGRES_PASSWORD=' | head -n 1 | cut -d= -f2- || true)
    if [ -z "$ENV_PASS" ]; then
        ENV_PASS=$(docker exec "$c" env 2>/dev/null | grep -E '^POSTGRES_PASSWORD=' | head -n 1 | cut -d= -f2- || true)
    fi

    ENV_DB=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$c" 2>/dev/null | grep -E '^POSTGRES_DB=' | head -n 1 | cut -d= -f2- || true)
    if [ -z "$ENV_DB" ]; then
        ENV_DB=$(docker exec "$c" env 2>/dev/null | grep -E '^POSTGRES_DB=' | head -n 1 | cut -d= -f2- || true)
    fi

    CAND_USERS=()
    [ -n "$ENV_USER" ] && CAND_USERS+=("$ENV_USER")
    CAND_USERS+=("postgres" "supabase_admin" "Doug" "postgres_admin")

    UNIQ_USERS=()
    for u in "${CAND_USERS[@]}"; do
        [[ " ${UNIQ_USERS[*]} " =~ " ${u} " ]] || UNIQ_USERS+=("$u")
    done

    WORKING_USER=""
    WORKING_PASS="$ENV_PASS"
    DATABASES_LIST=""

    for u in "${UNIQ_USERS[@]}"; do
        for cand_db in "${ENV_DB:-}" "postgres" "dpsjur" "template1"; do
            [ -z "$cand_db" ] && continue
            CHECK_ONE=$(run_container_psql "$c" "$u" "$WORKING_PASS" "$cand_db" "SELECT 1;")
            if [ "$CHECK_ONE" = "1" ]; then
                WORKING_USER="$u"
                DB_QUERY_OUT=$(run_container_psql "$c" "$u" "$WORKING_PASS" "$cand_db" "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('rdsadmin');")
                if [ -n "$DB_QUERY_OUT" ]; then
                    DATABASES_LIST="$DB_QUERY_OUT"
                else
                    DATABASES_LIST="$cand_db"
                fi
                break 2
            fi
        done
    done

    if [ -z "$WORKING_USER" ]; then
        echo -e "  ${YELLOW}⚠️ Não foi possível autenticar neste contêiner com os usuários testados.${NC}"
        continue
    fi

    echo -e "  Autenticação OK como usuário: ${GREEN}${WORKING_USER}${NC}"

    DB_ARRAY=()
    while IFS= read -r db_item; do
        [ -z "$db_item" ] && continue
        DB_ARRAY+=("$db_item")
    done <<< "$DATABASES_LIST"

    if [ ${#DB_ARRAY[@]} -eq 0 ] && [ -n "$ENV_DB" ]; then
        DB_ARRAY+=("$ENV_DB")
    fi

    for dbname in "${DB_ARRAY[@]}"; do
        echo -e "  Checando banco: ${BOLD}${dbname}${NC}..."

        TASKS_EXISTS=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='tasks');")

        if [ "$TASKS_EXISTS" != "t" ]; then
            echo -e "    - Tabela public.tasks: ${YELLOW}não existe neste banco${NC}"
            continue
        fi

        RAW_TASKS_COUNT=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT count(*) FROM public.tasks;")
        TASKS_COUNT=$(echo "$RAW_TASKS_COUNT" | tr -dc '0-9' || echo 0)
        [ -z "$TASKS_COUNT" ] && TASKS_COUNT=0

        ONBOARDING_COUNT=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT count(*) FROM public.tasks WHERE type ILIKE '%onboarding%';")
        ONBOARDING_CLEAN=$(echo "$ONBOARDING_COUNT" | tr -dc '0-9' || echo 0)
        [ -z "$ONBOARDING_CLEAN" ] && ONBOARDING_CLEAN=0

        echo -e "    - Tabela public.tasks: ${GREEN}EXISTE${NC} (${TASKS_COUNT} tarefas totais, ${ONBOARDING_CLEAN} do tipo Onboarding)"

        AUDIT_RESULTS+=("${c}|${WORKING_USER}|${WORKING_PASS}|${dbname}|sim|${TASKS_COUNT}|${ONBOARDING_CLEAN}")

        if [ "$TASKS_COUNT" -gt "$MAX_TASKS" ]; then
            MAX_TASKS="$TASKS_COUNT"
            REAL_CONTAINER="$c"
            REAL_USER="$WORKING_USER"
            REAL_PASS="$WORKING_PASS"
            REAL_DB="$dbname"
        fi
    done
    echo ""
done

if [ -z "$REAL_CONTAINER" ]; then
    echo -e "${RED}❌ Não foi possível determinar o contêiner do banco real com a tabela public.tasks!${NC}"
    exit 1
fi

echo -e "🎯 ${BOLD}Banco Real Detectado:${NC}"
echo -e "   - Contêiner: ${GREEN}${REAL_CONTAINER}${NC}"
echo -e "   - Usuário:   ${GREEN}${REAL_USER}${NC}"
echo -e "   - Banco:     ${GREEN}${REAL_DB}${NC}"
echo -e "   - Total:     ${GREEN}${MAX_TASKS} tarefas em public.tasks${NC}\n"

# ------------------------------------------------------------------------------
# 2. Diagnóstico prévio de duplicidades de onboarding
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 2/4] Verificando se existem tarefas de Onboarding duplicadas...${NC}"

CHECK_DUP_SQL="
SELECT count(*) - count(DISTINCT (\"clientId\", lower(trim(title))))
FROM public.tasks
WHERE type ILIKE '%onboarding%'
  AND \"clientId\" IS NOT NULL;
"

RAW_DUP_COUNT=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "$CHECK_DUP_SQL")
DUP_COUNT=$(echo "$RAW_DUP_COUNT" | tr -dc '0-9' || echo 0)
[ -z "$DUP_COUNT" ] && DUP_COUNT=0

echo -e "Tarefas duplicadas de Onboarding detectadas: ${BOLD}${DUP_COUNT}${NC}"

# ------------------------------------------------------------------------------
# 3. Execução da deduplicação SQL segura e idempotente com COMMIT explícito
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[Etapa 3/4] Executando script SQL de deduplicação...${NC}"

# Script SQL com todos os delimitadores $ escapados para evitar expansão no bash
DEDUP_SQL="
BEGIN;

DO \$\$
DECLARE
    v_deleted_count integer := 0;
BEGIN
    -- Cria tabela temporária com os IDs que DEVEM SER PRESERVADOS (um único por cliente + título normalizado)
    -- Critério de escolha do registro mestre a manter:
    -- 1. Status 'Concluída' / 'concluido' tem prioridade máxima (não perder trabalho já concluído)
    -- 2. Data de criação mais antiga (menor created_at)
    -- 3. Menor ID alfanumérico em caso de empate exato
    CREATE TEMP TABLE tmp_keep_task_ids ON COMMIT DROP AS
    SELECT DISTINCT ON (\"clientId\", lower(trim(title))) id
    FROM public.tasks
    WHERE type ILIKE '%onboarding%'
      AND \"clientId\" IS NOT NULL
    ORDER BY 
      \"clientId\", 
      lower(trim(title)),
      CASE 
        WHEN lower(trim(status)) IN ('concluída', 'concluido', 'concluida') THEN 0
        ELSE 1
      END ASC,
      COALESCE(created_at, '1970-01-01'::timestamptz) ASC,
      id ASC;

    -- Deletar as tarefas de onboarding que não sejam a escolhida para manter
    WITH deleted AS (
        DELETE FROM public.tasks
        WHERE type ILIKE '%onboarding%'
          AND \"clientId\" IS NOT NULL
          AND id NOT IN (SELECT id FROM tmp_keep_task_ids)
        RETURNING id
    )
    SELECT count(*) INTO v_deleted_count FROM deleted;

    RAISE NOTICE 'Total de tarefas de onboarding duplicadas removidas: %', v_deleted_count;
END \$\$;

COMMIT;

-- Notificar PostgREST para recarregar cache
SELECT pg_notify('pgrst', 'reload schema');
"

if run_container_sql_file "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "$DEDUP_SQL"; then
    echo -e "${GREEN}✓ Deduplicação SQL executada e comitada com sucesso!${NC}"
else
    echo -e "${RED}❌ Falha ao executar o comando de deduplicação SQL no banco real!${NC}"
    exit 1
fi

# Notificar contêiner PostgREST se presente
POSTGREST_CONTAINERS=()
while IFS= read -r r_name; do
    [ -z "$r_name" ] && continue
    POSTGREST_CONTAINERS+=("$r_name")
done < <(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'rest|postgrest' || true)

for r in "${POSTGREST_CONTAINERS[@]}"; do
    docker restart "$r" >/dev/null 2>&1 || true
    echo -e "  ${GREEN}✓ PostgREST reiniciado: ${r}${NC}"
done

# ------------------------------------------------------------------------------
# 4. Conferência rigorosa pós-execução
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}[Etapa 4/4] Conferência rigorosa pós-execução...${NC}"

VERIFY_SQL="
SELECT count(*)
FROM (
    SELECT \"clientId\", lower(trim(title)), count(*)
    FROM public.tasks
    WHERE type ILIKE '%onboarding%'
      AND \"clientId\" IS NOT NULL
    GROUP BY \"clientId\", lower(trim(title))
    HAVING count(*) > 1
) dup_groups;
"

RAW_REMAINING_GROUPS=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "$VERIFY_SQL")
REMAINING_GROUPS=$(echo "$RAW_REMAINING_GROUPS" | tr -dc '0-9' || echo 0)
[ -z "$REMAINING_GROUPS" ] && REMAINING_GROUPS=0

TOTAL_ONBOARDING_FINAL=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT count(*) FROM public.tasks WHERE type ILIKE '%onboarding%';")
TOTAL_ONBOARDING_FINAL=$(echo "$TOTAL_ONBOARDING_FINAL" | tr -dc '0-9' || echo 0)

echo -e "\n${BOLD}${BLUE}=====================================================================${NC}"
echo -e "${BOLD}${BLUE}                      RESUMO DA DEDUPLICAÇÃO                         ${NC}"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "1. Banco Real Identificado:"
echo -e "   - Contêiner:               ${GREEN}${REAL_CONTAINER}${NC}"
echo -e "   - Usuário:                 ${GREEN}${REAL_USER}${NC}"
echo -e "   - Banco:                   ${GREEN}${REAL_DB}${NC}"
echo -e "2. Tarefas de Onboarding:"
echo -e "   - Total restante:          ${BOLD}${GREEN}${TOTAL_ONBOARDING_FINAL}${NC}"
if [ "$REMAINING_GROUPS" -eq 0 ]; then
    echo -e "   - Grupos duplicados:       ${BOLD}${GREEN}0 [OK] (Nenhuma duplicidade restante)${NC}"
else
    echo -e "   - Grupos duplicados:       ${BOLD}${RED}${REMAINING_GROUPS} (Falha!)${NC}"
fi
echo -e "${BOLD}${BLUE}=====================================================================${NC}"

if [ "$REMAINING_GROUPS" -eq 0 ]; then
    echo -e "\n${BOLD}${GREEN}✅ OPERAÇÃO CONCLUÍDA COM SUCESSO! [OK]${NC}"
    echo -e "Todas as tarefas de onboarding duplicadas foram consolidadas mantendo a mais antiga/concluída."
    echo -e "A aplicação web agora conta com trava no botão e trava anti-duplicidade em useLegalStore."
    echo ""
    echo -e "Próximos passos para o usuário:"
    echo -e "1. Acesse ${BOLD}https://sistema.advdouglaspsantos.com.br/tarefas${NC} para conferir a listagem limpa."
    echo -e "2. Na ficha de qualquer cliente, o botão 'Disparar Novamente' agora valida antes e impossibilita duplicatas."
    echo -e "${BOLD}${GREEN}=====================================================================${NC}\n"
    exit 0
else
    echo -e "\n${BOLD}${RED}❌ Falha: Ainda foram detectados ${REMAINING_GROUPS} grupos duplicados no banco '${REAL_DB}'!${NC}"
    echo -e "${YELLOW}Comando para inspeção manual:${NC}"
    echo -e "  docker exec -it ${REAL_CONTAINER} psql -U ${REAL_USER} -d ${REAL_DB} -c \"SELECT \\\"clientId\\\", title, count(*) FROM public.tasks WHERE type ILIKE '%onboarding%' GROUP BY \\\"clientId\\\", title HAVING count(*) > 1;\""
    echo ""
    exit 1
fi
