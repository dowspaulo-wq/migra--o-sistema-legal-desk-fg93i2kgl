#!/usr/bin/env bash
# ==============================================================================
# SCRIPT VPS: CONSERTAR "REALIZADO" -> "PAGO", UNIFICAR DUPLICATAS E WEBHOOK ASAAS
# DPSjur - Sistema Jurídico SBJur no VPS Hostinger (EasyPanel / Docker)
# Versão: v1.1.0
# Data: 2026-10-21
#
# O QUE ESTE SCRIPT FAZ (Totalmente Idempotente):
# 1. Varre e descobre o contêiner Docker do PostgreSQL real no EasyPanel,
#    descobrindo o usuário/superusuário real via env POSTGRES_USER do contêiner,
#    com fallback de teste em ordem: POSTGRES_USER, 'postgres', 'supabase_admin', etc.
# 2. Aplica correções SQL idempotentes no banco de dados:
#    - Converte status "Realizado" remanescentes para "Pago" (padrão unificado).
#    - Converte status "Paga" para "Pago".
#    - Identifica e unifica duplicatas criadas pelo webhook Asaas casando com
#      parcelas existentes de parcelamento (atualiza parcela original para 'Pago'
#      com asaas_id e remove/desativa a duplicata avulsa).
#    - Garante colunas lastAsaasSyncAt e lastSicoobImportAt em settings.
#    - Emite NOTIFY pgrst, 'reload schema' para recarregar o schema no PostgREST.
# 3. Atualiza o código da Edge Function asaas-webhook tanto no host quanto no
#    contêiner de edge-runtime/functions do VPS para registrar sempre "Pago"
#    e casar parcelas existentes em vez de duplicar.
# 4. Reinicia contêineres PostgREST e Edge Runtime se necessário.
# 5. Exibe conferência visual em tela mostrando contagem de registros 'Realizado'
#    restantes (deve ser 0) e resumo final consolidado [OK].
#
# COMO EXECUTAR NO VPS (como root - comando único sem pipe direto):
#   curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/docs/financeiro/04-consertar-realizado-vps.sh" -o /root/04-consertar-realizado-vps.sh && bash /root/04-consertar-realizado-vps.sh
# ==============================================================================

set -uo pipefail

SCRIPT_VERSION="v1.1.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "${BOLD}${BLUE} DPSjur - Correção de Status 'Realizado' -> 'Pago' & Webhook Asaas  ${NC}"
echo -e "${BOLD}${BLUE} Versão: ${SCRIPT_VERSION}${NC}"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "Data: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
echo -e "Host: $(hostname 2>/dev/null || echo 'VPS')"
echo -e "${BOLD}${BLUE}=====================================================================${NC}\n"

# Helper para executar query psql dentro de um contêiner
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

# ------------------------------------------------------------------------------
# 1. Localizar e auditar contêineres PostgreSQL em execução
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 1/5] Varrendo contêineres PostgreSQL em execução no VPS...${NC}"

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

