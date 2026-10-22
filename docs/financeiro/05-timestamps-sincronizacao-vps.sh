#!/usr/bin/env bash
# ==============================================================================
# SCRIPT VPS: GARANTIR TIMESTAMPS DE SINCRONIZAÇÃO/IMPORTAÇÃO EM SETTINGS
# DPSjur - Sistema Jurídico SBJur no VPS Hostinger (EasyPanel / Docker)
# Versão: v1.2.3
# Data: 2026-10-21
#
# O QUE ESTE SCRIPT FAZ (Totalmente Idempotente e Confiável):
# 1. Varre e descobre TODOS os contêineres Docker do PostgreSQL no VPS.
#    Descobre o usuário/superusuário real via env POSTGRES_USER do contêiner,
#    com fallback de teste dinâmico e em cada contêiner com tabela public.settings:
#      - POSTGRES_USER, postgres, supabase_admin, postgres_admin, Doug.
#    Identifica o banco real da aplicação (presença de public.settings e maior volume
#    de dados) e guarda as credenciais reais validadas para este banco.
# 2. Executa a migração SQL sem heredocs frágeis no docker exec:
#    - Cria arquivo SQL temporário tanto no host quanto dentro do contêiner
#      (via docker cp + psql -f /tmp/...) para evitar perdas de stdin e engolimento
#      silencioso de erros por pipe/subshell.
#    - Executa bloco BEGIN/COMMIT explícito.
#    - Adiciona de forma idempotente (ADD COLUMN IF NOT EXISTS) as colunas:
#        * "lastAsaasSyncAt" timestamptz
#        * "lastSicoobImportAt" timestamptz
#      na tabela public.settings.
#    - Notifica o PostgREST ('reload schema') para invalidar o schema cache.
# 3. Reinicia serviços de PostgREST para garantir reflexo imediato na API REST.
# 4. Conferência estrita dos dados na MESMA conexão e usuário detectados:
#    - Verifica se as colunas "lastAsaasSyncAt" e "lastSicoobImportAt" existem no banco.
#    - Só emite [OK] se AMBAS as colunas forem confirmadas com sucesso no information_schema.
#    - Se qualquer coluna não existir, encerra com código 1 e exibe o comando psql
#      exato para inspeção manual.
#
# COMO EXECUTAR NO VPS (como root - comando único sem pipe direto):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/financeiro/05-timestamps-sincronizacao-vps.sh" -o /root/05-timestamps-sincronizacao-vps.sh && bash /root/05-timestamps-sincronizacao-vps.sh
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
echo -e "${BOLD}${BLUE} DPSjur - Garantir Timestamps de Sincronização em settings (VPS)   ${NC}"
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
# Usa docker cp para evitar qualquer perda de stdin no subshell
run_container_sql_file() {
    local container="$1"
    local user="$2"
    local pass="$3"
    local dbname="$4"
    local sql_content="$5"

    local rand_id="dpsjur_sql_${RANDOM:-$$}_$(date +%s%N 2>/dev/null || date +%s)_$$"
    local host_tmp="/tmp/${rand_id}.sql"
    local cont_tmp="/tmp/${rand_id}.sql"

    printf "%s\n" "$sql_content" > "$host_tmp"

    # Copiar arquivo para dentro do contêiner
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
        # Fallback caso docker cp falhe
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
# 1. Localizar e auditar contêineres PostgreSQL em execução
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

# Estrutura para auditar: CONTAINER|DB_USER|DB_PASS|DB_NAME|HAS_SETTINGS|TX_COUNT
AUDIT_RESULTS=()

REAL_CONTAINER=""
REAL_USER=""
REAL_PASS=""
REAL_DB=""
MAX_TX=-1

for c in "${ALL_DB_CONTAINERS[@]}"; do
    echo -e "🔎 Inspecionando contêiner: ${BOLD}${c}${NC}..."

    # Ler envs do contêiner via docker inspect e docker exec env
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

    # Candidatos a usuário: POSTGRES_USER do container em primeiro, depois postgres, depois supabase_admin, Doug, postgres_admin
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

    # Testar usuários dinamicamente contra template1 / postgres / dpsjur
    for u in "${UNIQ_USERS[@]}"; do
        for cand_db in "${ENV_DB:-}" "postgres" "dpsjur" "template1"; do
            [ -z "$cand_db" ] && continue
            CHECK_ONE=$(run_container_psql "$c" "$u" "$WORKING_PASS" "$cand_db" "SELECT 1;")
            if [ "$CHECK_ONE" = "1" ]; then
                WORKING_USER="$u"
                # Obter lista completa de bancos
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

        SETTINGS_EXISTS=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='settings');")

        if [ "$SETTINGS_EXISTS" != "t" ]; then
            echo -e "    - Tabela public.settings: ${YELLOW}não existe neste banco${NC}"
            AUDIT_RESULTS+=("${c}|${WORKING_USER}|${WORKING_PASS}|${dbname}|nao|0")
            continue
        fi

        RAW_TX_COUNT=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';")
        TX_COUNT=$(echo "$RAW_TX_COUNT" | tr -dc '0-9' || echo 0)
        [ -z "$TX_COUNT" ] && TX_COUNT=0

        echo -e "    - Tabela public.settings: ${GREEN}EXISTE${NC} (${TX_COUNT} tabelas no schema public)"

        AUDIT_RESULTS+=("${c}|${WORKING_USER}|${WORKING_PASS}|${dbname}|sim|${TX_COUNT}")

        # Identificar o banco real da aplicação (com settings e maior contagem de tabelas públicas)
        if [ "$TX_COUNT" -gt "$MAX_TX" ]; then
            MAX_TX="$TX_COUNT"
            REAL_CONTAINER="$c"
            REAL_USER="$WORKING_USER"
            REAL_PASS="$WORKING_PASS"
            REAL_DB="$dbname"
        fi
    done
    echo ""