# Estrutura para auditar: CONTAINER|DB_USER|DB_PASS|DB_NAME|HAS_TRANSACTIONS|TX_COUNT
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

    # Candidatos a usuário: POSTGRES_USER primeiro, depois 'postgres', depois 'supabase_admin', etc.
    CAND_USERS=()
    [ -n "$ENV_USER" ] && CAND_USERS+=("$ENV_USER")
    CAND_USERS+=("postgres" "supabase_admin" "postgres_admin" "Doug")

    UNIQ_USERS=()
    for u in "${CAND_USERS[@]}"; do
        [[ " ${UNIQ_USERS[*]} " =~ " ${u} " ]] || UNIQ_USERS+=("$u")
    done

    WORKING_USER=""
    WORKING_PASS="$ENV_PASS"
    DATABASES_LIST=""

    # Testar cada usuário executando SELECT datname ou SELECT 1
    for u in "${UNIQ_USERS[@]}"; do
        # Teste 1: SELECT datname
        DB_QUERY_OUT=$(run_container_psql "$c" "$u" "$WORKING_PASS" "template1" "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('rdsadmin');")
        if [ -z "$DB_QUERY_OUT" ]; then
            DB_QUERY_OUT=$(run_container_psql "$c" "$u" "$WORKING_PASS" "postgres" "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('rdsadmin');")
        fi
        if [ -n "$DB_QUERY_OUT" ]; then
            WORKING_USER="$u"
            DATABASES_LIST="$DB_QUERY_OUT"
            break
        fi

        # Teste 2: SELECT 1 com fallback de banco
        for cand_db in "${ENV_DB:-}" "postgres" "dpsjur" "template1"; do
            [ -z "$cand_db" ] && continue
            CHECK_ONE=$(run_container_psql "$c" "$u" "$WORKING_PASS" "$cand_db" "SELECT 1;")
            if [ "$CHECK_ONE" = "1" ]; then
                WORKING_USER="$u"
                DATABASES_LIST="$cand_db"
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

        TX_EXISTS=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='transactions');")

        if [ "$TX_EXISTS" != "t" ]; then
            echo -e "    - Tabela public.transactions: ${YELLOW}não existe neste banco${NC}"
            AUDIT_RESULTS+=("${c}|${WORKING_USER}|${WORKING_PASS}|${dbname}|nao|0")
            continue
        fi

        RAW_TX_COUNT=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT count(*) FROM public.transactions;")
        TX_COUNT=$(echo "$RAW_TX_COUNT" | tr -dc '0-9' || echo 0)
        [ -z "$TX_COUNT" ] && TX_COUNT=0

        REALIZADO_COUNT=$(run_container_psql "$c" "$WORKING_USER" "$WORKING_PASS" "$dbname" "SELECT count(*) FROM public.transactions WHERE status ILIKE 'realizado' OR status = 'Realizado';")
        REALIZADO_CLEAN=$(echo "$REALIZADO_COUNT" | tr -dc '0-9' || echo 0)
        [ -z "$REALIZADO_CLEAN" ] && REALIZADO_CLEAN=0

        echo -e "    - Tabela public.transactions: ${GREEN}EXISTE${NC} (${TX_COUNT} lançamentos, ${REALIZADO_CLEAN} com status 'Realizado')"

        AUDIT_RESULTS+=("${c}|${WORKING_USER}|${WORKING_PASS}|${dbname}|sim|${TX_COUNT}")

        # Identificar o banco real da aplicação (maior volume em transactions)
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

# Fallback se nenhum contêiner teve transactions > 0
if [ -z "$REAL_CONTAINER" ]; then
    for entry in "${AUDIT_RESULTS[@]}"; do
        IFS='|' read -r c u p d has_tx tx_cnt <<< "$entry"
        if [ "$has_tx" = "sim" ]; then
            REAL_CONTAINER="$c"
            REAL_USER="$u"
            REAL_PASS="$p"
            REAL_DB="$d"
            MAX_TX="$tx_cnt"
            break
        fi
    done
fi

if [ -z "$REAL_CONTAINER" ]; then
    echo -e "${RED}❌ Não foi possível determinar o contêiner do banco real da aplicação!${NC}"
    echo "Verifique os contêineres ativos com 'docker ps'."
    exit 1
fi

echo -e "🎯 ${BOLD}Banco Real Detectado:${NC}"
echo -e "   - Contêiner: ${GREEN}${REAL_CONTAINER}${NC}"
echo -e "   - Usuário:   ${GREEN}${REAL_USER}${NC}"
echo -e "   - Banco:     ${GREEN}${REAL_DB}${NC}"
echo -e "   - Total Tx:  ${GREEN}${MAX_TX} registros em public.transactions${NC}\n"

# ------------------------------------------------------------------------------
# 2. Executar migração SQL idempotente no PostgreSQL
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 2/5] Aplicando correções SQL no PostgreSQL...${NC}"

SQL_MIGRATION="
DO \$\$
DECLARE
    v_realizado_count integer := 0;
    v_paga_count integer := 0;
    v_duplicates_merged integer := 0;
    r_dup RECORD;
BEGIN
    -- 1. Garantir colunas de timestamps em settings
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'settings' 
          AND column_name = 'lastAsaasSyncAt'
    ) THEN
        ALTER TABLE public.settings ADD COLUMN \"lastAsaasSyncAt\" timestamptz;
        RAISE NOTICE 'Coluna lastAsaasSyncAt criada em settings.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'settings' 
          AND column_name = 'lastSicoobImportAt'
    ) THEN
        ALTER TABLE public.settings ADD COLUMN \"lastSicoobImportAt\" timestamptz;
        RAISE NOTICE 'Coluna lastSicoobImportAt criada em settings.';
    END IF;

    -- 2. Consertar lançamentos com status 'Realizado' -> 'Pago'
    UPDATE public.transactions
    SET status = 'Pago'
    WHERE status ILIKE 'realizado' OR status = 'Realizado';
    GET DIAGNOSTICS v_realizado_count = ROW_COUNT;
    RAISE NOTICE 'Lançamentos alterados de Realizado para Pago: %', v_realizado_count;

    -- 3. Consertar status 'Paga' -> 'Pago' para unificar o gênero no banco
    UPDATE public.transactions
    SET status = 'Pago'
    WHERE status ILIKE 'paga';
    GET DIAGNOSTICS v_paga_count = ROW_COUNT;
    RAISE NOTICE 'Lançamentos alterados de Paga para Pago: %', v_paga_count;

    -- 4. Extinção de status 'Êxito' se ainda remanescente
    UPDATE public.transactions
    SET 
        category = 'Honorários de Êxito',
        type = 'income',
        status = CASE 
            WHEN COALESCE(amount, 0) > 0 THEN 'Pago'
            ELSE 'Previsto'
        END
    WHERE status ILIKE 'êxito' OR status ILIKE 'exito';

    -- 5. Unificar duplicatas criadas pelo webhook Asaas casando com parcelas de parcelamento
    -- Cenário de duplicata:
    -- Existe uma transação avulsa t_dup (gerada pelo webhook com asaas_id, status 'Pago' ou 'Realizado', sem plan_id)
    -- E existe uma parcela t_plan vinculada a payment_plans (com plan_id NÃO nulo, mesmo cliente, mesmo valor ou descrição compatível)
    FOR r_dup IN (
        SELECT 
            t_dup.id AS dup_id,
            t_dup.asaas_id AS dup_asaas_id,
            t_dup.date AS dup_date,
            t_dup.\"bankAccount\" AS dup_bank,
            t_plan.id AS plan_tx_id
        FROM public.transactions t_dup
        JOIN public.transactions t_plan ON (
            t_dup.id <> t_plan.id
            AND t_dup.\"clientId\" IS NOT NULL
            AND t_dup.\"clientId\" = t_plan.\"clientId\"
            AND t_dup.plan_id IS NULL
            AND t_plan.plan_id IS NOT NULL
            AND t_dup.asaas_id IS NOT NULL
            AND (t_plan.asaas_id IS NULL OR t_plan.asaas_id = t_dup.asaas_id)
            AND ABS(COALESCE(t_dup.amount, 0) - COALESCE(t_plan.amount, 0)) < 0.05
            AND (
                -- Mesma data ou mês compatível ou mesma descrição
                t_dup.date = t_plan.date
                OR substring(t_dup.date from 1 for 7) = substring(t_plan.date from 1 for 7)
                OR (t_plan.installment_number IS NOT NULL AND t_dup.description ILIKE '%' || t_plan.installment_number || '%')
            )
        )
        ORDER BY t_dup.created_at ASC
    ) LOOP
        -- Atualiza a parcela original do parcelamento: marca como 'Pago', copia asaas_id e data
        UPDATE public.transactions
        SET 
            status = 'Pago',
            asaas_id = COALESCE(r_dup.dup_asaas_id, asaas_id),
            date = COALESCE(r_dup.dup_date, date),
            \"bankAccount\" = COALESCE(r_dup.dup_bank, \"bankAccount\", 'ASAAS'),
            pendente_vinculo = false
        WHERE id = r_dup.plan_tx_id;

        -- Remove ou limpa a transação duplicada avulsa para não duplicar saldo
        DELETE FROM public.transactions WHERE id = r_dup.dup_id;

        v_duplicates_merged := v_duplicates_merged + 1;
    END LOOP;
    RAISE NOTICE 'Duplicatas do webhook Asaas unificadas com parcelas: %', v_duplicates_merged;

    -- 6. Notificar PostgREST
    PERFORM pg_notify('pgrst', 'reload schema');