done

# Fallback se nenhum contêiner teve settings detectado
if [ -z "$REAL_CONTAINER" ]; then
    for entry in "${AUDIT_RESULTS[@]}"; do
        IFS='|' read -r c u p d has_st t_cnt <<< "$entry"
        if [ "$has_st" = "sim" ]; then
            REAL_CONTAINER="$c"
            REAL_USER="$u"
            REAL_PASS="$p"
            REAL_DB="$d"
            MAX_TX="$t_cnt"
            break
        fi
    done
fi

if [ -z "$REAL_CONTAINER" ]; then
    echo -e "${RED}❌ Não foi possível determinar o contêiner do banco real da aplicação com public.settings!${NC}"
    echo "Verifique os contêineres ativos com 'docker ps'."
    exit 1
fi

echo -e "🎯 ${BOLD}Banco Real Detectado:${NC}"
echo -e "   - Contêiner: ${GREEN}${REAL_CONTAINER}${NC}"
echo -e "   - Usuário:   ${GREEN}${REAL_USER}${NC}"
echo -e "   - Banco:     ${GREEN}${REAL_DB}${NC}"
echo -e "   - Tabelas:   ${GREEN}${MAX_TX} tabelas públicas detectadas${NC}\n"

# ------------------------------------------------------------------------------
# 2. Executar migração SQL idempotente no PostgreSQL
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 2/4] Aplicando migração SQL idempotente em public.settings...${NC}"

SQL_MIGRATION_FILE="
-- ==============================================================================
-- GARANTIR COLUNAS DE TIMESTAMPS DE SINCRONIZAÇÃO/IMPORTAÇÃO
-- ==============================================================================
BEGIN;

DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'settings' 
          AND column_name = 'lastAsaasSyncAt'
    ) THEN
        ALTER TABLE public.settings ADD COLUMN \"lastAsaasSyncAt\" timestamptz;
        RAISE NOTICE 'Coluna lastAsaasSyncAt criada com sucesso em settings.';
    ELSE
        RAISE NOTICE 'Coluna lastAsaasSyncAt já existe em settings.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'settings' 
          AND column_name = 'lastSicoobImportAt'
    ) THEN
        ALTER TABLE public.settings ADD COLUMN \"lastSicoobImportAt\" timestamptz;
        RAISE NOTICE 'Coluna lastSicoobImportAt criada com sucesso em settings.';
    ELSE
        RAISE NOTICE 'Coluna lastSicoobImportAt já existe em settings.';
    END IF;
END \$\$;

COMMIT;

-- Notificar PostgREST após commit
SELECT pg_notify('pgrst', 'reload schema');
"

echo -e "Executando migração no banco real (${REAL_CONTAINER} / ${REAL_DB} com usuário ${REAL_USER})..."
if run_container_sql_file "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "$SQL_MIGRATION_FILE"; then
    echo -e "${GREEN}[OK] Migração SQL aplicada com sucesso no banco real!${NC}"
else
    echo -e "${RED}❌ Falha na execução da migração SQL no banco real!${NC}"
    exit 1
fi

# Aplicar preventivamente em outros contêineres/bancos se houverem
for entry in "${AUDIT_RESULTS[@]}"; do
    IFS='|' read -r ac_c ac_u ac_p ac_d ac_has_st ac_t_cnt <<< "$entry"
    if [ "$ac_has_st" = "sim" ]; then
        if [ "$ac_c" != "$REAL_CONTAINER" ] || [ "$ac_d" != "$REAL_DB" ]; then
            echo -e "ℹ️ Aplicando preventivamente também no contêiner ${ac_c} (banco ${ac_d} com usuário ${ac_u})..."
            PREV_SQL="
BEGIN;
ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS \"lastAsaasSyncAt\" timestamptz;
ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS \"lastSicoobImportAt\" timestamptz;
COMMIT;
SELECT pg_notify('pgrst', 'reload schema');
"
            run_container_sql_file "$ac_c" "$ac_u" "$ac_p" "$ac_d" "$PREV_SQL" >/dev/null 2>&1 || true
        fi
    fi