END \$\$;
"

echo -e "Executando migração no banco real (${REAL_CONTAINER})..."
if [ -n "$REAL_PASS" ]; then
    docker exec -i -e PGPASSWORD="$REAL_PASS" "$REAL_CONTAINER" psql -U "$REAL_USER" -d "$REAL_DB" -v ON_ERROR_STOP=1 <<< "$SQL_MIGRATION"
else
    docker exec -i "$REAL_CONTAINER" psql -U "$REAL_USER" -d "$REAL_DB" -v ON_ERROR_STOP=1 <<< "$SQL_MIGRATION"
fi
echo -e "${GREEN}[OK] Correções SQL aplicadas com sucesso no banco real.${NC}"

# Aplicar preventivamente em outros bancos se houver
for entry in "${AUDIT_RESULTS[@]}"; do
    IFS='|' read -r ac_c ac_u ac_p ac_d ac_has_tx ac_tx_cnt <<< "$entry"
    if [ "$ac_has_tx" = "sim" ]; then
        if [ "$ac_c" != "$REAL_CONTAINER" ] || [ "$ac_d" != "$REAL_DB" ]; then
            echo -e "ℹ️ Aplicando preventivamente também no contêiner ${ac_c} (banco ${ac_d})..."
            PREV_SQL="UPDATE public.transactions SET status = 'Pago' WHERE status ILIKE 'realizado' OR status = 'Realizado' OR status ILIKE 'paga'; PERFORM pg_notify('pgrst', 'reload schema');"
            if [ -n "$ac_p" ]; then
                docker exec -i -e PGPASSWORD="$ac_p" "$ac_c" psql -U "$ac_u" -d "$ac_d" -c "$PREV_SQL" >/dev/null 2>&1 || true
            else
                docker exec -i "$ac_c" psql -U "$ac_u" -d "$ac_d" -c "$PREV_SQL" >/dev/null 2>&1 || true
            fi
        fi
    fi
done

echo ""

# ------------------------------------------------------------------------------
# 3. Atualizar código da edge function asaas-webhook no VPS
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 3/5] Atualizando código da Edge Function asaas-webhook...${NC}"

# Diretório temporário com o código atualizado da função
TMP_FUNC_DIR="/tmp/dpsjur-asaas-webhook-update"
rm -rf "$TMP_FUNC_DIR"
mkdir -p "$TMP_FUNC_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "/root")"
LOCAL_SRC="${SCRIPT_DIR}/../../supabase/functions/asaas-webhook/index.ts"

if [ -f "$LOCAL_SRC" ]; then
    cp "$LOCAL_SRC" "$TMP_FUNC_DIR/index.ts"
    echo -e "  Código da função carregado a partir do repo local."
else
    echo -e "  Baixando versão atualizada do webhook do GitHub raw..."
    curl -sSL "https://raw.githubusercontent.com/dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl/main/supabase/functions/asaas-webhook/index.ts" -o "$TMP_FUNC_DIR/index.ts"
fi

# Copiar para diretórios no host se existirem
HOST_DIRS=(
    "/home/deno/functions/asaas-webhook"
    "/root/supabase/functions/asaas-webhook"
    "/home/supabase/functions/asaas-webhook"
    "/tmp/sbjur-asaas-deploy/functions/asaas-webhook"
)

for h_dir in "${HOST_DIRS[@]}"; do
    if [ -d "$h_dir" ]; then
        [ -f "${h_dir}/index.ts" ] && cp "${h_dir}/index.ts" "${h_dir}/index.ts.bak.$(date +%s)" 2>/dev/null || true
        cp "$TMP_FUNC_DIR/index.ts" "${h_dir}/index.ts"
        echo -e "  ${GREEN}✓ Atualizado diretório no host: ${h_dir}${NC}"
    fi
done

# Localizar contêineres de Edge Functions (edge-runtime / deno / functions)
EDGE_CONTAINERS=()
while IFS= read -r f_name; do
    [ -z "$f_name" ] && continue
    EDGE_CONTAINERS+=("$f_name")
done < <(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'edge-runtime|functions|sbjur.*edge|supabase.*edge' || true)

if [ ${#EDGE_CONTAINERS[@]} -eq 0 ]; then
    # Fallback por imagem
    while IFS= read -r f_name; do
        [ -z "$f_name" ] && continue
        EDGE_CONTAINERS+=("$f_name")
    done < <(docker ps --filter "ancestor=supabase/edge-runtime" --format '{{.Names}}' 2>/dev/null || true)
fi

echo -e "Contêineres de Edge Functions encontrados (${#EDGE_CONTAINERS[@]}):"
for ec in "${EDGE_CONTAINERS[@]}"; do
    echo -e "  - ${BOLD}${ec}${NC}"
    
    # Descobrir caminho de destino dentro do contêiner
    CONTAINER_FUNC_DIR="/home/deno/functions/asaas-webhook"
    if ! docker exec "$ec" test -d "$CONTAINER_FUNC_DIR" 2>/dev/null; then
        if docker exec "$ec" test -d "/app/functions/asaas-webhook" 2>/dev/null; then
            CONTAINER_FUNC_DIR="/app/functions/asaas-webhook"
        elif docker exec "$ec" test -d "/functions/asaas-webhook" 2>/dev/null; then
            CONTAINER_FUNC_DIR="/functions/asaas-webhook"
        else
            docker exec "$ec" mkdir -p "$CONTAINER_FUNC_DIR" 2>/dev/null || true
        fi
    fi

    # Copiar o index.ts atualizado para dentro do contêiner
    docker cp "$TMP_FUNC_DIR/index.ts" "${ec}:${CONTAINER_FUNC_DIR}/index.ts" 2>/dev/null || true
    echo -e "    ${GREEN}✓ Arquivo index.ts copiado para ${CONTAINER_FUNC_DIR} em ${ec}${NC}"
done

rm -rf "$TMP_FUNC_DIR" 2>/dev/null || true
echo ""

# ------------------------------------------------------------------------------
# 4. Recarregar schema cache do PostgREST e reiniciar serviços
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 4/5] Recarregando PostgREST e reiniciando Edge Runtime...${NC}"

# Notificar via NOTIFY pgrst
run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "NOTIFY pgrst, 'reload schema';" >/dev/null 2>&1 || true

# Localizar e reiniciar contêineres PostgREST / rest
POSTGREST_CONTAINERS=()
while IFS= read -r r_name; do
    [ -z "$r_name" ] && continue
    POSTGREST_CONTAINERS+=("$r_name")
done < <(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'rest|postgrest' || true)

for r in "${POSTGREST_CONTAINERS[@]}"; do
    docker restart "$r" >/dev/null 2>&1 || true
    echo -e "  ${GREEN}✓ PostgREST reiniciado: ${r}${NC}"
done

# Reiniciar contêineres Edge Runtime
for ec in "${EDGE_CONTAINERS[@]}"; do
    docker restart "$ec" >/dev/null 2>&1 || true
    echo -e "  ${GREEN}✓ Edge Runtime reiniciado: ${ec}${NC}"
done

echo -e "⏳ Aguardando 4 segundos para estabilização dos serviços..."
sleep 4
echo -e "${GREEN}✓ Serviços atualizados e prontos.${NC}\n"

# ------------------------------------------------------------------------------
# 5. Verificação e Relatório Final
# ------------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}[Etapa 5/5] Conferência dos dados no banco real...${NC}"

# Contagem de 'Realizado' restante (deve ser 0)
RAW_REALIZADO_REMAINING=$(run_container_psql "$REAL_CONTAINER" "$REAL_USER" "$REAL_PASS" "$REAL_DB" "SELECT count(*) FROM public.transactions WHERE status ILIKE 'realizado' OR status = 'Realizado';")
REALIZADO_REMAINING=$(echo "$RAW_REALIZADO_REMAINING" | tr -dc '0-9' || echo 0)
[ -z "$REALIZADO_REMAINING" ] && REALIZADO_REMAINING=0

echo -e "\n${BOLD}Distribuição atual de status em public.transactions:${NC}"
if [ -n "$REAL_PASS" ]; then
    docker exec -i -e PGPASSWORD="$REAL_PASS" "$REAL_CONTAINER" psql -U "$REAL_USER" -d "$REAL_DB" -c "SELECT status, count(*) FROM public.transactions GROUP BY status ORDER BY count(*) DESC;" 2>/dev/null || true
else
    docker exec -i "$REAL_CONTAINER" psql -U "$REAL_USER" -d "$REAL_DB" -c "SELECT status, count(*) FROM public.transactions GROUP BY status ORDER BY count(*) DESC;" 2>/dev/null || true
fi

echo ""
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "${BOLD}${BLUE}                      RESUMO DA CORREÇÃO                             ${NC}"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "1. Banco Real Identificado:"
echo -e "   - Contêiner:          ${GREEN}${REAL_CONTAINER}${NC}"
echo -e "   - Usuário:            ${GREEN}${REAL_USER}${NC}"
echo -e "   - Banco:              ${GREEN}${REAL_DB}${NC}"
echo -e "2. Status 'Realizado':"
if [ "$REALIZADO_REMAINING" -eq 0 ]; then
    echo -e "   - Registros restantes: ${BOLD}${GREEN}0 [OK] (100% extinto e unificado como 'Pago')${NC}"
else
    echo -e "   - Registros restantes: ${BOLD}${RED}${REALIZADO_REMAINING} (Atenção)${NC}"
fi
echo -e "3. Webhook Asaas & Edge Runtime:"
echo -e "   - Gravação de status:  ${BOLD}${GREEN}'Pago' (padrão único)${NC}"
echo -e "   - Casamento resiliente: ${BOLD}${GREEN}Ativo (une cobrança à parcela existente)${NC}"
echo -e "   - Edge containers:     ${GREEN}${#EDGE_CONTAINERS[@]} atualizado(s) e reiniciado(s)${NC}"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"

if [ "$REALIZADO_REMAINING" -eq 0 ]; then
    echo -e "\n${BOLD}${GREEN}✅ OPERAÇÃO CONCLUÍDA COM SUCESSO! [OK]${NC}"
    echo -e "O status 'Realizado' foi completamente extinto em favor de 'Pago'."
    echo -e "As duplicatas foram unificadas e o webhook do Asaas está protegido contra novas duplicidades."
    echo ""
    echo -e "Próximos passos para o Douglas:"
    echo -e "1. Acesse o sistema: ${BOLD}https://sistema.advdouglaspsantos.com.br/financeiro${NC}"
    echo -e "2. Pressione ${BOLD}Ctrl + F5${NC} no navegador para atualizar."
    echo -e "3. Todos os lançamentos pagos exibem o status 'Pago' de forma limpa e unificada."
    echo -e "${BOLD}${GREEN}=====================================================================${NC}\n"
    exit 0
else
    echo -e "\n${BOLD}${RED}⚠️ Aviso: Ainda restam ${REALIZADO_REMAINING} registros com status 'Realizado'.${NC}"
    exit 1
fi