done

echo ""

# ------------------------------------------------------------------------------
# 3. Recarregar schema cache do PostgREST
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 3/4] Recarregando PostgREST...${NC}"

run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "NOTIFY pgrst, 'reload schema';" >/dev/null 2>&1 || true

POSTGREST_CONTAINERS=()
while IFS= read -r r_name; do
    [ -z "$r_name" ] && continue
    POSTGREST_CONTAINERS+=("$r_name")
done < <(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'rest|postgrest' || true)

for r in "${POSTGREST_CONTAINERS[@]}"; do
    docker restart "$r" >/dev/null 2>&1 || true
    echo -e "  ${GREEN}✓ PostgREST reiniciado: ${r}${NC}"
done

echo -e "⏳ Aguardando 3 segundos para estabilização dos serviços..."
sleep 3
echo -e "${GREEN}✓ Serviços prontos.${NC}\n"

# ------------------------------------------------------------------------------
# 4. Verificação estrita e Relatório Final
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 4/4] Conferência estrita das colunas no banco real...${NC}"

CHECK_ASAAS=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='settings' AND column_name='lastAsaasSyncAt');")
CHECK_SICOOB=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='settings' AND column_name='lastSicoobImportAt');")

echo -e "\n${BOLD}Status das colunas em public.settings:${NC}"
if [ -n "$REAL_PASS" ]; then
    docker exec -i -e PGPASSWORD="$REAL_PASS" "$REAL_CONTAINER" psql -U "$REAL_USER" -d "$REAL_DB" -c "SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_schema='public' AND table_name='settings' AND column_name IN ('lastAsaasSyncAt', 'lastSicoobImportAt');" 2>/dev/null || true
else
    docker exec -i "$REAL_CONTAINER" psql -U "$REAL_USER" -d "$REAL_DB" -c "SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_schema='public' AND table_name='settings' AND column_name IN ('lastAsaasSyncAt', 'lastSicoobImportAt');" 2>/dev/null || true
fi

echo ""
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "${BOLD}${BLUE}                      RESUMO DA MIGRAÇÃO                             ${NC}"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "1. Banco Real Identificado:"
echo -e "   - Contêiner:              ${GREEN}${REAL_CONTAINER}${NC}"
echo -e "   - Usuário:                ${GREEN}${REAL_USER}${NC}"
echo -e "   - Banco:                  ${GREEN}${REAL_DB}${NC}"
echo -e "2. Coluna 'lastAsaasSyncAt':"
if [ "$CHECK_ASAAS" = "t" ]; then
    echo -e "   - Presença no schema:     ${BOLD}${GREEN}EXISTE [OK]${NC}"
else
    echo -e "   - Presença no schema:     ${BOLD}${RED}NÃO EXISTE (Falha)${NC}"
fi
echo -e "3. Coluna 'lastSicoobImportAt':"
if [ "$CHECK_SICOOB" = "t" ]; then
    echo -e "   - Presença no schema:     ${BOLD}${GREEN}EXISTE [OK]${NC}"
else
    echo -e "   - Presença no schema:     ${BOLD}${RED}NÃO EXISTE (Falha)${NC}"
fi
echo -e "${BOLD}${BLUE}=====================================================================${NC}"

if [ "$CHECK_ASAAS" = "t" ] && [ "$CHECK_SICOOB" = "t" ]; then
    echo -e "\n${BOLD}${GREEN}✅ OPERAÇÃO CONCLUÍDA COM SUCESSO! [OK]${NC}"
    echo -e "As colunas de timestamp de sincronização e importação estão ativas e funcionais no VPS."
    echo ""
    echo -e "Próximos passos para o Douglas:"
    echo -e "1. Acesse o sistema: ${BOLD}https://sistema.advdouglaspsantos.com.br/financeiro${NC}"
    echo -e "2. Pressione ${BOLD}Ctrl + F5${NC} no navegador para atualizar."
    echo -e "3. Ao sincronizar com Asaas ou importar extrato PDF, o timestamp aparecerá logo abaixo de cada botão."
    echo -e "${BOLD}${GREEN}=====================================================================${NC}\n"
    exit 0
else
    echo -e "\n${BOLD}${RED}❌ Falha: Pelo menos uma das colunas não foi confirmada no banco '${REAL_DB}' (contêiner '${REAL_CONTAINER}').${NC}"
    echo -e "${YELLOW}Comando para diagnóstico manual:${NC}"
    if [ -n "$REAL_PASS" ]; then
        echo -e "  docker exec -it -e PGPASSWORD='${REAL_PASS}' ${REAL_CONTAINER} psql -U ${REAL_USER} -d ${REAL_DB} -c \"SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='settings';\""
    else
        echo -e "  docker exec -it ${REAL_CONTAINER} psql -U ${REAL_USER} -d ${REAL_DB} -c \"SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='settings';\""
    fi
    echo ""
    exit 1
fi
